`timescale 1ns / 1ps

module sram_axi_bridge(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        inst_req,
    input  wire        inst_wr,
    input  wire [ 1:0] inst_size,
    input  wire [ 3:0] inst_wstrb,
    input  wire [31:0] inst_addr,
    input  wire [31:0] inst_wdata,
    output wire [31:0] inst_rdata,
    output wire        inst_addr_ok,
    output wire        inst_data_ok,
    input  wire        data_req,
    input  wire        data_wr,
    input  wire [ 1:0] data_size,
    input  wire [ 3:0] data_wstrb,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_wdata,
    output wire [31:0] data_rdata,
    output wire        data_addr_ok,
    output wire        data_data_ok,
    output wire [ 3:0] arid,
    output wire [31:0] araddr,
    output wire [ 7:0] arlen,
    output wire [ 2:0] arsize,
    output wire [ 1:0] arburst,
    output wire [ 1:0] arlock,
    output wire [ 3:0] arcache,
    output wire [ 2:0] arprot,
    output wire        arvalid,
    input  wire        arready,
    input  wire [ 3:0] rid,
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,
    output wire [ 3:0] awid,
    output wire [31:0] awaddr,
    output wire [ 7:0] awlen,
    output wire [ 2:0] awsize,
    output wire [ 1:0] awburst,
    output wire [ 1:0] awlock,
    output wire [ 3:0] awcache,
    output wire [ 2:0] awprot,
    output wire        awvalid,
    input  wire        awready,
    output wire [ 3:0] wid,
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    input  wire [ 3:0] bid,
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready
);

localparam [2:0] IDLE       = 3'd0;
localparam [2:0] READ_ADDR  = 3'd1;
localparam [2:0] READ_DATA  = 3'd2;
localparam [2:0] READ_RESP  = 3'd3;
localparam [2:0] WRITE_SEND = 3'd4;
localparam [2:0] WRITE_WAIT = 3'd5;
localparam [2:0] WRITE_RESP = 3'd6;

reg [2:0] state;
reg       from_data;
reg [31:0] req_addr;
reg [ 1:0] req_size;
reg [31:0] req_wdata;
reg [ 3:0] req_wstrb;
reg [31:0] read_buffer;
reg       aw_done;
reg       w_done;
reg       addr_ack;

wire aw_fire = awvalid && awready;
wire w_fire  = wvalid && wready;

// One complete transaction at a time also orders every read after a write
// response, including instruction fetches that could observe modified memory.
always @(posedge aclk) begin
    if (!aresetn) begin
        state       <= IDLE;
        from_data   <= 1'b0;
        req_addr    <= 32'b0;
        req_size    <= 2'b0;
        req_wdata   <= 32'b0;
        req_wstrb   <= 4'b0;
        read_buffer <= 32'b0;
        aw_done     <= 1'b0;
        w_done      <= 1'b0;
        addr_ack    <= 1'b0;
    end else begin
        addr_ack <= 1'b0;
        case (state)
            IDLE: begin
                if (data_req) begin
                    from_data <= 1'b1;
                    req_addr  <= data_addr;
                    req_size  <= data_size;
                    req_wdata <= data_wdata;
                    req_wstrb <= data_wstrb;
                    aw_done   <= 1'b0;
                    w_done    <= 1'b0;
                    state     <= data_wr ? WRITE_SEND : READ_ADDR;
                end else if (inst_req && !inst_wr) begin
                    from_data <= 1'b0;
                    req_addr  <= inst_addr;
                    req_size  <= inst_size;
                    state     <= READ_ADDR;
                end
            end
            READ_ADDR: begin
                if (arvalid && arready) begin
                    addr_ack <= 1'b1;
                    state <= READ_DATA;
                end
            end
            READ_DATA: begin
                if (rvalid && rready) begin
                    read_buffer <= rdata;
                    state <= READ_RESP;
                end
            end
            READ_RESP: state <= IDLE;
            WRITE_SEND: begin
                if (aw_fire) aw_done <= 1'b1;
                if (w_fire)  w_done  <= 1'b1;
                if ((aw_done || aw_fire) && (w_done || w_fire)) begin
                    addr_ack <= 1'b1;
                    state <= WRITE_WAIT;
                end
            end
            WRITE_WAIT: begin
                if (bvalid && bready) state <= WRITE_RESP;
            end
            WRITE_RESP: state <= IDLE;
            default: state <= IDLE;
        endcase
    end
end

assign inst_addr_ok = aresetn && addr_ack && !from_data;
assign data_addr_ok = aresetn && addr_ack && from_data;
assign inst_data_ok = aresetn && (state == READ_RESP) && !from_data;
assign data_data_ok = aresetn && from_data &&
                      ((state == READ_RESP) || (state == WRITE_RESP));
assign inst_rdata = read_buffer;
assign data_rdata = read_buffer;

assign arid    = from_data ? 4'd1 : 4'd0;
assign araddr  = req_addr;
assign arlen   = 8'd0;
assign arsize  = {1'b0, req_size};
assign arburst = 2'b01;
assign arlock  = 2'b00;
assign arcache = 4'b0000;
assign arprot  = 3'b000;
assign arvalid = aresetn && (state == READ_ADDR);
assign rready  = aresetn && (state == READ_DATA);

assign awid    = 4'd1;
assign awaddr  = req_addr;
assign awlen   = 8'd0;
assign awsize  = {1'b0, req_size};
assign awburst = 2'b01;
assign awlock  = 2'b00;
assign awcache = 4'b0000;
assign awprot  = 3'b000;
assign awvalid = aresetn && (state == WRITE_SEND) && !aw_done;
assign wid     = 4'd1;
assign wdata   = req_wdata;
assign wstrb   = req_wstrb;
assign wlast   = 1'b1;
assign wvalid  = aresetn && (state == WRITE_SEND) && !w_done;
assign bready  = aresetn && (state == WRITE_WAIT);

endmodule
