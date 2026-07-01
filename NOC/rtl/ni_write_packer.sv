// ni_write_packer.sv — AXI4 AW+W channels to flit stream
module ni_write_packer #(
  parameter int DATA_W  = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic [7:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [1:0]  awburst,
  input  logic [3:0]  awsize,
  input  logic [3:0]  awlock,
  input  logic [1:0]  awcache,
  input  logic [3:0]  awqos,

  input  logic        wvalid,
  output logic        wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [(DATA_W/8)-1:0] wstrb,
  input  logic        wlast,

  input  noc_config_pkg::coord_t     dst_coord,
  input  noc_config_pkg::coord_t     src_coord,
  input  noc_config_pkg::node_id_t   dst_id,

  output noc_flit_pkg::flit_t        flit_out,
  output logic        flit_valid,
  input  logic        flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE, ST_HEADER, ST_BODY
  } state_t;
  state_t state;

  // AW capture buffer — decouples AW handshake from flit processing
  logic        aw_buf_valid;
  logic [31:0] aw_buf_addr;
  logic [7:0]  aw_buf_id, aw_buf_len;
  logic [1:0]  aw_buf_burst;
  logic [3:0]  aw_buf_size, aw_buf_lock, aw_buf_qos;
  logic [1:0]  aw_buf_cache;

  assign awready = !aw_buf_valid;

  always_ff @(posedge clk or negedge rst_n) begin
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
        ST_IDLE:   if (aw_buf_valid)           state <= ST_HEADER;
        ST_HEADER: if (flit_valid && flit_ready) state <= ST_BODY;
        ST_BODY:   if (wvalid && wready && wlast) begin
                     state <= ST_IDLE;
                     aw_buf_valid <= 1'b0;
                   end
      endcase
    end
  end

  always_comb begin
    flit_out = '0;
    if (state == ST_HEADER) begin
      flit_header_t hdr;
      hdr.dst_y   = dst_coord.y;
      hdr.dst_x   = dst_coord.x;
      hdr.src_y   = src_coord.y;
      hdr.src_x   = src_coord.x;
      hdr.qos     = qos_t'(aw_buf_qos);
      hdr.axlen   = aw_buf_len;
      hdr.axid    = aw_buf_id;
      hdr.axaddr  = aw_buf_addr;
      hdr.axburst = aw_buf_burst;
      hdr.axsize  = aw_buf_size;
      hdr.axlock  = aw_buf_lock;
      hdr.axcache = aw_buf_cache;
      hdr.axprot      = '0;
      hdr.is_read     = 1'b0;
      hdr.is_response = 1'b0;
      flit_out = flit_make_header(hdr);
    end else if (state == ST_BODY) begin
      flit_out = flit_make_body(wstrb, wdata[445:0],
                                wlast ? FLIT_TAIL : FLIT_BODY);
    end
  end

  assign flit_valid = (state == ST_HEADER) || (state == ST_BODY && wvalid);
  assign wready     = (state == ST_BODY && flit_ready);
endmodule
