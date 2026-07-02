// ni_write_unpacker.v — Flit stream to AXI4 B channel
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_write_unpacker #(
  parameter DATA_W = 512
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [`FLIT_PAYLOAD_W-1:0] flit_in_payload,
  input  wire [1:0]                 flit_in_ftype,
  input  wire        flit_valid,
  output wire        flit_ready,

  output wire        bvalid,
  input  wire        bready,
  output wire [7:0]  bid,
  output wire [1:0]  bresp
);

  reg b_pending;
  reg [7:0] b_id;
  reg [1:0] b_resp;

  assign flit_ready = !b_pending || bready;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_pending <= 1'b0;
      b_id      <= {8{1'b0}};
      b_resp    <= {2{1'b0}};
    end else begin
      if (flit_valid && flit_ready && flit_in_ftype == `FLIT_HEADER) begin
        b_id      <= `FLIT_HDR_AXID(flit_in_payload);
        b_resp    <= 2'b00;  // OKAY
        b_pending <= 1'b1;
      end else if (bready && b_pending) begin
        b_pending <= 1'b0;
      end
    end
  end

  assign bvalid = b_pending;
  assign bid    = b_id;
  assign bresp  = b_resp;
endmodule
