// ni_read_packer.sv — AXI4 AR channel to flit header
module ni_read_packer #(
  parameter int DATA_W = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  input  logic [7:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [1:0]  arburst,
  input  logic [3:0]  arsize,
  input  logic [3:0]  arlock,
  input  logic [1:0]  arcache,
  input  logic [3:0]  arqos,

  input  noc_config_pkg::coord_t     dst_coord,
  input  noc_config_pkg::coord_t     src_coord,
  input  noc_config_pkg::node_id_t   dst_id,

  output noc_flit_pkg::flit_t        flit_out,
  output logic        flit_valid,
  input  logic        flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic in_header;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      in_header <= 1'b0;
    else if (arvalid && arready)
      in_header <= 1'b1;
    else if (flit_valid && flit_ready)
      in_header <= 1'b0;
  end

  always_comb begin
    flit_out = '0;
    if (in_header) begin
      flit_header_t hdr;
      hdr.dst_y   = dst_coord.y;
      hdr.dst_x   = dst_coord.x;
      hdr.src_y   = src_coord.y;
      hdr.src_x   = src_coord.x;
      hdr.qos     = qos_t'(arqos);
      hdr.axlen   = arlen;
      hdr.axid    = arid;
      hdr.axaddr  = araddr;
      hdr.axburst = arburst;
      hdr.axsize  = arsize;
      hdr.axlock  = arlock;
      hdr.axcache = arcache;
      hdr.axprot  = '0;
      flit_out = flit_make_header(hdr);
    end
  end

  assign flit_valid = in_header;
  assign arready    = !in_header && !flit_valid;
endmodule
