// AXI Read Crossbar -- Per-slave AR round-robin arb, R demux with ID LUT
// 2 masters -> 2 slaves
// Supports out-of-order R responses via ID lookup table

module axi_crossbar_rd #(
    parameter NUM_MASTERS = 2,
    parameter NUM_SLAVES  = 2,
    parameter ID_W  = 8,
    parameter ADDR_W = 32,
    parameter DATA_W = 256
) (
    input  wire aclk,
    input  wire aresetn,

    // ============================================================
    // Master-side interfaces
    // ============================================================
    // AR channel
    input  wire [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  wire [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  wire [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  wire [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  wire [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  wire [NUM_MASTERS-1:0]             m_arvalid,
    output wire [NUM_MASTERS-1:0]             m_arready,
    // R channel
    output reg  [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output reg  [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output reg  [NUM_MASTERS-1:0][1:0]        m_rresp,
    output reg  [NUM_MASTERS-1:0]             m_rlast,
    output reg  [NUM_MASTERS-1:0]             m_rvalid,
    input  wire [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave-side interfaces
    // ============================================================
    // AR channel
    output wire [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output wire [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output wire [NUM_SLAVES-1:0][7:0]        s_arlen,
    output wire [NUM_SLAVES-1:0][2:0]        s_arsize,
    output wire [NUM_SLAVES-1:0][1:0]        s_arburst,
    output wire [NUM_SLAVES-1:0]             s_arvalid,
    input  wire [NUM_SLAVES-1:0]             s_arready,
    // R channel
    input  wire [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  wire [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  wire [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  wire [NUM_SLAVES-1:0]             s_rlast,
    input  wire [NUM_SLAVES-1:0]             s_rvalid,
    output reg  [NUM_SLAVES-1:0]             s_rready
);

    localparam LUT_DEPTH = 256;

    // Per-slave: current AR owner
    reg [NUM_SLAVES-1:0]                             ar_owner;
    reg [NUM_SLAVES-1:0]                             ar_owner_valid;
    reg [NUM_SLAVES-1:0]                             rr_ptr;

    // ID Lookup Table: per-slave, LUT_DEPTH entries x (master_id + valid)
    // Each entry is 2-bit packed: bit 0 = slave 0's master, bit 1 = slave 1's master
    reg [NUM_SLAVES-1:0]                             id_lut_master [0:LUT_DEPTH-1];
    reg [NUM_SLAVES-1:0]                             id_lut_valid  [0:LUT_DEPTH-1];

    genvar si;

    // ============================================================
    // Per-slave AR arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : ar_arb
            reg next_master;
            reg has_req;

            always @(*) begin : find_next_master
                integer m_off;
                integer m_idx;
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_arvalid[m_idx] && !ar_owner_valid[si]) begin
                        next_master = m_idx[0];
                        has_req = 1'b1;
                        disable find_next_master;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    ar_owner[si]       <= 1'b0;
                    ar_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= 1'b0;
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

            // AR channel output -- mux from granted master
            assign s_arid[si]    = (ar_owner_valid[si]) ? m_arid[ar_owner[si]]    : {ID_W{1'b0}};
            assign s_araddr[si]  = (ar_owner_valid[si]) ? m_araddr[ar_owner[si]]  : {ADDR_W{1'b0}};
            assign s_arlen[si]   = (ar_owner_valid[si]) ? m_arlen[ar_owner[si]]   : {8{1'b0}};
            assign s_arsize[si]  = (ar_owner_valid[si]) ? m_arsize[ar_owner[si]]  : {3{1'b0}};
            assign s_arburst[si] = (ar_owner_valid[si]) ? m_arburst[ar_owner[si]] : {2{1'b0}};
            assign s_arvalid[si] = ar_owner_valid[si];

            // ========================================================
            // ID LUT: write on AR handshake
            // ========================================================
            always @(posedge aclk or negedge aresetn) begin
                integer i;
                if (!aresetn) begin
                    for (i = 0; i < LUT_DEPTH; i = i + 1) begin
                        id_lut_valid[i][si]  <= 1'b0;
                        id_lut_master[i][si] <= 1'b0;
                    end
                end else begin
                    // Write on AR handshake
                    if (ar_owner_valid[si] && s_arvalid[si] && s_arready[si]) begin
                        id_lut_valid[m_arid[ar_owner[si]]][si]  <= 1'b1;
                        id_lut_master[m_arid[ar_owner[si]]][si] <= ar_owner[si];
                    end
                    // Clear on R last beat handshake
                    if (s_rvalid[si] && s_rready[si] && s_rlast[si]) begin
                        id_lut_valid[s_rid[si]][si] <= 1'b0;
                    end
                end
            end

        end // per-slave
    endgenerate

    // ============================================================
    // Master AR ready -- route from granted slave
    // ============================================================
    generate
        genvar mi;
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ar_rdy
            reg ar_ready_sig;
            always @(*) begin
                integer si_inner;
                ar_ready_sig = 1'b0;
                for (si_inner = 0; si_inner < NUM_SLAVES; si_inner = si_inner + 1) begin
                    if (ar_owner_valid[si_inner] && ar_owner[si_inner] == mi)
                        ar_ready_sig = s_arready[si_inner];
                end
            end
            assign m_arready[mi] = ar_ready_sig;
        end
    endgenerate

    // ============================================================
    // R channel demux -- ID LUT lookup
    // ============================================================
    always @(*) begin
        integer mi_idx, si_idx;
        integer r_master;
        for (mi_idx = 0; mi_idx < NUM_MASTERS; mi_idx = mi_idx + 1) begin
            m_rid[mi_idx]    = {ID_W{1'b0}};
            m_rdata[mi_idx]  = {DATA_W{1'b0}};
            m_rresp[mi_idx]  = {2{1'b0}};
            m_rlast[mi_idx]  = 1'b0;
            m_rvalid[mi_idx] = 1'b0;
        end
        for (si_idx = 0; si_idx < NUM_SLAVES; si_idx = si_idx + 1) begin
            if (s_rvalid[si_idx]) begin
                r_master = id_lut_master[s_rid[si_idx]][si_idx];
                if (id_lut_valid[s_rid[si_idx]][si_idx]) begin
                    m_rid[r_master]    = s_rid[si_idx];
                    m_rdata[r_master]  = s_rdata[si_idx];
                    m_rresp[r_master]  = s_rresp[si_idx];
                    m_rlast[r_master]  = s_rlast[si_idx];
                    m_rvalid[r_master] = 1'b1;
                end
            end
        end
    end

    // ============================================================
    // R ready -- route from master to slave
    // ============================================================
    always @(*) begin
        integer si_idx2;
        s_rready = {NUM_SLAVES{1'b0}};
        for (si_idx2 = 0; si_idx2 < NUM_SLAVES; si_idx2 = si_idx2 + 1) begin
            if (s_rvalid[si_idx2] && id_lut_valid[s_rid[si_idx2]][si_idx2])
                s_rready[si_idx2] = m_rready[id_lut_master[s_rid[si_idx2]][si_idx2]];
        end
    end

endmodule
