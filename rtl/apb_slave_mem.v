// APB3 Memory Slave — 256 × 32-bit
// Address range: 0x0000-0x0FFF
// Randomized PREADY stall using 8-bit LFSR
// PSTRB byte-write masking supported
// Address range guarded: writes outside 0x000-0xFFF are ignored

module apb_slave_mem #(
    parameter STALL_PROB = 64   // 64/256 = 25% stall chance
) (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    input  wire [3:0]   pwstrb,
    output reg  [31:0]  prdata,
    output reg          pready
);

    reg [31:0] mem [0:255];
    reg [7:0]  lfsr;

    // Address range check
    wire addr_ok = (paddr[15:12] == 4'h0);

    // PREADY with LFSR-based randomized stall
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pready <= 1'b1;
            lfsr   <= 8'h5A;
        end else begin
            if (penable && psel && addr_ok) begin
                lfsr   <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
                pready <= (lfsr >= STALL_PROB);
            end else begin
                pready <= 1'b1;
            end
        end
    end

    // Write with PSTRB byte masking and address guard
    always @(posedge pclk) begin
        if (psel && penable && pready && pwrite && addr_ok) begin
            if (pwstrb[0]) mem[paddr[9:2]][ 7: 0] <= pwdata[ 7: 0];
            if (pwstrb[1]) mem[paddr[9:2]][15: 8] <= pwdata[15: 8];
            if (pwstrb[2]) mem[paddr[9:2]][23:16] <= pwdata[23:16];
            if (pwstrb[3]) mem[paddr[9:2]][31:24] <= pwdata[31:24];
        end
    end

    // Read — combinational, gated by psel and address range
    always @(*) begin
        if (psel && addr_ok)
            prdata = mem[paddr[9:2]];
        else
            prdata = 32'd0;
    end

endmodule
