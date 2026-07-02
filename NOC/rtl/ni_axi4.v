// ni_axi4.v — Complete AXI4 Network Interface
// Connects NPU core AXI4 interface to the NOC router local port
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_axi4 #(
  parameter DATA_W        = 512,
  parameter NI_FIFO_DEPTH = 16
) (
  input  wire        clk,
  input  wire        rst_n,

  // === AXI4 Master Interface (faces NPU Core) ===
  input  wire        awvalid,
  output wire        awready,
  input  wire [31:0] awaddr,
  input  wire [7:0]  awid,
  input  wire [7:0]  awlen,
  input  wire [1:0]  awburst,
  input  wire [3:0]  awsize,
  input  wire [3:0]  awlock,
  input  wire [1:0]  awcache,
  input  wire [3:0]  awqos,
  input  wire        wvalid,
  output wire        wready,
  input  wire [DATA_W-1:0] wdata,
  input  wire [(DATA_W/8)-1:0] wstrb,
  input  wire        wlast,
  output wire        bvalid,
  input  wire        bready,
  output wire [7:0]  bid,
  output wire [1:0]  bresp,
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
  output wire        rvalid,
  input  wire        rready,
  output wire [7:0]  rid,
  output wire [DATA_W-1:0] rdata,
  output wire [1:0]  rresp,
  output wire        rlast,

  // Local node info
  input  wire [`NODE_ID_W-1:0] local_id,
  input  wire [`COORD_W-1:0]   local_coord,

  // Destination lookup: addr -> dst_id/coord (simplified: addr bit-slice)
  output wire        lookup_done,
  output wire [`NODE_ID_W-1:0] dst_id,
  output wire [`COORD_W-1:0]   dst_coord,

  // Flit output to router local input (VC0 sender)
  output wire [`FLIT_PAYLOAD_W-1:0] vc0_flit_out_payload,
  output wire [1:0]                 vc0_flit_out_ftype,
  output wire        vc0_flit_valid,
  input  wire        vc0_flit_ready,

  // Flit input from router local output (VC1 receiver)
  input  wire [`FLIT_PAYLOAD_W-1:0] vc1_flit_in_payload,
  input  wire [1:0]                 vc1_flit_in_ftype,
  input  wire        vc1_flit_valid,
  output wire        vc1_flit_ready
);

  // Address-to-node routing: addr[31:26] -> node_id[5:0], addr[25:23]->x, addr[28:26]->y
  // Simple linear mapping for 8x8 mesh
  wire [`NODE_ID_W-1:0] aw_dst_id, ar_dst_id;
  wire [`COORD_W-1:0]   aw_dst_coord, ar_dst_coord;

  assign aw_dst_id      = {awaddr[28:26], awaddr[25:23]};
  assign aw_dst_coord   = {awaddr[28:26], awaddr[25:23]};
  assign ar_dst_id      = {araddr[28:26], araddr[25:23]};
  assign ar_dst_coord   = {araddr[28:26], araddr[25:23]};

  assign dst_id    = awvalid ? aw_dst_id    : ar_dst_id;
  assign dst_coord = awvalid ? aw_dst_coord : ar_dst_coord;
  assign lookup_done = awvalid || arvalid;

  // --- Write path ---
  wire [`FLIT_PAYLOAD_W-1:0] wp_flit_payload;
  wire [1:0] wp_flit_ftype;
  wire wp_valid, wp_ready;

  ni_write_packer #(.DATA_W(DATA_W)) wp (
    .clk(clk), .rst_n(rst_n),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr), .awid(awid),
    .awlen(awlen), .awburst(awburst), .awsize(awsize),
    .awlock(awlock), .awcache(awcache), .awqos(awqos),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .dst_coord(aw_dst_coord),
    .src_coord(local_coord),
    .dst_id(aw_dst_id),
    .flit_out_payload(wp_flit_payload), .flit_out_ftype(wp_flit_ftype),
    .flit_valid(wp_valid), .flit_ready(wp_ready)
  );

  // --- Read path ---
  wire [`FLIT_PAYLOAD_W-1:0] rp_flit_payload;
  wire [1:0] rp_flit_ftype;
  wire rp_valid, rp_ready;

  ni_read_packer #(.DATA_W(DATA_W)) rp (
    .clk(clk), .rst_n(rst_n),
    .arvalid(arvalid), .arready(arready), .araddr(araddr), .arid(arid),
    .arlen(arlen), .arburst(arburst), .arsize(arsize),
    .arlock(arlock), .arcache(arcache), .arqos(arqos),
    .dst_coord(ar_dst_coord),
    .src_coord(local_coord),
    .dst_id(ar_dst_id),
    .flit_out_payload(rp_flit_payload), .flit_out_ftype(rp_flit_ftype),
    .flit_valid(rp_valid), .flit_ready(rp_ready)
  );

  // --- VC1 header decode for demux ---
  wire vc1_hdr_is_read, vc1_hdr_is_resp;
  assign vc1_hdr_is_read = vc1_flit_valid && (vc1_flit_in_ftype == `FLIT_HEADER)
                           && `FLIT_HDR_IS_READ(vc1_flit_in_payload);
  assign vc1_hdr_is_resp = vc1_flit_valid && (vc1_flit_in_ftype == `FLIT_HEADER)
                           && `FLIT_HDR_IS_RESPONSE(vc1_flit_in_payload);

  // --- VC0 Sender: 4-source priority mux ---
  // Priority: B response > read response > write request > read request
  wire [`FLIT_PAYLOAD_W-1:0] rs_flit_payload, rr_flit_payload;
  wire [1:0] rs_flit_ftype, rr_flit_ftype;
  wire rs_valid, rs_ready, rr_valid, rr_ready;

  ni_response_sender #(.DATA_W(DATA_W)) rs (
    .clk(clk), .rst_n(rst_n),
    .vc1_flit_in_payload(vc1_flit_in_payload),
    .vc1_flit_in_ftype(vc1_flit_in_ftype),
    .vc1_flit_valid(vc1_flit_valid && (vc1_flit_in_ftype == `FLIT_HEADER) && !vc1_hdr_is_read && !vc1_hdr_is_resp),
    .vc1_flit_ready(1'b1),
    .local_coord(local_coord),
    .resp_flit_out_payload(rs_flit_payload),
    .resp_flit_out_ftype(rs_flit_ftype),
    .resp_flit_valid(rs_valid),
    .resp_flit_ready(rs_ready)
  );

  ni_read_responder #(.DATA_W(DATA_W)) rr (
    .clk(clk), .rst_n(rst_n),
    .vc1_flit_in_payload(vc1_flit_in_payload),
    .vc1_flit_in_ftype(vc1_flit_in_ftype),
    .vc1_flit_valid(vc1_flit_valid && (vc1_flit_in_ftype == `FLIT_HEADER) && vc1_hdr_is_read && !vc1_hdr_is_resp),
    .vc1_flit_ready(1'b1),
    .local_coord(local_coord),
    .resp_flit_out_payload(rr_flit_payload),
    .resp_flit_out_ftype(rr_flit_ftype),
    .resp_flit_valid(rr_valid),
    .resp_flit_ready(rr_ready)
  );

  assign vc0_flit_out_payload = rs_valid ? rs_flit_payload : (rr_valid ? rr_flit_payload : (wp_valid ? wp_flit_payload : rp_flit_payload));
  assign vc0_flit_out_ftype   = rs_valid ? rs_flit_ftype   : (rr_valid ? rr_flit_ftype   : (wp_valid ? wp_flit_ftype   : rp_flit_ftype));
  assign vc0_flit_valid = rs_valid || rr_valid || wp_valid || rp_valid;
  assign rs_ready       = vc0_flit_ready;
  assign rr_ready       = !rs_valid && vc0_flit_ready;
  assign wp_ready       = !rs_valid && !rr_valid && vc0_flit_ready;
  assign rp_ready       = !rs_valid && !rr_valid && !wp_valid && vc0_flit_ready;

  // --- VC1 Receiver: Demux to write/read unpackers ---
  // Write response headers: HEADER && !is_read
  // Read response: HEADER with is_read + all BODY/TAIL flits
  ni_write_unpacker #(.DATA_W(DATA_W)) wup (
    .clk(clk), .rst_n(rst_n),
    .flit_in_payload(vc1_flit_in_payload),
    .flit_in_ftype(vc1_flit_in_ftype),
    .flit_valid(vc1_flit_valid && (vc1_flit_in_ftype == `FLIT_HEADER) && !vc1_hdr_is_read && vc1_hdr_is_resp),
    .flit_ready(),
    .bvalid(bvalid), .bready(bready), .bid(bid), .bresp(bresp)
  );

  ni_read_unpacker #(.DATA_W(DATA_W)) rup (
    .clk(clk), .rst_n(rst_n),
    .flit_in_payload(vc1_flit_in_payload),
    .flit_in_ftype(vc1_flit_in_ftype),
    .flit_valid(vc1_flit_valid && ((vc1_flit_in_ftype != `FLIT_HEADER) || (vc1_hdr_is_read && vc1_hdr_is_resp))),
    .flit_ready(),
    .rvalid(rvalid), .rready(rready), .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast)
  );

  assign vc1_flit_ready = 1'b1;  // simplified

endmodule
