// AXI4-Full Master -- Per-channel FSMs + transaction sequencer
// 256-bit data, 8-bit ID, 32-bit address
// Single-issue FSM (TB driver handles burst calc and re-ordering)

module axi_master #(
    parameter ID_W   = 8,
    parameter ADDR_W = 32,
    parameter DATA_W = 256
) (
    input  wire                 aclk,
    input  wire                 aresetn,

    // Arbiter handshake (per-channel: aw_req/gnt, ar_req/gnt)
    output wire                 aw_req,
    input  wire                 aw_gnt,
    output wire                 ar_req,
    input  wire                 ar_gnt,

    // Write Address Channel
    output wire [ID_W-1:0]      awid,
    output wire [ADDR_W-1:0]    awaddr,
    output wire [7:0]           awlen,
    output wire [2:0]           awsize,
    output wire [1:0]           awburst,
    output wire                 awlock,
    output wire [3:0]           awcache,
    output wire [2:0]           awprot,
    output wire [3:0]           awqos,
    output wire                 awvalid,
    input  wire                 awready,

    // Write Data Channel
    output wire [DATA_W-1:0]    wdata,
    output wire [DATA_W/8-1:0]  wstrb,
    output wire                 wlast,
    output wire                 wvalid,
    input  wire                 wready,

    // Write Response Channel
    input  wire [ID_W-1:0]      bid,
    input  wire [1:0]           bresp,
    input  wire                 bvalid,
    output wire                 bready,

    // Read Address Channel
    output wire [ID_W-1:0]      arid,
    output wire [ADDR_W-1:0]    araddr,
    output wire [7:0]           arlen,
    output wire [2:0]           arsize,
    output wire [1:0]           arburst,
    output wire                 arlock,
    output wire [3:0]           arcache,
    output wire [2:0]           arprot,
    output wire [3:0]           arqos,
    output wire                 arvalid,
    input  wire                 arready,

    // Read Data Channel
    input  wire [ID_W-1:0]      rid,
    input  wire [DATA_W-1:0]    rdata,
    input  wire [1:0]           rresp,
    input  wire                 rlast,
    input  wire                 rvalid,
    output wire                 rready,

    // Testbench stimulus interface
    input  wire                 txn_req,
    input  wire                 txn_is_write,
    input  wire [ID_W-1:0]      txn_awid,
    input  wire [ADDR_W-1:0]    txn_awaddr,
    input  wire [7:0]           txn_awlen,
    input  wire [2:0]           txn_awsize,
    input  wire [1:0]           txn_awburst,
    input  wire [ID_W-1:0]      txn_arid,
    input  wire [ADDR_W-1:0]    txn_araddr,
    input  wire [7:0]           txn_arlen,
    input  wire [2:0]           txn_arsize,
    input  wire [1:0]           txn_arburst,
    // Write data streaming
    input  wire                 txn_wvalid,
    input  wire [DATA_W-1:0]    txn_wdata,
    input  wire [DATA_W/8-1:0]  txn_wstrb,
    input  wire                 txn_wlast,
    output wire                 txn_wready,
    // Read data streaming (back to TB)
    output wire                 txn_rvalid,
    output wire [DATA_W-1:0]    txn_rdata,
    output wire [1:0]           txn_rresp,
    output wire                 txn_rlast,
    input  wire                 txn_rready,
    // Completion
    output wire                 txn_done,
    output wire [1:0]           txn_bresp_out
);

    localparam FSM_IDLE     = 4'd0;
    localparam FSM_AW_REQ   = 4'd1;
    localparam FSM_AW_WAIT  = 4'd2;
    localparam FSM_W_SEND   = 4'd3;
    localparam FSM_B_WAIT   = 4'd4;
    localparam FSM_AR_REQ   = 4'd5;
    localparam FSM_AR_WAIT  = 4'd6;
    localparam FSM_R_COLL   = 4'd7;
    localparam FSM_DONE     = 4'd8;

    reg [3:0] state, next_state;

    // Latched transaction descriptor
    reg                 latched_is_write;
    reg [ID_W-1:0]      latched_awid, latched_arid;
    reg [ADDR_W-1:0]    latched_awaddr, latched_araddr;
    reg [7:0]           latched_awlen, latched_arlen;
    reg [2:0]           latched_awsize, latched_arsize;
    reg [1:0]           latched_awburst, latched_arburst;

    // Latched B response (held until txn_done is consumed)
    reg [1:0]           latched_bresp;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            FSM_IDLE:    if (txn_req) begin
                             if (txn_is_write) next_state = FSM_AW_REQ;
                             else              next_state = FSM_AR_REQ;
                         end
            FSM_AW_REQ:  if (aw_gnt)    next_state = FSM_AW_WAIT;
            FSM_AW_WAIT: if (awvalid && awready) next_state = FSM_W_SEND;
            FSM_W_SEND:  if (wvalid && wready && wlast) next_state = FSM_B_WAIT;
            FSM_B_WAIT:  if (bvalid && bready) next_state = latched_is_write ? FSM_DONE : FSM_AR_REQ;
            FSM_AR_REQ:  if (ar_gnt)   next_state = FSM_AR_WAIT;
            FSM_AR_WAIT: if (arvalid && arready) next_state = FSM_R_COLL;
            FSM_R_COLL:  if (rvalid && rready && rlast) next_state = FSM_DONE;
            FSM_DONE:    next_state = FSM_IDLE;
            default:     next_state = FSM_IDLE;
        endcase
    end

    // Latch transaction descriptor on IDLE->transition
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            latched_is_write <= 1'b0;
            latched_awid     <= {ID_W{1'b0}};
            latched_awaddr   <= {ADDR_W{1'b0}};
            latched_awlen    <= {8{1'b0}};
            latched_awsize   <= {3{1'b0}};
            latched_awburst  <= {2{1'b0}};
            latched_arid     <= {ID_W{1'b0}};
            latched_araddr   <= {ADDR_W{1'b0}};
            latched_arlen    <= {8{1'b0}};
            latched_arsize   <= {3{1'b0}};
            latched_arburst  <= {2{1'b0}};
            latched_bresp   <= 2'b00;
        end else if (state == FSM_IDLE && txn_req) begin
            latched_is_write <= txn_is_write;
            latched_awid     <= txn_awid;
            latched_awaddr   <= txn_awaddr;
            latched_awlen    <= txn_awlen;
            latched_awsize   <= txn_awsize;
            latched_awburst  <= txn_awburst;
            latched_arid     <= txn_arid;
            latched_araddr   <= txn_araddr;
            latched_arlen    <= txn_arlen;
            latched_arsize   <= txn_arsize;
            latched_arburst  <= txn_arburst;
        end else if (state == FSM_B_WAIT && bvalid && bready) begin
            latched_bresp <= bresp;
        end
    end

    // AW channel drive
    assign awvalid  = (state == FSM_AW_WAIT);
    assign awid     = latched_awid;
    assign awaddr   = latched_awaddr;
    assign awlen    = latched_awlen;
    assign awsize   = latched_awsize;
    assign awburst  = latched_awburst;
    assign awlock   = 1'b0;
    assign awcache  = 4'b0011;  // Normal non-cacheable bufferable
    assign awprot   = 3'b000;
    assign awqos    = 4'd0;

    // W channel drive -- pass through from TB stimulus, gate by state
    assign wvalid = (state == FSM_W_SEND) && txn_wvalid;
    assign wdata  = txn_wdata;
    assign wstrb  = txn_wstrb;
    assign wlast  = txn_wlast;
    assign txn_wready = (state == FSM_W_SEND) && wready;

    // B channel
    assign bready = (state == FSM_B_WAIT);

    // AR channel drive
    assign arvalid = (state == FSM_AR_WAIT);
    assign arid    = latched_arid;
    assign araddr  = latched_araddr;
    assign arlen   = latched_arlen;
    assign arsize  = latched_arsize;
    assign arburst = latched_arburst;
    assign arlock  = 1'b0;
    assign arcache = 4'b0011;
    assign arprot  = 3'b000;
    assign arqos   = 4'd0;

    // R channel -- pass through to TB
    assign txn_rvalid = (state == FSM_R_COLL) && rvalid;
    assign txn_rdata  = rdata;
    assign txn_rresp  = rresp;
    assign txn_rlast  = rlast;
    assign rready     = (state == FSM_R_COLL) && txn_rready;

    // Arbiter requests
    assign aw_req = (state == FSM_AW_REQ) || (state == FSM_AW_WAIT);
    assign ar_req = (state == FSM_AR_REQ) || (state == FSM_AR_WAIT);

    // Completion
    assign txn_done     = (state == FSM_DONE);
    assign txn_bresp_out = latched_bresp;

endmodule
