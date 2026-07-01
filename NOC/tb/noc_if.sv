// noc_if.sv — NOC AXI4 interface for UVM
interface noc_axi_if #(
  parameter int DATA_W = 512
) (
  input logic clk,
  input logic rst_n
);
  // AXI4 Master signals
  logic        awvalid, awready;
  logic [31:0] awaddr;
  logic [7:0]  awid, awlen;
  logic [1:0]  awburst;
  logic [3:0]  awsize, awlock, awqos;
  logic [1:0]  awcache;
  logic        wvalid, wready;
  logic [DATA_W-1:0] wdata;
  logic [(DATA_W/8)-1:0] wstrb;
  logic        wlast;
  logic        bvalid, bready;
  logic [7:0]  bid;
  logic [1:0]  bresp;
  logic        arvalid, arready;
  logic [31:0] araddr;
  logic [7:0]  arid, arlen;
  logic [1:0]  arburst;
  logic [3:0]  arsize, arlock, arqos;
  logic [1:0]  arcache;
  logic        rvalid, rready;
  logic [7:0]  rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]  rresp;
  logic        rlast;

  modport master (
    output awvalid, awaddr, awid, awlen, awburst, awsize, awlock, awcache, awqos,
    input  awready,
    output wvalid, wdata, wstrb, wlast, input wready,
    input  bvalid, output bready, input bid, bresp,
    output arvalid, araddr, arid, arlen, arburst, arsize, arlock, arcache, arqos,
    input  arready,
    input  rvalid, output rready, input rid, rdata, rresp, rlast
  );

  modport slave (
    input  awvalid, awaddr, awid, awlen, awburst, awsize, awlock, awcache, awqos,
    output awready,
    input  wvalid, wdata, wstrb, wlast, output wready,
    output bvalid, input bready, output bid, bresp,
    input  arvalid, araddr, arid, arlen, arburst, arsize, arlock, arcache, arqos,
    output arready,
    output rvalid, input rready, output rid, rdata, rresp, rlast
  );
endinterface
