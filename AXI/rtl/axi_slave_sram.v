// AXI4-Full Slave: SRAM with configurable depth and stall insertion
// Supports FIXED, INCR, WRAP bursts
// Narrow transfers via WSTRB per-byte masking

module axi_slave_sram #(
    parameter DEPTH      = 1024,
    parameter DATA_W     = 256,
    parameter ID_W       = 8,
    parameter ADDR_W     = 32,
    parameter STALL_PROB = 0   // 0-255 out of 256 chance to stall
) (
    input  wire                aclk,
    input  wire                aresetn,

    // Write Address Channel
    input  wire [ID_W-1:0]     awid,
    input  wire [ADDR_W-1:0]   awaddr,
    input  wire [7:0]          awlen,
    input  wire [2:0]          awsize,
    input  wire [1:0]          awburst,
    input  wire                awvalid,
    output wire                awready,

    // Write Data Channel
    input  wire [DATA_W-1:0]   wdata,
    input  wire [DATA_W/8-1:0] wstrb,
    input  wire                wlast,
    input  wire                wvalid,
    output wire                wready,

    // Write Response Channel
    output reg  [ID_W-1:0]     bid,
    output reg  [1:0]          bresp,
    output reg                 bvalid,
    input  wire                bready,

    // Read Address Channel
    input  wire [ID_W-1:0]     arid,
    input  wire [ADDR_W-1:0]   araddr,
    input  wire [7:0]          arlen,
    input  wire [2:0]          arsize,
    input  wire [1:0]          arburst,
    input  wire                arvalid,
    output wire                arready,

    // Read Data Channel
    output wire [ID_W-1:0]     rid,
    output reg  [DATA_W-1:0]   rdata,
    output wire [1:0]          rresp,
    output wire                rlast,
    output wire                rvalid,
    input  wire                rready
);

    localparam AW = 0, W  = 1, B  = 2, AR = 3, R  = 4;

    // BRAM
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // Latched transaction info
    reg [ID_W-1:0]   awid_latched, arid_latched;
    reg [ADDR_W-1:0] awaddr_latched, araddr_latched;
    reg [7:0]        awlen_latched, arlen_latched;
    reg [2:0]        awsize_latched, arsize_latched;
    reg [1:0]        awburst_latched, arburst_latched;
    reg [7:0]        w_beat, r_beat;
    reg              w_active, r_active;
    reg [1:0]        w_resp;

    // Stall randomizer
    reg [7:0] stall_rng;
    wire      stall_now;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) stall_rng <= 8'h5A;
        else         stall_rng <= {stall_rng[6:0], stall_rng[7] ^ stall_rng[5] ^ stall_rng[4] ^ stall_rng[3]};
    end
    assign stall_now = (stall_rng < STALL_PROB);

    // AW channel
    assign awready = !w_active;  // one write at a time

    always @(posedge aclk or negedge aresetn) begin
        reg [9:0] word_addr;
        reg [DATA_W-1:0] old_data;
        integer b;
        if (!aresetn) begin
            w_active <= 1'b0;
        end else begin
            if (awvalid && awready) begin
                awid_latched   <= awid;
                awaddr_latched <= awaddr;
                awlen_latched  <= awlen;
                awsize_latched <= awsize;
                awburst_latched <= awburst;
                w_beat         <= {8{1'b0}};
                w_active       <= 1'b1;
                w_resp         <= 2'b00;  // OKAY
            end
            // Write data
            if (w_active && wvalid && wready) begin
                // Calculate address for this beat
                word_addr = get_word_addr(awaddr_latched, w_beat, awsize_latched, awburst_latched, awlen_latched);

                // Read-modify-write for narrow transfers via WSTRB
                old_data = mem[word_addr];
                for (b = 0; b < 32; b = b + 1) begin
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
    always @(posedge aclk or negedge aresetn) begin
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

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_active <= 1'b0;
        end else begin
            if (arvalid && arready) begin
                arid_latched    <= arid;
                araddr_latched  <= araddr;
                arlen_latched   <= arlen;
                arsize_latched  <= arsize;
                arburst_latched <= arburst;
                r_beat          <= {8{1'b0}};
                r_active        <= 1'b1;
            end
            if (r_active && rvalid && rready && rlast)
                r_active <= 1'b0;
            // r_beat increment (merged from separate always_ff)
            if (r_active && rvalid && rready && (r_beat < arlen_latched))
                r_beat <= r_beat + 1;
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
    function [9:0] get_word_addr;
        input [ADDR_W-1:0] base;
        input [7:0] beat;
        input [2:0] size;
        input [1:0] burst;
        input [7:0] len;
        reg [ADDR_W-1:0] byte_addr;
        reg [ADDR_W-1:0] wrap_boundary;
        begin
            case (burst)
                2'b00: byte_addr = base;                                      // FIXED
                2'b01: byte_addr = base + (beat << size);                     // INCR
                2'b10: begin                                                   // WRAP
                    wrap_boundary = (len + 1) << size;
                    byte_addr = (base & ~(wrap_boundary - 1)) +
                                ((base + (beat << size)) & (wrap_boundary - 1));
                end
                default: byte_addr = base + (beat << size);                   // INCR fallback
            endcase
            get_word_addr = byte_addr[14:5];
        end
    endfunction

    always @(*) begin
        rdata = mem[get_word_addr(araddr_latched, r_beat, arsize_latched, arburst_latched, arlen_latched)];
    end

endmodule
