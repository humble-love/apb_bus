// noc_config.vh — NOC configuration parameters (Verilog-2001)
`ifndef NOC_CONFIG_VH
`define NOC_CONFIG_VH

  // Mesh dimensions
  `define MESH_X 8
  `define MESH_Y 8
  `define NODE_NUM 64           // MESH_X * MESH_Y
  `define NODE_ID_W 6           // clog2(NODE_NUM)

  // Link parameters
  `define DATA_W 512
  `define CTRL_W 8

  // VC parameters
  `define VC_NUM 2
  `define VC_DEPTH 8
  `define VC_ID_W 1             // clog2(VC_NUM)

  // QoS parameters
  `define QOS_W 4
  `define PRIO_LEVELS 4
  `define AGING_THRESHOLD 64

  // Router pipeline
  `define PIPELINE_STAGES 5

  // NI parameters
  `define NI_FIFO_DEPTH 16
  `define MAX_OUTSTANDING 64

  // Port direction encoding
  `define PORT_DIR_W 3
  `define PORT_NORTH 3'b000
  `define PORT_SOUTH 3'b001
  `define PORT_EAST  3'b010
  `define PORT_WEST  3'b011
  `define PORT_LOCAL 3'b100
  `define PORT_NONE  3'b111

  // Coordinate widths
  `define COORD_X_W 3           // clog2(MESH_X)
  `define COORD_Y_W 3           // clog2(MESH_Y)
  `define COORD_W   6           // COORD_X_W + COORD_Y_W

  // Coord access macros: coord = {y[2:0], x[2:0]}
  `define COORD_X(c) c[2:0]
  `define COORD_Y(c) c[5:3]
  `define COORD_MAKE(x, y) {y[2:0], x[2:0]}

`endif
