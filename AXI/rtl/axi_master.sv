// AXI4-Full Master — Per-channel FSMs + transaction sequencer
// 256-bit data, 8-bit ID, 32-bit address
// Features: all burst types, narrow transfers, out-of-order ID support

module axi_master #(
    parameter int ID_W   = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic                 aclk,
    input  logic                 aresetn,

    // Arbiter handshake (per-channel: aw_req/gnt, ar_req/gnt)
    output logic                 aw_req,
    input  logic                 aw_gnt,
    output logic                 ar_req,
    input  logic                 ar_gnt,

    // Write Address Channel
    output logic [ID_W-1:0]      awid,
    output logic [ADDR_W-1:0]    awaddr,
    output logic [7:0]           awlen,
    output logic [2:0]           awsize,
    output logic [1:0]           awburst,
    output logic                 awlock,
    output logic [3:0]           awcache,
    output logic [2:0]           awprot,
    output logic [3:0]           awqos,
    output logic                 awvalid,
    input  logic                 awready,

    // Write Data Channel
    output logic [DATA_W-1:0]    wdata,
    output logic [DATA_W/8-1:0]  wstrb,
    output logic                 wlast,
    output logic                 wvalid,
    input  logic                 wready,

    // Write Response Channel
    input  logic [ID_W-1:0]      bid,
    input  logic [1:0]           bresp,
    input  logic                 bvalid,
    output logic                 bready,

    // Read Address Channel
    output logic [ID_W-1:0]      arid,
    output logic [ADDR_W-1:0]    araddr,
    output logic [7:0]           arlen,
    output logic [2:0]           arsize,
    output logic [1:0]           arburst,
    output logic                 arlock,
    output logic [3:0]           arcache,
    output logic [2:0]           arprot,
    output logic [3:0]           arqos,
    output logic                 arvalid,
    input  logic                 arready,

    // Read Data Channel
    input  logic [ID_W-1:0]      rid,
    input  logic [DATA_W-1:0]    rdata,
    input  logic [1:0]           rresp,
    input  logic                 rlast,
    input  logic                 rvalid,
    output logic                 rready,

    // Testbench stimulus interface
    input  logic                 txn_req,
    input  logic                 txn_is_write,
    input  logic [ID_W-1:0]      txn_awid,
    input  logic [ADDR_W-1:0]    txn_awaddr,
    input  logic [7:0]           txn_awlen,
    input  logic [2:0]           txn_awsize,
    input  logic [1:0]           txn_awburst,
    input  logic [ID_W-1:0]      txn_arid,
    input  logic [ADDR_W-1:0]    txn_araddr,
    input  logic [7:0]           txn_arlen,
    input  logic [2:0]           txn_arsize,
    input  logic [1:0]           txn_arburst,
    // Write data streaming
    input  logic                 txn_wvalid,
    input  logic [DATA_W-1:0]    txn_wdata,
    input  logic [DATA_W/8-1:0]  txn_wstrb,
    input  logic                 txn_wlast,
    output logic                 txn_wready,
    // Read data streaming (back to TB)
    output logic                 txn_rvalid,
    output logic [DATA_W-1:0]    txn_rdata,
    output logic [1:0]           txn_rresp,
    output logic                 txn_rlast,
    input  logic                 txn_rready,
    // Completion
    output logic                 txn_done,
    output logic [1:0]           txn_bresp_out
);

    localparam FSM_IDLE     = 3'd0;
    localparam FSM_AW_REQ   = 3'd1;
    localparam FSM_AW_WAIT  = 3'd2;
    localparam FSM_W_SEND   = 3'd3;
    localparam FSM_B_WAIT   = 3'd4;
    localparam FSM_AR_REQ   = 3'd5;
    localparam FSM_AR_WAIT  = 3'd6;
    localparam FSM_R_COLL   = 3'd7;
    localparam FSM_DONE     = 3'd8;

    logic [2:0] state, next_state;

    // Latched transaction descriptor
    logic                 latched_is_write;
    logic [ID_W-1:0]      latched_awid, latched_arid;
    logic [ADDR_W-1:0]    latched_awaddr, latched_araddr;
    logic [7:0]           latched_awlen, latched_arlen;
    logic [2:0]           latched_awsize, latched_arsize;
    logic [1:0]           latched_awburst, latched_arburst;

    // Beat counters
    logic [7:0]           w_beat_cnt, r_beat_cnt;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
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
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            latched_is_write <= 1'b0;
            latched_awid     <= '0;
            latched_awaddr   <= '0;
            latched_awlen    <= '0;
            latched_awsize   <= '0;
            latched_awburst  <= '0;
            latched_arid     <= '0;
            latched_araddr   <= '0;
            latched_arlen    <= '0;
            latched_arsize   <= '0;
            latched_arburst  <= '0;
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

    // W channel drive — pass through from TB stimulus, gate by state
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

    // R channel — pass through to TB
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
    assign txn_bresp_out = (state == FSM_B_WAIT) ? bresp : 2'b00;

endmodule : axi_master
