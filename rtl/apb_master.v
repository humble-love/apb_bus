// APB3 Master — Thin FSM Controller
// txn_* inputs: driven by testbench (UVM driver)
// req: asserted to arbiter when txn_req is high
// txn_* values are latched on IDLE→REQ to prevent mid-transfer glitches
// APB outputs are zeroed during IDLE per APB3 protocol

module apb_master #(
    parameter MASTER_ID = 0
) (
    input  wire         pclk,
    input  wire         presetn,

    // Arbiter handshake
    output reg          req,
    input  wire         gnt,

    // APB bus outputs (driven in SETUP/ACCESS)
    output reg  [31:0]  paddr,
    output reg  [31:0]  pwdata,
    input  wire [31:0]  prdata,
    output reg          pwrite,
    output reg          psel,
    output reg          penable,
    output reg  [3:0]   pwstrb,
    input  wire         pready,

    // Txn stimulus from testbench
    input  wire         txn_req,
    input  wire [31:0]  txn_addr,
    input  wire [31:0]  txn_wdata,
    input  wire         txn_write
);

    localparam FSM_IDLE   = 3'd0;
    localparam FSM_REQ    = 3'd1;
    localparam FSM_SETUP  = 3'd2;
    localparam FSM_ACCESS = 3'd3;
    localparam FSM_ERROR  = 3'd4;

    reg [2:0] state, next_state;

    // Latched txn values — captured on IDLE→REQ transition
    reg [31:0] latched_addr;
    reg [31:0] latched_wdata;
    reg        latched_write;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state <= FSM_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            FSM_IDLE:   if (txn_req)  next_state = FSM_REQ;
            FSM_REQ:    if (gnt)      next_state = FSM_SETUP;
            FSM_SETUP:                next_state = FSM_ACCESS;
            FSM_ACCESS: if (pready)   next_state = FSM_IDLE;
            default: begin
                $warning("[MASTER %0d] Illegal state 0x%0h, resetting to IDLE", MASTER_ID, state);
                next_state = FSM_IDLE;
            end
        endcase
    end

    // Latch txn_* on IDLE→REQ edge
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            latched_addr  <= 32'd0;
            latched_wdata <= 32'd0;
            latched_write <= 1'b0;
        end else if (state == FSM_IDLE && txn_req) begin
            latched_addr  <= txn_addr;
            latched_wdata <= txn_wdata;
            latched_write <= txn_write;
        end
    end

    // APB bus outputs — driven from latched values, zeroed in IDLE
    always @(*) begin
        case (state)
            FSM_SETUP, FSM_ACCESS: begin
                paddr   = latched_addr;
                pwdata  = latched_wdata;
                pwrite  = latched_write;
                pwstrb  = 4'b1111;
            end
            FSM_REQ: begin
                paddr   = 32'd0;
                pwdata  = 32'd0;
                pwrite  = 1'b0;
                pwstrb  = 4'b0000;
            end
            default: begin
                paddr   = 32'd0;
                pwdata  = 32'd0;
                pwrite  = 1'b0;
                pwstrb  = 4'b0000;
            end
        endcase
    end

    always @(*) begin
        req     = (state == FSM_REQ);
        psel    = (state == FSM_SETUP) || (state == FSM_ACCESS);
        penable = (state == FSM_ACCESS);
    end

endmodule
