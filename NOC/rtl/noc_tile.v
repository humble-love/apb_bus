// noc_tile.v — Single mesh tile: NI + Router
`include "noc_config.vh"
`include "noc_flit.vh"

module noc_tile #(
  parameter MESH_X          = 8,
  parameter MESH_Y          = 8,
  parameter VC_NUM          = 2,
  parameter VC_DEPTH        = 8,
  parameter DATA_W          = 512,
  parameter QOS_W           = 4,
  parameter PRIO_LEVELS     = 4,
  parameter NI_FIFO_DEPTH   = 16,
  parameter MAX_OUTSTANDING = 64
) (
  input  wire        clk,
  input  wire        rst_n,

  // Tile coordinate (set at synthesis time)
  input  wire [3:0]  tile_x,
  input  wire [3:0]  tile_y,

  // === AXI4 Master Interface (faces NPU Core) ===
  input  wire        awvalid, output wire awready,
  input  wire [31:0] awaddr,  input  wire [7:0] awid,
  input  wire [7:0]  awlen,   input  wire [1:0] awburst,
  input  wire [3:0]  awsize,  input  wire [3:0] awlock,
  input  wire [1:0]  awcache, input  wire [3:0] awqos,
  input  wire        wvalid,  output wire wready,
  input  wire [DATA_W-1:0] wdata,
  input  wire [(DATA_W/8)-1:0] wstrb,
  input  wire        wlast,
  output wire        bvalid,  input  wire bready,
  output wire [7:0]  bid,     output wire [1:0] bresp,
  input  wire        arvalid, output wire arready,
  input  wire [31:0] araddr,  input  wire [7:0] arid,
  input  wire [7:0]  arlen,   input  wire [1:0] arburst,
  input  wire [3:0]  arsize,  input  wire [3:0] arlock,
  input  wire [1:0]  arcache, input  wire [3:0] arqos,
  output wire        rvalid,  input  wire rready,
  output wire [7:0]  rid,
  output wire [DATA_W-1:0] rdata,
  output wire [1:0]  rresp,  output wire rlast,

  // === 4 mesh links: N, S, E, W — flat signals ===
  input  wire [`FLIT_PAYLOAD_W-1:0] n_in_flit_payload, s_in_flit_payload, e_in_flit_payload, w_in_flit_payload,
  input  wire [1:0] n_in_flit_ftype, s_in_flit_ftype, e_in_flit_ftype, w_in_flit_ftype,
  input  wire       n_in_valid, s_in_valid, e_in_valid, w_in_valid,
  input  wire       n_in_vc, s_in_vc, e_in_vc, w_in_vc,

  output wire       n_credit_v0, s_credit_v0, e_credit_v0, w_credit_v0,
  output wire       n_credit_v1, s_credit_v1, e_credit_v1, w_credit_v1,

  output wire [`FLIT_PAYLOAD_W-1:0] n_out_flit_payload, s_out_flit_payload, e_out_flit_payload, w_out_flit_payload,
  output wire [1:0] n_out_flit_ftype, s_out_flit_ftype, e_out_flit_ftype, w_out_flit_ftype,
  output wire       n_out_valid, s_out_valid, e_out_valid, w_out_valid,
  output wire       n_out_vc, s_out_vc, e_out_vc, w_out_vc,

  input  wire       n_credit_in_v0, s_credit_in_v0, e_credit_in_v0, w_credit_in_v0,
  input  wire       n_credit_in_v1, s_credit_in_v1, e_credit_in_v1, w_credit_in_v1
);

  // Local coordinates and ID
  wire [`COORD_W-1:0]   local_coord;
  wire [`NODE_ID_W-1:0] local_id;
  assign local_coord = `COORD_MAKE(tile_x, tile_y);
  assign local_id = {tile_y[`COORD_Y_W-1:0], tile_x[`COORD_X_W-1:0]};

  // --- Router ports (5: N,S,E,W,L) — flat signal arrays ---
  wire [`FLIT_PAYLOAD_W-1:0] router_in_payload  [0:4];
  wire [1:0]                 router_in_ftype    [0:4];
  wire   router_in_valid [0:4];
  wire   router_in_vc    [0:4];
  wire   router_credit_out_v0 [0:4], router_credit_out_v1 [0:4];

  wire [`FLIT_PAYLOAD_W-1:0] router_out_payload  [0:4];
  wire [1:0]                 router_out_ftype    [0:4];
  wire   router_out_valid [0:4];
  wire   router_out_vc    [0:4];
  wire   router_credit_in_v0 [0:4], router_credit_in_v1 [0:4];

  // Map N/S/E/W tile input pins to router input port arrays
  assign router_in_payload [`PORT_NORTH] = n_in_flit_payload;
  assign router_in_ftype   [`PORT_NORTH] = n_in_flit_ftype;
  assign router_in_payload [`PORT_SOUTH] = s_in_flit_payload;
  assign router_in_ftype   [`PORT_SOUTH] = s_in_flit_ftype;
  assign router_in_payload [`PORT_EAST]  = e_in_flit_payload;
  assign router_in_ftype   [`PORT_EAST]  = e_in_flit_ftype;
  assign router_in_payload [`PORT_WEST]  = w_in_flit_payload;
  assign router_in_ftype   [`PORT_WEST]  = w_in_flit_ftype;
  assign router_in_valid[`PORT_NORTH] = n_in_valid;
  assign router_in_valid[`PORT_SOUTH] = s_in_valid;
  assign router_in_valid[`PORT_EAST]  = e_in_valid;
  assign router_in_valid[`PORT_WEST]  = w_in_valid;
  assign router_in_vc   [`PORT_NORTH] = n_in_vc;
  assign router_in_vc   [`PORT_SOUTH] = s_in_vc;
  assign router_in_vc   [`PORT_EAST]  = e_in_vc;
  assign router_in_vc   [`PORT_WEST]  = w_in_vc;

  // Tile credit output pins = router credit outputs (to upstream)
  assign n_credit_v0 = router_credit_out_v0[`PORT_NORTH];
  assign s_credit_v0 = router_credit_out_v0[`PORT_SOUTH];
  assign e_credit_v0 = router_credit_out_v0[`PORT_EAST];
  assign w_credit_v0 = router_credit_out_v0[`PORT_WEST];
  assign n_credit_v1 = router_credit_out_v1[`PORT_NORTH];
  assign s_credit_v1 = router_credit_out_v1[`PORT_SOUTH];
  assign e_credit_v1 = router_credit_out_v1[`PORT_EAST];
  assign w_credit_v1 = router_credit_out_v1[`PORT_WEST];
  // Tile credit input pins -> router credit inputs (from downstream)
  assign router_credit_in_v0[`PORT_NORTH] = n_credit_in_v0;
  assign router_credit_in_v0[`PORT_SOUTH] = s_credit_in_v0;
  assign router_credit_in_v0[`PORT_EAST]  = e_credit_in_v0;
  assign router_credit_in_v0[`PORT_WEST]  = w_credit_in_v0;
  assign router_credit_in_v1[`PORT_NORTH] = n_credit_in_v1;
  assign router_credit_in_v1[`PORT_SOUTH] = s_credit_in_v1;
  assign router_credit_in_v1[`PORT_EAST]  = e_credit_in_v1;
  assign router_credit_in_v1[`PORT_WEST]  = w_credit_in_v1;

  // Router output port arrays drive tile output pins
  assign n_out_flit_payload = router_out_payload [`PORT_NORTH];
  assign n_out_flit_ftype   = router_out_ftype   [`PORT_NORTH];
  assign s_out_flit_payload = router_out_payload [`PORT_SOUTH];
  assign s_out_flit_ftype   = router_out_ftype   [`PORT_SOUTH];
  assign e_out_flit_payload = router_out_payload [`PORT_EAST];
  assign e_out_flit_ftype   = router_out_ftype   [`PORT_EAST];
  assign w_out_flit_payload = router_out_payload [`PORT_WEST];
  assign w_out_flit_ftype   = router_out_ftype   [`PORT_WEST];
  assign n_out_valid = router_out_valid[`PORT_NORTH];
  assign s_out_valid = router_out_valid[`PORT_SOUTH];
  assign e_out_valid = router_out_valid[`PORT_EAST];
  assign w_out_valid = router_out_valid[`PORT_WEST];
  assign n_out_vc    = router_out_vc   [`PORT_NORTH];
  assign s_out_vc    = router_out_vc   [`PORT_SOUTH];
  assign e_out_vc    = router_out_vc   [`PORT_EAST];
  assign w_out_vc    = router_out_vc   [`PORT_WEST];

  // --- NI <-> Router local port (index 4) ---
  // NI VC0 -> Router local input
  // Router local output -> NI VC1

  // Credit counter for NI->Router VC0 (mirrors output_port credit tracking)
  reg [3:0] ni_vc0_credits;     // $clog2(VC_DEPTH) = 3, so [3:0]
  wire ni_vc0_ready;
  wire ni_vc0_dec, ni_vc0_inc;
  assign ni_vc0_dec = router_in_valid[`PORT_LOCAL] && ni_vc0_ready && (ni_vc0_credits > 0);
  assign ni_vc0_inc = router_credit_out_v0[`PORT_LOCAL];
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ni_vc0_credits <= VC_DEPTH;
    end else begin
      if (ni_vc0_dec && !ni_vc0_inc)
        ni_vc0_credits <= ni_vc0_credits - 1'b1;
      else if (!ni_vc0_dec && ni_vc0_inc)
        ni_vc0_credits <= ni_vc0_credits + 1'b1;
    end
  end
  assign ni_vc0_ready = (ni_vc0_credits > 0);

  // VC1 credit pulse for LOCAL output port (NI->Router VC1)
  // NI vc1_flit_ready is a level (simplified: always 1).
  // Credit must be a pulse, not a level, for output_port counter.
  // Pulse on rising edge of valid (one-shot per flit consumed by NI).
  wire vc1_ni_ready;
  reg vc1_consumed_d;  // registered to detect edge
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vc1_consumed_d <= 1'b0;
    else vc1_consumed_d <= router_out_valid[`PORT_LOCAL] && vc1_ni_ready;
  end
  // 1-cycle pulse when NI receives a new flit
  wire vc1_credit_pulse = router_out_valid[`PORT_LOCAL] && vc1_ni_ready && !vc1_consumed_d;

  ni_axi4 #(.DATA_W(DATA_W), .NI_FIFO_DEPTH(NI_FIFO_DEPTH)) ni (
    .clk(clk),
    .rst_n(rst_n),
    .awvalid(awvalid), .awready(awready), .awaddr(awaddr), .awid(awid),
    .awlen(awlen), .awburst(awburst), .awsize(awsize),
    .awlock(awlock), .awcache(awcache), .awqos(awqos),
    .wvalid(wvalid), .wready(wready), .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
    .bvalid(bvalid), .bready(bready), .bid(bid), .bresp(bresp),
    .arvalid(arvalid), .arready(arready), .araddr(araddr), .arid(arid),
    .arlen(arlen), .arburst(arburst), .arsize(arsize),
    .arlock(arlock), .arcache(arcache), .arqos(arqos),
    .rvalid(rvalid), .rready(rready), .rid(rid), .rdata(rdata),
    .rresp(rresp), .rlast(rlast),
    .local_id(local_id),
    .local_coord(local_coord),
    .lookup_done(),
    .dst_id(),
    .dst_coord(),
    .vc0_flit_out_payload(router_in_payload[`PORT_LOCAL]),
    .vc0_flit_out_ftype(router_in_ftype[`PORT_LOCAL]),
    .vc0_flit_valid(router_in_valid[`PORT_LOCAL]),
    .vc0_flit_ready(ni_vc0_ready),
    .vc1_flit_in_payload(router_out_payload[`PORT_LOCAL]),
    .vc1_flit_in_ftype(router_out_ftype[`PORT_LOCAL]),
    .vc1_flit_valid(router_out_valid[`PORT_LOCAL]),
    .vc1_flit_ready(vc1_ni_ready)
  );

  assign router_in_vc[`PORT_LOCAL] = 1'b0;  // NI always sends on VC0
  assign router_credit_in_v0[`PORT_LOCAL] = 1'b0;       // NI receives only on VC1, not VC0
  assign router_credit_in_v1[`PORT_LOCAL] = vc1_credit_pulse;  // pulse: NI consumed a flit

  // Router
  router_5port #(
    .MESH_X(MESH_X), .MESH_Y(MESH_Y),
    .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
    .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS)
  ) router (
    .clk(clk),
    .rst_n(rst_n),
    .link_in_flit_payload(router_in_payload),
    .link_in_flit_ftype(router_in_ftype),
    .link_in_valid(router_in_valid),
    .link_in_vc(router_in_vc),
    .credit_out_v0(router_credit_out_v0),
    .credit_out_v1(router_credit_out_v1),
    .link_out_flit_payload(router_out_payload),
    .link_out_flit_ftype(router_out_ftype),
    .link_out_valid(router_out_valid),
    .link_out_vc(router_out_vc),
    .credit_in_v0(router_credit_in_v0),
    .credit_in_v1(router_credit_in_v1),
    .local_coord(local_coord)
  );
endmodule
