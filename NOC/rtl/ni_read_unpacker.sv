// ni_read_unpacker.sv — Flit stream to AXI4 R channel with OOO support
module ni_read_unpacker #(
  parameter int DATA_W         = 512,
  parameter int AXI_ID_W       = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  input  noc_flit_pkg::flit_t        flit_in,
  input  logic        flit_valid,
  output logic        flit_ready,

  output logic        rvalid,
  input  logic        rready,
  output logic [AXI_ID_W-1:0] rid,
  output logic [DATA_W-1:0]   rdata,
  output logic [1:0]          rresp,
  output logic                rlast
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic r_pending;
  logic [7:0] r_id;
  logic [DATA_W-1:0] r_data;
  logic r_last;

  assign flit_ready = !r_pending || rready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_pending <= 1'b0;
      r_id      <= '0;
      r_data    <= '0;
      r_last    <= 1'b0;
    end else begin
      if (flit_valid && flit_ready &&
          (flit_in.ftype == FLIT_BODY || flit_in.ftype == FLIT_TAIL)) begin
        // Extract header for ID (carried in first body's context or from tracking)
        // Simplified: ID from flit metadata passed by the response header
        flit_header_t hdr = unpack_header(flit_in.payload);
        r_id      <= hdr.axid;
        r_data    <= {flit_get_data(flit_in), flit_get_wstrb(flit_in)};
        r_last    <= (flit_in.ftype == FLIT_TAIL);
        r_pending <= 1'b1;
      end else if (rready && r_pending) begin
        r_pending <= 1'b0;
      end
    end
  end

  assign rvalid = r_pending;
  assign rid    = r_id;
  assign rdata  = r_data;
  assign rresp  = 2'b00;
  assign rlast  = r_last;
endmodule
