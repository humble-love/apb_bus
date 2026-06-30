// AXI Interconnect — Crossbar + Address Decoder integration
// 2 masters → decoder → write/read crossbars → 2 slaves

module axi_interconnect #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master ports (M x 5 channels)
    // ============================================================
    // AW
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  logic [NUM_MASTERS-1:0]             m_awvalid,
    output logic [NUM_MASTERS-1:0]             m_awready,
    // W
    input  logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]               m_wlast,
    input  logic [NUM_MASTERS-1:0]               m_wvalid,
    output logic [NUM_MASTERS-1:0]               m_wready,
    // B
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output logic [NUM_MASTERS-1:0][1:0]        m_bresp,
    output logic [NUM_MASTERS-1:0]             m_bvalid,
    input  logic [NUM_MASTERS-1:0]             m_bready,
    // AR
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  logic [NUM_MASTERS-1:0]             m_arvalid,
    output logic [NUM_MASTERS-1:0]             m_arready,
    // R
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output logic [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]        m_rresp,
    output logic [NUM_MASTERS-1:0]             m_rlast,
    output logic [NUM_MASTERS-1:0]             m_rvalid,
    input  logic [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave ports
    // ============================================================
    // AW
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_awlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_awsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_awburst,
    output logic [NUM_SLAVES-1:0]             s_awvalid,
    input  logic [NUM_SLAVES-1:0]             s_awready,
    // W
    output logic [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]               s_wlast,
    output logic [NUM_SLAVES-1:0]               s_wvalid,
    input  logic [NUM_SLAVES-1:0]               s_wready,
    // B
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  logic [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  logic [NUM_SLAVES-1:0]             s_bvalid,
    output logic [NUM_SLAVES-1:0]             s_bready,
    // AR
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_arlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_arsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_arburst,
    output logic [NUM_SLAVES-1:0]             s_arvalid,
    input  logic [NUM_SLAVES-1:0]             s_arready,
    // R
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  logic [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  logic [NUM_SLAVES-1:0]             s_rlast,
    input  logic [NUM_SLAVES-1:0]             s_rvalid,
    output logic [NUM_SLAVES-1:0]             s_rready
);

    // Decoder outputs
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0] m_aw_sel, m_ar_sel;
    logic [NUM_MASTERS-1:0]                m_aw_decerr, m_ar_decerr;

    // Per-master → per-slave AW/W signals (gated by decoder)
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_awid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_awaddr;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_awlen;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_awsize;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_awburst;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awready;

    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W-1:0]   x_wdata;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W/8-1:0] x_wstrb;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wlast;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wready;

    // Per-master → per-slave AR signals
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_arid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_araddr;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_arlen;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_arsize;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_arburst;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arready;

    genvar mi, si;

    // ============================================================
    // Per-master address decoders
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_dec
            axi_addr_decoder #(.NUM_SLAVES(NUM_SLAVES), .ADDR_W(ADDR_W)) u_dec (
                .awaddr   (m_awaddr[mi]),
                .awvalid  (m_awvalid[mi]),
                .aw_sel   (m_aw_sel[mi]),
                .aw_decerr(m_aw_decerr[mi]),
                .araddr   (m_araddr[mi]),
                .arvalid  (m_arvalid[mi]),
                .ar_sel   (m_ar_sel[mi]),
                .ar_decerr(m_ar_decerr[mi])
            );
        end
    endgenerate

    // ============================================================
    // Gate master signals to per-slave crossbar ports
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_gate
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin : s_gate
                // AW: only pass valid if decoder selected this slave
                assign x_awid[mi][si]   = m_awid[mi];
                assign x_awaddr[mi][si] = m_awaddr[mi];
                assign x_awlen[mi][si]  = m_awlen[mi];
                assign x_awsize[mi][si] = m_awsize[mi];
                assign x_awburst[mi][si] = m_awburst[mi];
                assign x_awvalid[mi][si] = m_awvalid[mi] && m_aw_sel[mi][si];

                // W: no decoder gating — awvalid is deasserted after AW handshake
                // while W data is still flowing. Crossbar w_locked handles routing.
                assign x_wdata[mi][si]  = m_wdata[mi];
                assign x_wstrb[mi][si]  = m_wstrb[mi];
                assign x_wlast[mi][si]  = m_wlast[mi];
                assign x_wvalid[mi][si] = m_wvalid[mi];

                // AR
                assign x_arid[mi][si]   = m_arid[mi];
                assign x_araddr[mi][si] = m_araddr[mi];
                assign x_arlen[mi][si]  = m_arlen[mi];
                assign x_arsize[mi][si] = m_arsize[mi];
                assign x_arburst[mi][si] = m_arburst[mi];
                assign x_arvalid[mi][si] = m_arvalid[mi] && m_ar_sel[mi][si];
            end
        end
    endgenerate

    // Per-slave B/R channel outputs from crossbars
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0][ID_W-1:0]   x_bid;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0][1:0]        x_bresp;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_bvalid;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_bready;

    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0][ID_W-1:0]   x_rid;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0][DATA_W-1:0] x_rdata;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0][1:0]        x_rresp;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rlast;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rvalid;
    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rready;

    // ============================================================
    // Per-slave Write Crossbars (NUM_SLAVES=1 each)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : s_wr_xbar
            // Extract [M] signals from [M][S] for this slave
            logic [NUM_MASTERS-1:0][ID_W-1:0]   si_awid;
            logic [NUM_MASTERS-1:0][ADDR_W-1:0] si_awaddr;
            logic [NUM_MASTERS-1:0][7:0]        si_awlen;
            logic [NUM_MASTERS-1:0][2:0]        si_awsize;
            logic [NUM_MASTERS-1:0][1:0]        si_awburst;
            logic [NUM_MASTERS-1:0]             si_awvalid;
            logic [NUM_MASTERS-1:0]             si_awready;
            logic [NUM_MASTERS-1:0][DATA_W-1:0]   si_wdata;
            logic [NUM_MASTERS-1:0][DATA_W/8-1:0] si_wstrb;
            logic [NUM_MASTERS-1:0]               si_wlast;
            logic [NUM_MASTERS-1:0]               si_wvalid;
            logic [NUM_MASTERS-1:0]               si_wready;

            for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_map
                assign si_awid[mi]   = x_awid[mi][si];
                assign si_awaddr[mi] = x_awaddr[mi][si];
                assign si_awlen[mi]  = x_awlen[mi][si];
                assign si_awsize[mi] = x_awsize[mi][si];
                assign si_awburst[mi]= x_awburst[mi][si];
                assign si_awvalid[mi]= x_awvalid[mi][si];
                assign x_awready[mi][si] = si_awready[mi];
                assign si_wdata[mi]  = x_wdata[mi][si];
                assign si_wstrb[mi]  = x_wstrb[mi][si];
                assign si_wlast[mi]  = x_wlast[mi][si];
                assign si_wvalid[mi] = x_wvalid[mi][si];
                assign x_wready[mi][si] = si_wready[mi];
            end

            axi_crossbar_wr #(
                .NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(1),
                .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)
            ) u_wr (
                .aclk, .aresetn,
                .m_awid(si_awid), .m_awaddr(si_awaddr), .m_awlen(si_awlen),
                .m_awsize(si_awsize), .m_awburst(si_awburst),
                .m_awvalid(si_awvalid), .m_awready(si_awready),
                .m_wdata(si_wdata), .m_wstrb(si_wstrb), .m_wlast(si_wlast),
                .m_wvalid(si_wvalid), .m_wready(si_wready),
                .m_bid(x_bid[si]), .m_bresp(x_bresp[si]),
                .m_bvalid(x_bvalid[si]), .m_bready(x_bready[si]),
                .s_awid(s_awid[si]), .s_awaddr(s_awaddr[si]),
                .s_awlen(s_awlen[si]), .s_awsize(s_awsize[si]),
                .s_awburst(s_awburst[si]), .s_awvalid(s_awvalid[si]),
                .s_awready(s_awready[si]),
                .s_wdata(s_wdata[si]), .s_wstrb(s_wstrb[si]),
                .s_wlast(s_wlast[si]), .s_wvalid(s_wvalid[si]),
                .s_wready(s_wready[si]),
                .s_bid(s_bid[si]), .s_bresp(s_bresp[si]),
                .s_bvalid(s_bvalid[si]), .s_bready(s_bready[si])
            );
        end
    endgenerate

    // ============================================================
    // Per-slave Read Crossbars (NUM_SLAVES=1 each)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : s_rd_xbar
            logic [NUM_MASTERS-1:0][ID_W-1:0]   si_arid;
            logic [NUM_MASTERS-1:0][ADDR_W-1:0] si_araddr;
            logic [NUM_MASTERS-1:0][7:0]        si_arlen;
            logic [NUM_MASTERS-1:0][2:0]        si_arsize;
            logic [NUM_MASTERS-1:0][1:0]        si_arburst;
            logic [NUM_MASTERS-1:0]             si_arvalid;
            logic [NUM_MASTERS-1:0]             si_arready;

            for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_map
                assign si_arid[mi]    = x_arid[mi][si];
                assign si_araddr[mi]  = x_araddr[mi][si];
                assign si_arlen[mi]   = x_arlen[mi][si];
                assign si_arsize[mi]  = x_arsize[mi][si];
                assign si_arburst[mi] = x_arburst[mi][si];
                assign si_arvalid[mi] = x_arvalid[mi][si];
                assign x_arready[mi][si] = si_arready[mi];
            end

            axi_crossbar_rd #(
                .NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(1),
                .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)
            ) u_rd (
                .aclk, .aresetn,
                .m_arid(si_arid), .m_araddr(si_araddr), .m_arlen(si_arlen),
                .m_arsize(si_arsize), .m_arburst(si_arburst),
                .m_arvalid(si_arvalid), .m_arready(si_arready),
                .m_rid(x_rid[si]), .m_rdata(x_rdata[si]),
                .m_rresp(x_rresp[si]), .m_rlast(x_rlast[si]),
                .m_rvalid(x_rvalid[si]), .m_rready(x_rready[si]),
                .s_arid(s_arid[si]), .s_araddr(s_araddr[si]),
                .s_arlen(s_arlen[si]), .s_arsize(s_arsize[si]),
                .s_arburst(s_arburst[si]), .s_arvalid(s_arvalid[si]),
                .s_arready(s_arready[si]),
                .s_rid(s_rid[si]), .s_rdata(s_rdata[si]),
                .s_rresp(s_rresp[si]), .s_rlast(s_rlast[si]),
                .s_rvalid(s_rvalid[si]), .s_rready(s_rready[si])
            );
        end
    endgenerate

    // ============================================================
    // Merge per-slave B/R channels → flat [M] outputs
    // ============================================================
    always_comb begin
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            m_bid[mi]   = '0;
            m_bresp[mi] = '0;
            m_bvalid[mi] = 1'b0;
            m_rid[mi]   = '0;
            m_rdata[mi] = '0;
            m_rresp[mi] = '0;
            m_rlast[mi] = 1'b0;
            m_rvalid[mi] = 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
                if (x_bvalid[si][mi]) begin
                    m_bid[mi]   = x_bid[si][mi];
                    m_bresp[mi] = x_bresp[si][mi];
                    m_bvalid[mi] = 1'b1;
                end
                if (x_rvalid[si][mi]) begin
                    m_rid[mi]   = x_rid[si][mi];
                    m_rdata[mi] = x_rdata[si][mi];
                    m_rresp[mi] = x_rresp[si][mi];
                    m_rlast[mi] = x_rlast[si][mi];
                    m_rvalid[mi] = 1'b1;
                end
            end
        end
    end

    // B/R ready: fan out from master to per-slave crossbar
    always_comb begin
        for (int si = 0; si < NUM_SLAVES; si = si + 1)
            for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
                x_bready[si][mi] = m_bready[mi];
                x_rready[si][mi] = m_rready[mi];
            end
    end

    // ============================================================
    // Master AW/AR/W ready: route from per-slave crossbar with decoder gating
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_rdy
            logic aw_rdy, ar_rdy;
            always_comb begin
                aw_rdy = 1'b0;
                ar_rdy = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si++) begin
                    if (m_aw_sel[mi][si]) aw_rdy = x_awready[mi][si];
                    if (m_ar_sel[mi][si]) ar_rdy = x_arready[mi][si];
                end
            end
            assign m_awready[mi] = aw_rdy;
            assign m_arready[mi] = ar_rdy;

            // W ready: OR across all slave crossbars (no decoder gating).
            // Only the crossbar with w_locked asserts wready.
            assign m_wready[mi] = |x_wready[mi];
        end
    endgenerate

endmodule : axi_interconnect
