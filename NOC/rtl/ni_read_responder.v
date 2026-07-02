// ni_read_responder.v — Responds to read requests with data flits
// When a read request header arrives on VC1, generates a response:
//   header flit (src/dst swapped) + single body flit with pattern data
// Response goes out on VC0 back to the requester
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_read_responder #(
  parameter DATA_W = 512
) (
  input  wire        clk,
  input  wire        rst_n,

  // Incoming flit from router (VC1) — read request header detected here
  input  wire [`FLIT_PAYLOAD_W-1:0] vc1_flit_in_payload,
  input  wire [1:0]                 vc1_flit_in_ftype,
  input  wire        vc1_flit_valid,
  input  wire        vc1_flit_ready,

  // Local coordinate — only respond to headers addressed to this tile
  input  wire [`COORD_W-1:0] local_coord,

  // Response flits to send on VC0 back to requester
  output wire [`FLIT_PAYLOAD_W-1:0] resp_flit_out_payload,
  output wire [1:0]                 resp_flit_out_ftype,
  output wire        resp_flit_valid,
  input  wire        resp_flit_ready
);

  localparam ST_IDLE   = 2'd0;
  localparam ST_HEADER = 2'd1;
  localparam ST_BODY   = 2'd2;

  reg [1:0] state;

  reg [`FLIT_PAYLOAD_W-1:0] saved_payload;

  // VCS 2018: cannot access struct member from function return inline
  wire vc1_is_read     = `FLIT_HDR_IS_READ(vc1_flit_in_payload);
  wire vc1_is_response = `FLIT_HDR_IS_RESPONSE(vc1_flit_in_payload);
  wire [2:0] vc1_dst_x = `FLIT_HDR_DST_X(vc1_flit_in_payload);
  wire [2:0] vc1_dst_y = `FLIT_HDR_DST_Y(vc1_flit_in_payload);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= ST_IDLE;
      saved_payload <= {(`FLIT_PAYLOAD_W){1'b0}};
    end else begin
      case (state)
        ST_IDLE: begin
          // Capture read request header on VC1 (is_read == 1)
          if (vc1_flit_valid && vc1_flit_ready &&
              vc1_flit_in_ftype == `FLIT_HEADER &&
              vc1_is_read && !vc1_is_response &&
              vc1_dst_x == `COORD_X(local_coord) && vc1_dst_y == `COORD_Y(local_coord)) begin
            saved_payload <= vc1_flit_in_payload;
            state         <= ST_HEADER;
          end
        end
        ST_HEADER: if (resp_flit_valid && resp_flit_ready) state <= ST_BODY;
        ST_BODY:   if (resp_flit_valid && resp_flit_ready) state <= ST_IDLE;
      endcase
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

  // Body data construction and intermediate wires for macros
  reg [445:0] body_data;
  wire [63:0] body_wstrb_all1 = {64{1'b1}};

  reg [`FLIT_PAYLOAD_W-1:0] resp_flit_payload_comb;
  reg [1:0] resp_flit_ftype_comb;

  always @(*) begin
    resp_flit_payload_comb = {(`FLIT_PAYLOAD_W){1'b0}};
    resp_flit_ftype_comb   = `FLIT_IDLE;
    body_data = {446{1'b0}};
    if (state == ST_HEADER) begin
      resp_flit_payload_comb = `FLIT_HDR_PACK(
        resp_dst_y, resp_dst_x,
        resp_src_y, resp_src_x,
        resp_qos, resp_axlen, resp_axid, resp_axaddr,
        resp_axburst, resp_axsize, resp_axlock, resp_axcache,
        resp_axprot, resp_is_read, 1'b1
      );
      resp_flit_ftype_comb = `FLIT_HEADER;
    end else if (state == ST_BODY) begin
      // Return pattern data: {dst_coord, src_coord, axaddr} in lower bits
      body_data[47:0]  = `FLIT_HDR_AXADDR(saved_payload);
      body_data[3:0]   = `FLIT_HDR_DST_X(saved_payload);
      body_data[7:4]   = `FLIT_HDR_DST_Y(saved_payload);
      body_data[11:8]  = `FLIT_HDR_SRC_X(saved_payload);
      body_data[15:12] = `FLIT_HDR_SRC_Y(saved_payload);
      resp_flit_payload_comb = `FLIT_BODY_PACK(body_data, body_wstrb_all1);
      resp_flit_ftype_comb   = `FLIT_TAIL;
    end
  end

  assign resp_flit_out_payload = resp_flit_payload_comb;
  assign resp_flit_out_ftype   = resp_flit_ftype_comb;
  assign resp_flit_valid = (state == ST_HEADER) || (state == ST_BODY);

endmodule
