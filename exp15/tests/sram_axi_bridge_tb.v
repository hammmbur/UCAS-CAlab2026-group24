`timescale 1ns / 1ps

module sram_axi_bridge_tb;
reg clk = 0;
always #5 clk = ~clk;
reg resetn = 0;
reg inst_req = 0;
reg inst_wr = 0;
reg [1:0] inst_size = 2;
reg [3:0] inst_wstrb = 0;
reg [31:0] inst_addr = 0;
reg [31:0] inst_wdata = 0;
wire [31:0] inst_rdata;
wire inst_addr_ok, inst_data_ok;
reg data_req = 0;
reg data_wr = 0;
reg [1:0] data_size = 0;
reg [3:0] data_wstrb = 0;
reg [31:0] data_addr = 0;
reg [31:0] data_wdata = 0;
wire [31:0] data_rdata;
wire data_addr_ok, data_data_ok;
wire [3:0] arid, awid, wid;
wire [31:0] araddr, awaddr, wdata;
wire [7:0] arlen, awlen;
wire [2:0] arsize, awsize, arprot, awprot;
wire [1:0] arburst, arlock, awburst, awlock;
wire [3:0] arcache, awcache, wstrb;
wire arvalid, rready, awvalid, wlast, wvalid, bready;
reg arready = 0;
reg [3:0] rid = 0;
reg [31:0] rdata = 0;
reg [1:0] rresp = 0;
reg rlast = 1;
reg rvalid = 0;
reg awready = 0;
reg wready = 0;
reg [3:0] bid = 1;
reg [1:0] bresp = 0;
reg bvalid = 0;
integer ar_count = 0;
integer aw_count = 0;
integer w_count = 0;

sram_axi_bridge dut(
    .aclk(clk), .aresetn(resetn),
    .inst_req(inst_req), .inst_wr(inst_wr), .inst_size(inst_size),
    .inst_wstrb(inst_wstrb), .inst_addr(inst_addr), .inst_wdata(inst_wdata),
    .inst_rdata(inst_rdata), .inst_addr_ok(inst_addr_ok),
    .inst_data_ok(inst_data_ok),
    .data_req(data_req), .data_wr(data_wr), .data_size(data_size),
    .data_wstrb(data_wstrb), .data_addr(data_addr), .data_wdata(data_wdata),
    .data_rdata(data_rdata), .data_addr_ok(data_addr_ok),
    .data_data_ok(data_data_ok),
    .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
    .arburst(arburst), .arlock(arlock), .arcache(arcache),
    .arprot(arprot), .arvalid(arvalid), .arready(arready),
    .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
    .rvalid(rvalid), .rready(rready),
    .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
    .awburst(awburst), .awlock(awlock), .awcache(awcache),
    .awprot(awprot), .awvalid(awvalid), .awready(awready),
    .wid(wid), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .wvalid(wvalid), .wready(wready),
    .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
);

always @(posedge clk) if (resetn) begin
    if (arvalid && arready) ar_count = ar_count + 1;
    if (awvalid && awready) aw_count = aw_count + 1;
    if (wvalid && wready) w_count = w_count + 1;
end

task step;
    begin @(posedge clk); #1; end
endtask

task check;
    input condition;
    input [255:0] message;
    begin
        if (condition !== 1'b1) begin
            $fatal(1, "FAIL: %0s at %0t", message, $time);
        end
    end
endtask

initial begin
    step;
    check(!arvalid && !awvalid && !wvalid && !rready && !bready,
          "reset bus outputs");
    @(negedge clk);
    resetn = 1;
    inst_req = 1;
    inst_addr = 32'h1c000000;
    data_req = 1;
    data_wr = 1;
    data_size = 2;
    data_addr = 32'h10000000;
    data_wstrb = 4'hf;
    data_wdata = 32'h12345678;
    step;
    check(awvalid && wvalid && !arvalid && awaddr == data_addr &&
          wdata == data_wdata && wstrb == 4'hf && awsize == 2,
          "data write wins arbitration");
    @(negedge clk); awready = 1;
    step;
    check(!awvalid && wvalid && !data_addr_ok,
          "AW accepted before W");
    @(negedge clk); awready = 0; wready = 1;
    step;
    check(!awvalid && !wvalid && data_addr_ok && !arvalid,
          "write addr_ok only after AW and W");
    @(negedge clk); data_req = 0; wready = 0;
    step;
    check(!arvalid && !data_data_ok && bready,
          "read waits for write response");
    @(negedge clk); bvalid = 1;
    step;
    check(data_data_ok && !inst_data_ok && !arvalid,
          "write data_ok after B");
    @(negedge clk); bvalid = 0;
    step;
    step;
    check(arvalid && arid == 0 && araddr == inst_addr && arsize == 2,
          "instruction read starts after write");
    @(negedge clk); arready = 1;
    step;
    check(inst_addr_ok && !data_addr_ok && rready && !arvalid,
          "instruction address acknowledged once");
    @(negedge clk); inst_req = 0; arready = 0;
    rid = 0; rdata = 32'hdeadbeef; rvalid = 1;
    step;
    check(inst_data_ok && inst_rdata == 32'hdeadbeef && !data_data_ok,
          "instruction response buffered and routed");
    @(negedge clk); rvalid = 0;
    step;
    @(negedge clk);
    data_req = 1;
    data_wr = 0;
    data_size = 0;
    data_addr = 32'h10000003;
    step;
    check(arvalid && arid == 1 && arsize == 0 && araddr == data_addr,
          "byte load request");
    @(negedge clk); arready = 1;
    step;
    check(data_addr_ok && !inst_addr_ok, "load addr_ok");
    @(negedge clk); data_req = 0; arready = 0;
    rid = 1; rdata = 32'h44332211; rvalid = 1;
    step;
    check(data_data_ok && data_rdata == 32'h44332211 && !inst_data_ok,
          "load response routed");
    @(negedge clk); rvalid = 0;
    step;
    @(negedge clk);
    data_req = 1; data_wr = 1; data_size = 1;
    data_addr = 32'h10000002; data_wstrb = 4'b1100;
    data_wdata = 32'habcd0000;
    step;
    check(awvalid && wvalid && awsize == 1 && wstrb == 4'b1100,
          "halfword write request");
    @(negedge clk); wready = 1;
    step;
    check(awvalid && !wvalid && !data_addr_ok,
          "W accepted before AW");
    @(negedge clk); wready = 0; awready = 1;
    step;
    check(data_addr_ok && !awvalid && !wvalid,
          "second write addr_ok");
    @(negedge clk); data_req = 0; awready = 0; bvalid = 1;
    step;
    check(data_data_ok, "second write response");
    @(negedge clk); bvalid = 0;
    step;
    check(ar_count == 2 && aw_count == 2 && w_count == 2,
          "exactly one AXI transaction per SRAM request");
    $display("PASS: sram_axi_bridge_tb");
    $finish;
end
endmodule
