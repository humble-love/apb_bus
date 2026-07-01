// tb_top.sv — 8x8 NOC mesh testbench top
`timescale 1ns/1ps

module tb_top;
  import uvm_pkg::*;
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  `include "uvm_macros.svh"

  // Clock and reset
  logic clk;
  logic rst_n;

  localparam int N_TILES = MESH_Y * MESH_X;

  // 64 AXI interfaces — 1D array (VCS 2018: no 2D interface arrays)
  noc_axi_if #(.DATA_W(DATA_W)) axi_if [0:N_TILES-1] (.clk, .rst_n);

  // Intermediate 2D wires for connecting 1D interfaces → 2D DUT ports
  logic [MESH_Y-1:0][MESH_X-1:0]        awvalid_w, awready_w;
  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  awaddr_w;
  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   awid_w, awlen_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awburst_w;
  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awsize_w, awlock_w, awqos_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awcache_w;

  logic [MESH_Y-1:0][MESH_X-1:0]        wvalid_w, wready_w;
  logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] wdata_w;
  logic [MESH_Y-1:0][MESH_X-1:0][(DATA_W/8)-1:0] wstrb_w;
  logic [MESH_Y-1:0][MESH_X-1:0]        wlast_w;

  logic [MESH_Y-1:0][MESH_X-1:0]        bvalid_w, bready_w;
  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   bid_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   bresp_w;

  logic [MESH_Y-1:0][MESH_X-1:0]        arvalid_w, arready_w;
  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  araddr_w;
  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   arid_w, arlen_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arburst_w;
  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arsize_w, arlock_w, arqos_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arcache_w;

  logic [MESH_Y-1:0][MESH_X-1:0]        rvalid_w, rready_w;
  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   rid_w;
  logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] rdata_w;
  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   rresp_w;
  logic [MESH_Y-1:0][MESH_X-1:0]        rlast_w;

  // DUT instantiation — connect via 2D wire arrays
  mesh_8x8 #(
    .MESH_X(MESH_X), .MESH_Y(MESH_Y),
    .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
    .DATA_W(DATA_W), .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS),
    .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
  ) dut (
    .clk, .rst_n,
    .awvalid(awvalid_w), .awready(awready_w), .awaddr(awaddr_w),
    .awid(awid_w), .awlen(awlen_w), .awburst(awburst_w),
    .awsize(awsize_w), .awlock(awlock_w), .awcache(awcache_w), .awqos(awqos_w),
    .wvalid(wvalid_w), .wready(wready_w), .wdata(wdata_w),
    .wstrb(wstrb_w), .wlast(wlast_w),
    .bvalid(bvalid_w), .bready(bready_w), .bid(bid_w), .bresp(bresp_w),
    .arvalid(arvalid_w), .arready(arready_w), .araddr(araddr_w),
    .arid(arid_w), .arlen(arlen_w), .arburst(arburst_w),
    .arsize(arsize_w), .arlock(arlock_w), .arcache(arcache_w), .arqos(arqos_w),
    .rvalid(rvalid_w), .rready(rready_w), .rid(rid_w),
    .rdata(rdata_w), .rresp(rresp_w), .rlast(rlast_w)
  );

  // Clock generation — 500 MHz -> 2 ns period
  initial clk = 0;
  always #1 clk = ~clk;

  // Reset
  initial begin
    rst_n = 0;
    #10 rst_n = 1;
  end

  // Connect 1D interfaces ↔ 2D wire arrays (IDX = y*MESH_X + x)
  genvar x, y;
  generate
    for (y = 0; y < MESH_Y; y++) begin : y_gen
      for (x = 0; x < MESH_X; x++) begin : x_gen
        localparam int IDX = y * MESH_X + x;

        // Default: tie off unused AXI inputs for tiles without BFM
        if (IDX != 0) begin : tie_off
          assign axi_if[IDX].bready  = 1'b1;
          assign axi_if[IDX].rready  = 1'b1;
          assign axi_if[IDX].awvalid = 1'b0;
          assign axi_if[IDX].wvalid  = 1'b0;
          assign axi_if[IDX].arvalid = 1'b0;
        end

        // AW channel
        assign awvalid_w[y][x] = axi_if[IDX].awvalid;
        assign axi_if[IDX].awready = awready_w[y][x];
        assign awaddr_w[y][x]  = axi_if[IDX].awaddr;
        assign awid_w[y][x]    = axi_if[IDX].awid;
        assign awlen_w[y][x]   = axi_if[IDX].awlen;
        assign awburst_w[y][x] = axi_if[IDX].awburst;
        assign awsize_w[y][x]  = axi_if[IDX].awsize;
        assign awlock_w[y][x]  = axi_if[IDX].awlock;
        assign awcache_w[y][x] = axi_if[IDX].awcache;
        assign awqos_w[y][x]   = axi_if[IDX].awqos;

        // W channel
        assign wvalid_w[y][x] = axi_if[IDX].wvalid;
        assign axi_if[IDX].wready = wready_w[y][x];
        assign wdata_w[y][x]  = axi_if[IDX].wdata;
        assign wstrb_w[y][x]  = axi_if[IDX].wstrb;
        assign wlast_w[y][x]  = axi_if[IDX].wlast;

        // B channel
        assign axi_if[IDX].bvalid = bvalid_w[y][x];
        assign bready_w[y][x] = axi_if[IDX].bready;
        assign axi_if[IDX].bid   = bid_w[y][x];
        assign axi_if[IDX].bresp = bresp_w[y][x];

        // AR channel
        assign arvalid_w[y][x] = axi_if[IDX].arvalid;
        assign axi_if[IDX].arready = arready_w[y][x];
        assign araddr_w[y][x]  = axi_if[IDX].araddr;
        assign arid_w[y][x]    = axi_if[IDX].arid;
        assign arlen_w[y][x]   = axi_if[IDX].arlen;
        assign arburst_w[y][x] = axi_if[IDX].arburst;
        assign arsize_w[y][x]  = axi_if[IDX].arsize;
        assign arlock_w[y][x]  = axi_if[IDX].arlock;
        assign arcache_w[y][x] = axi_if[IDX].arcache;
        assign arqos_w[y][x]   = axi_if[IDX].arqos;

        // R channel
        assign axi_if[IDX].rvalid = rvalid_w[y][x];
        assign rready_w[y][x] = axi_if[IDX].rready;
        assign axi_if[IDX].rid   = rid_w[y][x];
        assign axi_if[IDX].rdata = rdata_w[y][x];
        assign axi_if[IDX].rresp = rresp_w[y][x];
        assign axi_if[IDX].rlast = rlast_w[y][x];
      end
    end
  endgenerate

  // UVM
  initial begin
    uvm_config_db #(virtual noc_axi_if)::set(null, "*", "axi_vif", axi_if[0]);
    run_test();
  end

  // Waveform dump
  initial begin
    $fsdbDumpfile("waves/noc.fsdb");
    $fsdbDumpvars(0, tb_top);
  end
endmodule
