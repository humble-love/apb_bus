// APB Address Decoder
// PADDR[15:12] = 0x0 → Slave 0 (Memory)
// PADDR[15:12] = 0x1 → Slave 1 (GPIO)

module apb_decoder (
    input  wire [31:0] paddr,
    input  wire        psel_in,
    output wire [1:0]  psel_o
);

    assign psel_o[0] = psel_in && (paddr[15:12] == 4'h0);
    assign psel_o[1] = psel_in && (paddr[15:12] == 4'h1);

endmodule
