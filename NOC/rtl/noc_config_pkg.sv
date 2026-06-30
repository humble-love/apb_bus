// noc_config_pkg.sv — Parameterized NOC configuration
package noc_config_pkg;

  // Mesh dimensions
  parameter int MESH_X = 8;
  parameter int MESH_Y = 8;
  localparam int NODE_NUM = MESH_X * MESH_Y;
  localparam int NODE_ID_W = $clog2(NODE_NUM);

  // Link parameters
  parameter int DATA_W = 512;
  parameter int CTRL_W = 8;

  // VC parameters
  parameter int VC_NUM = 2;
  parameter int VC_DEPTH = 8;
  localparam int VC_ID_W = $clog2(VC_NUM);

  // QoS parameters
  parameter int QOS_W = 4;
  parameter int PRIO_LEVELS = 4;
  parameter int AGING_THRESHOLD = 64;

  // Router pipeline
  parameter int PIPELINE_STAGES = 5;   // RC+VA+SA+ST+LT

  // NI parameters
  parameter int NI_FIFO_DEPTH = 16;
  parameter int MAX_OUTSTANDING = 64;

  // Port direction encoding
  typedef enum logic [2:0] {
    PORT_NORTH = 3'b000,
    PORT_SOUTH = 3'b001,
    PORT_EAST  = 3'b010,
    PORT_WEST  = 3'b011,
    PORT_LOCAL = 3'b100,
    PORT_NONE  = 3'b111
  } port_dir_t;

  // X/Y coordinates — widths derived from mesh dimensions
  localparam int COORD_X_W = $clog2(MESH_X);
  localparam int COORD_Y_W = $clog2(MESH_Y);

  typedef struct packed {
    logic [COORD_X_W-1:0] x;
    logic [COORD_Y_W-1:0] y;
  } coord_t;

  // Node ID = {Y[2:0], X[2:0]}
  typedef logic [NODE_ID_W-1:0] node_id_t;

  // VC ID
  typedef logic [VC_ID_W-1:0] vc_id_t;

  // QoS ID
  typedef logic [QOS_W-1:0] qos_t;

endpackage
