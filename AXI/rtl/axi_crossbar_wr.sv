// AXI Write Crossbar — Per-slave AW round-robin arb, W mux + locking, B demux
// 2 masters → 2 slaves

module axi_crossbar_wr #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master-side interfaces (M x 1)
    // ============================================================
    // AW channel
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  logic [NUM_MASTERS-1:0]             m_awvalid,
    output logic [NUM_MASTERS-1:0]             m_awready,
    // W channel
    input  logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]               m_wlast,
    input  logic [NUM_MASTERS-1:0]               m_wvalid,
    output logic [NUM_MASTERS-1:0]               m_wready,
    // B channel
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output logic [NUM_MASTERS-1:0][1:0]        m_bresp,
    output logic [NUM_MASTERS-1:0]             m_bvalid,
    input  logic [NUM_MASTERS-1:0]             m_bready,

    // ============================================================
    // Slave-side interfaces (S x 1)
    // ============================================================
    // AW channel
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_awlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_awsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_awburst,
    output logic [NUM_SLAVES-1:0]             s_awvalid,
    input  logic [NUM_SLAVES-1:0]             s_awready,
    // W channel
    output logic [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]               s_wlast,
    output logic [NUM_SLAVES-1:0]               s_wvalid,
    input  logic [NUM_SLAVES-1:0]               s_wready,
    // B channel
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  logic [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  logic [NUM_SLAVES-1:0]             s_bvalid,
    output logic [NUM_SLAVES-1:0]             s_bready
);

    // Per-slave: current AW owner (which master is granted for this slave)
    logic [NUM_SLAVES-1:0]                    aw_owner;       // which master
    logic [NUM_SLAVES-1:0]                    aw_owner_valid; // grant active
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0] rr_ptr;  // round-robin pointer

    // W channel locking: per-slave, lock from AW grant until WLAST
    logic [NUM_SLAVES-1:0]                    w_owner;       // which master
    logic [NUM_SLAVES-1:0]                    w_locked;      // W burst in progress

    genvar si, mi;

    // ============================================================
    // Per-slave AW arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : aw_arb

            // Combinational: find next requesting master starting from rr_ptr
            logic [NUM_MASTERS-1:0] req_mask;
            logic [$clog2(NUM_MASTERS)-1:0] next_master;
            logic has_req;

            always_comb begin
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (int m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    automatic int m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_awvalid[m_idx] && !aw_owner_valid[si]) begin
                        next_master = m_idx;
                        has_req = 1'b1;
                        break;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    aw_owner[si]       <= '0;
                    aw_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= '0;
                end else begin
                    // AW grant: assign owner on handshake
                    if (!aw_owner_valid[si] && !w_locked[si] && has_req) begin
                        aw_owner[si]       <= next_master[$clog2(NUM_MASTERS)-1:0];
                        aw_owner_valid[si] <= 1'b1;
                        rr_ptr[si]         <= (next_master + 1) % NUM_MASTERS;
                    end
                    // Release AW grant on AW handshake
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        aw_owner_valid[si] <= 1'b0;
                    end
                end
            end

            // AW channel output — mux from granted master
            assign s_awid[si]    = (aw_owner_valid[si]) ? m_awid[aw_owner[si]]    : '0;
            assign s_awaddr[si]  = (aw_owner_valid[si]) ? m_awaddr[aw_owner[si]]  : '0;
            assign s_awlen[si]   = (aw_owner_valid[si]) ? m_awlen[aw_owner[si]]   : '0;
            assign s_awsize[si]  = (aw_owner_valid[si]) ? m_awsize[aw_owner[si]]  : '0;
            assign s_awburst[si] = (aw_owner_valid[si]) ? m_awburst[aw_owner[si]] : '0;
            assign s_awvalid[si] = aw_owner_valid[si];

            // W channel locking: lock when AW handshake completes
            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    w_locked[si] <= 1'b0;
                    w_owner[si]  <= '0;
                end else begin
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        w_locked[si] <= 1'b1;
                        w_owner[si]  <= aw_owner[si];
                    end
                    if (w_locked[si] && s_wvalid[si] && s_wready[si] && s_wlast[si]) begin
                        w_locked[si] <= 1'b0;
                    end
                end
            end

            // W channel output — mux from locked master
            assign s_wdata[si]  = (w_locked[si]) ? m_wdata[w_owner[si]]  : '0;
            assign s_wstrb[si]  = (w_locked[si]) ? m_wstrb[w_owner[si]]  : '0;
            assign s_wlast[si]  = (w_locked[si]) ? m_wlast[w_owner[si]]  : 1'b0;
            assign s_wvalid[si] = w_locked[si] && m_wvalid[w_owner[si]];

            // B channel — demux to locked master
            assign s_bready[si] = w_locked[si] && m_bready[w_owner[si]];

        end // per-slave
    endgenerate

    // ============================================================
    // Master-side ready signals
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ready
            logic aw_ready_sig, w_ready_sig;
            always_comb begin
                aw_ready_sig = 1'b0;
                w_ready_sig  = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
                    if (aw_owner_valid[si] && aw_owner[si] == mi)
                        aw_ready_sig = s_awready[si];
                    if (w_locked[si] && w_owner[si] == mi)
                        w_ready_sig = s_wready[si];
                end
            end
            assign m_awready[mi] = aw_ready_sig;
            assign m_wready[mi]  = w_ready_sig;
        end
    endgenerate

    // ============================================================
    // B channel — route from slave to owner master
    // ============================================================
    always_comb begin
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            m_bid[mi]   = '0;
            m_bresp[mi] = '0;
            m_bvalid[mi] = 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (w_locked[si] && s_bvalid[si]) begin
                m_bid[w_owner[si]]    = s_bid[si];
                m_bresp[w_owner[si]]  = s_bresp[si];
                m_bvalid[w_owner[si]] = 1'b1;
            end
        end
    end

endmodule : axi_crossbar_wr
