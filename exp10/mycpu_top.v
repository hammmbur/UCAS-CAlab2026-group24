module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg reset;
always @(posedge clk) reset <= ~resetn;

// IF and IF/ID pipeline register.
reg        if_valid;
reg [31:0] if_pc;
// A block RAM returns an instruction one clock after its address request.
// These registers label that returned instruction with its request PC.
reg        if_resp_valid;
reg [31:0] if_resp_pc;
reg        id_valid;
reg [31:0] id_pc;
reg [31:0] id_inst;

// ID/EXE pipeline register.
reg        exe_valid;
reg [31:0] exe_pc;
reg [11:0] exe_alu_op;
reg [31:0] exe_alu_src1;
reg [31:0] exe_alu_src2;
reg [31:0] exe_store_data;
reg [ 4:0] exe_dest;
reg        exe_gr_we;
reg        exe_mem_we;
reg        exe_res_from_mem;

// EXE/MEM pipeline register.
reg        mem_valid;
reg [31:0] mem_pc;
reg [31:0] mem_alu_result;
reg [ 4:0] mem_dest;
reg        mem_gr_we;
reg        mem_res_from_mem;

// MEM/WB pipeline register.
reg        wb_valid;
reg [31:0] wb_pc;
reg [31:0] wb_alu_result;
reg [31:0] wb_mem_result;
reg [ 4:0] wb_dest;
reg        wb_gr_we;
reg        wb_res_from_mem;

//IF stage
wire [31:0] if_seq_pc;
wire [31:0] if_nextpc;
wire        id_br_taken;
wire [31:0] id_br_target;
assign if_seq_pc = if_pc + 32'h4;
assign if_nextpc = id_br_taken ? id_br_target : if_seq_pc;

// ID stage instruction fields and decoded controls.
wire [ 5:0] op_31_26;
wire [ 3:0] op_25_22;
wire [ 1:0] op_21_20;
wire [ 4:0] op_19_15;
wire [ 4:0] rd;
wire [ 4:0] rj;
wire [ 4:0] rk;
wire [11:0] i12;
wire [19:0] i20;
wire [15:0] i16;
wire [25:0] i26;
wire [63:0] op_31_26_d;
wire [15:0] op_25_22_d;
wire [ 3:0] op_21_20_d;
wire [31:0] op_19_15_d;

wire inst_add_w, inst_sub_w, inst_slt, inst_sltu;
wire inst_nor, inst_and, inst_or, inst_xor;
wire inst_slli_w, inst_srli_w, inst_srai_w, inst_addi_w;
wire inst_ld_w, inst_st_w, inst_jirl, inst_b, inst_bl, inst_beq, inst_bne, inst_lu12i_w;
wire [11:0] id_alu_op;
wire        id_src1_is_pc;
wire        id_src2_is_imm;
wire        id_res_from_mem;
wire        id_dst_is_r1;
wire        id_gr_we;
wire        id_mem_we;
wire        id_src_reg_is_rd;
wire        id_rj_used;
wire        id_rkd_used;
wire [ 4:0] id_dest;
wire [31:0] id_imm;
wire [31:0] id_br_offs;
wire [31:0] id_jirl_offs;

/*
Decoding the instruction
*/
assign op_31_26 = id_inst[31:26];
assign op_25_22 = id_inst[25:22];
assign op_21_20 = id_inst[21:20];
assign op_19_15 = id_inst[19:15];
assign rd        = id_inst[ 4: 0];
assign rj        = id_inst[ 9: 5];
assign rk        = id_inst[14:10];
assign i12       = id_inst[21:10];
assign i20       = id_inst[24: 5];
assign i16       = id_inst[25:10];
assign i26       = {id_inst[9:0], id_inst[25:10]};

decoder_6_64 u_dec0(.in(op_31_26), .out(op_31_26_d));
decoder_4_16 u_dec1(.in(op_25_22), .out(op_25_22_d));
decoder_2_4  u_dec2(.in(op_21_20), .out(op_21_20_d));
decoder_5_32 u_dec3(.in(op_19_15), .out(op_19_15_d));

assign inst_add_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
assign inst_sub_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
assign inst_slt     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
assign inst_sltu    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
assign inst_nor     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
assign inst_and     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
assign inst_or      = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
assign inst_xor     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
assign inst_slli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
assign inst_srli_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
assign inst_srai_w  = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
assign inst_addi_w  = op_31_26_d[6'h00] & op_25_22_d[4'ha];
assign inst_ld_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
assign inst_st_w    = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
assign inst_jirl    = op_31_26_d[6'h13];
assign inst_b       = op_31_26_d[6'h14];
assign inst_bl      = op_31_26_d[6'h15];
assign inst_beq     = op_31_26_d[6'h16];
assign inst_bne     = op_31_26_d[6'h17];
assign inst_lu12i_w = op_31_26_d[6'h05] & ~id_inst[25];

assign id_alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl;
assign id_alu_op[ 1] = inst_sub_w;
assign id_alu_op[ 2] = inst_slt;
assign id_alu_op[ 3] = inst_sltu;
assign id_alu_op[ 4] = inst_and;
assign id_alu_op[ 5] = inst_nor;
assign id_alu_op[ 6] = inst_or;
assign id_alu_op[ 7] = inst_xor;
assign id_alu_op[ 8] = inst_slli_w;
assign id_alu_op[ 9] = inst_srli_w;
assign id_alu_op[10] = inst_srai_w;
assign id_alu_op[11] = inst_lu12i_w;

assign id_imm = (inst_jirl | inst_bl) ? 32'h4 :
                inst_lu12i_w          ? {i20, 12'b0} :
                                      {{20{i12[11]}}, i12};
assign id_br_offs = (inst_b | inst_bl) ? {{4{i26[25]}}, i26, 2'b0} :
                                          {{14{i16[15]}}, i16, 2'b0};
assign id_jirl_offs = {{14{i16[15]}}, i16, 2'b0};
assign id_src_reg_is_rd = inst_beq | inst_bne | inst_st_w;
assign id_src1_is_pc    = inst_jirl | inst_bl;
assign id_src2_is_imm   = inst_slli_w | inst_srli_w | inst_srai_w |
                          inst_addi_w | inst_ld_w | inst_st_w | inst_lu12i_w |
                          inst_jirl | inst_bl;
assign id_res_from_mem  = inst_ld_w;
assign id_dst_is_r1     = inst_bl;
assign id_gr_we         = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                          inst_ld_w | inst_jirl | inst_bl | inst_lu12i_w;
assign id_mem_we        = inst_st_w;
assign id_dest          = id_dst_is_r1 ? 5'd1 : rd;
assign id_rj_used       = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                          inst_ld_w | inst_st_w | inst_jirl | inst_beq | inst_bne;
assign id_rkd_used      = inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_st_w | inst_beq | inst_bne;

/*
Instantiate register file
*/
// The register file is read in ID and written only by WB.
wire [ 4:0] rf_raddr1;
wire [31:0] rf_rdata1;
wire [ 4:0] rf_raddr2;
wire [31:0] rf_rdata2;
wire        rf_we;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
wire [31:0] id_rj_value;
wire [31:0] id_rkd_value;
wire        id_rj_eq_rkd;
wire [31:0] exe_alu_result;
wire [31:0] wb_final_result;
assign rf_raddr1 = rj;
assign rf_raddr2 = id_src_reg_is_rd ? rd : rk;
regfile u_regfile(
    .clk(clk), .raddr1(rf_raddr1), .rdata1(rf_rdata1),
    .raddr2(rf_raddr2), .rdata2(rf_rdata2),
    .we(rf_we), .waddr(rf_waddr), .wdata(rf_wdata)
);

/*
Forwarding unit
*/
// Forward completed results back to the decode stage.  The newest producer
// has priority: EXE, then MEM, then WB, and finally the register file.
wire [31:0] exe_forward_value;
wire [31:0] mem_forward_value;
wire [31:0] wb_forward_value;
assign exe_forward_value = exe_alu_result;
assign mem_forward_value = mem_res_from_mem ? data_sram_rdata : mem_alu_result;
assign wb_forward_value  = wb_final_result;

assign id_rj_value =
    (exe_valid && exe_gr_we && !exe_res_from_mem && (exe_dest != 5'd0) &&
     id_rj_used && (rj == exe_dest)) ? exe_forward_value :
    (mem_valid && mem_gr_we && (mem_dest != 5'd0) &&
     id_rj_used && (rj == mem_dest)) ? mem_forward_value :
    (wb_valid && wb_gr_we && (wb_dest != 5'd0) &&
     id_rj_used && (rj == wb_dest)) ? wb_forward_value :
    rf_rdata1;

assign id_rkd_value =
    (exe_valid && exe_gr_we && !exe_res_from_mem && (exe_dest != 5'd0) &&
     id_rkd_used && (rf_raddr2 == exe_dest)) ? exe_forward_value :
    (mem_valid && mem_gr_we && (mem_dest != 5'd0) &&
     id_rkd_used && (rf_raddr2 == mem_dest)) ? mem_forward_value :
    (wb_valid && wb_gr_we && (wb_dest != 5'd0) &&
     id_rkd_used && (rf_raddr2 == wb_dest)) ? wb_forward_value :
    rf_rdata2;

assign id_rj_eq_rkd = (id_rj_value == id_rkd_value);

/*
Blocking unit: for exp9, only take place when coming across RAW hazard in ld.w
*/
wire exe_load_use_hazard;
wire id_stall;
assign exe_load_use_hazard = exe_valid && exe_gr_we && exe_res_from_mem &&
                             (exe_dest != 5'd0) &&
                             ((id_rj_used  && (rj        == exe_dest)) ||
                              (id_rkd_used && (rf_raddr2 == exe_dest)));
assign id_stall = id_valid && exe_load_use_hazard;

assign id_br_taken  = id_valid && !id_stall && ((inst_beq && id_rj_eq_rkd) ||
                                   (inst_bne && !id_rj_eq_rkd) ||
                                    inst_jirl || inst_bl || inst_b);
assign id_br_target = (inst_beq || inst_bne || inst_bl || inst_b) ?
                      (id_pc + id_br_offs) : (id_rj_value + id_jirl_offs);

// EXE stage and its SRAM request.
alu u_alu(
    .alu_op(exe_alu_op), .alu_src1(exe_alu_src1),
    .alu_src2(exe_alu_src2), .alu_result(exe_alu_result)
);
assign inst_sram_en    = if_valid && !id_stall;
assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = if_pc;
assign inst_sram_wdata = 32'b0;
assign data_sram_en    = exe_valid && (exe_mem_we || exe_res_from_mem);
assign data_sram_we    = (exe_valid && exe_mem_we) ? 4'b1111 : 4'b0000;
assign data_sram_addr  = exe_alu_result;
assign data_sram_wdata = exe_store_data;

/*
CPU pipeline: IF->ID->EX->MEM->WB
*/
// A load result is unavailable while the load is in EXE.  Hold ID/IF for that
// one cycle and inject a bubble into EXE; MEM/WB continue to advance.
always @(posedge clk) begin
    if (reset) begin
        if_valid  <= 1'b0;
        if_pc     <= 32'h1bfffffc;
        if_resp_valid <= 1'b0;
        id_valid  <= 1'b0;
        exe_valid <= 1'b0;
        mem_valid <= 1'b0;
        wb_valid  <= 1'b0;
    end
    else begin
        if (!id_stall) begin
            if_valid <= 1'b1;
            if_pc    <= if_nextpc;

            if (id_br_taken) begin
                id_valid <= 1'b0;
                if_resp_valid <= 1'b0;
            end
            else begin
                id_valid <= if_resp_valid;
                id_pc    <= if_resp_pc;
                id_inst  <= inst_sram_rdata;
                if_resp_valid <= if_valid;
            end
            if_resp_pc <= if_pc;
        end

        if (id_stall) begin
            exe_valid        <= 1'b0;
            exe_pc           <= 32'b0;
            exe_alu_op       <= 12'b0;
            exe_alu_src1     <= 32'b0;
            exe_alu_src2     <= 32'b0;
            exe_store_data   <= 32'b0;
            exe_dest         <= 5'b0;
            exe_gr_we        <= 1'b0;
            exe_mem_we       <= 1'b0;
            exe_res_from_mem <= 1'b0;
        end
        else begin
            exe_valid        <= id_valid;
            exe_pc           <= id_pc;
            exe_alu_op       <= id_alu_op;
            exe_alu_src1     <= id_src1_is_pc ? id_pc : id_rj_value;
            exe_alu_src2     <= id_src2_is_imm ? id_imm : id_rkd_value;
            exe_store_data   <= id_rkd_value;
            exe_dest         <= id_dest;
            exe_gr_we        <= id_gr_we;
            exe_mem_we       <= id_mem_we;
            exe_res_from_mem <= id_res_from_mem;
        end

        mem_valid        <= exe_valid;
        mem_pc           <= exe_pc;
        mem_alu_result   <= exe_alu_result;
        mem_dest         <= exe_dest;
        mem_gr_we        <= exe_gr_we;
        mem_res_from_mem <= exe_res_from_mem;

        wb_valid        <= mem_valid;
        wb_pc           <= mem_pc;
        wb_alu_result   <= mem_alu_result;
        wb_mem_result   <= data_sram_rdata;
        wb_dest         <= mem_dest;
        wb_gr_we        <= mem_gr_we;
        wb_res_from_mem <= mem_res_from_mem;
    end
end

// WB stage
assign wb_final_result   = wb_res_from_mem ? wb_mem_result : wb_alu_result;
assign rf_we             = wb_valid && wb_gr_we;
assign rf_waddr          = wb_dest;
assign rf_wdata          = wb_final_result;
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_final_result;

endmodule
