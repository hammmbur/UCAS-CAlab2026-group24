module csr(
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  hw_int_in,

    input  wire [13:0] csr_num,
    output wire [31:0] csr_rvalue,
    input  wire        csr_we,
    input  wire [13:0] csr_w_num,
    input  wire [31:0] csr_wmask,
    input  wire [31:0] csr_wvalue,

    input wire [31:0] wb_badv, output wire has_int,
    input  wire        wb_ex,
    input  wire [31:0] wb_ex_pc,
    input  wire [ 5:0] wb_ecode,
    input  wire [ 8:0] wb_esubcode,
    input  wire        ertn_flush,

    output wire [31:0] ex_entry,
    output wire [31:0] era_value
);

localparam [13:0] CSR_CRMD   = 14'h0000;
localparam [13:0] CSR_PRMD   = 14'h0001;
localparam [13:0] CSR_ESTAT  = 14'h0005;
localparam [13:0] CSR_ERA    = 14'h0006;
localparam [13:0] CSR_EENTRY = 14'h000c;
localparam [13:0] CSR_SAVE0  = 14'h0030;
localparam [13:0] CSR_SAVE1  = 14'h0031;
localparam [13:0] CSR_SAVE2  = 14'h0032;
localparam [13:0] CSR_SAVE3  = 14'h0033;

reg [1:0]  crmd_plv;
reg        crmd_ie;
reg [1:0]  prmd_pplv;
reg        prmd_pie;
reg [12:0] estat_is;
reg [5:0]  estat_ecode;
reg [8:0]  estat_esubcode;
reg [31:0] era_pc;
reg [25:0] eentry_va;
reg [31:0] save0_data;
reg [31:0] save1_data;
reg [31:0] save2_data;
reg [31:0] save3_data;

wire [31:0] crmd_value = {23'b0, 2'b00, 2'b00, 1'b0, 1'b1,
                           crmd_ie, crmd_plv};
wire [31:0] prmd_value = {29'b0, prmd_pie, prmd_pplv};
wire [31:0] estat_value = {1'b0, estat_esubcode, estat_ecode,
                            3'b0, estat_is};
wire [31:0] eentry_value = {eentry_va, 6'b0};

reg [12:0] ecfg;
reg [31:0] badv, tid, tcfg, tval;
reg timer_en;
wire [31:0] tcfg_next = (tcfg & ~csr_wmask) | (csr_wvalue & csr_wmask);
// Hardware pending bits follow the input levels on every clock, including
// during exception entry, ERTN and CSR writes. Software cannot write them.
always @(posedge clk) begin
    if (reset) estat_is[9:2] <= 8'b0;
    else       estat_is[9:2] <= hw_int_in;
end
assign has_int = crmd_ie && (|(estat_is & ecfg));
always @(posedge clk) begin
    if (reset) begin
        ecfg <= 0; badv <= 0; tid <= 0; tcfg <= 0;
        tval <= 32'hffffffff; timer_en <= 0;
    end else begin
        if (wb_ex && (wb_ecode == 6'h08 || wb_ecode == 6'h09)) badv <= wb_badv;
        if (csr_we && csr_w_num == 14'h04)
            ecfg <= ((ecfg & ~csr_wmask[12:0]) | (csr_wvalue[12:0] & csr_wmask[12:0])) & 13'h1bff;
        if (csr_we && csr_w_num == 14'h40)
            tid <= (tid & ~csr_wmask) | (csr_wvalue & csr_wmask);
        if (csr_we && csr_w_num == 14'h41) begin
            tcfg <= tcfg_next;
            timer_en <= tcfg_next[0];
            if (tcfg_next[0]) tval <= {tcfg_next[31:2],2'b0};
        end else if (timer_en) begin
            if (tval == 0) begin
                tval <= tcfg[1] ? {tcfg[31:2],2'b0} : 32'hffffffff;
                timer_en <= tcfg[1];
            end else tval <= tval - 1'b1;
        end
    end
end
always @(posedge clk) begin
    if (reset) estat_is[11] <= 0;
    else if (timer_en && tval == 0) estat_is[11] <= 1;
    else if (csr_we && csr_w_num == 14'h44 && csr_wmask[0] && csr_wvalue[0])
        estat_is[11] <= 0;
end
assign csr_rvalue =
    ({32{csr_num == 14'h04}} & {19'b0,ecfg}) |
    ({32{csr_num == 14'h07}} & badv) |
    ({32{csr_num == 14'h40}} & tid) |
    ({32{csr_num == 14'h41}} & tcfg) |
    ({32{csr_num == 14'h42}} & tval) |
    ({32{csr_num == CSR_CRMD}}   & crmd_value) |
    ({32{csr_num == CSR_PRMD}}   & prmd_value) |
    ({32{csr_num == CSR_ESTAT}}  & estat_value) |
    ({32{csr_num == CSR_ERA}}    & era_pc) |
    ({32{csr_num == CSR_EENTRY}} & eentry_value) |
    ({32{csr_num == CSR_SAVE0}}  & save0_data) |
    ({32{csr_num == CSR_SAVE1}}  & save1_data) |
    ({32{csr_num == CSR_SAVE2}}  & save2_data) |
    ({32{csr_num == CSR_SAVE3}}  & save3_data);

assign ex_entry  = eentry_value;
assign era_value = era_pc;

always @(posedge clk) begin
    if (reset) begin
        crmd_plv      <= 2'b00;
        crmd_ie       <= 1'b0;
        prmd_pplv     <= 2'b00;
        prmd_pie      <= 1'b0;
        estat_is[1:0] <= 0; estat_is[10] <= 0; estat_is[12] <= 0;
        estat_ecode   <= 6'b0;
        estat_esubcode<= 9'b0;
        era_pc        <= 32'b0;
        eentry_va     <= 26'b0;
        save0_data    <= 32'b0;
        save1_data    <= 32'b0;
        save2_data    <= 32'b0;
        save3_data    <= 32'b0;
    end
    else if (wb_ex) begin
        // Exception entry saves the old execution mode before entering PLV0.
        prmd_pplv      <= crmd_plv;
        prmd_pie       <= crmd_ie;
        crmd_plv       <= 2'b00;
        crmd_ie        <= 1'b0;
        era_pc         <= wb_ex_pc;
        estat_ecode    <= wb_ecode;
        estat_esubcode <= wb_esubcode;
    end
    else if (ertn_flush) begin
        crmd_plv <= prmd_pplv;
        crmd_ie  <= prmd_pie;
    end
    else if (csr_we) begin
        case (csr_w_num)
            CSR_CRMD: begin
                crmd_plv <= (csr_wmask[1:0] & csr_wvalue[1:0]) |
                            (~csr_wmask[1:0] & crmd_plv);
                crmd_ie  <= csr_wmask[2] ? csr_wvalue[2] : crmd_ie;
            end
            CSR_PRMD: begin
                prmd_pplv <= (csr_wmask[1:0] & csr_wvalue[1:0]) |
                             (~csr_wmask[1:0] & prmd_pplv);
                prmd_pie  <= csr_wmask[2] ? csr_wvalue[2] : prmd_pie;
            end
            CSR_ESTAT: begin
                // Only the software interrupt bits are writable in this task.
                estat_is[1:0] <= (csr_wmask[1:0] & csr_wvalue[1:0]) |
                                 (~csr_wmask[1:0] & estat_is[1:0]);
            end
            CSR_ERA: begin
                era_pc <= (csr_wmask & csr_wvalue) |
                          (~csr_wmask & era_pc);
            end
            CSR_EENTRY: begin
                eentry_va <= (csr_wmask[31:6] & csr_wvalue[31:6]) |
                             (~csr_wmask[31:6] & eentry_va);
            end
            CSR_SAVE0: begin
                save0_data <= (csr_wmask & csr_wvalue) |
                              (~csr_wmask & save0_data);
            end
            CSR_SAVE1: begin
                save1_data <= (csr_wmask & csr_wvalue) |
                              (~csr_wmask & save1_data);
            end
            CSR_SAVE2: begin
                save2_data <= (csr_wmask & csr_wvalue) |
                              (~csr_wmask & save2_data);
            end
            CSR_SAVE3: begin
                save3_data <= (csr_wmask & csr_wvalue) |
                              (~csr_wmask & save3_data);
            end
            default: begin
            end
        endcase
    end
end

endmodule


