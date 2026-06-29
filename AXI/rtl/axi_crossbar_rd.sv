// AXI Read Crossbar — Per-slave AR round-robin arb, R demux with ID LUT
// 2 masters → 2 slaves
// Supports out-of-order R responses via ID lookup table

module axi_crossbar_rd #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master-side interfaces
    // ============================================================
    // AR channel
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  logic [NUM_MASTERS-1:0]             m_arvalid,
    output logic [NUM_MASTERS-1:0]             m_arready,
    // R channel
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output logic [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]        m_rresp,
    output logic [NUM_MASTERS-1:0]             m_rlast,
    output logic [NUM_MASTERS-1:0]             m_rvalid,
    input  logic [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave-side interfaces
    // ============================================================
    // AR channel
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_arlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_arsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_arburst,
    output logic [NUM_SLAVES-1:0]             s_arvalid,
    input  logic [NUM_SLAVES-1:0]             s_arready,
    // R channel
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  logic [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  logic [NUM_SLAVES-1:0]             s_rlast,
    input  logic [NUM_SLAVES-1:0]             s_rvalid,
    output logic [NUM_SLAVES-1:0]             s_rready
);

    localparam int LUT_DEPTH = 1 << ID_W;

    // Per-slave: current AR owner
    logic [NUM_SLAVES-1:0]                             ar_owner;
    logic [NUM_SLAVES-1:0]                             ar_owner_valid;
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0]    rr_ptr;

    // ID Lookup Table: per-slave, LUT_DEPTH entries × (master_id + valid)
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0]    id_lut_master [LUT_DEPTH-1:0];
    logic [NUM_SLAVES-1:0]                             id_lut_valid  [LUT_DEPTH-1:0];

    genvar si;

    // ============================================================
    // Per-slave AR arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : ar_arb
            logic [$clog2(NUM_MASTERS)-1:0] next_master;
            logic has_req;

            always_comb begin
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (int m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    automatic int m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_arvalid[m_idx] && !ar_owner_valid[si]) begin
                        next_master = m_idx;
                        has_req = 1'b1;
                        break;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    ar_owner[si]       <= '0;
                    ar_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= '0;
                end else begin
                    if (!ar_owner_valid[si] && has_req) begin
                        ar_owner[si]       <= next_master;
                        ar_owner_valid[si] <= 1'b1;
                        rr_ptr[si]         <= (next_master + 1) % NUM_MASTERS;
                    end
                    if (ar_owner_valid[si] && s_arvalid[si] && s_arready[si]) begin
                        ar_owner_valid[si] <= 1'b0;
                    end
                end
            end

            // AR channel output — mux from granted master
            assign s_arid[si]    = (ar_owner_valid[si]) ? m_arid[ar_owner[si]]    : '0;
            assign s_araddr[si]  = (ar_owner_valid[si]) ? m_araddr[ar_owner[si]]  : '0;
            assign s_arlen[si]   = (ar_owner_valid[si]) ? m_arlen[ar_owner[si]]   : '0;
            assign s_arsize[si]  = (ar_owner_valid[si]) ? m_arsize[ar_owner[si]]  : '0;
            assign s_arburst[si] = (ar_owner_valid[si]) ? m_arburst[ar_owner[si]] : '0;
            assign s_arvalid[si] = ar_owner_valid[si];

            // ========================================================
            // ID LUT: write on AR handshake
            // ========================================================
            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    for (int i = 0; i < LUT_DEPTH; i = i + 1) begin
                        id_lut_valid[si][i]  <= 1'b0;
                        id_lut_master[si][i] <= '0;
                    end
                end else begin
                    // Write on AR handshake
                    if (ar_owner_valid[si] && s_arvalid[si] && s_arready[si]) begin
                        id_lut_valid[si][m_arid[ar_owner[si]]]  <= 1'b1;
                        id_lut_master[si][m_arid[ar_owner[si]]] <= ar_owner[si];
                    end
                    // Clear on R last beat handshake
                    if (s_rvalid[si] && s_rready[si] && s_rlast[si]) begin
                        id_lut_valid[si][s_rid[si]] <= 1'b0;
                    end
                end
            end

        end // per-slave
    endgenerate

    // ============================================================
    // Master AR ready — route from granted slave
    // ============================================================
    generate
        genvar mi;
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ar_rdy
            logic ar_ready_sig;
            always_comb begin
                ar_ready_sig = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
                    if (ar_owner_valid[si] && ar_owner[si] == mi)
                        ar_ready_sig = s_arready[si];
                end
            end
            assign m_arready[mi] = ar_ready_sig;
        end
    endgenerate

    // ============================================================
    // R channel demux — ID LUT lookup
    // ============================================================
    always_comb begin
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            m_rid[mi]    = '0;
            m_rdata[mi]  = '0;
            m_rresp[mi]  = '0;
            m_rlast[mi]  = 1'b0;
            m_rvalid[mi] = 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (s_rvalid[si]) begin
                automatic int r_master = id_lut_master[si][s_rid[si]];
                if (id_lut_valid[si][s_rid[si]]) begin
                    m_rid[r_master]    = s_rid[si];
                    m_rdata[r_master]  = s_rdata[si];
                    m_rresp[r_master]  = s_rresp[si];
                    m_rlast[r_master]  = s_rlast[si];
                    m_rvalid[r_master] = 1'b1;
                end
            end
        end
    end

    // ============================================================
    // R ready — route from master to slave
    // ============================================================
    always_comb begin
        s_rready = '0;
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (s_rvalid[si] && id_lut_valid[si][s_rid[si]])
                s_rready[si] = m_rready[id_lut_master[si][s_rid[si]]];
        end
    end

endmodule : axi_crossbar_rd
