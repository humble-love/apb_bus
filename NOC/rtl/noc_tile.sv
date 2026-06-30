// noc_tile.sv — Single mesh tile: NI + Router
module noc_tile #(
  parameter int MESH_X          = 8,
  parameter int MESH_Y          = 8,
  parameter int VC_NUM          = 2,
  parameter int VC_DEPTH        = 8,
  parameter int DATA_W          = 512,
  parameter int QOS_W           = 4,
  parameter int PRIO_LEVELS     = 4,
  parameter int NI_FIFO_DEPTH   = 16,
  parameter int MAX_OUTSTANDING = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // Tile coordinate (set at synthesis time)
  input  logic [3:0]  tile_x,
  input  logic [3:0]  tile_y,

  // === AXI4 Master Interface (faces NPU Core) ===
  input  logic        awvalid, output logic awready,
  input  logic [31:0] awaddr,  input  logic [7:0] awid,
  input  logic [7:0]  awlen,   input  logic [1:0] awburst,
  input  logic [3:0]  awsize,  input  logic [3:0] awlock,
  input  logic [1:0]  awcache, input  logic [3:0] awqos,
  input  logic        wvalid,  output logic wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [(DATA_W/8)-1:0] wstrb,
  input  logic        wlast,
  output logic        bvalid,  input  logic bready,
  output logic [7:0]  bid,     output logic [1:0] bresp,
  input  logic        arvalid, output logic arready,
  input  logic [31:0] araddr,  input  logic [7:0] arid,
  input  logic [7:0]  arlen,   input  logic [1:0] arburst,
  input  logic [3:0]  arsize,  input  logic [3:0] arlock,
  input  logic [1:0]  arcache, input  logic [3:0] arqos,
  output logic        rvalid,  input  logic rready,
  output logic [7:0]  rid,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]  rresp,  output logic rlast,

  // === 4 mesh links: N, S, E, W — flat signals ===
  input  noc_flit_pkg::flit_t     n_in_flit, s_in_flit, e_in_flit, w_in_flit,
  input  logic     n_in_valid, s_in_valid, e_in_valid, w_in_valid,
  input  noc_config_pkg::vc_id_t  n_in_vc, s_in_vc, e_in_vc, w_in_vc,

  output logic     n_credit_v0, s_credit_v0, e_credit_v0, w_credit_v0,
  output logic     n_credit_v1, s_credit_v1, e_credit_v1, w_credit_v1,

  output noc_flit_pkg::flit_t     n_out_flit, s_out_flit, e_out_flit, w_out_flit,
  output logic     n_out_valid, s_out_valid, e_out_valid, w_out_valid,
  output noc_config_pkg::vc_id_t  n_out_vc, s_out_vc, e_out_vc, w_out_vc,

  input  logic     n_credit_in_v0, s_credit_in_v0, e_credit_in_v0, w_credit_in_v0,
  input  logic     n_credit_in_v1, s_credit_in_v1, e_credit_in_v1, w_credit_in_v1
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Local coordinates and ID
  coord_t local_coord;
  node_id_t local_id;
  assign local_coord.x = tile_x[COORD_X_W-1:0];
  assign local_coord.y = tile_y[COORD_Y_W-1:0];
  assign local_id = {tile_y[COORD_Y_W-1:0], tile_x[COORD_X_W-1:0]};

  // --- Router ports (5: N,S,E,W,L) — flat signal arrays ---
  flit_t  router_in_flit  [5];
  logic   router_in_valid [5];
  vc_id_t router_in_vc    [5];
  logic   router_credit_out_v0 [5], router_credit_out_v1 [5];

  flit_t  router_out_flit  [5];
  logic   router_out_valid [5];
  vc_id_t router_out_vc    [5];
  logic   router_credit_in_v0 [5], router_credit_in_v1 [5];

  // Map N/S/E/W tile input pins to router input port arrays
  assign router_in_flit [PORT_NORTH] = n_in_flit;
  assign router_in_flit [PORT_SOUTH] = s_in_flit;
  assign router_in_flit [PORT_EAST]  = e_in_flit;
  assign router_in_flit [PORT_WEST]  = w_in_flit;
  assign router_in_valid[PORT_NORTH] = n_in_valid;
  assign router_in_valid[PORT_SOUTH] = s_in_valid;
  assign router_in_valid[PORT_EAST]  = e_in_valid;
  assign router_in_valid[PORT_WEST]  = w_in_valid;
  assign router_in_vc   [PORT_NORTH] = n_in_vc;
  assign router_in_vc   [PORT_SOUTH] = s_in_vc;
  assign router_in_vc   [PORT_EAST]  = e_in_vc;
  assign router_in_vc   [PORT_WEST]  = w_in_vc;

  // Tile credit output pins = router credit outputs (to upstream)
  assign n_credit_v0 = router_credit_out_v0[PORT_NORTH];
  assign s_credit_v0 = router_credit_out_v0[PORT_SOUTH];
  assign e_credit_v0 = router_credit_out_v0[PORT_EAST];
  assign w_credit_v0 = router_credit_out_v0[PORT_WEST];
  assign n_credit_v1 = router_credit_out_v1[PORT_NORTH];
  assign s_credit_v1 = router_credit_out_v1[PORT_SOUTH];
  assign e_credit_v1 = router_credit_out_v1[PORT_EAST];
  assign w_credit_v1 = router_credit_out_v1[PORT_WEST];
  // Tile credit input pins → router credit inputs (from downstream)
  assign router_credit_in_v0[PORT_NORTH] = n_credit_in_v0;
  assign router_credit_in_v0[PORT_SOUTH] = s_credit_in_v0;
  assign router_credit_in_v0[PORT_EAST]  = e_credit_in_v0;
  assign router_credit_in_v0[PORT_WEST]  = w_credit_in_v0;
  assign router_credit_in_v1[PORT_NORTH] = n_credit_in_v1;
  assign router_credit_in_v1[PORT_SOUTH] = s_credit_in_v1;
  assign router_credit_in_v1[PORT_EAST]  = e_credit_in_v1;
  assign router_credit_in_v1[PORT_WEST]  = w_credit_in_v1;

  // Router output port arrays drive tile output pins
  assign n_out_flit  = router_out_flit [PORT_NORTH];
  assign s_out_flit  = router_out_flit [PORT_SOUTH];
  assign e_out_flit  = router_out_flit [PORT_EAST];
  assign w_out_flit  = router_out_flit [PORT_WEST];
  assign n_out_valid = router_out_valid[PORT_NORTH];
  assign s_out_valid = router_out_valid[PORT_SOUTH];
  assign e_out_valid = router_out_valid[PORT_EAST];
  assign w_out_valid = router_out_valid[PORT_WEST];
  assign n_out_vc    = router_out_vc   [PORT_NORTH];
  assign s_out_vc    = router_out_vc   [PORT_SOUTH];
  assign e_out_vc    = router_out_vc   [PORT_EAST];
  assign w_out_vc    = router_out_vc   [PORT_WEST];

  // --- NI ↔ Router local port (index 4) ---
  // NI VC0 → Router local input
  // Router local output → NI VC1

  ni_axi4 #(.DATA_W(DATA_W), .NI_FIFO_DEPTH(NI_FIFO_DEPTH)) ni (
    .clk, .rst_n,
    .awvalid, .awready, .awaddr, .awid, .awlen, .awburst, .awsize,
    .awlock, .awcache, .awqos,
    .wvalid, .wready, .wdata, .wstrb, .wlast,
    .bvalid, .bready, .bid, .bresp,
    .arvalid, .arready, .araddr, .arid, .arlen, .arburst, .arsize,
    .arlock, .arcache, .arqos,
    .rvalid, .rready, .rid, .rdata, .rresp, .rlast,
    .local_id, .local_coord,
    .lookup_done(),
    .dst_id(),
    .dst_coord(),
    .vc0_flit_out(router_in_flit[PORT_LOCAL]),
    .vc0_flit_valid(router_in_valid[PORT_LOCAL]),
    .vc0_flit_ready(),  // credit from router
    .vc1_flit_in(router_out_flit[PORT_LOCAL]),
    .vc1_flit_valid(router_out_valid[PORT_LOCAL]),
    .vc1_flit_ready()   // credit to router
  );

  assign router_in_vc[PORT_LOCAL] = '{default: '0};  // default VC0 for local
  assign router_credit_in_v0[PORT_LOCAL] = 1'b1;      // backpressure from NI later
  assign router_credit_in_v1[PORT_LOCAL] = 1'b1;

  // Router
  router_5port #(
    .MESH_X(MESH_X), .MESH_Y(MESH_Y),
    .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
    .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS)
  ) router (
    .clk, .rst_n,
    .link_in_flit(router_in_flit),
    .link_in_valid(router_in_valid),
    .link_in_vc(router_in_vc),
    .credit_out_v0(router_credit_out_v0),
    .credit_out_v1(router_credit_out_v1),
    .link_out_flit(router_out_flit),
    .link_out_valid(router_out_valid),
    .link_out_vc(router_out_vc),
    .credit_in_v0(router_credit_in_v0),
    .credit_in_v1(router_credit_in_v1),
    .local_coord(local_coord)
  );
endmodule
