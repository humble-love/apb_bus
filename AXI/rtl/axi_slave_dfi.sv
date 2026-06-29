// AXI4-Full to DFI Bridge (DDR5 PHY Interface)
// Translates AXI read/write bursts to DFI commands with DDR5 timing
// 16-entry command queue, bank-aware scheduling
// DDR5: BL16 per access (16x16bit = 256-bit per AXI beat)

module axi_slave_dfi #(
    parameter int DATA_W  = 256,
    parameter int ID_W    = 8,
    parameter int ADDR_W  = 32,
    parameter int CMD_Q_DEPTH = 16
) (
    input  logic                aclk,
    input  logic                aresetn,

    // ============================================================
    // AXI Slave Port
    // ============================================================
    // AW
    input  logic [ID_W-1:0]     awid,
    input  logic [ADDR_W-1:0]   awaddr,
    input  logic [7:0]          awlen,
    input  logic [2:0]          awsize,
    input  logic [1:0]          awburst,
    input  logic                awvalid,
    output logic                awready,
    // W
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    input  logic                wlast,
    input  logic                wvalid,
    output logic                wready,
    // B
    output logic [ID_W-1:0]     bid,
    output logic [1:0]          bresp,
    output logic                bvalid,
    input  logic                bready,
    // AR
    input  logic [ID_W-1:0]     arid,
    input  logic [ADDR_W-1:0]   araddr,
    input  logic [7:0]          arlen,
    input  logic [2:0]          arsize,
    input  logic [1:0]          arburst,
    input  logic                arvalid,
    output logic                arready,
    // R
    output logic [ID_W-1:0]     rid,
    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp,
    output logic                rlast,
    output logic                rvalid,
    input  logic                rready,

    // ============================================================
    // DFI Interface (simplified DDR5)
    // ============================================================
    output logic [31:0]         dfi_address,
    output logic [3:0]          dfi_bank,
    output logic [DATA_W-1:0]   dfi_wrdata,
    output logic [DATA_W/8-1:0] dfi_wrdata_mask,
    input  logic [DATA_W-1:0]   dfi_rddata,
    input  logic                dfi_rddata_valid,
    output logic                dfi_wrdata_valid,
    output logic                dfi_cs_n,
    output logic                dfi_ras_n,
    output logic                dfi_cas_n,
    output logic                dfi_we_n,
    output logic                dfi_act_n,
    output logic                dfi_cke
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

    // Command queue entry
    typedef struct packed {
        logic                valid;
        logic                is_write;
        logic [ID_W-1:0]     id;
        logic [31:0]         addr;
        logic [7:0]          len;
        logic [2:0]          size;
        logic [7:0]          beat_cnt;
        logic [1:0]          resp;
    } cmd_entry_t;

    // FSM states
    typedef enum logic [3:0] {
        FSM_IDLE, FSM_ACT, FSM_ACT_WAIT, FSM_RD, FSM_RD_WAIT,
        FSM_WR, FSM_WR_WAIT, FSM_PRE, FSM_PRE_WAIT, FSM_DONE
    } state_t;

    state_t state, next_state;

    cmd_entry_t cmd_q [CMD_Q_DEPTH-1:0];
    logic [$clog2(CMD_Q_DEPTH)-1:0] q_wr_ptr, q_rd_ptr;
    logic [4:0]                     q_count;  // up to 16

    // Timing counters
    logic [5:0] timer, timer_next;

    // Current command
    cmd_entry_t cur_cmd;
    logic       cur_active;
    logic       cur_w_beat_done, cur_r_beat_done;

    // Bank tracking (4 banks, track open/closed and row)
    logic [3:0]                bank_open;
    logic [3:0][15:0]          bank_row;  // simplified row address

    // =============================================================
    // Command queue management
    // =============================================================
    assign awready = (q_count < CMD_Q_DEPTH);
    assign arready = (q_count < CMD_Q_DEPTH);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            q_wr_ptr <= '0;
            q_rd_ptr <= '0;
            q_count  <= '0;
            for (int i = 0; i < CMD_Q_DEPTH; i++) cmd_q[i].valid <= 1'b0;
        end else begin
            // Enqueue write
            if (awvalid && awready) begin
                cmd_q[q_wr_ptr].valid    <= 1'b1;
                cmd_q[q_wr_ptr].is_write <= 1'b1;
                cmd_q[q_wr_ptr].id       <= awid;
                cmd_q[q_wr_ptr].addr     <= awaddr;
                cmd_q[q_wr_ptr].len      <= awlen;
                cmd_q[q_wr_ptr].size     <= awsize;
                cmd_q[q_wr_ptr].beat_cnt <= '0;
                cmd_q[q_wr_ptr].resp     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Enqueue read
            if (arvalid && arready) begin
                cmd_q[q_wr_ptr].valid    <= 1'b1;
                cmd_q[q_wr_ptr].is_write <= 1'b0;
                cmd_q[q_wr_ptr].id       <= arid;
                cmd_q[q_wr_ptr].addr     <= araddr;
                cmd_q[q_wr_ptr].len      <= arlen;
                cmd_q[q_wr_ptr].size     <= arsize;
                cmd_q[q_wr_ptr].beat_cnt <= '0;
                cmd_q[q_wr_ptr].resp     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Dequeue on completion
            if (state == FSM_DONE) begin
                cmd_q[q_rd_ptr].valid <= 1'b0;
                q_rd_ptr <= q_rd_ptr + 1;
                q_count  <= q_count - 1;
            end
        end
    end

    assign cur_cmd   = cmd_q[q_rd_ptr];
    assign cur_active = (q_count > 0) && cmd_q[q_rd_ptr].valid;

    // =============================================================
    // DDR5 Timing FSM
    // =============================================================
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
            timer <= '0;
        end else begin
            state <= next_state;
            timer <= timer_next;
        end
    end

    always_comb begin
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

        case (state)
            FSM_IDLE: begin
                if (cur_active) begin
                    if (!bank_open[cur_cmd.addr[15:14]]) begin
                        // Need ACTIVATE
                        next_state = FSM_ACT;
                        timer_next = tRCD;
                    end else if (cur_cmd.is_write) begin
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
                dfi_address = {16'd0, cur_cmd.addr[27:16], 4'd0};
                dfi_bank    = cur_cmd.addr[15:14];
                next_state = FSM_ACT_WAIT;
            end

            FSM_ACT_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_cmd.is_write) begin
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
                dfi_address = {16'd0, cur_cmd.addr[27:6]};
                dfi_bank    = cur_cmd.addr[15:14];
                next_state = FSM_RD_WAIT;
            end

            FSM_RD_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (dfi_rddata_valid) begin
                    // Data returned - handled in R channel logic
                    if (cur_cmd.beat_cnt >= cur_cmd.len) begin
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
                dfi_address    = {16'd0, cur_cmd.addr[27:6]};
                dfi_bank       = cur_cmd.addr[15:14];
                dfi_wrdata       = wdata;
                dfi_wrdata_mask  = wstrb;
                dfi_wrdata_valid = 1'b1;
                next_state = FSM_WR_WAIT;
            end

            FSM_WR_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_cmd.beat_cnt >= cur_cmd.len) begin
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
                dfi_bank  = cur_cmd.addr[15:14];
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
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bank_open <= '0;
            bank_row  <= '0;
        end else begin
            if (state == FSM_ACT) begin
                bank_open[cur_cmd.addr[15:14]] <= 1'b1;
                bank_row[cur_cmd.addr[15:14]]   <= cur_cmd.addr[27:16];
            end
            if (state == FSM_PRE) begin
                bank_open[cur_cmd.addr[15:14]] <= 1'b0;
            end
        end
    end

    // Beat counter increment
    always_ff @(posedge aclk) begin
        if (state == FSM_RD && dfi_rddata_valid)
            cmd_q[q_rd_ptr].beat_cnt <= cur_cmd.beat_cnt + 1;
        if (state == FSM_WR && wvalid && wready)
            cmd_q[q_rd_ptr].beat_cnt <= cur_cmd.beat_cnt + 1;
    end

    // =============================================================
    // AXI Response Channels
    // =============================================================

    // Write data ready - accept when in WR state
    assign wready = (state == FSM_WR);

    // B channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid <= 1'b0;
        end else begin
            if (state == FSM_DONE && cur_cmd.is_write) begin
                bid    <= cur_cmd.id;
                bresp  <= cur_cmd.resp;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // R channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
        end else begin
            if (state == FSM_RD_WAIT && dfi_rddata_valid) begin
                rid    <= cur_cmd.id;
                rdata  <= dfi_rddata;
                rresp  <= cur_cmd.resp;
                rlast  <= (cur_cmd.beat_cnt >= cur_cmd.len);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) rvalid <= 1'b0;
        end
    end

endmodule : axi_slave_dfi
