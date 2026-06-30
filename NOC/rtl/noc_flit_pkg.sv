// noc_flit_pkg.sv — Flit type definitions
package noc_flit_pkg;
  import noc_config_pkg::*;

  // Flit type encoding
  typedef enum logic [1:0] {
    FLIT_IDLE   = 2'b00,
    FLIT_HEADER = 2'b01,
    FLIT_BODY   = 2'b10,
    FLIT_TAIL   = 2'b11
  } flit_type_t;

  // Header flit fields (packed struct)
  typedef struct packed {
    logic [7:0]  src_y;
    logic [7:0]  src_x;
    logic [7:0]  dst_y;
    logic [7:0]  dst_x;
    qos_t        qos;
    flit_type_t  ftype;       // = FLIT_HEADER
    node_id_t    src_id;
    node_id_t    dst_id;
    logic [7:0]  axlen;
    logic [7:0]  axid;
    logic [31:0] axaddr;
    logic [1:0]  axburst;
    logic [3:0]  axsize;
    logic [3:0]  axlock;
    logic [1:0]  axcache;
    logic [249:0] reserved;
  } flit_header_t;

  // Data payload (body/tail flit)
  typedef struct packed {
    logic [63:0] wstrb;
    logic [445:0] data;
  } flit_data_t;

  // Unified flit structure
  typedef struct packed {
    flit_data_t  payload;
    flit_type_t  ftype;
  } flit_t;

  // Link signals (data + valid + credit return)
  typedef struct packed {
    flit_t flit;
    logic  valid;
    vc_id_t vc;
  } link_in_t;    // downstream-facing input

  typedef struct packed {
    flit_t flit;
    logic  valid;
    vc_id_t vc;
  } link_out_t;   // upstream-facing output

  // Credit return signal (per VC)
  typedef logic [VC_NUM-1:0] credit_t;

endpackage
