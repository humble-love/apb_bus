// ni_axi4.sv — Complete AXI4 Network Interface
// Connects NPU core AXI4 interface to the NOC router local port
module ni_axi4 #(
  parameter int DATA_W          = 512,
  parameter int NI_FIFO_DEPTH   = 16
) (
  input  logic        clk,
  input  logic        rst_n,

  // === AXI4 Master Interface (faces NPU Core) ===
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
  output logic        bvalid,
  input  logic        bready,
  output logic [7:0]  bid,
  output logic [1:0]  bresp,
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
  output logic        rvalid,
  input  logic        rready,
  output logic [7:0]  rid,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,

  // Local node info
  input  noc_config_pkg::node_id_t   local_id,
  input  noc_config_pkg::coord_t     local_coord,

  // Destination lookup: addr → dst_id/coord (simplified: addr bit-slice)
  output logic        lookup_done,
  output noc_config_pkg::node_id_t   dst_id,
  output noc_config_pkg::coord_t     dst_coord,

  // Flit output to router local input (VC0 sender)
  output noc_flit_pkg::flit_t        vc0_flit_out,
  output logic        vc0_flit_valid,
  input  logic        vc0_flit_ready,

  // Flit input from router local output (VC1 receiver)
  input  noc_flit_pkg::flit_t        vc1_flit_in,
  input  logic        vc1_flit_valid,
  output logic        vc1_flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Address-to-node routing: addr[31:26] → node_id[5:0], addr[25:23]→x, addr[28:26]→y
  // Simple linear mapping for 8x8 mesh
  node_id_t aw_dst_id, ar_dst_id;
  coord_t   aw_dst_coord, ar_dst_coord;

  assign aw_dst_id      = {awaddr[28:26], awaddr[25:23]};
  assign aw_dst_coord.x = awaddr[25:23];
  assign aw_dst_coord.y = awaddr[28:26];
  assign ar_dst_id      = {araddr[28:26], araddr[25:23]};
  assign ar_dst_coord.x = araddr[25:23];
  assign ar_dst_coord.y = araddr[28:26];

  assign dst_id    = awvalid ? aw_dst_id    : ar_dst_id;
  assign dst_coord = awvalid ? aw_dst_coord : ar_dst_coord;
  assign lookup_done = awvalid || arvalid;

  // --- Write path ---
  noc_flit_pkg::flit_t wp_flit;
  logic wp_valid, wp_ready;

  ni_write_packer #(.DATA_W(DATA_W)) wp (
    .clk, .rst_n,
    .awvalid, .awready, .awaddr, .awid, .awlen, .awburst, .awsize,
    .awlock, .awcache, .awqos,
    .wvalid, .wready, .wdata, .wstrb, .wlast,
    .dst_coord(aw_dst_coord),
    .src_coord(local_coord),
    .dst_id(aw_dst_id),
    .flit_out(wp_flit), .flit_valid(wp_valid), .flit_ready(wp_ready)
  );

  // --- Read path ---
  noc_flit_pkg::flit_t rp_flit;
  logic rp_valid, rp_ready;

  ni_read_packer #(.DATA_W(DATA_W)) rp (
    .clk, .rst_n,
    .arvalid, .arready, .araddr, .arid, .arlen, .arburst, .arsize,
    .arlock, .arcache, .arqos,
    .dst_coord(ar_dst_coord),
    .src_coord(local_coord),
    .dst_id(ar_dst_id),
    .flit_out(rp_flit), .flit_valid(rp_valid), .flit_ready(rp_ready)
  );

  // --- VC1 header decode for demux ---
  logic vc1_hdr_is_read, vc1_hdr_is_resp;
  flit_header_t vc1_hdr;
  assign vc1_hdr = unpack_header(vc1_flit_in.payload);
  assign vc1_hdr_is_read = vc1_flit_valid && (vc1_flit_in.ftype == FLIT_HEADER)
                           && vc1_hdr.is_read;
  assign vc1_hdr_is_resp = vc1_flit_valid && (vc1_flit_in.ftype == FLIT_HEADER)
                           && vc1_hdr.is_response;

  // --- VC0 Sender: 4-source priority mux ---
  // Priority: B response > read response > write request > read request
  noc_flit_pkg::flit_t rs_flit, rr_flit;
  logic rs_valid, rs_ready, rr_valid, rr_ready;

  ni_response_sender #(.DATA_W(DATA_W)) rs (
    .clk, .rst_n,
    .vc1_flit_in,
    .vc1_flit_valid(vc1_flit_valid && (vc1_flit_in.ftype == FLIT_HEADER) && !vc1_hdr_is_read && !vc1_hdr_is_resp),
    .vc1_flit_ready(1'b1),
    .local_coord(local_coord),
    .resp_flit_out(rs_flit),
    .resp_flit_valid(rs_valid),
    .resp_flit_ready(rs_ready)
  );

  ni_read_responder #(.DATA_W(DATA_W)) rr (
    .clk, .rst_n,
    .vc1_flit_in,
    .vc1_flit_valid(vc1_flit_valid && (vc1_flit_in.ftype == FLIT_HEADER) && vc1_hdr_is_read && !vc1_hdr_is_resp),
    .vc1_flit_ready(1'b1),
    .local_coord(local_coord),
    .resp_flit_out(rr_flit),
    .resp_flit_valid(rr_valid),
    .resp_flit_ready(rr_ready)
  );

  assign vc0_flit_out   = rs_valid ? rs_flit : (rr_valid ? rr_flit : (wp_valid ? wp_flit : rp_flit));
  assign vc0_flit_valid = rs_valid || rr_valid || wp_valid || rp_valid;
  assign rs_ready       = vc0_flit_ready;
  assign rr_ready       = !rs_valid && vc0_flit_ready;
  assign wp_ready       = !rs_valid && !rr_valid && vc0_flit_ready;
  assign rp_ready       = !rs_valid && !rr_valid && !wp_valid && vc0_flit_ready;

  // --- VC1 Receiver: Demux to write/read unpackers ---
  // Write response headers: HEADER && !is_read
  // Read response: HEADER with is_read + all BODY/TAIL flits
  ni_write_unpacker #(.DATA_W(DATA_W)) wup (
    .clk, .rst_n,
    .flit_in(vc1_flit_in),
    .flit_valid(vc1_flit_valid && (vc1_flit_in.ftype == FLIT_HEADER) && !vc1_hdr_is_read && vc1_hdr_is_resp),
    .flit_ready(1'b1),
    .bvalid, .bready, .bid, .bresp
  );

  ni_read_unpacker #(.DATA_W(DATA_W)) rup (
    .clk, .rst_n,
    .flit_in(vc1_flit_in),
    .flit_valid(vc1_flit_valid && ((vc1_flit_in.ftype != FLIT_HEADER) || (vc1_hdr_is_read && vc1_hdr_is_resp))),
    .flit_ready(1'b1),
    .rvalid, .rready, .rid, .rdata, .rresp, .rlast
  );

  assign vc1_flit_ready = 1'b1;  // simplified

endmodule
