// AXI Interconnect -- Crossbar + Address Decoder integration
// 2 masters -> decoder -> write/read crossbars -> 2 slaves

module axi_interconnect #(
    parameter NUM_MASTERS = 2,
    parameter NUM_SLAVES  = 2,
    parameter ID_W  = 8,
    parameter ADDR_W = 32,
    parameter DATA_W = 256
) (
    input  wire aclk,
    input  wire aresetn,

    // ============================================================
    // Master ports (M x 5 channels)
    // ============================================================
    // AW
    input  wire [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  wire [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  wire [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  wire [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  wire [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  wire [NUM_MASTERS-1:0]             m_awvalid,
    output wire [NUM_MASTERS-1:0]             m_awready,
    // W
    input  wire [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  wire [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  wire [NUM_MASTERS-1:0]               m_wlast,
    input  wire [NUM_MASTERS-1:0]               m_wvalid,
    output wire [NUM_MASTERS-1:0]               m_wready,
    // B
    output reg  [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output reg  [NUM_MASTERS-1:0][1:0]        m_bresp,
    output reg  [NUM_MASTERS-1:0]             m_bvalid,
    input  wire [NUM_MASTERS-1:0]             m_bready,
    // AR
    input  wire [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  wire [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  wire [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  wire [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  wire [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  wire [NUM_MASTERS-1:0]             m_arvalid,
    output wire [NUM_MASTERS-1:0]             m_arready,
    // R
    output reg  [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output reg  [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output reg  [NUM_MASTERS-1:0][1:0]        m_rresp,
    output reg  [NUM_MASTERS-1:0]             m_rlast,
    output reg  [NUM_MASTERS-1:0]             m_rvalid,
    input  wire [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave ports
    // ============================================================
    // AW
    output wire [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output wire [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output wire [NUM_SLAVES-1:0][7:0]        s_awlen,
    output wire [NUM_SLAVES-1:0][2:0]        s_awsize,
    output wire [NUM_SLAVES-1:0][1:0]        s_awburst,
    output wire [NUM_SLAVES-1:0]             s_awvalid,
    input  wire [NUM_SLAVES-1:0]             s_awready,
    // W
    output wire [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output wire [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output wire [NUM_SLAVES-1:0]               s_wlast,
    output wire [NUM_SLAVES-1:0]               s_wvalid,
    input  wire [NUM_SLAVES-1:0]               s_wready,
    // B
    input  wire [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  wire [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  wire [NUM_SLAVES-1:0]             s_bvalid,
    output wire [NUM_SLAVES-1:0]             s_bready,
    // AR
    output wire [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output wire [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output wire [NUM_SLAVES-1:0][7:0]        s_arlen,
    output wire [NUM_SLAVES-1:0][2:0]        s_arsize,
    output wire [NUM_SLAVES-1:0][1:0]        s_arburst,
    output wire [NUM_SLAVES-1:0]             s_arvalid,
    input  wire [NUM_SLAVES-1:0]             s_arready,
    // R
    input  wire [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  wire [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  wire [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  wire [NUM_SLAVES-1:0]             s_rlast,
    input  wire [NUM_SLAVES-1:0]             s_rvalid,
    output wire [NUM_SLAVES-1:0]             s_rready
);

    // Decoder outputs
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0] m_aw_sel, m_ar_sel;
    wire [NUM_MASTERS-1:0]                m_aw_decerr, m_ar_decerr;

    // Per-master -> per-slave AW/W signals (gated by decoder)
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_awid;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_awaddr;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_awlen;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_awsize;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_awburst;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awvalid;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awready;

    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W-1:0]   x_wdata;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W/8-1:0] x_wstrb;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wlast;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wvalid;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wready;

    // Per-master -> per-slave AR signals
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_arid;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_araddr;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_arlen;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_arsize;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_arburst;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arvalid;
    wire [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arready;

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

                // W: no decoder gating -- awvalid is deasserted after AW handshake
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
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0][ID_W-1:0]   x_bid;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0][1:0]        x_bresp;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_bvalid;
    reg  [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_bready;

    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0][ID_W-1:0]   x_rid;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0][DATA_W-1:0] x_rdata;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0][1:0]        x_rresp;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rlast;
    wire [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rvalid;
    reg  [NUM_SLAVES-1:0][NUM_MASTERS-1:0]             x_rready;

    // ============================================================
    // Per-slave Write Crossbars (NUM_SLAVES=1 each)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : s_wr_xbar
            // Extract [M] signals from [M][S] for this slave
            wire [NUM_MASTERS-1:0][ID_W-1:0]   si_awid;
            wire [NUM_MASTERS-1:0][ADDR_W-1:0] si_awaddr;
            wire [NUM_MASTERS-1:0][7:0]        si_awlen;
            wire [NUM_MASTERS-1:0][2:0]        si_awsize;
            wire [NUM_MASTERS-1:0][1:0]        si_awburst;
            wire [NUM_MASTERS-1:0]             si_awvalid;
            wire [NUM_MASTERS-1:0]             si_awready;
            wire [NUM_MASTERS-1:0][DATA_W-1:0]   si_wdata;
            wire [NUM_MASTERS-1:0][DATA_W/8-1:0] si_wstrb;
            wire [NUM_MASTERS-1:0]               si_wlast;
            wire [NUM_MASTERS-1:0]               si_wvalid;
            wire [NUM_MASTERS-1:0]               si_wready;

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
                .aclk(aclk), .aresetn(aresetn),
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
            wire [NUM_MASTERS-1:0][ID_W-1:0]   si_arid;
            wire [NUM_MASTERS-1:0][ADDR_W-1:0] si_araddr;
            wire [NUM_MASTERS-1:0][7:0]        si_arlen;
            wire [NUM_MASTERS-1:0][2:0]        si_arsize;
            wire [NUM_MASTERS-1:0][1:0]        si_arburst;
            wire [NUM_MASTERS-1:0]             si_arvalid;
            wire [NUM_MASTERS-1:0]             si_arready;

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
                .aclk(aclk), .aresetn(aresetn),
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
    // Merge per-slave B/R channels -> flat [M] outputs
    // ============================================================
    always @(*) begin
        integer mi2, si2;
        for (mi2 = 0; mi2 < NUM_MASTERS; mi2 = mi2 + 1) begin
            m_bid[mi2]   = {ID_W{1'b0}};
            m_bresp[mi2] = {2{1'b0}};
            m_bvalid[mi2] = 1'b0;
            m_rid[mi2]   = {ID_W{1'b0}};
            m_rdata[mi2] = {DATA_W{1'b0}};
            m_rresp[mi2] = {2{1'b0}};
            m_rlast[mi2] = 1'b0;
            m_rvalid[mi2] = 1'b0;
        end
        for (si2 = 0; si2 < NUM_SLAVES; si2 = si2 + 1) begin
            for (mi2 = 0; mi2 < NUM_MASTERS; mi2 = mi2 + 1) begin
                if (x_bvalid[si2][mi2]) begin
                    m_bid[mi2]   = x_bid[si2][mi2];
                    m_bresp[mi2] = x_bresp[si2][mi2];
                    m_bvalid[mi2] = 1'b1;
                end
                if (x_rvalid[si2][mi2]) begin
                    m_rid[mi2]   = x_rid[si2][mi2];
                    m_rdata[mi2] = x_rdata[si2][mi2];
                    m_rresp[mi2] = x_rresp[si2][mi2];
                    m_rlast[mi2] = x_rlast[si2][mi2];
                    m_rvalid[mi2] = 1'b1;
                end
            end
        end
    end

    // B/R ready: fan out from master to per-slave crossbar
    always @(*) begin
        integer si3, mi3;
        for (si3 = 0; si3 < NUM_SLAVES; si3 = si3 + 1)
            for (mi3 = 0; mi3 < NUM_MASTERS; mi3 = mi3 + 1) begin
                x_bready[si3][mi3] = m_bready[mi3];
                x_rready[si3][mi3] = m_rready[mi3];
            end
    end

    // ============================================================
    // Master AW/AR/W ready: route from per-slave crossbar with decoder gating
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_rdy
            reg aw_rdy, ar_rdy;
            always @(*) begin
                integer si_inner;
                aw_rdy = 1'b0;
                ar_rdy = 1'b0;
                for (si_inner = 0; si_inner < NUM_SLAVES; si_inner = si_inner + 1) begin
                    if (m_aw_sel[mi][si_inner]) aw_rdy = x_awready[mi][si_inner];
                    if (m_ar_sel[mi][si_inner]) ar_rdy = x_arready[mi][si_inner];
                end
            end
            assign m_awready[mi] = aw_rdy;
            assign m_arready[mi] = ar_rdy;

            // W ready: OR across all slave crossbars (no decoder gating).
            // Only the crossbar with w_locked asserts wready.
            assign m_wready[mi] = |x_wready[mi];
        end
    endgenerate

endmodule
