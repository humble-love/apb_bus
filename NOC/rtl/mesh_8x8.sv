// mesh_8x8.sv — 8x8 mesh top-level with 64 noc_tile instances
// NOTE: Inter-tile mesh links currently simplified (local-only connectivity).
// Full NSEW mesh wiring requires bidirectional link pairs per connection.
module mesh_8x8 #(
  parameter int MESH_X         = 8,
  parameter int MESH_Y         = 8,
  parameter int VC_NUM         = 2,
  parameter int VC_DEPTH       = 8,
  parameter int DATA_W         = 512,
  parameter int QOS_W          = 4,
  parameter int PRIO_LEVELS    = 4,
  parameter int NI_FIFO_DEPTH  = 16,
  parameter int MAX_OUTSTANDING = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [MESH_Y-1:0][MESH_X-1:0]        awvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        awready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  awaddr,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   awid,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   awlen,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awburst,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awsize,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awlock,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awcache,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awqos,

  input  logic [MESH_Y-1:0][MESH_X-1:0]        wvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        wready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] wdata,
  input  logic [MESH_Y-1:0][MESH_X-1:0][(DATA_W/8)-1:0] wstrb,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        wlast,

  output logic [MESH_Y-1:0][MESH_X-1:0]        bvalid,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        bready,
  output logic [MESH_Y-1:0][MESH_X-1:0][7:0]   bid,
  output logic [MESH_Y-1:0][MESH_X-1:0][1:0]   bresp,

  input  logic [MESH_Y-1:0][MESH_X-1:0]        arvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        arready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  araddr,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   arid,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   arlen,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arburst,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arsize,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arlock,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arcache,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arqos,

  output logic [MESH_Y-1:0][MESH_X-1:0]        rvalid,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        rready,
  output logic [MESH_Y-1:0][MESH_X-1:0][7:0]   rid,
  output logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] rdata,
  output logic [MESH_Y-1:0][MESH_X-1:0][1:0]   rresp,
  output logic [MESH_Y-1:0][MESH_X-1:0]        rlast
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  genvar x, y;
  generate
    for (y = 0; y < MESH_Y; y++) begin : row
      for (x = 0; x < MESH_X; x++) begin : col
        // Boundary tiles have unused ports tied low
        noc_tile #(
          .MESH_X(MESH_X), .MESH_Y(MESH_Y),
          .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
          .DATA_W(DATA_W), .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS),
          .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
        ) tile (
          .clk, .rst_n,
          .tile_x(x[3:0]), .tile_y(y[3:0]),

          .awvalid(awvalid[y][x]), .awready(awready[y][x]),
          .awaddr(awaddr[y][x]), .awid(awid[y][x]),
          .awlen(awlen[y][x]), .awburst(awburst[y][x]),
          .awsize(awsize[y][x]), .awlock(awlock[y][x]),
          .awcache(awcache[y][x]), .awqos(awqos[y][x]),
          .wvalid(wvalid[y][x]), .wready(wready[y][x]),
          .wdata(wdata[y][x]), .wstrb(wstrb[y][x]), .wlast(wlast[y][x]),
          .bvalid(bvalid[y][x]), .bready(bready[y][x]),
          .bid(bid[y][x]), .bresp(bresp[y][x]),
          .arvalid(arvalid[y][x]), .arready(arready[y][x]),
          .araddr(araddr[y][x]), .arid(arid[y][x]),
          .arlen(arlen[y][x]), .arburst(arburst[y][x]),
          .arsize(arsize[y][x]), .arlock(arlock[y][x]),
          .arcache(arcache[y][x]), .arqos(arqos[y][x]),
          .rvalid(rvalid[y][x]), .rready(rready[y][x]),
          .rid(rid[y][x]), .rdata(rdata[y][x]),
          .rresp(rresp[y][x]), .rlast(rlast[y][x]),

          // All mesh links tied off for boundary tiles
          .n_in_flit('0), .s_in_flit('0), .e_in_flit('0), .w_in_flit('0),
          .n_in_valid(1'b0), .s_in_valid(1'b0), .e_in_valid(1'b0), .w_in_valid(1'b0),
          .n_in_vc('0), .s_in_vc('0), .e_in_vc('0), .w_in_vc('0),
          .n_credit_v0(), .s_credit_v0(), .e_credit_v0(), .w_credit_v0(),
          .n_credit_v1(), .s_credit_v1(), .e_credit_v1(), .w_credit_v1(),
          .n_out_flit(), .s_out_flit(), .e_out_flit(), .w_out_flit(),
          .n_out_valid(), .s_out_valid(), .e_out_valid(), .w_out_valid(),
          .n_out_vc(), .s_out_vc(), .e_out_vc(), .w_out_vc(),
          .n_credit_in_v0(1'b0), .s_credit_in_v0(1'b0), .e_credit_in_v0(1'b0), .w_credit_in_v0(1'b0),
          .n_credit_in_v1(1'b0), .s_credit_in_v1(1'b0), .e_credit_in_v1(1'b0), .w_credit_in_v1(1'b0)
        );
      end
    end
  endgenerate
endmodule
