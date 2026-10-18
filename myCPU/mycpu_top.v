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
reg [6:0] exe_md_op;
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
reg [31:0] exe_br_offs;
reg        exe_may_branch;
reg        exe_br_cond_is_ge;
reg [ 2:0] exe_load_type;
reg [ 1:0] exe_store_type;
reg        exe_csr_read;
reg        exe_csr_we;
reg [13:0] exe_csr_num;
reg [31:0] exe_csr_rvalue;
reg [31:0] exe_csr_wvalue;
reg [31:0] exe_csr_wmask;
reg        exe_ex;
reg [ 5:0] exe_ecode;
reg [ 8:0] exe_esubcode;
reg        exe_ertn;

// EXE/MEM pipeline register.
reg        mem_valid;
reg [31:0] mem_pc;
reg [31:0] mem_alu_result;
reg [ 4:0] mem_dest;
reg        mem_gr_we;
reg        mem_res_from_mem;
reg [ 2:0] mem_load_type;
reg        mem_csr_read;
reg        mem_csr_we;
reg [13:0] mem_csr_num;
reg [31:0] mem_csr_rvalue;
reg [31:0] mem_csr_wvalue;
reg [31:0] mem_csr_wmask;
reg        mem_ex;
reg [ 5:0] mem_ecode;
reg [ 8:0] mem_esubcode;
reg        mem_ertn;
wire [31:0] mem_load_shifted;
wire [31:0] mem_result;

// MEM/WB pipeline register.
reg        wb_valid;
reg [31:0] wb_pc;
reg [31:0] wb_alu_result;
reg [31:0] wb_mem_result;
reg [ 4:0] wb_dest;
reg        wb_gr_we;
reg        wb_res_from_mem;
reg        wb_csr_read;
reg        wb_csr_we;
reg [13:0] wb_csr_num;
reg [31:0] wb_csr_rvalue;
reg [31:0] wb_csr_wvalue;
reg [31:0] wb_csr_wmask;
reg        wb_ex_flag;
reg [ 5:0] wb_ecode;
reg [ 8:0] wb_esubcode;
reg        wb_ertn;

//IF stage
wire [31:0] if_seq_pc;
wire [31:0] if_nextpc;
wire        id_br_taken;
wire [31:0] id_br_target;

wire id_ex_will_branch;
wire exe_br_taken;
wire [31:0] exe_br_target;
assign if_seq_pc = if_pc + 32'h4;
assign if_nextpc = exe_br_taken      ? exe_br_target :
                   id_br_taken       ? id_br_target  :
                   id_ex_will_branch ? id_pc + 32'd4 : //ensure sequent pc being reserved if branch not taken
                                       if_seq_pc;

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
wire inst_slti;
wire inst_sltui;
wire inst_andi;
wire inst_ori;
wire inst_xori;
wire inst_sll_w;
wire inst_srl_w;
wire inst_sra_w;
wire inst_pcaddu12i;
wire inst_csr;
wire inst_csrrd;
wire inst_csrwr;
wire inst_csrxchg;
wire inst_syscall;
wire inst_ertn;
wire inst_mul_w;
wire inst_mulh_w;
wire inst_mulh_wu;
wire inst_div_w;
wire inst_mod_w;
wire inst_div_wu;
wire inst_mod_wu;
wire [6:0] id_md_op;
wire id_new_imm = inst_slti | inst_sltui | inst_andi | inst_ori | inst_xori;
wire id_new_reg = inst_sll_w | inst_srl_w | inst_sra_w | (|id_md_op);
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
wire        id_csr_read;
wire        id_csr_we;
wire [13:0] id_csr_num;
wire [31:0] id_csr_rvalue;
wire [31:0] id_csr_wvalue;
wire [31:0] id_csr_wmask;
wire        id_syscall;
wire        id_ertn;
wire [31:0] id_rj_value;
wire [31:0] id_rkd_value;

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

assign inst_slti = op_31_26_d[0] & op_25_22_d[8];
assign inst_sltui = op_31_26_d[0] & op_25_22_d[9];
assign inst_andi = op_31_26_d[0] & op_25_22_d[13];
assign inst_ori = op_31_26_d[0] & op_25_22_d[14];
assign inst_xori = op_31_26_d[0] & op_25_22_d[15];
assign inst_sll_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[14];
assign inst_srl_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[15];
assign inst_sra_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[16];
assign inst_mul_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[24];
assign inst_mulh_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[25];
assign inst_mulh_wu = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[1] & op_19_15_d[26];
assign inst_div_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[2] & op_19_15_d[0];
assign inst_mod_w = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[2] & op_19_15_d[1];
assign inst_div_wu = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[2] & op_19_15_d[2];
assign inst_mod_wu = op_31_26_d[0] & op_25_22_d[0] & op_21_20_d[2] & op_19_15_d[3];
assign inst_pcaddu12i = op_31_26_d[7] & ~id_inst[25];
assign inst_csr     = op_31_26 == 6'h01;
assign inst_csrrd   = inst_csr && (rj == 5'd0);
assign inst_csrwr   = inst_csr && (rj == 5'd1);
assign inst_csrxchg = inst_csr && (rj != 5'd0) && (rj != 5'd1);
assign inst_syscall = (id_inst & 32'hffff8000) == 32'h002b0000;
assign inst_ertn    = id_inst == 32'h06483800;
assign id_md_op = {inst_mod_wu, inst_div_wu, inst_mod_w, inst_div_w, inst_mulh_wu, inst_mulh_w, inst_mul_w};

/*
exp11: blt、bge、bltu、bgeu
       ld.b、ld.h、ld.bu、ld.hu、st.b、st.h
*/
wire inst_blt, inst_bge, inst_bltu, inst_bgeu;
wire inst_ld_b, inst_ld_h, inst_ld_bu, inst_ld_hu, inst_st_b, inst_st_h;
assign inst_blt = op_31_26_d[6'h18];
assign inst_bge = op_31_26_d[6'h19];
assign inst_bltu = op_31_26_d[6'h1a];
assign inst_bgeu = op_31_26_d[6'h1b];
assign inst_ld_b = op_31_26_d[6'h0a] & op_25_22_d[4'h0];
assign inst_ld_h = op_31_26_d[6'h0a] & op_25_22_d[4'h1];
assign inst_ld_bu = op_31_26_d[6'h0a] & op_25_22_d[4'h8];
assign inst_ld_hu = op_31_26_d[6'h0a] & op_25_22_d[4'h9];
assign inst_st_b = op_31_26_d[6'h0a] & op_25_22_d[4'h4];
assign inst_st_h = op_31_26_d[6'h0a] & op_25_22_d[4'h5];

wire inst_is_ld, inst_is_st;
assign inst_is_ld = inst_ld_w | inst_ld_b | inst_ld_h | inst_ld_bu | inst_ld_hu;
assign inst_is_st = inst_st_w | inst_st_b | inst_st_h;

//when loading byte/halfword, loading type must be passed down
wire [2:0] id_load_type;
wire [1:0] id_store_type;
assign id_load_type = {op_25_22[3], op_25_22[1:0]};
assign id_store_type = op_25_22[1:0];

assign id_alu_op[ 0] = inst_add_w | inst_addi_w | inst_is_ld | inst_is_st | inst_jirl | inst_bl | inst_pcaddu12i;
assign id_alu_op[ 1] = inst_sub_w;
assign id_alu_op[ 2] = inst_slt | inst_slti | inst_blt | inst_bge;
assign id_alu_op[ 3] = inst_sltu | inst_sltui | inst_bltu | inst_bgeu;
assign id_alu_op[ 4] = inst_and | inst_andi;
assign id_alu_op[ 5] = inst_nor;
assign id_alu_op[ 6] = inst_or | inst_ori;
assign id_alu_op[ 7] = inst_xor | inst_xori;
assign id_alu_op[ 8] = inst_slli_w | inst_sll_w;
assign id_alu_op[ 9] = inst_srli_w | inst_srl_w;
assign id_alu_op[10] = inst_srai_w | inst_sra_w;
assign id_alu_op[11] = inst_lu12i_w;

assign id_imm = (inst_jirl | inst_bl) ? 32'h4 :
                (inst_lu12i_w | inst_pcaddu12i) ? {i20, 12'b0} :
                (inst_andi | inst_ori | inst_xori) ? {20'b0, i12} :
                                      {{20{i12[11]}}, i12};
assign id_br_offs = (inst_b | inst_bl) ? {{4{i26[25]}}, i26, 2'b0} :
                                          {{14{i16[15]}}, i16, 2'b0};
assign id_jirl_offs = {{14{i16[15]}}, i16, 2'b0};
assign id_src1_is_pc    = inst_jirl | inst_bl | inst_pcaddu12i;
assign id_src2_is_imm   = id_new_imm | inst_pcaddu12i | inst_slli_w | inst_srli_w | inst_srai_w |
                          inst_addi_w | inst_is_ld | inst_is_st | inst_lu12i_w |
                          inst_jirl | inst_bl;
assign id_res_from_mem  = inst_is_ld;
assign id_dst_is_r1     = inst_bl;
assign id_gr_we         = id_new_imm | id_new_reg | inst_pcaddu12i | inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                          inst_is_ld | inst_jirl | inst_bl | inst_lu12i_w |
                          inst_csrrd | inst_csrwr | inst_csrxchg;
assign id_mem_we        = inst_is_st;
assign id_dest          = id_dst_is_r1 ? 5'd1 : rd;
assign id_rj_used       = id_new_imm | id_new_reg | inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_slli_w | inst_srli_w | inst_srai_w | inst_addi_w |
                          inst_is_ld | inst_is_st | inst_jirl | inst_beq | inst_bne |
                          inst_blt | inst_bge | inst_bltu | inst_bgeu | inst_csrxchg;
assign id_rkd_used      = id_new_reg | inst_add_w | inst_sub_w | inst_slt | inst_sltu |
                          inst_nor | inst_and | inst_or | inst_xor |
                          inst_is_st | inst_beq | inst_bne |
                          inst_blt | inst_bge | inst_bltu | inst_bgeu |
                          inst_csrwr | inst_csrxchg;

assign id_src_reg_is_rd = inst_beq | inst_bne | inst_blt | inst_bge | inst_bltu | inst_bgeu |
                          inst_is_st | inst_csrwr | inst_csrxchg;
assign id_csr_read      = inst_csrrd | inst_csrwr | inst_csrxchg;
assign id_csr_we        = inst_csrwr | inst_csrxchg;
assign id_csr_num       = id_inst[23:10];
assign id_csr_wvalue    = id_csr_we ? id_rkd_value : 32'b0;
assign id_csr_wmask     = inst_csrwr ? 32'hffffffff :
                          inst_csrxchg ? id_rj_value : 32'b0;
assign id_syscall       = inst_syscall;
assign id_ertn           = inst_ertn;

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
wire        id_rj_eq_rkd;
wire [31:0] exe_alu_result;
wire [31:0] exe_final_result;
wire        exe_wait;
wire [31:0] wb_final_result;
wire [31:0] csr_rvalue;
wire [31:0] csr_eentry;
wire [31:0] csr_era;
wire        wb_ex;
wire        ertn_flush;
wire        csr_we;
assign wb_ex      = wb_valid && wb_ex_flag;
assign ertn_flush = wb_valid && wb_ertn;
assign csr_we     = wb_valid && wb_csr_we;
assign id_csr_rvalue = csr_rvalue;
assign rf_raddr1 = rj;
assign rf_raddr2 = id_src_reg_is_rd ? rd : rk;
regfile u_regfile(
    .clk(clk), .raddr1(rf_raddr1), .rdata1(rf_rdata1),
    .raddr2(rf_raddr2), .rdata2(rf_rdata2),
    .we(rf_we), .waddr(rf_waddr), .wdata(rf_wdata)
);

csr u_csr(
    .clk(clk),
    .reset(reset),
    .csr_num(id_csr_num),
    .csr_rvalue(csr_rvalue),
    .csr_we(csr_we),
    .csr_w_num(wb_csr_num),
    .csr_wmask(wb_csr_wmask),
    .csr_wvalue(wb_csr_wvalue),
    .wb_ex(wb_ex),
    .wb_ex_pc(wb_pc),
    .wb_ecode(wb_ecode),
    .wb_esubcode(wb_esubcode),
    .ertn_flush(ertn_flush),
    .ex_entry(csr_eentry),
    .era_value(csr_era)
);

/*
Forwarding unit
*/
// Forward completed results back to the decode stage.  The newest producer
// has priority: EXE, then MEM, then WB, and finally the register file.
wire [31:0] exe_forward_value;
wire [31:0] mem_forward_value;
wire [31:0] wb_forward_value;
assign exe_forward_value = exe_final_result;
assign mem_forward_value = mem_csr_read ? mem_csr_rvalue :
                           mem_res_from_mem ? mem_result : mem_alu_result;
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
Stalling unit: load-use bubble and multi-cycle division backpressure
*/
wire exe_load_use_hazard;
wire id_csr_hazard;
wire id_ertn_hazard;
wire id_stall;
assign exe_load_use_hazard = exe_valid && exe_gr_we && exe_res_from_mem &&
                             (exe_dest != 5'd0) &&
                             ((id_rj_used  && (rj        == exe_dest)) ||
                              (id_rkd_used && (rf_raddr2 == exe_dest)));
assign id_csr_hazard = id_valid && id_csr_read &&
                       ((exe_valid && exe_csr_we && (exe_csr_num == id_csr_num)) ||
                        (mem_valid && mem_csr_we && (mem_csr_num == id_csr_num)) ||
                        (wb_valid  && wb_csr_we  && (wb_csr_num  == id_csr_num)));
assign id_ertn_hazard = id_valid && id_ertn &&
                       ((exe_valid && exe_csr_we &&
                         ((exe_csr_num == 14'h0001) || (exe_csr_num == 14'h0006))) ||
                        (mem_valid && mem_csr_we &&
                         ((mem_csr_num == 14'h0001) || (mem_csr_num == 14'h0006))) ||
                        (wb_valid  && wb_csr_we  &&
                         ((wb_csr_num == 14'h0001) || (wb_csr_num == 14'h0006))));
assign id_stall = exe_wait || (id_valid && exe_load_use_hazard) ||
                   id_csr_hazard || id_ertn_hazard;

assign id_br_taken  = id_valid && !id_stall && ((inst_beq && id_rj_eq_rkd) ||
                                   (inst_bne && !id_rj_eq_rkd) ||
                                    inst_jirl || inst_bl || inst_b);
assign id_br_target = (inst_beq || inst_bne || inst_bl || inst_b) ?
                      (id_pc + id_br_offs) : (id_rj_value + id_jirl_offs);

// One signed 33x33 multiplier supports both signed and unsigned high words.
wire signed [32:0] mul_a = {exe_md_op[1] & exe_alu_src1[31], exe_alu_src1};
wire signed [32:0] mul_b = {exe_md_op[1] & exe_alu_src2[31], exe_alu_src2};
wire signed [65:0] mul_product = mul_a * mul_b;

/*
Divider module
*/
wire exe_is_div = |exe_md_op[6:3];
wire exe_div_signed = exe_md_op[3] | exe_md_op[4];
reg div_busy, div_done;
reg [5:0] div_count;
reg [31:0] div_quot, div_rem, div_den;
reg div_neg_quot, div_neg_rem;
wire [32:0] div_shift = {div_rem, div_quot[31]};
wire [32:0] div_diff = div_shift - {1'b0, div_den};
wire [31:0] div_next_rem = div_diff[32] ? div_shift[31:0] : div_diff[31:0];
wire [31:0] div_next_quot = {div_quot[30:0], !div_diff[32]};
wire [31:0] div_result = (exe_md_op[4] | exe_md_op[6]) ? div_rem : div_quot;
assign exe_wait = exe_valid && exe_is_div && !div_done;
assign exe_final_result =
    exe_csr_read ? exe_csr_rvalue :
    exe_md_op[0] ? mul_product[31:0] :
    (exe_md_op[1] | exe_md_op[2]) ? mul_product[63:32] :
    exe_is_div ? div_result : exe_alu_result;

// Restoring division: 32 iterations on magnitudes, followed by sign correction.
// Hold IF/ID/EXE while busy; older MEM/WB instructions continue to retire.
always @(posedge clk) begin
    if (reset) begin
        div_busy <= 1'b0;
        div_done <= 1'b0;
        div_count <= 6'b0;
        div_quot <= 32'b0;
        div_rem <= 32'b0;
        div_den <= 32'b0;
        div_neg_quot <= 1'b0;
        div_neg_rem <= 1'b0;
    end else if (div_busy) begin
        div_count <= div_count + 1'b1;
        if (div_count == 6'd31) begin
            div_quot <= div_neg_quot ? (~div_next_quot + 32'd1) : div_next_quot;
            div_rem <= div_neg_rem ? (~div_next_rem + 32'd1) : div_next_rem;
            div_busy <= 1'b0;
            div_done <= 1'b1;
        end else begin
            div_quot <= div_next_quot;
            div_rem <= div_next_rem;
        end
    end else begin
        div_done <= 1'b0;
        if (exe_valid && exe_is_div && !div_done) begin
            div_busy <= 1'b1;
            div_count <= 6'b0;
            div_rem <= 32'b0;
            div_quot <= (exe_div_signed && exe_alu_src1[31]) ?
                        (~exe_alu_src1 + 32'd1) : exe_alu_src1;
            div_den <= (exe_div_signed && exe_alu_src2[31]) ?
                       (~exe_alu_src2 + 32'd1) : exe_alu_src2;
            div_neg_quot <= exe_div_signed && (exe_alu_src1[31] ^ exe_alu_src2[31]);
            div_neg_rem <= exe_div_signed && exe_alu_src1[31];
        end
    end
end

// EXE stage and its SRAM request.
alu u_alu(
    .alu_op(exe_alu_op), .alu_src1(exe_alu_src1),
    .alu_src2(exe_alu_src2), .alu_result(exe_alu_result)
);
assign inst_sram_en    = if_valid && !id_stall && !wb_ex && !ertn_flush;
assign inst_sram_we    = 4'b0000;
assign inst_sram_addr  = if_pc;
assign inst_sram_wdata = 32'b0;
assign data_sram_en    = exe_valid && !exe_ex && !mem_ex && !wb_ex &&
                         (exe_mem_we || exe_res_from_mem);
assign data_sram_we    = (exe_valid && exe_mem_we && !exe_ex && !mem_ex && !wb_ex) ?
                         (exe_store_type[1] ? 4'b1111 :
                          exe_store_type[0] ? 4'b0011 << exe_alu_result[1:0] :
                                              4'b0001 << exe_alu_result[1:0])
                         : 4'b0000;
assign data_sram_addr  = exe_alu_result;
assign data_sram_wdata = exe_store_data << {exe_alu_result[1:0], 3'b000};

assign mem_load_shifted = data_sram_rdata >> {mem_alu_result[1:0], 3'b000};
assign mem_result = mem_load_type[1] ? data_sram_rdata :
                    mem_load_type[0] ? {{16{mem_load_shifted[15] & ~mem_load_type[2]}}, mem_load_shifted[15:0]} :
                                       {{24{mem_load_shifted[ 7] & ~mem_load_type[2]}}, mem_load_shifted[ 7:0]};

/*
Control hazard: result comes from EX stage, thus stall pipeline until the result is valid
*/
assign id_ex_will_branch = id_valid && 
                           (inst_blt | inst_bge | inst_bltu | inst_bgeu);
assign exe_br_taken  = exe_valid && exe_may_branch && 
                      (exe_br_cond_is_ge ^ exe_alu_result[0]);
assign exe_br_target = exe_pc + exe_br_offs;
/*
CPU pipeline: IF->ID->EX->MEM->WB
*/
// A load-use hazard injects an EXE bubble; division holds IF/ID/EXE.
// In both cases MEM/WB continue to advance, without retiring EXE twice.
always @(posedge clk) begin
    if (reset) begin
        if_valid  <= 1'b0;
        if_pc     <= 32'h1bfffffc;
        if_resp_valid <= 1'b0;
        id_valid  <= 1'b0;
        exe_valid <= 1'b0;
        exe_md_op <= 7'b0;
        mem_valid <= 1'b0;
        wb_valid  <= 1'b0;
        exe_csr_read <= 1'b0;
        exe_csr_we <= 1'b0;
        exe_csr_num <= 14'b0;
        exe_csr_rvalue <= 32'b0;
        exe_csr_wvalue <= 32'b0;
        exe_csr_wmask <= 32'b0;
        exe_ex <= 1'b0;
        exe_ecode <= 6'b0;
        exe_esubcode <= 9'b0;
        exe_ertn <= 1'b0;
        mem_csr_read <= 1'b0;
        mem_csr_we <= 1'b0;
        mem_csr_num <= 14'b0;
        mem_csr_rvalue <= 32'b0;
        mem_csr_wvalue <= 32'b0;
        mem_csr_wmask <= 32'b0;
        mem_ex <= 1'b0;
        mem_ecode <= 6'b0;
        mem_esubcode <= 9'b0;
        mem_ertn <= 1'b0;
        wb_csr_read <= 1'b0;
        wb_csr_we <= 1'b0;
        wb_csr_num <= 14'b0;
        wb_csr_rvalue <= 32'b0;
        wb_csr_wvalue <= 32'b0;
        wb_csr_wmask <= 32'b0;
        wb_ex_flag <= 1'b0;
        wb_ecode <= 6'b0;
        wb_esubcode <= 9'b0;
        wb_ertn <= 1'b0;
    end
    else if (wb_ex || ertn_flush) begin
        // An exception/ERTN commits at WB and discards all younger stages.
        if_valid      <= 1'b1;
        if_pc         <= wb_ex ? csr_eentry : csr_era;
        if_resp_valid <= 1'b0;
        if_resp_pc    <= 32'b0;
        id_valid      <= 1'b0;
        exe_valid     <= 1'b0;
        mem_valid     <= 1'b0;
        wb_valid      <= 1'b0;
        exe_csr_read  <= 1'b0;
        exe_csr_we    <= 1'b0;
        exe_ex        <= 1'b0;
        exe_ertn      <= 1'b0;
        mem_csr_read  <= 1'b0;
        mem_csr_we    <= 1'b0;
        mem_ex        <= 1'b0;
        mem_ertn      <= 1'b0;
        wb_csr_read   <= 1'b0;
        wb_csr_we     <= 1'b0;
        wb_ex_flag    <= 1'b0;
        wb_ertn       <= 1'b0;
    end
    else begin
        if (!id_stall) begin
            if_valid <= 1'b1;
            if_pc    <= if_nextpc;

            if (id_br_taken | id_ex_will_branch | exe_br_taken) begin
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

        if (!exe_wait) begin
            if (id_stall) begin
                exe_md_op        <= 7'b0;
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
                exe_br_offs      <= 32'b0;
                exe_may_branch   <= 1'b0;
                exe_br_cond_is_ge <= 1'b0;
                exe_csr_read     <= 1'b0;
                exe_csr_we       <= 1'b0;
                exe_csr_num      <= 14'b0;
                exe_csr_rvalue   <= 32'b0;
                exe_csr_wvalue   <= 32'b0;
                exe_csr_wmask    <= 32'b0;
                exe_ex           <= 1'b0;
                exe_ecode        <= 6'b0;
                exe_esubcode     <= 9'b0;
                exe_ertn         <= 1'b0;
            end
            else begin
                exe_md_op        <= id_md_op;
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
                exe_br_offs      <= id_br_offs;
                exe_may_branch   <= id_ex_will_branch;
                exe_br_cond_is_ge <= inst_bge | inst_bgeu;
                exe_load_type    <= id_load_type;
                exe_store_type   <= id_store_type;
                exe_csr_read     <= id_valid && id_csr_read;
                exe_csr_we       <= id_valid && id_csr_we;
                exe_csr_num      <= id_valid ? id_csr_num : 14'b0;
                exe_csr_rvalue   <= id_valid ? id_csr_rvalue : 32'b0;
                exe_csr_wvalue   <= id_valid ? id_csr_wvalue : 32'b0;
                exe_csr_wmask    <= id_valid ? id_csr_wmask : 32'b0;
                exe_ex           <= id_valid && id_syscall;
                exe_ecode        <= (id_valid && id_syscall) ? 6'h0b : 6'b0;
                exe_esubcode     <= 9'b0;
                exe_ertn         <= id_valid && id_ertn;
            end

        end // !exe_wait

        mem_valid        <= exe_valid && !exe_wait;
        mem_pc           <= exe_pc;
        mem_alu_result   <= exe_final_result;
        mem_dest         <= exe_dest;
        mem_gr_we        <= exe_gr_we;
        mem_res_from_mem <= exe_res_from_mem;
        mem_load_type    <= exe_load_type;
        mem_csr_read     <= exe_csr_read;
        mem_csr_we       <= exe_csr_we;
        mem_csr_num      <= exe_csr_num;
        mem_csr_rvalue   <= exe_csr_rvalue;
        mem_csr_wvalue   <= exe_csr_wvalue;
        mem_csr_wmask    <= exe_csr_wmask;
        mem_ex           <= exe_ex;
        mem_ecode        <= exe_ecode;
        mem_esubcode     <= exe_esubcode;
        mem_ertn         <= exe_ertn;

        wb_valid        <= mem_valid;
        wb_pc           <= mem_pc;
        wb_alu_result   <= mem_alu_result;
        wb_mem_result   <= mem_result;
        wb_dest         <= mem_dest;
        wb_gr_we        <= mem_gr_we;
        wb_res_from_mem <= mem_res_from_mem;
        wb_csr_read     <= mem_csr_read;
        wb_csr_we       <= mem_csr_we;
        wb_csr_num      <= mem_csr_num;
        wb_csr_rvalue   <= mem_csr_rvalue;
        wb_csr_wvalue   <= mem_csr_wvalue;
        wb_csr_wmask    <= mem_csr_wmask;
        wb_ex_flag      <= mem_ex;
        wb_ecode        <= mem_ecode;
        wb_esubcode     <= mem_esubcode;
        wb_ertn         <= mem_ertn;
    end
end

// WB stage
assign wb_final_result   = wb_csr_read ? wb_csr_rvalue :
                           wb_res_from_mem ? wb_mem_result : wb_alu_result;
assign rf_we             = wb_valid && wb_gr_we;
assign rf_waddr          = wb_dest;
assign rf_wdata          = wb_final_result;
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_final_result;

endmodule
