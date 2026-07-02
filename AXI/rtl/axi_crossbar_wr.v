// AXI Write Crossbar -- Per-slave AW round-robin arb, W mux + locking, B demux
// 2 masters -> 2 slaves

module axi_crossbar_wr #(
    parameter NUM_MASTERS = 2,
    parameter NUM_SLAVES  = 2,
    parameter ID_W  = 8,
    parameter ADDR_W = 32,
    parameter DATA_W = 256
) (
    input  wire aclk,
    input  wire aresetn,

    // ============================================================
    // Master-side interfaces (M x 1)
    // ============================================================
    // AW channel
    input  wire [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  wire [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  wire [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  wire [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  wire [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  wire [NUM_MASTERS-1:0]             m_awvalid,
    output wire [NUM_MASTERS-1:0]             m_awready,
    // W channel
    input  wire [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  wire [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  wire [NUM_MASTERS-1:0]               m_wlast,
    input  wire [NUM_MASTERS-1:0]               m_wvalid,
    output wire [NUM_MASTERS-1:0]               m_wready,
    // B channel
    output reg  [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output reg  [NUM_MASTERS-1:0][1:0]        m_bresp,
    output reg  [NUM_MASTERS-1:0]             m_bvalid,
    input  wire [NUM_MASTERS-1:0]             m_bready,

    // ============================================================
    // Slave-side interfaces (S x 1)
    // ============================================================
    // AW channel
    output wire [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output wire [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output wire [NUM_SLAVES-1:0][7:0]        s_awlen,
    output wire [NUM_SLAVES-1:0][2:0]        s_awsize,
    output wire [NUM_SLAVES-1:0][1:0]        s_awburst,
    output wire [NUM_SLAVES-1:0]             s_awvalid,
    input  wire [NUM_SLAVES-1:0]             s_awready,
    // W channel
    output wire [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output wire [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output wire [NUM_SLAVES-1:0]               s_wlast,
    output wire [NUM_SLAVES-1:0]               s_wvalid,
    input  wire [NUM_SLAVES-1:0]               s_wready,
    // B channel
    input  wire [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  wire [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  wire [NUM_SLAVES-1:0]             s_bvalid,
    output wire [NUM_SLAVES-1:0]             s_bready
);

    // Per-slave: current AW owner (which master is granted for this slave)
    reg [NUM_SLAVES-1:0]                    aw_owner;       // which master
    reg [NUM_SLAVES-1:0]                    aw_owner_valid; // grant active
    reg [NUM_SLAVES-1:0]                    rr_ptr;         // round-robin pointer (1 bit per slave)

    // W channel locking: per-slave, lock from AW grant until WLAST
    reg [NUM_SLAVES-1:0]                    w_owner;       // which master
    reg [NUM_SLAVES-1:0]                    w_locked;      // W burst in progress

    genvar si, mi;

    // ============================================================
    // Per-slave AW arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : aw_arb

            // Combinational: find next requesting master starting from rr_ptr
            reg [NUM_MASTERS-1:0] req_mask;
            reg next_master;
            reg has_req;

            always @(*) begin : find_next_master
                integer m_off;
                integer m_idx;
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_awvalid[m_idx] && !aw_owner_valid[si]) begin
                        next_master = m_idx[0];
                        has_req = 1'b1;
                        disable find_next_master;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    aw_owner[si]       <= 1'b0;
                    aw_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= 1'b0;
                end else begin
                    // AW grant: assign owner on handshake
                    if (!aw_owner_valid[si] && !w_locked[si] && has_req) begin
                        aw_owner[si]       <= next_master;
                        aw_owner_valid[si] <= 1'b1;
                        rr_ptr[si]         <= (next_master + 1) % NUM_MASTERS;
                    end
                    // Release AW grant on AW handshake
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        aw_owner_valid[si] <= 1'b0;
                    end
                end
            end

            // AW channel output -- mux from granted master
            assign s_awid[si]    = (aw_owner_valid[si]) ? m_awid[aw_owner[si]]    : {ID_W{1'b0}};
            assign s_awaddr[si]  = (aw_owner_valid[si]) ? m_awaddr[aw_owner[si]]  : {ADDR_W{1'b0}};
            assign s_awlen[si]   = (aw_owner_valid[si]) ? m_awlen[aw_owner[si]]   : {8{1'b0}};
            assign s_awsize[si]  = (aw_owner_valid[si]) ? m_awsize[aw_owner[si]]  : {3{1'b0}};
            assign s_awburst[si] = (aw_owner_valid[si]) ? m_awburst[aw_owner[si]] : {2{1'b0}};
            assign s_awvalid[si] = aw_owner_valid[si];

            // W channel locking: lock when AW handshake completes
            always @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    w_locked[si] <= 1'b0;
                    w_owner[si]  <= 1'b0;
                end else begin
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        w_locked[si] <= 1'b1;
                        w_owner[si]  <= aw_owner[si];
                    end
                    // Release lock when B handshake completes.
                    // Must NOT clear on W last beat: B response arrives one cycle
                    // later and B routing also depends on w_locked.
                    if (w_locked[si] && s_bvalid[si] && s_bready[si]) begin
                        w_locked[si] <= 1'b0;
                    end
                end
            end

            // W channel output -- mux from locked master
            assign s_wdata[si]  = (w_locked[si]) ? m_wdata[w_owner[si]]  : {DATA_W{1'b0}};
            assign s_wstrb[si]  = (w_locked[si]) ? m_wstrb[w_owner[si]]  : {(DATA_W/8){1'b0}};
            assign s_wlast[si]  = (w_locked[si]) ? m_wlast[w_owner[si]]  : 1'b0;
            assign s_wvalid[si] = w_locked[si] && m_wvalid[w_owner[si]];

            // B channel -- demux to locked master
            assign s_bready[si] = w_locked[si] && m_bready[w_owner[si]];

        end // per-slave
    endgenerate

    // ============================================================
    // Master-side ready signals
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ready
            reg aw_ready_sig, w_ready_sig;
            always @(*) begin
                integer si_inner;
                aw_ready_sig = 1'b0;
                w_ready_sig  = 1'b0;
                for (si_inner = 0; si_inner < NUM_SLAVES; si_inner = si_inner + 1) begin
                    if (aw_owner_valid[si_inner] && aw_owner[si_inner] == mi)
                        aw_ready_sig = s_awready[si_inner];
                    if (w_locked[si_inner] && w_owner[si_inner] == mi)
                        w_ready_sig = s_wready[si_inner];
                end
            end
            assign m_awready[mi] = aw_ready_sig;
            assign m_wready[mi]  = w_ready_sig;
        end
    endgenerate

    // ============================================================
    // B channel -- route from slave to owner master
    // ============================================================
    always @(*) begin
        integer mi_idx, si_idx;
        for (mi_idx = 0; mi_idx < NUM_MASTERS; mi_idx = mi_idx + 1) begin
            m_bid[mi_idx]   = {ID_W{1'b0}};
            m_bresp[mi_idx] = {2{1'b0}};
            m_bvalid[mi_idx] = 1'b0;
        end
        for (si_idx = 0; si_idx < NUM_SLAVES; si_idx = si_idx + 1) begin
            if (w_locked[si_idx] && s_bvalid[si_idx]) begin
                m_bid[w_owner[si_idx]]    = s_bid[si_idx];
                m_bresp[w_owner[si_idx]]  = s_bresp[si_idx];
                m_bvalid[w_owner[si_idx]] = 1'b1;
            end
        end
    end

endmodule
