// APB3 Arbiter — Fixed Priority (Master 0 > Master 1)
// FSM: IDLE → GRANT → BUSY → IDLE
// Muxes the granted master's APB bus onto the shared APB bus.
// Bus outputs default to safe values (0) when idle.
// req is latched on IDLE→GRANT to prevent premature withdrawal.

module apb_arbiter (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 APB bus
    input  wire         req_0,
    output wire         gnt_0,
    input  wire [31:0]  paddr_0,
    input  wire [31:0]  pwdata_0,
    input  wire         pwrite_0,
    input  wire [3:0]   pwstrb_0,
    input  wire         psel_0,
    input  wire         penable_0,

    // Master 1 APB bus
    input  wire         req_1,
    output wire         gnt_1,
    input  wire [31:0]  paddr_1,
    input  wire [31:0]  pwdata_1,
    input  wire         pwrite_1,
    input  wire [3:0]   pwstrb_1,
    input  wire         psel_1,
    input  wire         penable_1,

    // Shared APB bus output
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire         pwrite,
    output wire [3:0]   pwstrb,
    output wire         psel,
    output wire         penable,

    input  wire         pready
);

    localparam IDLE  = 2'd0;
    localparam GRANT = 2'd1;
    localparam BUSY  = 2'd2;
    // 2'd3 is illegal → error recovery

    reg [1:0] state, next_state;
    reg       granted_master, granted_master_next;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state          <= IDLE;
            granted_master <= 1'b0;
        end else begin
            state          <= next_state;
            granted_master <= granted_master_next;
        end
    end

    always @(*) begin
        next_state          = state;
        granted_master_next = granted_master;
        case (state)
            IDLE: begin
                if (req_0) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b0;
                end else if (req_1) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b1;
                end
            end
            GRANT:  next_state = BUSY;
            BUSY:   if (pready) next_state = IDLE;
            default: begin
                $warning("[ARBITER] Illegal state 0x%0h, resetting to IDLE", state);
                next_state = IDLE;
            end
        endcase
    end

    assign gnt_0 = (state == GRANT) && (granted_master == 1'b0);
    assign gnt_1 = (state == GRANT) && (granted_master == 1'b1);

    // Shared bus mux — gated: only drive active values in BUSY or GRANT
    assign paddr   = (state == BUSY) ? ((granted_master == 1'b0) ? paddr_0   : paddr_1)   : 32'd0;
    assign pwdata  = (state == BUSY) ? ((granted_master == 1'b0) ? pwdata_0  : pwdata_1)  : 32'd0;
    assign pwrite  = (state == BUSY) ? ((granted_master == 1'b0) ? pwrite_0  : pwrite_1)  : 1'b0;
    assign pwstrb  = (state == BUSY) ? ((granted_master == 1'b0) ? pwstrb_0  : pwstrb_1)  : 4'b0000;
    assign psel    = (state == BUSY) ? ((granted_master == 1'b0) ? psel_0    : psel_1)    : 1'b0;
    assign penable = (state == BUSY) ? ((granted_master == 1'b0) ? penable_0 : penable_1) : 1'b0;

endmodule
