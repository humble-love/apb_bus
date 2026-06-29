// AXI4-Full Slave: SRAM with configurable depth and stall insertion
// Supports FIXED, INCR, WRAP bursts
// Narrow transfers via WSTRB per-byte masking

module axi_slave_sram #(
    parameter int DEPTH      = 1024,
    parameter int DATA_W     = 256,
    parameter int ID_W       = 8,
    parameter int ADDR_W     = 32,
    parameter int STALL_PROB = 0   // 0-255 out of 256 chance to stall
) (
    input  logic                aclk,
    input  logic                aresetn,

    // Write Address Channel
    input  logic [ID_W-1:0]     awid,
    input  logic [ADDR_W-1:0]   awaddr,
    input  logic [7:0]          awlen,
    input  logic [2:0]          awsize,
    input  logic [1:0]          awburst,
    input  logic                awvalid,
    output logic                awready,

    // Write Data Channel
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    input  logic                wlast,
    input  logic                wvalid,
    output logic                wready,

    // Write Response Channel
    output logic [ID_W-1:0]     bid,
    output logic [1:0]          bresp,
    output logic                bvalid,
    input  logic                bready,

    // Read Address Channel
    input  logic [ID_W-1:0]     arid,
    input  logic [ADDR_W-1:0]   araddr,
    input  logic [7:0]          arlen,
    input  logic [2:0]          arsize,
    input  logic [1:0]          arburst,
    input  logic                arvalid,
    output logic                arready,

    // Read Data Channel
    output logic [ID_W-1:0]     rid,
    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp,
    output logic                rlast,
    output logic                rvalid,
    input  logic                rready
);

    localparam AW = 0, W  = 1, B  = 2, AR = 3, R  = 4;

    // BRAM
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // Latched transaction info
    logic [ID_W-1:0]   awid_latched, arid_latched;
    logic [ADDR_W-1:0] awaddr_latched, araddr_latched;
    logic [7:0]        awlen_latched, arlen_latched;
    logic [2:0]        awsize_latched, arsize_latched;
    logic [1:0]        awburst_latched, arburst_latched;
    logic [7:0]        w_beat, r_beat;
    logic              w_active, r_active;
    logic [1:0]        w_resp;

    // Stall randomizer
    logic [7:0] stall_rng;
    logic       stall_now;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) stall_rng <= 8'h5A;
        else         stall_rng <= {stall_rng[6:0], stall_rng[7] ^ stall_rng[5] ^ stall_rng[4] ^ stall_rng[3]};
    end
    assign stall_now = (stall_rng < STALL_PROB);

    // AW channel
    assign awready = !w_active;  // one write at a time

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_active <= 1'b0;
        end else begin
            if (awvalid && awready) begin
                awid_latched   <= awid;
                awaddr_latched <= awaddr;
                awlen_latched  <= awlen;
                awsize_latched <= awsize;
                awburst_latched <= awburst;
                w_beat         <= '0;
                w_active       <= 1'b1;
                w_resp         <= 2'b00;  // OKAY
            end
            // Write data
            if (w_active && wvalid && wready) begin
                automatic logic [$clog2(DEPTH)-1:0] word_addr;
                automatic logic [DATA_W-1:0] old_data;

                // Calculate address for this beat
                word_addr = get_word_addr(awaddr_latched, w_beat, awsize_latched, awburst_latched);

                // Read-modify-write for narrow transfers via WSTRB
                old_data = mem[word_addr];
                for (int b = 0; b < DATA_W/8; b = b + 1) begin
                    if (wstrb[b])
                        old_data[b*8 +: 8] = wdata[b*8 +: 8];
                end
                mem[word_addr] <= old_data;

                w_beat <= w_beat + 1;
                if (wlast) w_active <= 1'b0;
            end
        end
    end

    assign wready = w_active && !(bvalid && !bready) && !stall_now;

    // B channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid <= 1'b0;
        end else begin
            if (w_active && wvalid && wready && wlast) begin
                bid    <= awid_latched;
                bresp  <= w_resp;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // AR channel
    assign arready = !r_active;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_active <= 1'b0;
        end else begin
            if (arvalid && arready) begin
                arid_latched    <= arid;
                araddr_latched  <= araddr;
                arlen_latched   <= arlen;
                arsize_latched  <= arsize;
                arburst_latched <= arburst;
                r_beat          <= '0;
                r_active        <= 1'b1;
            end
            if (r_active && rvalid && rready && rlast)
                r_active <= 1'b0;
        end
    end

    // R channel
    assign rvalid = r_active && !stall_now;
    assign rid    = arid_latched;
    assign rresp  = 2'b00;
    assign rlast  = (r_beat == arlen_latched);

    // Returns the word-aligned address for a given beat within a burst transaction.
    // Supports FIXED (0): same address for every beat
    //          INCR (1): base + beat << size
    //          WRAP (2): wraps within (awlen+1)*2^size boundary
    function automatic logic [$clog2(DEPTH)-1:0] get_word_addr(
        input logic [ADDR_W-1:0] base, input [7:0] beat, input [2:0] size, input [1:0] burst
    );
        automatic logic [ADDR_W-1:0] byte_addr;
        automatic logic [ADDR_W-1:0] wrap_boundary;
        case (burst)
            2'b00: byte_addr = base;                                      // FIXED
            2'b01: byte_addr = base + (beat << size);                     // INCR
            2'b10: begin                                                   // WRAP
                wrap_boundary = (awlen_latched + 1) << size;
                byte_addr = (base & ~(wrap_boundary - 1)) +
                            ((base + (beat << size)) & (wrap_boundary - 1));
            end
            default: byte_addr = base + (beat << size);                   // INCR fallback
        endcase
        return byte_addr[$clog2(DEPTH)+$clog2(DATA_W/8)-1:$clog2(DATA_W/8)];
    endfunction

    always_comb begin
        rdata = mem[get_word_addr(araddr_latched, r_beat, arsize_latched, arburst_latched)];
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            // handled above
        end else begin
            if (r_active && rvalid && rready) begin
                if (r_beat < arlen_latched)
                    r_beat <= r_beat + 1;
                // On rlast, r_active cleared above — r_beat not incremented further
            end
        end
    end

endmodule : axi_slave_sram
