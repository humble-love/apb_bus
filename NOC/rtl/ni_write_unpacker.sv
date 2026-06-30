// ni_write_unpacker.sv — Flit stream to AXI4 B channel
module ni_write_unpacker #(
  parameter int DATA_W = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  input  noc_flit_pkg::flit_t        flit_in,
  input  logic        flit_valid,
  output logic        flit_ready,

  output logic        bvalid,
  input  logic        bready,
  output logic [7:0]  bid,
  output logic [1:0]  bresp
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic b_pending;
  logic [7:0] b_id;
  logic [1:0] b_resp;

  assign flit_ready = !b_pending || bready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_pending <= 1'b0;
      b_id      <= '0;
      b_resp    <= '0;
    end else begin
      if (flit_valid && flit_ready && flit_in.ftype == FLIT_HEADER) begin
        flit_header_t hdr = unpack_header(flit_in.payload);
        b_id      <= hdr.axid;
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
