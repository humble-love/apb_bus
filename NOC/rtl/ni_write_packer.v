// ni_write_packer.v — AXI4 AW+W channels to flit stream
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_write_packer #(
  parameter DATA_W = 512
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire        awvalid,
  output wire        awready,
  input  wire [31:0] awaddr,
  input  wire [7:0]  awid,
  input  wire [7:0]  awlen,
  input  wire [1:0]  awburst,
  input  wire [3:0]  awsize,
  input  wire [3:0]  awlock,
  input  wire [1:0]  awcache,
  input  wire [3:0]  awqos,

  input  wire        wvalid,
  output wire        wready,
  input  wire [DATA_W-1:0] wdata,
  input  wire [(DATA_W/8)-1:0] wstrb,
  input  wire        wlast,

  input  wire [`COORD_W-1:0]   dst_coord,
  input  wire [`COORD_W-1:0]   src_coord,
  input  wire [`NODE_ID_W-1:0] dst_id,

  output wire [`FLIT_PAYLOAD_W-1:0] flit_out_payload,
  output wire [1:0]                 flit_out_ftype,
  output wire        flit_valid,
  input  wire        flit_ready
);

  localparam ST_IDLE   = 2'd0;
  localparam ST_HEADER = 2'd1;
  localparam ST_BODY   = 2'd2;

  reg [1:0] state;

  // AW capture buffer -- decouples AW handshake from flit processing
  reg        aw_buf_valid;
  reg [31:0] aw_buf_addr;
  reg [7:0]  aw_buf_id, aw_buf_len;
  reg [1:0]  aw_buf_burst;
  reg [3:0]  aw_buf_size, aw_buf_lock, aw_buf_qos;
  reg [1:0]  aw_buf_cache;

  assign awready = !aw_buf_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      aw_buf_valid <= 1'b0;
    end else begin
      // Capture AW on handshake
      if (awvalid && awready) begin
        aw_buf_addr  <= awaddr;
        aw_buf_id    <= awid;
        aw_buf_len   <= awlen;
        aw_buf_burst <= awburst;
        aw_buf_size  <= awsize;
        aw_buf_lock  <= awlock;
        aw_buf_cache <= awcache;
        aw_buf_qos   <= awqos;
        aw_buf_valid <= 1'b1;
      end

      // FSM: process buffered request
      case (state)
        ST_IDLE:   if (aw_buf_valid) begin
                     state <= ST_HEADER;
                   end
        ST_HEADER: if (flit_valid && flit_ready) begin
                     state <= ST_BODY;
                   end
        ST_BODY:   if (wvalid && wready && wlast) begin
                     state <= ST_IDLE;
                     aw_buf_valid <= 1'b0;
                   end
      endcase
    end
  end

  // Intermediate wires for header fields (avoid Verilog-2001 part-select on part-select)
  wire [2:0]  hdr_dst_y    = `COORD_Y(dst_coord);
  wire [2:0]  hdr_dst_x    = `COORD_X(dst_coord);
  wire [2:0]  hdr_src_y    = `COORD_Y(src_coord);
  wire [2:0]  hdr_src_x    = `COORD_X(src_coord);
  wire [3:0]  hdr_axprot   = 4'b0;
  wire [445:0] body_data_w = wdata[445:0];

  reg [`FLIT_PAYLOAD_W-1:0] flit_out_payload_comb;
  reg [1:0] flit_out_ftype_comb;

  always @(*) begin
    flit_out_payload_comb = {(`FLIT_PAYLOAD_W){1'b0}};
    flit_out_ftype_comb   = `FLIT_IDLE;
    if (state == ST_HEADER) begin
      flit_out_payload_comb = `FLIT_HDR_PACK(
        hdr_dst_y, hdr_dst_x,
        hdr_src_y, hdr_src_x,
        aw_buf_qos, aw_buf_len, aw_buf_id, aw_buf_addr,
        aw_buf_burst, aw_buf_size, aw_buf_lock, aw_buf_cache,
        hdr_axprot, 1'b0, 1'b0
      );
      flit_out_ftype_comb = `FLIT_HEADER;
    end else if (state == ST_BODY) begin
      flit_out_payload_comb = `FLIT_BODY_PACK(body_data_w, wstrb);
      flit_out_ftype_comb   = wlast ? `FLIT_TAIL : `FLIT_BODY;
    end
  end

  assign flit_out_payload = flit_out_payload_comb;
  assign flit_out_ftype   = flit_out_ftype_comb;
  assign flit_valid = (state == ST_HEADER) || (state == ST_BODY && wvalid);
  assign wready     = (state == ST_BODY && flit_ready);

endmodule
