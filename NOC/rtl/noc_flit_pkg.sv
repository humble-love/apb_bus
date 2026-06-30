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

  // Coordinate width aliases (from noc_config_pkg)
  typedef logic [COORD_X_W-1:0] coord_x_t;
  typedef logic [COORD_Y_W-1:0] coord_y_t;

  // Header flit field map (MSB-justified into payload)
  // Total width = $bits(flit_header_t), which varies with mesh dimensions
  typedef struct packed {
    coord_y_t    dst_y;    // destination Y
    coord_x_t    dst_x;    // destination X
    coord_y_t    src_y;    // source Y
    coord_x_t    src_x;    // source X
    qos_t        qos;      // QoS priority [3:0]
    logic [7:0]  axlen;    // AXI burst length
    logic [7:0]  axid;     // AXI transaction ID
    logic [31:0] axaddr;   // AXI address
    logic [1:0]  axburst;  // AXI burst type
    logic [3:0]  axsize;   // AXI burst size
    logic [3:0]  axlock;   // AXI lock type
    logic [1:0]  axcache;  // AXI cache type
    logic [3:0]  axprot;   // AXI protection type
  } flit_header_t;

  localparam int FLIT_PAYLOAD_W = 510;
  localparam int HDR_W = $bits(flit_header_t);
  localparam int HDR_PAD_W = FLIT_PAYLOAD_W - HDR_W;  // padding to fill payload

  // Flit is a flat 512-bit packed struct
  //   HEADER: payload[509:510-HDR_W] = flit_header_t, lower bits = 0
  //   BODY/TAIL: payload = {data[445:0], wstrb[63:0]}
  typedef struct packed {
    logic [FLIT_PAYLOAD_W-1:0] payload;
    flit_type_t                ftype;
  } flit_t;

  // Helper: place header into payload (MSB-justified)
  function automatic logic [FLIT_PAYLOAD_W-1:0] pack_header(flit_header_t hdr);
    logic [FLIT_PAYLOAD_W-1:0] p;
    p = '0;
    p[FLIT_PAYLOAD_W-1 -: HDR_W] = hdr;
    return p;
  endfunction

  // Helper: extract header from payload
  function automatic flit_header_t unpack_header(logic [FLIT_PAYLOAD_W-1:0] p);
    return flit_header_t'(p[FLIT_PAYLOAD_W-1 -: HDR_W]);
  endfunction

  // Construct flits
  function automatic flit_t flit_make_header(flit_header_t hdr);
    flit_t f;
    f.payload = pack_header(hdr);
    f.ftype   = FLIT_HEADER;
    return f;
  endfunction

  function automatic flit_t flit_make_body(logic [63:0] wstrb, logic [445:0] data,
                                            flit_type_t ftype);
    flit_t f;
    f.payload = {data, wstrb};
    f.ftype   = ftype;
    return f;
  endfunction

  // Extract fields from body/tail flit
  function automatic logic [63:0]  flit_get_wstrb(flit_t f);
    return f.payload[63:0];
  endfunction

  function automatic logic [445:0] flit_get_data(flit_t f);
    return f.payload[509:64];
  endfunction

  // Extract node_id from header coordinates
  function automatic node_id_t get_src_id(flit_header_t hdr);
    return {hdr.src_y, hdr.src_x};
  endfunction

  function automatic node_id_t get_dst_id(flit_header_t hdr);
    return {hdr.dst_y, hdr.dst_x};
  endfunction

  function automatic void node_id_to_coord(
    node_id_t id, output coord_x_t x, output coord_y_t y
  );
    x = id[COORD_X_W-1:0];
    y = id >> COORD_X_W;
  endfunction

  // Link signal bundle (direction is a usage convention)
  typedef struct packed {
    flit_t flit;
    logic  valid;
    vc_id_t vc;
  } link_t;

  typedef link_t link_in_t;
  typedef link_t link_out_t;

  // Credit return signal (per VC)
  typedef logic [VC_NUM-1:0] credit_t;

endpackage
