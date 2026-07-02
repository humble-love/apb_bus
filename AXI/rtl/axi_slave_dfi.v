// AXI4-Full to DFI Bridge (DDR5 PHY Interface)
// Translates AXI read/write bursts to DFI commands with DDR5 timing
// 16-entry command queue, bank-aware scheduling
// DDR5: BL16 per access (16x16bit = 256-bit per AXI beat)

module axi_slave_dfi #(
    parameter DATA_W  = 256,
    parameter ID_W    = 8,
    parameter ADDR_W  = 32,
    parameter CMD_Q_DEPTH = 16
) (
    input  wire                aclk,
    input  wire                aresetn,

    // ============================================================
    // AXI Slave Port
    // ============================================================
    // AW
    input  wire [ID_W-1:0]     awid,
    input  wire [ADDR_W-1:0]   awaddr,
    input  wire [7:0]          awlen,
    input  wire [2:0]          awsize,
    input  wire [1:0]          awburst,
    input  wire                awvalid,
    output wire                awready,
    // W
    input  wire [DATA_W-1:0]   wdata,
    input  wire [DATA_W/8-1:0] wstrb,
    input  wire                wlast,
    input  wire                wvalid,
    output wire                wready,
    // B
    output reg  [ID_W-1:0]     bid,
    output reg  [1:0]          bresp,
    output reg                 bvalid,
    input  wire                bready,
    // AR
    input  wire [ID_W-1:0]     arid,
    input  wire [ADDR_W-1:0]   araddr,
    input  wire [7:0]          arlen,
    input  wire [2:0]          arsize,
    input  wire [1:0]          arburst,
    input  wire                arvalid,
    output wire                arready,
    // R
    output reg  [ID_W-1:0]     rid,
    output reg  [DATA_W-1:0]   rdata,
    output reg  [1:0]          rresp,
    output reg                 rlast,
    output reg                 rvalid,
    input  wire                rready,

    // ============================================================
    // DFI Interface (simplified DDR5)
    // ============================================================
    output reg  [31:0]         dfi_address,
    output reg  [3:0]          dfi_bank,
    output reg  [DATA_W-1:0]   dfi_wrdata,
    output reg  [DATA_W/8-1:0] dfi_wrdata_mask,
    input  wire [DATA_W-1:0]   dfi_rddata,
    input  wire                dfi_rddata_valid,
    output reg                 dfi_wrdata_valid,
    output reg                 dfi_cs_n,
    output reg                 dfi_ras_n,
    output reg                 dfi_cas_n,
    output reg                 dfi_we_n,
    output reg                 dfi_act_n,
    output reg                 dfi_cke
);

    // DDR5 Timing constants
    localparam tRCD = 14;
    localparam tCL  = 14;
    localparam tRAS = 32;
    localparam tRP  = 14;
    localparam tWR  = 14;
    localparam tCCD = 4;   // CAS-to-CAS delay
    localparam BL   = 16;  // Burst Length (DDR5)

    // DFI command encoding
    localparam CMD_DES  = 4'b1111;  // DESELECT
    localparam CMD_ACT  = 4'b0011;  // ACTIVATE
    localparam CMD_RD   = 4'b0101;  // READ
    localparam CMD_WR   = 4'b0100;  // WRITE
    localparam CMD_PRE  = 4'b0010;  // PRECHARGE

    // FSM states
    localparam FSM_IDLE      = 4'd0;
    localparam FSM_ACT       = 4'd1;
    localparam FSM_ACT_WAIT  = 4'd2;
    localparam FSM_RD        = 4'd3;
    localparam FSM_RD_WAIT   = 4'd4;
    localparam FSM_WR        = 4'd5;
    localparam FSM_WR_WAIT   = 4'd6;
    localparam FSM_PRE       = 4'd7;
    localparam FSM_PRE_WAIT  = 4'd8;
    localparam FSM_DONE      = 4'd9;

    reg [3:0] state, next_state;

    // Command queue — flattened from struct cmd_entry_t
    reg                           cmd_q_valid    [0:CMD_Q_DEPTH-1];
    reg                           cmd_q_is_write [0:CMD_Q_DEPTH-1];
    reg [ID_W-1:0]                cmd_q_id       [0:CMD_Q_DEPTH-1];
    reg [31:0]                    cmd_q_addr     [0:CMD_Q_DEPTH-1];
    reg [7:0]                     cmd_q_len      [0:CMD_Q_DEPTH-1];
    reg [2:0]                     cmd_q_size     [0:CMD_Q_DEPTH-1];
    reg [7:0]                     cmd_q_beat_cnt [0:CMD_Q_DEPTH-1];
    reg [1:0]                     cmd_q_resp     [0:CMD_Q_DEPTH-1];

    reg [3:0] q_wr_ptr, q_rd_ptr;
    reg [4:0] q_count;  // up to 16

    // Timing counters
    reg [5:0] timer, timer_next;

    // Current command — combinational views of queue head
    wire                          cur_valid    = cmd_q_valid[q_rd_ptr];
    wire                          cur_is_write = cmd_q_is_write[q_rd_ptr];
    wire [ID_W-1:0]               cur_id       = cmd_q_id[q_rd_ptr];
    wire [31:0]                   cur_addr     = cmd_q_addr[q_rd_ptr];
    wire [7:0]                    cur_len      = cmd_q_len[q_rd_ptr];
    wire [7:0]                    cur_beat_cnt = cmd_q_beat_cnt[q_rd_ptr];
    wire [2:0]                    cur_size     = cmd_q_size[q_rd_ptr];
    wire [1:0]                    cur_resp     = cmd_q_resp[q_rd_ptr];

    wire       cur_active;

    // Bank tracking (4 banks, track open/closed and row)
    reg [3:0]                bank_open;
    reg [15:0]               bank_row [0:3];  // 4 banks, simplified row address

    // =============================================================
    // Command queue management
    // =============================================================
    assign awready = (q_count < CMD_Q_DEPTH);
    assign arready = (q_count < CMD_Q_DEPTH);

    always @(posedge aclk or negedge aresetn) begin
        integer i;
        if (!aresetn) begin
            q_wr_ptr <= 4'd0;
            q_rd_ptr <= 4'd0;
            q_count  <= 5'd0;
            for (i = 0; i < CMD_Q_DEPTH; i = i + 1) cmd_q_valid[i] <= 1'b0;
        end else begin
            // Enqueue write
            if (awvalid && awready) begin
                cmd_q_valid[q_wr_ptr]    <= 1'b1;
                cmd_q_is_write[q_wr_ptr] <= 1'b1;
                cmd_q_id[q_wr_ptr]       <= awid;
                cmd_q_addr[q_wr_ptr]     <= awaddr;
                cmd_q_len[q_wr_ptr]      <= awlen;
                cmd_q_size[q_wr_ptr]     <= awsize;
                cmd_q_beat_cnt[q_wr_ptr] <= 8'd0;
                cmd_q_resp[q_wr_ptr]     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Enqueue read
            if (arvalid && arready) begin
                cmd_q_valid[q_wr_ptr]    <= 1'b1;
                cmd_q_is_write[q_wr_ptr] <= 1'b0;
                cmd_q_id[q_wr_ptr]       <= arid;
                cmd_q_addr[q_wr_ptr]     <= araddr;
                cmd_q_len[q_wr_ptr]      <= arlen;
                cmd_q_size[q_wr_ptr]     <= arsize;
                cmd_q_beat_cnt[q_wr_ptr] <= 8'd0;
                cmd_q_resp[q_wr_ptr]     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Dequeue on completion
            if (state == FSM_DONE) begin
                cmd_q_valid[q_rd_ptr] <= 1'b0;
                q_rd_ptr <= q_rd_ptr + 1;
                q_count  <= q_count - 1;
            end
            // Beat counter increment (single driver for cmd_q fields)
            if (state == FSM_RD_WAIT && dfi_rddata_valid)
                cmd_q_beat_cnt[q_rd_ptr] <= cmd_q_beat_cnt[q_rd_ptr] + 1;
            if (state == FSM_WR && wvalid && wready)
                cmd_q_beat_cnt[q_rd_ptr] <= cmd_q_beat_cnt[q_rd_ptr] + 1;
        end
    end

    assign cur_active = (q_count > 0) && cmd_q_valid[q_rd_ptr];

    // =============================================================
    // DDR5 Timing FSM
    // =============================================================
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
            timer <= 6'd0;
        end else begin
            state <= next_state;
            timer <= timer_next;
        end
    end

    always @(*) begin
        next_state = state;
        timer_next = timer;

        // DFI defaults
        dfi_cs_n  = 1'b1;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b1;
        dfi_we_n  = 1'b1;
        dfi_act_n = 1'b1;
        dfi_cke   = 1'b1;
        dfi_wrdata_valid = 1'b0;
        dfi_address      = 32'd0;
        dfi_bank         = 4'd0;
        dfi_wrdata       = {DATA_W{1'b0}};
        dfi_wrdata_mask  = {(DATA_W/8){1'b0}};

        case (state)
            FSM_IDLE: begin
                if (cur_active) begin
                    if (!bank_open[cur_addr[15:14]]) begin
                        // Need ACTIVATE
                        next_state = FSM_ACT;
                        timer_next = tRCD;
                    end else if (cur_is_write) begin
                        next_state = FSM_WR;
                        timer_next = tWR;
                    end else begin
                        next_state = FSM_RD;
                        timer_next = tCL;
                    end
                end
            end

            FSM_ACT: begin
                dfi_cs_n  = 1'b0;
                dfi_ras_n = 1'b0;
                dfi_act_n = 1'b0;
                dfi_address = {16'd0, cur_addr[27:16], 4'd0};
                dfi_bank    = cur_addr[15:14];
                next_state = FSM_ACT_WAIT;
            end

            FSM_ACT_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_is_write) begin
                    next_state = FSM_WR;
                    timer_next = tWR;
                end else begin
                    next_state = FSM_RD;
                    timer_next = tCL;
                end
            end

            FSM_RD: begin
                dfi_cs_n  = 1'b0;
                dfi_cas_n = 1'b0;
                dfi_address = {16'd0, cur_addr[27:6]};
                dfi_bank    = cur_addr[15:14];
                next_state = FSM_RD_WAIT;
            end

            FSM_RD_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (dfi_rddata_valid) begin
                    // Data returned - handled in R channel logic
                    if (cur_beat_cnt > cur_len) begin
                        next_state = FSM_PRE;
                        timer_next = tRP;
                    end else begin
                        next_state = FSM_RD;
                        timer_next = tCCD;
                    end
                end
            end

            FSM_WR: begin
                dfi_cs_n   = 1'b0;
                dfi_cas_n  = 1'b0;
                dfi_we_n   = 1'b0;
                dfi_address    = {16'd0, cur_addr[27:6]};
                dfi_bank       = cur_addr[15:14];
                dfi_wrdata       = wdata;
                dfi_wrdata_mask  = wstrb;
                dfi_wrdata_valid = 1'b1;
                next_state = FSM_WR_WAIT;
            end

            FSM_WR_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_beat_cnt > cur_len) begin
                    next_state = FSM_PRE;
                    timer_next = tRP;
                end else begin
                    next_state = FSM_WR;
                    timer_next = tCCD;
                end
            end

            FSM_PRE: begin
                dfi_cs_n  = 1'b0;
                dfi_ras_n = 1'b0;
                dfi_we_n  = 1'b0;
                dfi_bank  = cur_addr[15:14];
                next_state = FSM_PRE_WAIT;
            end

            FSM_PRE_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else next_state = FSM_DONE;
            end

            FSM_DONE: begin
                next_state = FSM_IDLE;
            end

            default: next_state = FSM_IDLE;
        endcase
    end

    // Bank tracking
    always @(posedge aclk or negedge aresetn) begin
        integer i;
        if (!aresetn) begin
            bank_open <= 4'd0;
            for (i = 0; i < 4; i = i + 1) bank_row[i] <= 16'd0;
        end else begin
            if (state == FSM_ACT) begin
                bank_open[cur_addr[15:14]] <= 1'b1;
                bank_row[cur_addr[15:14]]   <= cur_addr[27:16];
            end
            if (state == FSM_PRE) begin
                bank_open[cur_addr[15:14]] <= 1'b0;
            end
        end
    end

    // =============================================================
    // AXI Response Channels
    // =============================================================

    // Write data ready - accept when in WR state
    assign wready = (state == FSM_WR);

    // B channel
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid <= 1'b0;
        end else begin
            if (state == FSM_DONE && cur_is_write) begin
                bid    <= cur_id;
                bresp  <= cur_resp;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // R channel
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
        end else begin
            if (state == FSM_RD_WAIT && dfi_rddata_valid) begin
                rid    <= cur_id;
                rdata  <= dfi_rddata;
                rresp  <= cur_resp;
                rlast  <= (cur_beat_cnt >= cur_len);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) rvalid <= 1'b0;
        end
    end

endmodule
