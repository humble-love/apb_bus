// ni_response_sender.v — Generate B response flit for incoming write requests
// When a write request header arrives on VC1, create a B response header flit
// to send back to the source via VC0 (swapped src/dst)
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_response_sender #(
  parameter DATA_W = 512
) (
  input  wire        clk,
  input  wire        rst_n,

  // Incoming flit from router (VC1) — write request header detected here
  input  wire [`FLIT_PAYLOAD_W-1:0] vc1_flit_in_payload,
  input  wire [1:0]                 vc1_flit_in_ftype,
  input  wire        vc1_flit_valid,
  input  wire        vc1_flit_ready,

  // Local coordinate — only respond to headers addressed to this tile
  input  wire [`COORD_W-1:0] local_coord,

  // Response flit to send on VC0 back to source
  output wire [`FLIT_PAYLOAD_W-1:0] resp_flit_out_payload,
  output wire [1:0]                 resp_flit_out_ftype,
  output wire        resp_flit_valid,
  input  wire        resp_flit_ready
);

  reg in_header;
  reg [`FLIT_PAYLOAD_W-1:0] saved_payload;

  // Detect incoming write request header (is_read == 0)
  // VCS 2018: cannot access struct member from function return inline
  wire vc1_is_read     = `FLIT_HDR_IS_READ(vc1_flit_in_payload);
  wire vc1_is_response = `FLIT_HDR_IS_RESPONSE(vc1_flit_in_payload);
  wire [2:0] vc1_dst_x = `FLIT_HDR_DST_X(vc1_flit_in_payload);
  wire [2:0] vc1_dst_y = `FLIT_HDR_DST_Y(vc1_flit_in_payload);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      in_header     <= 1'b0;
      saved_payload <= {(`FLIT_PAYLOAD_W){1'b0}};
    end else begin
      if (vc1_flit_valid && vc1_flit_ready && vc1_flit_in_ftype == `FLIT_HEADER
          && !vc1_is_read && !vc1_is_response
          && vc1_dst_x == `COORD_X(local_coord) && vc1_dst_y == `COORD_Y(local_coord)) begin
        in_header     <= 1'b1;
        saved_payload <= vc1_flit_in_payload;
      end else if (resp_flit_valid && resp_flit_ready) begin
        in_header <= 1'b0;
      end
    end
  end

  // Intermediate wires for response header fields (avoid Verilog-2001 part-select on part-select)
  wire [2:0]  resp_dst_y    = `FLIT_HDR_SRC_Y(saved_payload);
  wire [2:0]  resp_dst_x    = `FLIT_HDR_SRC_X(saved_payload);
  wire [2:0]  resp_src_y    = `FLIT_HDR_DST_Y(saved_payload);
  wire [2:0]  resp_src_x    = `FLIT_HDR_DST_X(saved_payload);
  wire [3:0]  resp_qos      = `FLIT_HDR_QOS(saved_payload);
  wire [7:0]  resp_axlen    = `FLIT_HDR_AXLEN(saved_payload);
  wire [7:0]  resp_axid     = `FLIT_HDR_AXID(saved_payload);
  wire [31:0] resp_axaddr   = `FLIT_HDR_AXADDR(saved_payload);
  wire [1:0]  resp_axburst  = `FLIT_HDR_AXBURST(saved_payload);
  wire [3:0]  resp_axsize   = `FLIT_HDR_AXSIZE(saved_payload);
  wire [3:0]  resp_axlock   = `FLIT_HDR_AXLOCK(saved_payload);
  wire [1:0]  resp_axcache  = `FLIT_HDR_AXCACHE(saved_payload);
  wire [3:0]  resp_axprot   = `FLIT_HDR_AXPROT(saved_payload);
  wire        resp_is_read  = `FLIT_HDR_IS_READ(saved_payload);

  reg [`FLIT_PAYLOAD_W-1:0] resp_flit_payload_comb;
  reg [1:0] resp_flit_ftype_comb;

  always @(*) begin
    resp_flit_payload_comb = {(`FLIT_PAYLOAD_W){1'b0}};
    resp_flit_ftype_comb   = `FLIT_IDLE;
    if (in_header) begin
      resp_flit_payload_comb = `FLIT_HDR_PACK(
        resp_dst_y, resp_dst_x,
        resp_src_y, resp_src_x,
        resp_qos, resp_axlen, resp_axid, resp_axaddr,
        resp_axburst, resp_axsize, resp_axlock, resp_axcache,
        resp_axprot, resp_is_read, 1'b1
      );
      resp_flit_ftype_comb = `FLIT_HEADER;
    end
  end

  assign resp_flit_out_payload = resp_flit_payload_comb;
  assign resp_flit_out_ftype   = resp_flit_ftype_comb;
  assign resp_flit_valid = in_header;

endmodule
