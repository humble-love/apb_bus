// APB3 Arbiter — Fixed Priority (Master 0 > Master 1)
// FSM: IDLE → GRANT → BUSY → IDLE
// Muxes the granted master's APB bus onto the shared APB bus

module apb_arbiter (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 APB bus
    input  wire         req_0,
    output wire         gnt_0,
    input  wire [31:0]  paddr_0,
    input  wire [31:0]  pwdata_0,
    input  wire         pwrite_0,
    input  wire         psel_0,
    input  wire         penable_0,

    // Master 1 APB bus
    input  wire         req_1,
    output wire         gnt_1,
    input  wire [31:0]  paddr_1,
    input  wire [31:0]  pwdata_1,
    input  wire         pwrite_1,
    input  wire         psel_1,
    input  wire         penable_1,

    // Shared APB bus output
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,

    input  wire         pready
);

    localparam IDLE  = 2'd0;
    localparam GRANT = 2'd1;
    localparam BUSY  = 2'd2;

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
            default: next_state = IDLE;
        endcase
    end

    assign gnt_0 = (state == GRANT) && (granted_master == 1'b0);
    assign gnt_1 = (state == GRANT) && (granted_master == 1'b1);

    assign paddr   = (granted_master == 1'b0) ? paddr_0   : paddr_1;
    assign pwdata  = (granted_master == 1'b0) ? pwdata_0  : pwdata_1;
    assign pwrite  = (granted_master == 1'b0) ? pwrite_0  : pwrite_1;
    assign psel    = (granted_master == 1'b0) ? psel_0    : psel_1;
    assign penable = (granted_master == 1'b0) ? penable_0 : penable_1;

endmodule
