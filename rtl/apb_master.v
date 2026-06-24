// APB3 Master — Thin FSM Controller
// txn_* inputs: driven by testbench (UVM driver)
// req: asserted to arbiter when txn_req is high
// APB bus outputs: pass-through from txn_* when in SETUP/ACCESS

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

    reg [2:0] state, next_state;

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
            default:                  next_state = FSM_IDLE;
        endcase
    end

    always @(*) begin
        req     = (state == FSM_REQ);
        psel    = (state == FSM_SETUP) || (state == FSM_ACCESS);
        penable = (state == FSM_ACCESS);
        pwrite  = txn_write;
        paddr   = txn_addr;
        pwdata  = txn_wdata;
    end

endmodule
