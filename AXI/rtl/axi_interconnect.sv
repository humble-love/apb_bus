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

                // W
                assign x_wdata[mi][si]  = m_wdata[mi];
                assign x_wstrb[mi][si]  = m_wstrb[mi];
                assign x_wlast[mi][si]  = m_wlast[mi];
                assign x_wvalid[mi][si] = m_wvalid[mi] && m_aw_sel[mi][si];

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

    // ============================================================
    // Write Crossbar
    // ============================================================
    axi_crossbar_wr #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                      .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_crossbar_wr (
        .aclk, .aresetn,
        .m_awid   (x_awid),   .m_awaddr  (x_awaddr),  .m_awlen (x_awlen),
        .m_awsize (x_awsize), .m_awburst (x_awburst), .m_awvalid(x_awvalid),
        .m_awready(x_awready),
        .m_wdata  (x_wdata),  .m_wstrb   (x_wstrb),   .m_wlast (x_wlast),
        .m_wvalid (x_wvalid), .m_wready  (x_wready),
        .m_bid    (m_bid),    .m_bresp   (m_bresp),   .m_bvalid(m_bvalid),
        .m_bready (m_bready),
        .s_awid   (s_awid),   .s_awaddr  (s_awaddr),  .s_awlen (s_awlen),
        .s_awsize (s_awsize), .s_awburst (s_awburst), .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata  (s_wdata),  .s_wstrb   (s_wstrb),   .s_wlast (s_wlast),
        .s_wvalid (s_wvalid), .s_wready  (s_wready),
        .s_bid    (s_bid),    .s_bresp   (s_bresp),   .s_bvalid(s_bvalid),
        .s_bready (s_bready)
    );

    // ============================================================
    // Read Crossbar
    // ============================================================
    axi_crossbar_rd #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                      .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_crossbar_rd (
        .aclk, .aresetn,
        .m_arid   (x_arid),   .m_araddr  (x_araddr),  .m_arlen (x_arlen),
        .m_arsize (x_arsize), .m_arburst (x_arburst), .m_arvalid(x_arvalid),
        .m_arready(x_arready),
        .m_rid    (m_rid),    .m_rdata   (m_rdata),   .m_rresp (m_rresp),
        .m_rlast  (m_rlast),  .m_rvalid  (m_rvalid),  .m_rready(m_rready),
        .s_arid   (s_arid),   .s_araddr  (s_araddr),  .s_arlen (s_arlen),
        .s_arsize (s_arsize), .s_arburst (s_arburst), .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid    (s_rid),    .s_rdata   (s_rdata),   .s_rresp (s_rresp),
        .s_rlast  (s_rlast),  .s_rvalid  (s_rvalid),  .s_rready(s_rready)
    );

    // Master AW/AR ready: route from crossbar with decoder gating
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

            // W ready
            logic w_rdy;
            always_comb begin
                w_rdy = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si++)
                    if (m_aw_sel[mi][si]) w_rdy = x_wready[mi][si];
            end
            assign m_wready[mi] = w_rdy;
        end
    endgenerate

endmodule : axi_interconnect
