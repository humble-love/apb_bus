// APB3 Memory Slave — 256 × 32-bit
// Address range: 0x0000-0x0FFF
// Randomized PREADY stall using 8-bit LFSR

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
    output reg  [31:0]  prdata,
    output reg          pready
);

    reg [31:0] mem [0:255];
    reg [7:0]  lfsr;

    // PREADY with LFSR-based randomized stall
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pready <= 1'b1;
            lfsr   <= 8'h5A;
        end else begin
            if (penable && psel) begin
                lfsr   <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
                pready <= (lfsr >= STALL_PROB);
            end else begin
                pready <= 1'b1;
            end
        end
    end

    // Write
    always @(posedge pclk) begin
        if (psel && penable && pready && pwrite)
            mem[paddr[9:2]] <= pwdata;
    end

    // Read (combinational — APB spec)
    always @(*) begin
        prdata = mem[paddr[9:2]];
    end

endmodule
