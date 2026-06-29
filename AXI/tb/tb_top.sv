// AXI4-Full UVM Testbench Top
// Drives axi_interconnect directly via UVM agents (no axi_top internal masters)
// 2 masters, 2 slaves: SRAM (0x0xxx_xxxx) and DFI/DDR5 (0x1xxx_xxxx)
// 256-bit data, 32-bit address, 8-bit ID

`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_pkg::*;

module tb_top;

    // ============================================================
    // Testbench Parameters
    // ============================================================
    localparam int DATA_W     = 256;
    localparam int ADDR_W     = 32;
    localparam int ID_W       = 8;
    localparam int NUM_MASTERS = 2;
    localparam int NUM_SLAVES  = 2;
    localparam int STRB_W     = DATA_W / 8;  // 32

    // ============================================================
    // Clock and Reset
    // ============================================================
    logic aclk;
    logic aresetn;

    // 200 MHz clock (5ns period)
    initial aclk = 1'b0;
    always #2.5 aclk = ~aclk;

    // ============================================================
    // AXI Interface Instances (one per UVM master agent)
    // ============================================================
    axi_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W))
        m_if [NUM_MASTERS] (.aclk(aclk), .aresetn(aresetn));

    // ============================================================
    // Master-Side Unpacked Wire Arrays
    // These connect directly to the axi_if signals.
    // Direction: IF-driver drives → wire → interconnect input
    //           IF-driver reads  ← wire ← interconnect output
    // ============================================================

    // --- AW Channel ---
    logic [ID_W-1:0]     m_awid    [NUM_MASTERS];
    logic [ADDR_W-1:0]   m_awaddr  [NUM_MASTERS];
    logic [7:0]          m_awlen   [NUM_MASTERS];
    logic [2:0]          m_awsize  [NUM_MASTERS];
    logic [1:0]          m_awburst [NUM_MASTERS];
    logic                m_awvalid [NUM_MASTERS];
    logic                m_awready [NUM_MASTERS];

    // --- W Channel ---
    logic [DATA_W-1:0]   m_wdata   [NUM_MASTERS];
    logic [STRB_W-1:0]   m_wstrb   [NUM_MASTERS];
    logic                m_wlast   [NUM_MASTERS];
    logic                m_wvalid  [NUM_MASTERS];
    logic                m_wready  [NUM_MASTERS];

    // --- B Channel ---
    logic [ID_W-1:0]     m_bid     [NUM_MASTERS];
    logic [1:0]          m_bresp   [NUM_MASTERS];
    logic                m_bvalid  [NUM_MASTERS];
    logic                m_bready  [NUM_MASTERS];

    // --- AR Channel ---
    logic [ID_W-1:0]     m_arid    [NUM_MASTERS];
    logic [ADDR_W-1:0]   m_araddr  [NUM_MASTERS];
    logic [7:0]          m_arlen   [NUM_MASTERS];
    logic [2:0]          m_arsize  [NUM_MASTERS];
    logic [1:0]          m_arburst [NUM_MASTERS];
    logic                m_arvalid [NUM_MASTERS];
    logic                m_arready [NUM_MASTERS];

    // --- R Channel ---
    logic [ID_W-1:0]     m_rid     [NUM_MASTERS];
    logic [DATA_W-1:0]   m_rdata   [NUM_MASTERS];
    logic [1:0]          m_rresp   [NUM_MASTERS];
    logic                m_rlast   [NUM_MASTERS];
    logic                m_rvalid  [NUM_MASTERS];
    logic                m_rready  [NUM_MASTERS];

    // ============================================================
    // Connect AXI Interfaces to Master-Side Unpacked Wires
    // ============================================================
    generate
        genvar mi;
        for (mi = 0; mi < NUM_MASTERS; mi++) begin : m_if_conn
            // AW: IF drives addr/valid, interconnect drives ready
            assign m_awid[mi]    = m_if[mi].awid;
            assign m_awaddr[mi]  = m_if[mi].awaddr;
            assign m_awlen[mi]   = m_if[mi].awlen;
            assign m_awsize[mi]  = m_if[mi].awsize;
            assign m_awburst[mi] = m_if[mi].awburst;
            assign m_awvalid[mi] = m_if[mi].awvalid;
            assign m_if[mi].awready = m_awready[mi];

            // W: IF drives data/valid, interconnect drives ready
            assign m_wdata[mi]   = m_if[mi].wdata;
            assign m_wstrb[mi]   = m_if[mi].wstrb;
            assign m_wlast[mi]   = m_if[mi].wlast;
            assign m_wvalid[mi]  = m_if[mi].wvalid;
            assign m_if[mi].wready = m_wready[mi];

            // B: interconnect drives response, IF drives ready
            assign m_bid[mi]     = m_if[mi].bid;
            assign m_bresp[mi]   = m_if[mi].bresp;
            assign m_bvalid[mi]  = m_if[mi].bvalid;
            assign m_if[mi].bready = m_bready[mi];

            // AR: IF drives addr/valid, interconnect drives ready
            assign m_arid[mi]    = m_if[mi].arid;
            assign m_araddr[mi]  = m_if[mi].araddr;
            assign m_arlen[mi]   = m_if[mi].arlen;
            assign m_arsize[mi]  = m_if[mi].arsize;
            assign m_arburst[mi] = m_if[mi].arburst;
            assign m_arvalid[mi] = m_if[mi].arvalid;
            assign m_if[mi].arready = m_arready[mi];

            // R: interconnect drives response/data, IF drives ready
            assign m_rid[mi]     = m_if[mi].rid;
            assign m_rdata[mi]   = m_if[mi].rdata;
            assign m_rresp[mi]   = m_if[mi].rresp;
            assign m_rlast[mi]   = m_if[mi].rlast;
            assign m_rvalid[mi]  = m_if[mi].rvalid;
            assign m_if[mi].rready = m_rready[mi];
        end
    endgenerate

    // ============================================================
    // Master-Side Packed Intermediate Wire Arrays
    // axi_interconnect uses packed-array ports like
    // [NUM_MASTERS-1:0][ID_W-1:0] m_awid.
    // These intermediates bridge the unpacked ↔ packed conversion.
    // ============================================================

    // --- AW Channel ---
    logic [NUM_MASTERS-1:0][ID_W-1:0]     ic_m_awid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0]   ic_m_awaddr;
    logic [NUM_MASTERS-1:0][7:0]          ic_m_awlen;
    logic [NUM_MASTERS-1:0][2:0]          ic_m_awsize;
    logic [NUM_MASTERS-1:0][1:0]          ic_m_awburst;
    logic [NUM_MASTERS-1:0]               ic_m_awvalid;
    logic [NUM_MASTERS-1:0]               ic_m_awready;

    // --- W Channel ---
    logic [NUM_MASTERS-1:0][DATA_W-1:0]   ic_m_wdata;
    logic [NUM_MASTERS-1:0][STRB_W-1:0]   ic_m_wstrb;
    logic [NUM_MASTERS-1:0]               ic_m_wlast;
    logic [NUM_MASTERS-1:0]               ic_m_wvalid;
    logic [NUM_MASTERS-1:0]               ic_m_wready;

    // --- B Channel ---
    logic [NUM_MASTERS-1:0][ID_W-1:0]     ic_m_bid;
    logic [NUM_MASTERS-1:0][1:0]          ic_m_bresp;
    logic [NUM_MASTERS-1:0]               ic_m_bvalid;
    logic [NUM_MASTERS-1:0]               ic_m_bready;

    // --- AR Channel ---
    logic [NUM_MASTERS-1:0][ID_W-1:0]     ic_m_arid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0]   ic_m_araddr;
    logic [NUM_MASTERS-1:0][7:0]          ic_m_arlen;
    logic [NUM_MASTERS-1:0][2:0]          ic_m_arsize;
    logic [NUM_MASTERS-1:0][1:0]          ic_m_arburst;
    logic [NUM_MASTERS-1:0]               ic_m_arvalid;
    logic [NUM_MASTERS-1:0]               ic_m_arready;

    // --- R Channel ---
    logic [NUM_MASTERS-1:0][ID_W-1:0]     ic_m_rid;
    logic [NUM_MASTERS-1:0][DATA_W-1:0]   ic_m_rdata;
    logic [NUM_MASTERS-1:0][1:0]          ic_m_rresp;
    logic [NUM_MASTERS-1:0]               ic_m_rlast;
    logic [NUM_MASTERS-1:0]               ic_m_rvalid;
    logic [NUM_MASTERS-1:0]               ic_m_rready;

    // ============================================================
    // Assign Unpacked ↔ Packed Master-Side Wires
    // Unpacked m_*[mi] ↔ Packed ic_m_*[mi]
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi++) begin : m_pack
            // AW — unpacked drives packed for interconnect inputs
            assign ic_m_awid[mi]    = m_awid[mi];
            assign ic_m_awaddr[mi]  = m_awaddr[mi];
            assign ic_m_awlen[mi]   = m_awlen[mi];
            assign ic_m_awsize[mi]  = m_awsize[mi];
            assign ic_m_awburst[mi] = m_awburst[mi];
            assign ic_m_awvalid[mi] = m_awvalid[mi];
            // AW ready — packed driven by interconnect output
            assign m_awready[mi]    = ic_m_awready[mi];

            // W
            assign ic_m_wdata[mi]   = m_wdata[mi];
            assign ic_m_wstrb[mi]   = m_wstrb[mi];
            assign ic_m_wlast[mi]   = m_wlast[mi];
            assign ic_m_wvalid[mi]  = m_wvalid[mi];
            assign m_wready[mi]     = ic_m_wready[mi];

            // B
            assign m_bid[mi]        = ic_m_bid[mi];
            assign m_bresp[mi]      = ic_m_bresp[mi];
            assign m_bvalid[mi]     = ic_m_bvalid[mi];
            assign ic_m_bready[mi]  = m_bready[mi];

            // AR
            assign ic_m_arid[mi]    = m_arid[mi];
            assign ic_m_araddr[mi]  = m_araddr[mi];
            assign ic_m_arlen[mi]   = m_arlen[mi];
            assign ic_m_arsize[mi]  = m_arsize[mi];
            assign ic_m_arburst[mi] = m_arburst[mi];
            assign ic_m_arvalid[mi] = m_arvalid[mi];
            assign m_arready[mi]    = ic_m_arready[mi];

            // R
            assign m_rid[mi]        = ic_m_rid[mi];
            assign m_rdata[mi]      = ic_m_rdata[mi];
            assign m_rresp[mi]      = ic_m_rresp[mi];
            assign m_rlast[mi]      = ic_m_rlast[mi];
            assign m_rvalid[mi]     = ic_m_rvalid[mi];
            assign ic_m_rready[mi]  = m_rready[mi];
        end
    endgenerate

    // ============================================================
    // Slave-Side Packed Intermediate Wire Arrays
    // These connect to the interconnect slave ports.
    // ============================================================

    // --- AW Channel ---
    logic [NUM_SLAVES-1:0][ID_W-1:0]     ic_s_awid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]   ic_s_awaddr;
    logic [NUM_SLAVES-1:0][7:0]          ic_s_awlen;
    logic [NUM_SLAVES-1:0][2:0]          ic_s_awsize;
    logic [NUM_SLAVES-1:0][1:0]          ic_s_awburst;
    logic [NUM_SLAVES-1:0]               ic_s_awvalid;
    logic [NUM_SLAVES-1:0]               ic_s_awready;

    // --- W Channel ---
    logic [NUM_SLAVES-1:0][DATA_W-1:0]   ic_s_wdata;
    logic [NUM_SLAVES-1:0][STRB_W-1:0]   ic_s_wstrb;
    logic [NUM_SLAVES-1:0]               ic_s_wlast;
    logic [NUM_SLAVES-1:0]               ic_s_wvalid;
    logic [NUM_SLAVES-1:0]               ic_s_wready;

    // --- B Channel ---
    logic [NUM_SLAVES-1:0][ID_W-1:0]     ic_s_bid;
    logic [NUM_SLAVES-1:0][1:0]          ic_s_bresp;
    logic [NUM_SLAVES-1:0]               ic_s_bvalid;
    logic [NUM_SLAVES-1:0]               ic_s_bready;

    // --- AR Channel ---
    logic [NUM_SLAVES-1:0][ID_W-1:0]     ic_s_arid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]   ic_s_araddr;
    logic [NUM_SLAVES-1:0][7:0]          ic_s_arlen;
    logic [NUM_SLAVES-1:0][2:0]          ic_s_arsize;
    logic [NUM_SLAVES-1:0][1:0]          ic_s_arburst;
    logic [NUM_SLAVES-1:0]               ic_s_arvalid;
    logic [NUM_SLAVES-1:0]               ic_s_arready;

    // --- R Channel ---
    logic [NUM_SLAVES-1:0][ID_W-1:0]     ic_s_rid;
    logic [NUM_SLAVES-1:0][DATA_W-1:0]   ic_s_rdata;
    logic [NUM_SLAVES-1:0][1:0]          ic_s_rresp;
    logic [NUM_SLAVES-1:0]               ic_s_rlast;
    logic [NUM_SLAVES-1:0]               ic_s_rvalid;
    logic [NUM_SLAVES-1:0]               ic_s_rready;

    // ============================================================
    // Slave-Side Unpacked Wire Arrays
    // These connect to individual slave module ports.
    // ============================================================

    // --- AW Channel ---
    logic [ID_W-1:0]     s_awid    [NUM_SLAVES];
    logic [ADDR_W-1:0]   s_awaddr  [NUM_SLAVES];
    logic [7:0]          s_awlen   [NUM_SLAVES];
    logic [2:0]          s_awsize  [NUM_SLAVES];
    logic [1:0]          s_awburst [NUM_SLAVES];
    logic                s_awvalid [NUM_SLAVES];
    logic                s_awready [NUM_SLAVES];

    // --- W Channel ---
    logic [DATA_W-1:0]   s_wdata   [NUM_SLAVES];
    logic [STRB_W-1:0]   s_wstrb   [NUM_SLAVES];
    logic                s_wlast   [NUM_SLAVES];
    logic                s_wvalid  [NUM_SLAVES];
    logic                s_wready  [NUM_SLAVES];

    // --- B Channel ---
    logic [ID_W-1:0]     s_bid     [NUM_SLAVES];
    logic [1:0]          s_bresp   [NUM_SLAVES];
    logic                s_bvalid  [NUM_SLAVES];
    logic                s_bready  [NUM_SLAVES];

    // --- AR Channel ---
    logic [ID_W-1:0]     s_arid    [NUM_SLAVES];
    logic [ADDR_W-1:0]   s_araddr  [NUM_SLAVES];
    logic [7:0]          s_arlen   [NUM_SLAVES];
    logic [2:0]          s_arsize  [NUM_SLAVES];
    logic [1:0]          s_arburst [NUM_SLAVES];
    logic                s_arvalid [NUM_SLAVES];
    logic                s_arready [NUM_SLAVES];

    // --- R Channel ---
    logic [ID_W-1:0]     s_rid     [NUM_SLAVES];
    logic [DATA_W-1:0]   s_rdata   [NUM_SLAVES];
    logic [1:0]          s_rresp   [NUM_SLAVES];
    logic                s_rlast   [NUM_SLAVES];
    logic                s_rvalid  [NUM_SLAVES];
    logic                s_rready  [NUM_SLAVES];

    // --- DFI Monitor Signals ---
    logic [31:0]         dfi_address;
    logic [3:0]          dfi_bank;
    logic [DATA_W-1:0]   dfi_wrdata;
    logic [STRB_W-1:0]   dfi_wrdata_mask;
    logic                dfi_wrdata_valid;
    logic                dfi_cs_n;
    logic                dfi_ras_n;
    logic                dfi_cas_n;
    logic                dfi_we_n;
    logic                dfi_act_n;

    // ============================================================
    // Assign Packed ↔ Unpacked Slave-Side Wires
    // Packed ic_s_*[si] ↔ Unpacked s_*[si]
    // ============================================================
    generate
        genvar si;
        for (si = 0; si < NUM_SLAVES; si++) begin : s_pack
            // AW — interconnect output → slave input
            assign s_awid[si]    = ic_s_awid[si];
            assign s_awaddr[si]  = ic_s_awaddr[si];
            assign s_awlen[si]   = ic_s_awlen[si];
            assign s_awsize[si]  = ic_s_awsize[si];
            assign s_awburst[si] = ic_s_awburst[si];
            assign s_awvalid[si] = ic_s_awvalid[si];
            assign ic_s_awready[si] = s_awready[si];

            // W — interconnect output → slave input
            assign s_wdata[si]   = ic_s_wdata[si];
            assign s_wstrb[si]   = ic_s_wstrb[si];
            assign s_wlast[si]   = ic_s_wlast[si];
            assign s_wvalid[si]  = ic_s_wvalid[si];
            assign ic_s_wready[si] = s_wready[si];

            // B — slave output → interconnect input
            assign ic_s_bid[si]  = s_bid[si];
            assign ic_s_bresp[si]= s_bresp[si];
            assign ic_s_bvalid[si]= s_bvalid[si];
            assign s_bready[si]  = ic_s_bready[si];

            // AR — interconnect output → slave input
            assign s_arid[si]    = ic_s_arid[si];
            assign s_araddr[si]  = ic_s_araddr[si];
            assign s_arlen[si]   = ic_s_arlen[si];
            assign s_arsize[si]  = ic_s_arsize[si];
            assign s_arburst[si] = ic_s_arburst[si];
            assign s_arvalid[si] = ic_s_arvalid[si];
            assign ic_s_arready[si] = s_arready[si];

            // R — slave output → interconnect input
            assign ic_s_rid[si]  = s_rid[si];
            assign ic_s_rdata[si]= s_rdata[si];
            assign ic_s_rresp[si]= s_rresp[si];
            assign ic_s_rlast[si]= s_rlast[si];
            assign ic_s_rvalid[si]= s_rvalid[si];
            assign s_rready[si]  = ic_s_rready[si];
        end
    endgenerate

    // ============================================================
    // DUT: AXI Interconnect
    // Master ports via packed intermediate wires.
    // Slave ports via packed intermediate wires.
    // ============================================================
    axi_interconnect #(
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES (NUM_SLAVES),
        .ID_W       (ID_W),
        .ADDR_W     (ADDR_W),
        .DATA_W     (DATA_W)
    ) u_interconnect (
        .aclk, .aresetn,

        // Master AW
        .m_awid    (ic_m_awid),
        .m_awaddr  (ic_m_awaddr),
        .m_awlen   (ic_m_awlen),
        .m_awsize  (ic_m_awsize),
        .m_awburst (ic_m_awburst),
        .m_awvalid (ic_m_awvalid),
        .m_awready (ic_m_awready),

        // Master W
        .m_wdata   (ic_m_wdata),
        .m_wstrb   (ic_m_wstrb),
        .m_wlast   (ic_m_wlast),
        .m_wvalid  (ic_m_wvalid),
        .m_wready  (ic_m_wready),

        // Master B
        .m_bid     (ic_m_bid),
        .m_bresp   (ic_m_bresp),
        .m_bvalid  (ic_m_bvalid),
        .m_bready  (ic_m_bready),

        // Master AR
        .m_arid    (ic_m_arid),
        .m_araddr  (ic_m_araddr),
        .m_arlen   (ic_m_arlen),
        .m_arsize  (ic_m_arsize),
        .m_arburst (ic_m_arburst),
        .m_arvalid (ic_m_arvalid),
        .m_arready (ic_m_arready),

        // Master R
        .m_rid     (ic_m_rid),
        .m_rdata   (ic_m_rdata),
        .m_rresp   (ic_m_rresp),
        .m_rlast   (ic_m_rlast),
        .m_rvalid  (ic_m_rvalid),
        .m_rready  (ic_m_rready),

        // Slave AW
        .s_awid    (ic_s_awid),
        .s_awaddr  (ic_s_awaddr),
        .s_awlen   (ic_s_awlen),
        .s_awsize  (ic_s_awsize),
        .s_awburst (ic_s_awburst),
        .s_awvalid (ic_s_awvalid),
        .s_awready (ic_s_awready),

        // Slave W
        .s_wdata   (ic_s_wdata),
        .s_wstrb   (ic_s_wstrb),
        .s_wlast   (ic_s_wlast),
        .s_wvalid  (ic_s_wvalid),
        .s_wready  (ic_s_wready),

        // Slave B
        .s_bid     (ic_s_bid),
        .s_bresp   (ic_s_bresp),
        .s_bvalid  (ic_s_bvalid),
        .s_bready  (ic_s_bready),

        // Slave AR
        .s_arid    (ic_s_arid),
        .s_araddr  (ic_s_araddr),
        .s_arlen   (ic_s_arlen),
        .s_arsize  (ic_s_arsize),
        .s_arburst (ic_s_arburst),
        .s_arvalid (ic_s_arvalid),
        .s_arready (ic_s_arready),

        // Slave R
        .s_rid     (ic_s_rid),
        .s_rdata   (ic_s_rdata),
        .s_rresp   (ic_s_rresp),
        .s_rlast   (ic_s_rlast),
        .s_rvalid  (ic_s_rvalid),
        .s_rready  (ic_s_rready)
    );

    // ============================================================
    // Slave 0: SRAM (address range 0x0xxx_xxxx)
    // ============================================================
    axi_slave_sram #(
        .DEPTH     (1024),
        .ADDR_W    (ADDR_W),
        .DATA_W    (DATA_W),
        .ID_W      (ID_W),
        .STALL_PROB(0)
    ) u_slave_sram (
        .aclk, .aresetn,

        .awid    (s_awid[0]),
        .awaddr  (s_awaddr[0]),
        .awlen   (s_awlen[0]),
        .awsize  (s_awsize[0]),
        .awburst (s_awburst[0]),
        .awvalid (s_awvalid[0]),
        .awready (s_awready[0]),

        .wdata   (s_wdata[0]),
        .wstrb   (s_wstrb[0]),
        .wlast   (s_wlast[0]),
        .wvalid  (s_wvalid[0]),
        .wready  (s_wready[0]),

        .bid     (s_bid[0]),
        .bresp   (s_bresp[0]),
        .bvalid  (s_bvalid[0]),
        .bready  (s_bready[0]),

        .arid    (s_arid[0]),
        .araddr  (s_araddr[0]),
        .arlen   (s_arlen[0]),
        .arsize  (s_arsize[0]),
        .arburst (s_arburst[0]),
        .arvalid (s_arvalid[0]),
        .arready (s_arready[0]),

        .rid     (s_rid[0]),
        .rdata   (s_rdata[0]),
        .rresp   (s_rresp[0]),
        .rlast   (s_rlast[0]),
        .rvalid  (s_rvalid[0]),
        .rready  (s_rready[0])
    );

    // ============================================================
    // Slave 1: DFI Bridge / DDR5 (address range 0x1xxx_xxxx)
    // ============================================================
    axi_slave_dfi #(
        .ADDR_W (ADDR_W),
        .DATA_W (DATA_W),
        .ID_W   (ID_W)
    ) u_slave_dfi (
        .aclk, .aresetn,

        .awid    (s_awid[1]),
        .awaddr  (s_awaddr[1]),
        .awlen   (s_awlen[1]),
        .awsize  (s_awsize[1]),
        .awburst (s_awburst[1]),
        .awvalid (s_awvalid[1]),
        .awready (s_awready[1]),

        .wdata   (s_wdata[1]),
        .wstrb   (s_wstrb[1]),
        .wlast   (s_wlast[1]),
        .wvalid  (s_wvalid[1]),
        .wready  (s_wready[1]),

        .bid     (s_bid[1]),
        .bresp   (s_bresp[1]),
        .bvalid  (s_bvalid[1]),
        .bready  (s_bready[1]),

        .arid    (s_arid[1]),
        .araddr  (s_araddr[1]),
        .arlen   (s_arlen[1]),
        .arsize  (s_arsize[1]),
        .arburst (s_arburst[1]),
        .arvalid (s_arvalid[1]),
        .arready (s_arready[1]),

        .rid     (s_rid[1]),
        .rdata   (s_rdata[1]),
        .rresp   (s_rresp[1]),
        .rlast   (s_rlast[1]),
        .rvalid  (s_rvalid[1]),
        .rready  (s_rready[1]),

        // DFI outputs
        .dfi_address      (dfi_address),
        .dfi_bank         (dfi_bank),
        .dfi_wrdata       (dfi_wrdata),
        .dfi_wrdata_mask  (dfi_wrdata_mask),
        .dfi_wrdata_valid (dfi_wrdata_valid),
        .dfi_cs_n         (dfi_cs_n),
        .dfi_ras_n        (dfi_ras_n),
        .dfi_cas_n        (dfi_cas_n),
        .dfi_we_n         (dfi_we_n),
        .dfi_act_n        (dfi_act_n),
        .dfi_cke          (),

        // DFI inputs — no external DRAM model
        .dfi_rddata       ('0),
        .dfi_rddata_valid (1'b0)
    );

    // ============================================================
    // UVM Configuration and Test Start
    // ============================================================
    initial begin
        // Pass virtual AXI interfaces to UVM agents
        uvm_config_db #(virtual axi_if)::set(
            null, "*master_agent[0]*", "vif", m_if[0]
        );
        uvm_config_db #(virtual axi_if)::set(
            null, "*master_agent[1]*", "vif", m_if[1]
        );

        run_test();
    end

    // ============================================================
    // Reset Sequence
    // Assert reset for 10 cycles, then release.
    // ============================================================
    initial begin
        aresetn = 1'b0;
        repeat (10) @(posedge aclk);
        aresetn = 1'b1;
        $display("=== TB_TOP: Reset released, test starting ===");
    end

    // ============================================================
    // Simulation Timeout
    // Stop simulation after 5 us if test is still running.
    // ============================================================
    initial begin
        #5000000;
        $display("=== TB_TOP: Timeout (5 us), finishing simulation ===");
        $finish;
    end

    // ============================================================
    // Waveform Dump (FSDB)
    // ============================================================
    initial begin
        $fsdbDumpfile("waves/axi_top.fsdb");
        $fsdbDumpvars(0, tb_top, "+all");
    end

    // ============================================================
    // Protocol Assertions — AXI4-Full compliance
    // ============================================================

    // AW: address, ID, and length must remain stable while awvalid is
    // asserted and awready is low (before handshake).
    property aw_signals_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].awvalid && !m_if[0].awready) |=> $stable(m_if[0].awaddr)
            && $stable(m_if[0].awid)
            && $stable(m_if[0].awlen);
    endproperty
    assert property (aw_signals_stable)
        else $error("AW[0]: addr/id/len changed during handshake");

    // AR: address, ID, and length must remain stable while arvalid is
    // asserted and arready is low (before handshake).
    property ar_signals_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].arvalid && !m_if[0].arready) |=> $stable(m_if[0].araddr)
            && $stable(m_if[0].arid)
            && $stable(m_if[0].arlen);
    endproperty
    assert property (ar_signals_stable)
        else $error("AR[0]: addr/id/len changed during handshake");

    // WLAST must be asserted on the final write beat.
    // If wvalid && wready, the beat count is consumed.
    // Simplified: wlast must not be deasserted mid-burst after first beat.
    property wlast_eventually;
        @(posedge aclk) disable iff (!aresetn)
        m_if[0].wvalid && m_if[0].wready && m_if[0].wlast
        |=> !m_if[0].wvalid || m_if[0].wlast;
    endproperty
    assert property (wlast_eventually)
        else $error("W[0]: wlast deasserted after last beat");

    // RLAST must be asserted on the final read beat.
    property rlast_eventually;
        @(posedge aclk) disable iff (!aresetn)
        m_if[0].rvalid && m_if[0].rready && m_if[0].rlast
        |=> !m_if[0].rvalid || m_if[0].rlast;
    endproperty
    assert property (rlast_eventually)
        else $error("R[0]: rlast deasserted after last beat");

    // AWVALID must not be asserted before aresetn is deasserted.
    property aw_valid_reset;
        @(posedge aclk) disable iff (aresetn)
        !m_if[0].awvalid;
    endproperty
    assert property (aw_valid_reset)
        else $error("AW[0]: awvalid asserted during reset");

    // ARVALID must not be asserted before aresetn is deasserted.
    property ar_valid_reset;
        @(posedge aclk) disable iff (aresetn)
        !m_if[0].arvalid;
    endproperty
    assert property (ar_valid_reset)
        else $error("AR[0]: arvalid asserted during reset");

endmodule : tb_top
