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
    ST_IDLE, ST_HEADER, ST_BODY, ST_WAIT_B
  } state_t;
  state_t state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
    end else begin
      case (state)
        ST_IDLE:   if (awvalid && awready) state <= ST_HEADER;
        ST_HEADER: if (flit_valid && flit_ready)
                     state <= (awlen == 0) ? ST_WAIT_B : ST_BODY;
        ST_BODY:   if (wvalid && wready && wlast)
                     state <= ST_WAIT_B;
        ST_WAIT_B: state <= ST_IDLE;
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
      hdr.qos     = qos_t'(awqos);
      hdr.axlen   = awlen;
      hdr.axid    = awid;
      hdr.axaddr  = awaddr;
      hdr.axburst = awburst;
      hdr.axsize  = awsize;
      hdr.axlock  = awlock;
      hdr.axcache = awcache;
      hdr.axprot  = '0;
      flit_out = flit_make_header(hdr);
    end else if (state == ST_BODY) begin
      flit_out = flit_make_body(wstrb, wdata[445:0],
                                wlast ? FLIT_TAIL : FLIT_BODY);
    end
  end

  assign flit_valid = (state == ST_HEADER) || (state == ST_BODY && wvalid);
  assign awready    = (state == ST_IDLE);
  assign wready     = (state == ST_BODY && flit_ready);
endmodule
