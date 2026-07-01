// ni_response_sender.sv — Generate B response flit for incoming write requests
// When a write request header arrives on VC1, create a B response header flit
// to send back to the source via VC0 (swapped src/dst)
module ni_response_sender #(
  parameter int DATA_W = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  // Incoming flit from router (VC1) — write request header detected here
  input  noc_flit_pkg::flit_t        vc1_flit_in,
  input  logic        vc1_flit_valid,
  input  logic        vc1_flit_ready,

  // Local coordinate — only respond to headers addressed to this tile
  input  noc_config_pkg::coord_t     local_coord,

  // Response flit to send on VC0 back to source
  output noc_flit_pkg::flit_t        resp_flit_out,
  output logic        resp_flit_valid,
  input  logic        resp_flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic in_header;
  flit_header_t saved_hdr;
  flit_header_t vc1_hdr;

  // VCS 2018: cannot access struct member from function return inline
  assign vc1_hdr = unpack_header(vc1_flit_in.payload);

  // Detect incoming write request header (is_read == 0)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_header <= 1'b0;
      saved_hdr <= '0;
    end else begin
      if (vc1_flit_valid && vc1_flit_ready && vc1_flit_in.ftype == FLIT_HEADER
          && !vc1_hdr.is_read && !vc1_hdr.is_response
          && vc1_hdr.dst_x == local_coord.x && vc1_hdr.dst_y == local_coord.y) begin
        in_header <= 1'b1;
        saved_hdr <= vc1_hdr;
      end else if (resp_flit_valid && resp_flit_ready) begin
        in_header <= 1'b0;
      end
    end
  end

  // Generate response header flit with src/dst swapped
  always_comb begin
    resp_flit_out = '0;
    if (in_header) begin
      flit_header_t hdr;
      hdr            = saved_hdr;
      // Swap src and dst for the response path
      hdr.dst_y      = saved_hdr.src_y;
      hdr.dst_x      = saved_hdr.src_x;
      hdr.src_y      = saved_hdr.dst_y;
      hdr.src_x      = saved_hdr.dst_x;
      hdr.is_response = 1'b1;
      resp_flit_out   = flit_make_header(hdr);
    end
  end

  assign resp_flit_valid = in_header;

endmodule
