// ni_read_packer.v — AXI4 AR channel to flit header
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_read_packer #(
  parameter DATA_W = 512
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire        arvalid,
  output wire        arready,
  input  wire [31:0] araddr,
  input  wire [7:0]  arid,
  input  wire [7:0]  arlen,
  input  wire [1:0]  arburst,
  input  wire [3:0]  arsize,
  input  wire [3:0]  arlock,
  input  wire [1:0]  arcache,
  input  wire [3:0]  arqos,

  input  wire [`COORD_W-1:0]   dst_coord,
  input  wire [`COORD_W-1:0]   src_coord,
  input  wire [`NODE_ID_W-1:0] dst_id,

  output wire [`FLIT_PAYLOAD_W-1:0] flit_out_payload,
  output wire [1:0]                 flit_out_ftype,
  output wire        flit_valid,
  input  wire        flit_ready
);

  reg in_header;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      in_header <= 1'b0;
    else if (arvalid && arready)
      in_header <= 1'b1;
    else if (flit_valid && flit_ready)
      in_header <= 1'b0;
  end

  // Intermediate wires for header fields (avoid Verilog-2001 part-select on part-select)
  wire [2:0]  hdr_dst_y  = `COORD_Y(dst_coord);
  wire [2:0]  hdr_dst_x  = `COORD_X(dst_coord);
  wire [2:0]  hdr_src_y  = `COORD_Y(src_coord);
  wire [2:0]  hdr_src_x  = `COORD_X(src_coord);
  wire [3:0]  hdr_axprot = 4'b0;

  reg [`FLIT_PAYLOAD_W-1:0] flit_out_payload_comb;
  reg [1:0] flit_out_ftype_comb;

  always @(*) begin
    flit_out_payload_comb = {(`FLIT_PAYLOAD_W){1'b0}};
    flit_out_ftype_comb   = `FLIT_IDLE;
    if (in_header) begin
      flit_out_payload_comb = `FLIT_HDR_PACK(
        hdr_dst_y, hdr_dst_x,
        hdr_src_y, hdr_src_x,
        arqos, arlen, arid, araddr,
        arburst, arsize, arlock, arcache,
        hdr_axprot, 1'b1, 1'b0
      );
      flit_out_ftype_comb = `FLIT_HEADER;
    end
  end

  assign flit_out_payload = flit_out_payload_comb;
  assign flit_out_ftype   = flit_out_ftype_comb;
  assign flit_valid = in_header;
  assign arready    = !in_header && !flit_valid;
endmodule
