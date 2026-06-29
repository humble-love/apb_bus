// AXI4-Full Interface with clocking blocks for UVM driver/monitor

interface axi_if #(
    parameter int DATA_W = 256,
    parameter int ADDR_W = 32,
    parameter int ID_W   = 8
) (
    input logic aclk,
    input logic aresetn
);
    // ========================================================
    // Write Address Channel (AW)
    // ========================================================
    logic [ID_W-1:0]     awid;
    logic [ADDR_W-1:0]   awaddr;
    logic [7:0]          awlen;
    logic [2:0]          awsize;
    logic [1:0]          awburst;
    logic                awlock;
    logic [3:0]          awcache;
    logic [2:0]          awprot;
    logic [3:0]          awqos;
    logic                awvalid;
    logic                awready;

    // ========================================================
    // Write Data Channel (W)
    // ========================================================
    logic [DATA_W-1:0]   wdata;
    logic [DATA_W/8-1:0] wstrb;
    logic                wlast;
    logic                wvalid;
    logic                wready;

    // ========================================================
    // Write Response Channel (B)
    // ========================================================
    logic [ID_W-1:0]     bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    // ========================================================
    // Read Address Channel (AR)
    // ========================================================
    logic [ID_W-1:0]     arid;
    logic [ADDR_W-1:0]   araddr;
    logic [7:0]          arlen;
    logic [2:0]          arsize;
    logic [1:0]          arburst;
    logic                arlock;
    logic [3:0]          arcache;
    logic [2:0]          arprot;
    logic [3:0]          arqos;
    logic                arvalid;
    logic                arready;

    // ========================================================
    // Read Data Channel (R)
    // ========================================================
    logic [ID_W-1:0]     rid;
    logic [DATA_W-1:0]   rdata;
    logic [1:0]          rresp;
    logic                rlast;
    logic                rvalid;
    logic                rready;

    // ========================================================
    // Clocking Blocks
    // ========================================================
    clocking drv_cb @(posedge aclk);
        // Master driver: drives address/write channels, samples response channels
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking mon_cb @(posedge aclk);
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos;
        input awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos;
        input arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    // ========================================================
    // Modports
    // ========================================================
    modport master_mp (
        input  aclk, aresetn,
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport slave_mp (
        input  aclk, aresetn,
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface : axi_if
