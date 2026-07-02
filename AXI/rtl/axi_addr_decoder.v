// AXI Address Decoder
// Maps AWADDR/ARADDR[31:28] to slave select
// Slave 0: 0x0xxx_xxxx (SRAM, 256KB)
// Slave 1: 0x1xxx_xxxx (DFI/DDR5, 256MB)
// Others: DECERR

module axi_addr_decoder #(
    parameter NUM_SLAVES = 2,
    parameter ADDR_W     = 32
) (
    input  wire [ADDR_W-1:0] awaddr,
    input  wire              awvalid,
    output wire [NUM_SLAVES-1:0] aw_sel,
    output wire              aw_decerr,

    input  wire [ADDR_W-1:0] araddr,
    input  wire              arvalid,
    output wire [NUM_SLAVES-1:0] ar_sel,
    output wire              ar_decerr
);

    function [NUM_SLAVES:0] decode;
        input [ADDR_W-1:0] addr;
        begin
            case (addr[ADDR_W-1:28])
                4'h0: decode = {{(NUM_SLAVES-1){1'b0}}, 1'b1, 1'b0};       // slave 0, no err
                4'h1: decode = {{(NUM_SLAVES-2){1'b0}}, 1'b1, 1'b0, 1'b0};  // slave 1, no err
                default: decode = {{NUM_SLAVES{1'b0}}, 1'b1};               // no sel, decerr
            endcase
        end
    endfunction

    wire [NUM_SLAVES:0] aw_decoded, ar_decoded;

    assign aw_decoded = decode(awaddr);
    assign ar_decoded = decode(araddr);

    assign aw_sel    = awvalid ? aw_decoded[NUM_SLAVES:1] : {NUM_SLAVES{1'b0}};
    assign aw_decerr = awvalid & aw_decoded[0];
    assign ar_sel    = arvalid ? ar_decoded[NUM_SLAVES:1] : {NUM_SLAVES{1'b0}};
    assign ar_decerr = arvalid & ar_decoded[0];

endmodule
