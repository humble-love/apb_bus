// ni_read_responder.sv — Responds to read requests with data flits
// When a read request header arrives on VC1, generates a response:
//   header flit (src/dst swapped) + single body flit with pattern data
// Response goes out on VC0 back to the requester
module ni_read_responder #(
  parameter int DATA_W = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  // Incoming flit from router (VC1) — read request header detected here
  input  noc_flit_pkg::flit_t        vc1_flit_in,
  input  logic        vc1_flit_valid,
  input  logic        vc1_flit_ready,

  // Local coordinate — only respond to headers addressed to this tile
  input  noc_config_pkg::coord_t     local_coord,

  // Response flits to send on VC0 back to requester
  output noc_flit_pkg::flit_t        resp_flit_out,
  output logic        resp_flit_valid,
  input  logic        resp_flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE, ST_HEADER, ST_BODY
  } state_t;
  state_t state;

  flit_header_t saved_hdr;
  flit_header_t vc1_hdr;

  // VCS 2018: cannot access struct member from function return inline
  assign vc1_hdr = unpack_header(vc1_flit_in.payload);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= ST_IDLE;
      saved_hdr <= '0;
    end else begin
      case (state)
        ST_IDLE: begin
          // Capture read request header on VC1 (is_read == 1)
          if (vc1_flit_valid && vc1_flit_ready &&
              vc1_flit_in.ftype == FLIT_HEADER &&
              vc1_hdr.is_read && !vc1_hdr.is_response &&
              vc1_hdr.dst_x == local_coord.x && vc1_hdr.dst_y == local_coord.y) begin
            saved_hdr <= vc1_hdr;
            state     <= ST_HEADER;
          end
        end
        ST_HEADER: if (resp_flit_valid && resp_flit_ready) state <= ST_BODY;
        ST_BODY:   if (resp_flit_valid && resp_flit_ready) state <= ST_IDLE;
      endcase
    end
  end

  always_comb begin
    resp_flit_out = '0;
    if (state == ST_HEADER) begin
      flit_header_t hdr;
      hdr            = saved_hdr;
      // Swap src and dst for the response path
      hdr.dst_y      = saved_hdr.src_y;
      hdr.dst_x      = saved_hdr.src_x;
      hdr.src_y      = saved_hdr.dst_y;
      hdr.src_x      = saved_hdr.dst_x;
      hdr.is_response = 1'b1;
      resp_flit_out   = flit_make_header(hdr);
    end else if (state == ST_BODY) begin
      // Return pattern data: {dst_coord, src_coord, axaddr} in lower bits
      logic [445:0] data;
      data = '0;
      data[47:0]  = saved_hdr.axaddr;
      data[3:0]   = saved_hdr.dst_x;
      data[7:4]   = saved_hdr.dst_y;
      data[11:8]  = saved_hdr.src_x;
      data[15:12] = saved_hdr.src_y;
      resp_flit_out = flit_make_body('1, data, FLIT_TAIL);
    end
  end

  assign resp_flit_valid = (state == ST_HEADER) || (state == ST_BODY);

endmodule
