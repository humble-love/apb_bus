// AXI4-Full Top-Level Integration
// 2 Masters → Interconnect (Crossbar + Decoder) → SRAM Slave + DFI Slave

module axi_top #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master 0 txn stimulus (from testbench)
    // ============================================================
    input  logic                 txn_req_0,
    input  logic                 txn_is_write_0,
    input  logic [ID_W-1:0]      txn_awid_0,
    input  logic [ADDR_W-1:0]    txn_awaddr_0,
    input  logic [7:0]           txn_awlen_0,
    input  logic [2:0]           txn_awsize_0,
    input  logic [1:0]           txn_awburst_0,
    input  logic [ID_W-1:0]      txn_arid_0,
    input  logic [ADDR_W-1:0]    txn_araddr_0,
    input  logic [7:0]           txn_arlen_0,
    input  logic [2:0]           txn_arsize_0,
    input  logic [1:0]           txn_arburst_0,
    // Write data streaming
    input  logic                 txn_wvalid_0,
    input  logic [DATA_W-1:0]    txn_wdata_0,
    input  logic [DATA_W/8-1:0]  txn_wstrb_0,
    input  logic                 txn_wlast_0,
    output logic                 txn_wready_0,
    // Read data streaming
    output logic                 txn_rvalid_0,
    output logic [DATA_W-1:0]    txn_rdata_0,
    output logic [1:0]           txn_rresp_0,
    output logic                 txn_rlast_0,
    input  logic                 txn_rready_0,
    // Completion
    output logic                 txn_done_0,
    output logic [1:0]           txn_bresp_0,

    // ============================================================
    // Master 1 txn stimulus (from testbench)
    // ============================================================
    input  logic                 txn_req_1,
    input  logic                 txn_is_write_1,
    input  logic [ID_W-1:0]      txn_awid_1,
    input  logic [ADDR_W-1:0]    txn_awaddr_1,
    input  logic [7:0]           txn_awlen_1,
    input  logic [2:0]           txn_awsize_1,
    input  logic [1:0]           txn_awburst_1,
    input  logic [ID_W-1:0]      txn_arid_1,
    input  logic [ADDR_W-1:0]    txn_araddr_1,
    input  logic [7:0]           txn_arlen_1,
    input  logic [2:0]           txn_arsize_1,
    input  logic [1:0]           txn_arburst_1,
    // Write data streaming
    input  logic                 txn_wvalid_1,
    input  logic [DATA_W-1:0]    txn_wdata_1,
    input  logic [DATA_W/8-1:0]  txn_wstrb_1,
    input  logic                 txn_wlast_1,
    output logic                 txn_wready_1,
    // Read data streaming
    output logic                 txn_rvalid_1,
    output logic [DATA_W-1:0]    txn_rdata_1,
    output logic [1:0]           txn_rresp_1,
    output logic                 txn_rlast_1,
    input  logic                 txn_rready_1,
    // Completion
    output logic                 txn_done_1,
    output logic [1:0]           txn_bresp_1,

    // ============================================================
    // DFI Port (exposed for monitoring)
    // ============================================================
    output logic [31:0]         dfi_address,
    output logic [3:0]          dfi_bank,
    output logic [DATA_W-1:0]   dfi_wrdata,
    output logic [DATA_W/8-1:0] dfi_wrdata_mask,
    output logic                dfi_wrdata_valid,
    output logic                dfi_cs_n,
    output logic                dfi_ras_n,
    output logic                dfi_cas_n,
    output logic                dfi_we_n,
    output logic                dfi_act_n

    // Note: dfi_rddata, dfi_rddata_valid driven low (no external DRAM model)
    // For verification, the scoreboard models DDR5 internally
);

    // Interconnect ↔ Master signals
    logic [NUM_MASTERS-1:0][ID_W-1:0]   ic_awid, ic_arid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0] ic_awaddr, ic_araddr;
    logic [NUM_MASTERS-1:0][7:0]        ic_awlen, ic_arlen;
    logic [NUM_MASTERS-1:0][2:0]        ic_awsize, ic_arsize;
    logic [NUM_MASTERS-1:0][1:0]        ic_awburst, ic_arburst;
    logic [NUM_MASTERS-1:0]             ic_awvalid, ic_awready;
    logic [NUM_MASTERS-1:0]             ic_arvalid, ic_arready;
    logic [NUM_MASTERS-1:0][DATA_W-1:0] ic_wdata, ic_rdata;
    logic [NUM_MASTERS-1:0][DATA_W/8-1:0] ic_wstrb;
    logic [NUM_MASTERS-1:0]             ic_wlast, ic_wvalid, ic_wready;
    logic [NUM_MASTERS-1:0][ID_W-1:0]   ic_bid, ic_rid;
    logic [NUM_MASTERS-1:0][1:0]        ic_bresp, ic_rresp;
    logic [NUM_MASTERS-1:0]             ic_bvalid, ic_bready;
    logic [NUM_MASTERS-1:0]             ic_rlast, ic_rvalid, ic_rready;

    // Interconnect ↔ Slave signals
    logic [NUM_SLAVES-1:0][ID_W-1:0]    s_awid, s_arid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]  s_awaddr, s_araddr;
    logic [NUM_SLAVES-1:0][7:0]         s_awlen, s_arlen;
    logic [NUM_SLAVES-1:0][2:0]         s_awsize, s_arsize;
    logic [NUM_SLAVES-1:0][1:0]         s_awburst, s_arburst;
    logic [NUM_SLAVES-1:0]              s_awvalid, s_awready;
    logic [NUM_SLAVES-1:0]              s_arvalid, s_arready;
    logic [NUM_SLAVES-1:0][DATA_W-1:0]  s_wdata, s_rdata;
    logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb;
    logic [NUM_SLAVES-1:0]              s_wlast, s_wvalid, s_wready;
    logic [NUM_SLAVES-1:0][ID_W-1:0]    s_bid, s_rid;
    logic [NUM_SLAVES-1:0][1:0]         s_bresp, s_rresp;
    logic [NUM_SLAVES-1:0]              s_bvalid, s_bready;
    logic [NUM_SLAVES-1:0]              s_rlast, s_rvalid, s_rready;

    // Master per-channel request/grant
    logic [NUM_MASTERS-1:0] m0_aw_req, m0_aw_gnt, m0_ar_req, m0_ar_gnt;
    logic [NUM_MASTERS-1:0] m1_aw_req, m1_aw_gnt, m1_ar_req, m1_ar_gnt;

    genvar i;

    // ============================================================
    // Master 0
    // ============================================================
    axi_master #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master0 (
        .aclk, .aresetn,
        .aw_req  (m0_aw_req),  .aw_gnt  (m0_aw_gnt),
        .ar_req  (m0_ar_req),  .ar_gnt  (m0_ar_gnt),
        .awid    (ic_awid[0]), .awaddr  (ic_awaddr[0]),
        .awlen   (ic_awlen[0]), .awsize  (ic_awsize[0]),
        .awburst (ic_awburst[0]), .awlock (), .awcache(), .awprot(), .awqos(),
        .awvalid (ic_awvalid[0]), .awready(ic_awready[0]),
        .wdata   (ic_wdata[0]), .wstrb   (ic_wstrb[0]),
        .wlast   (ic_wlast[0]), .wvalid  (ic_wvalid[0]),
        .wready  (ic_wready[0]),
        .bid     (ic_bid[0]),  .bresp    (ic_bresp[0]),
        .bvalid  (ic_bvalid[0]), .bready  (ic_bready[0]),
        .arid    (ic_arid[0]), .araddr   (ic_araddr[0]),
        .arlen   (ic_arlen[0]), .arsize   (ic_arsize[0]),
        .arburst (ic_arburst[0]), .arlock (), .arcache(), .arprot(), .arqos(),
        .arvalid (ic_arvalid[0]), .arready(ic_arready[0]),
        .rid     (ic_rid[0]),  .rdata    (ic_rdata[0]),
        .rresp   (ic_rresp[0]), .rlast    (ic_rlast[0]),
        .rvalid  (ic_rvalid[0]), .rready   (ic_rready[0]),
        .txn_req     (txn_req_0),
        .txn_is_write(txn_is_write_0),
        .txn_awid    (txn_awid_0),
        .txn_awaddr  (txn_awaddr_0),
        .txn_awlen   (txn_awlen_0),
        .txn_awsize  (txn_awsize_0),
        .txn_awburst (txn_awburst_0),
        .txn_arid    (txn_arid_0),
        .txn_araddr  (txn_araddr_0),
        .txn_arlen   (txn_arlen_0),
        .txn_arsize  (txn_arsize_0),
        .txn_arburst (txn_arburst_0),
        .txn_wvalid  (txn_wvalid_0),
        .txn_wdata   (txn_wdata_0),
        .txn_wstrb   (txn_wstrb_0),
        .txn_wlast   (txn_wlast_0),
        .txn_wready  (txn_wready_0),
        .txn_rvalid  (txn_rvalid_0),
        .txn_rdata   (txn_rdata_0),
        .txn_rresp   (txn_rresp_0),
        .txn_rlast   (txn_rlast_0),
        .txn_rready  (txn_rready_0),
        .txn_done    (txn_done_0),
        .txn_bresp_out(txn_bresp_0)
    );

    // ============================================================
    // Master 1
    // ============================================================
    axi_master #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master1 (
        .aclk, .aresetn,
        .aw_req  (m1_aw_req),  .aw_gnt  (m1_aw_gnt),
        .ar_req  (m1_ar_req),  .ar_gnt  (m1_ar_gnt),
        .awid    (ic_awid[1]), .awaddr  (ic_awaddr[1]),
        .awlen   (ic_awlen[1]), .awsize  (ic_awsize[1]),
        .awburst (ic_awburst[1]), .awlock (), .awcache(), .awprot(), .awqos(),
        .awvalid (ic_awvalid[1]), .awready(ic_awready[1]),
        .wdata   (ic_wdata[1]), .wstrb   (ic_wstrb[1]),
        .wlast   (ic_wlast[1]), .wvalid  (ic_wvalid[1]),
        .wready  (ic_wready[1]),
        .bid     (ic_bid[1]),  .bresp    (ic_bresp[1]),
        .bvalid  (ic_bvalid[1]), .bready  (ic_bready[1]),
        .arid    (ic_arid[1]), .araddr   (ic_araddr[1]),
        .arlen   (ic_arlen[1]), .arsize   (ic_arsize[1]),
        .arburst (ic_arburst[1]), .arlock (), .arcache(), .arprot(), .arqos(),
        .arvalid (ic_arvalid[1]), .arready(ic_arready[1]),
        .rid     (ic_rid[1]),  .rdata    (ic_rdata[1]),
        .rresp   (ic_rresp[1]), .rlast    (ic_rlast[1]),
        .rvalid  (ic_rvalid[1]), .rready   (ic_rready[1]),
        .txn_req     (txn_req_1),
        .txn_is_write(txn_is_write_1),
        .txn_awid    (txn_awid_1),
        .txn_awaddr  (txn_awaddr_1),
        .txn_awlen   (txn_awlen_1),
        .txn_awsize  (txn_awsize_1),
        .txn_awburst (txn_awburst_1),
        .txn_arid    (txn_arid_1),
        .txn_araddr  (txn_araddr_1),
        .txn_arlen   (txn_arlen_1),
        .txn_arsize  (txn_arsize_1),
        .txn_arburst (txn_arburst_1),
        .txn_wvalid  (txn_wvalid_1),
        .txn_wdata   (txn_wdata_1),
        .txn_wstrb   (txn_wstrb_1),
        .txn_wlast   (txn_wlast_1),
        .txn_wready  (txn_wready_1),
        .txn_rvalid  (txn_rvalid_1),
        .txn_rdata   (txn_rdata_1),
        .txn_rresp   (txn_rresp_1),
        .txn_rlast   (txn_rlast_1),
        .txn_rready  (txn_rready_1),
        .txn_done    (txn_done_1),
        .txn_bresp_out(txn_bresp_1)
    );

    // Master AW/AR request mapper: any request downstream (always granted via crossbar)
    assign m0_aw_gnt = ic_awvalid[0] ? 1'b1 : 1'b0;  // Interconnect grants immediately
    assign m0_ar_gnt = ic_arvalid[0] ? 1'b1 : 1'b0;
    assign m1_aw_gnt = ic_awvalid[1] ? 1'b1 : 1'b0;
    assign m1_ar_gnt = ic_arvalid[1] ? 1'b1 : 1'b0;

    // ============================================================
    // AXI Interconnect
    // ============================================================
    axi_interconnect #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                       .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_interconnect (
        .aclk, .aresetn,
        // Master ports
        .m_awid   (ic_awid),   .m_awaddr  (ic_awaddr),
        .m_awlen  (ic_awlen),  .m_awsize  (ic_awsize),
        .m_awburst(ic_awburst),.m_awvalid (ic_awvalid),
        .m_awready(ic_awready),
        .m_wdata  (ic_wdata),  .m_wstrb   (ic_wstrb),
        .m_wlast  (ic_wlast),  .m_wvalid  (ic_wvalid),
        .m_wready (ic_wready),
        .m_bid    (ic_bid),    .m_bresp   (ic_bresp),
        .m_bvalid (ic_bvalid), .m_bready  (ic_bready),
        .m_arid   (ic_arid),   .m_araddr  (ic_araddr),
        .m_arlen  (ic_arlen),  .m_arsize  (ic_arsize),
        .m_arburst(ic_arburst),.m_arvalid (ic_arvalid),
        .m_arready(ic_arready),
        .m_rid    (ic_rid),    .m_rdata   (ic_rdata),
        .m_rresp  (ic_rresp),  .m_rlast   (ic_rlast),
        .m_rvalid (ic_rvalid), .m_rready  (ic_rready),
        // Slave ports
        .s_awid   (s_awid),    .s_awaddr  (s_awaddr),
        .s_awlen  (s_awlen),   .s_awsize  (s_awsize),
        .s_awburst(s_awburst), .s_awvalid (s_awvalid),
        .s_awready(s_awready),
        .s_wdata  (s_wdata),   .s_wstrb   (s_wstrb),
        .s_wlast  (s_wlast),   .s_wvalid  (s_wvalid),
        .s_wready (s_wready),
        .s_bid    (s_bid),     .s_bresp   (s_bresp),
        .s_bvalid (s_bvalid),  .s_bready  (s_bready),
        .s_arid   (s_arid),    .s_araddr  (s_araddr),
        .s_arlen  (s_arlen),   .s_arsize  (s_arsize),
        .s_arburst(s_arburst), .s_arvalid (s_arvalid),
        .s_arready(s_arready),
        .s_rid    (s_rid),     .s_rdata   (s_rdata),
        .s_rresp  (s_rresp),   .s_rlast   (s_rlast),
        .s_rvalid (s_rvalid),  .s_rready  (s_rready)
    );

    // ============================================================
    // Slave 0: SRAM
    // ============================================================
    axi_slave_sram #(.DEPTH(1024), .DATA_W(DATA_W), .ID_W(ID_W),
                     .ADDR_W(ADDR_W), .STALL_PROB(0))
    u_slave_sram (
        .aclk, .aresetn,
        .awid   (s_awid[0]),   .awaddr (s_awaddr[0]),
        .awlen  (s_awlen[0]),  .awsize (s_awsize[0]),
        .awburst(s_awburst[0]),.awvalid(s_awvalid[0]),
        .awready(s_awready[0]),
        .wdata  (s_wdata[0]),  .wstrb (s_wstrb[0]),
        .wlast  (s_wlast[0]),  .wvalid(s_wvalid[0]),
        .wready (s_wready[0]),
        .bid    (s_bid[0]),    .bresp (s_bresp[0]),
        .bvalid (s_bvalid[0]), .bready(s_bready[0]),
        .arid   (s_arid[0]),   .araddr(s_araddr[0]),
        .arlen  (s_arlen[0]),  .arsize(s_arsize[0]),
        .arburst(s_arburst[0]),.arvalid(s_arvalid[0]),
        .arready(s_arready[0]),
        .rid    (s_rid[0]),    .rdata (s_rdata[0]),
        .rresp  (s_rresp[0]),  .rlast (s_rlast[0]),
        .rvalid (s_rvalid[0]), .rready(s_rready[0])
    );

    // ============================================================
    // Slave 1: DFI Bridge (DDR5)
    // ============================================================
    assign dfi_cke = 1'b1;  // Always on for simulation

    axi_slave_dfi #(.DATA_W(DATA_W), .ID_W(ID_W), .ADDR_W(ADDR_W))
    u_slave_dfi (
        .aclk, .aresetn,
        .awid   (s_awid[1]),   .awaddr (s_awaddr[1]),
        .awlen  (s_awlen[1]),  .awsize (s_awsize[1]),
        .awburst(s_awburst[1]),.awvalid(s_awvalid[1]),
        .awready(s_awready[1]),
        .wdata  (s_wdata[1]),  .wstrb (s_wstrb[1]),
        .wlast  (s_wlast[1]),  .wvalid(s_wvalid[1]),
        .wready (s_wready[1]),
        .bid    (s_bid[1]),    .bresp (s_bresp[1]),
        .bvalid (s_bvalid[1]), .bready(s_bready[1]),
        .arid   (s_arid[1]),   .araddr(s_araddr[1]),
        .arlen  (s_arlen[1]),  .arsize(s_arsize[1]),
        .arburst(s_arburst[1]),.arvalid(s_arvalid[1]),
        .arready(s_arready[1]),
        .rid    (s_rid[1]),    .rdata (s_rdata[1]),
        .rresp  (s_rresp[1]),  .rlast (s_rlast[1]),
        .rvalid (s_rvalid[1]), .rready(s_rready[1]),
        // DFI
        .dfi_address      (dfi_address),
        .dfi_bank         (dfi_bank),
        .dfi_wrdata       (dfi_wrdata),
        .dfi_wrdata_mask  (dfi_wrdata_mask),
        .dfi_rddata       ('0),   // No external DRAM model
        .dfi_rddata_valid (1'b0),
        .dfi_wrdata_valid (dfi_wrdata_valid),
        .dfi_cs_n         (dfi_cs_n),
        .dfi_ras_n        (dfi_ras_n),
        .dfi_cas_n        (dfi_cas_n),
        .dfi_we_n         (dfi_we_n),
        .dfi_act_n        (dfi_act_n)
    );

endmodule : axi_top
