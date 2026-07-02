// mesh_8x8.v — 8x8 mesh top-level with 64 noc_tile instances
// Full NSEW bidirectional mesh wiring between adjacent tiles.
`include "noc_config.vh"
`include "noc_flit.vh"

module mesh_8x8 #(
  parameter MESH_X         = 8,
  parameter MESH_Y         = 8,
  parameter VC_NUM         = 2,
  parameter VC_DEPTH       = 8,
  parameter DATA_W         = 512,
  parameter QOS_W          = 4,
  parameter PRIO_LEVELS    = 4,
  parameter NI_FIFO_DEPTH  = 16,
  parameter MAX_OUTSTANDING = 64
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [MESH_Y-1:0][MESH_X-1:0]        awvalid,
  output wire [MESH_Y-1:0][MESH_X-1:0]        awready,
  input  wire [MESH_Y-1:0][MESH_X-1:0][31:0]  awaddr,
  input  wire [MESH_Y-1:0][MESH_X-1:0][7:0]   awid,
  input  wire [MESH_Y-1:0][MESH_X-1:0][7:0]   awlen,
  input  wire [MESH_Y-1:0][MESH_X-1:0][1:0]   awburst,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   awsize,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   awlock,
  input  wire [MESH_Y-1:0][MESH_X-1:0][1:0]   awcache,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   awqos,

  input  wire [MESH_Y-1:0][MESH_X-1:0]        wvalid,
  output wire [MESH_Y-1:0][MESH_X-1:0]        wready,
  input  wire [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] wdata,
  input  wire [MESH_Y-1:0][MESH_X-1:0][(DATA_W/8)-1:0] wstrb,
  input  wire [MESH_Y-1:0][MESH_X-1:0]        wlast,

  output wire [MESH_Y-1:0][MESH_X-1:0]        bvalid,
  input  wire [MESH_Y-1:0][MESH_X-1:0]        bready,
  output wire [MESH_Y-1:0][MESH_X-1:0][7:0]   bid,
  output wire [MESH_Y-1:0][MESH_X-1:0][1:0]   bresp,

  input  wire [MESH_Y-1:0][MESH_X-1:0]        arvalid,
  output wire [MESH_Y-1:0][MESH_X-1:0]        arready,
  input  wire [MESH_Y-1:0][MESH_X-1:0][31:0]  araddr,
  input  wire [MESH_Y-1:0][MESH_X-1:0][7:0]   arid,
  input  wire [MESH_Y-1:0][MESH_X-1:0][7:0]   arlen,
  input  wire [MESH_Y-1:0][MESH_X-1:0][1:0]   arburst,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   arsize,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   arlock,
  input  wire [MESH_Y-1:0][MESH_X-1:0][1:0]   arcache,
  input  wire [MESH_Y-1:0][MESH_X-1:0][3:0]   arqos,

  output wire [MESH_Y-1:0][MESH_X-1:0]        rvalid,
  input  wire [MESH_Y-1:0][MESH_X-1:0]        rready,
  output wire [MESH_Y-1:0][MESH_X-1:0][7:0]   rid,
  output wire [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] rdata,
  output wire [MESH_Y-1:0][MESH_X-1:0][1:0]   rresp,
  output wire [MESH_Y-1:0][MESH_X-1:0]        rlast
);

  // ============================================================
  // Output wires: tile drives these -> received by neighbor input
  // Input wires:  neighbor drives these -> received by tile input
  // Separate arrays avoid multiple-driver conflicts.
  // ============================================================

  // Flit payload + ftype split for all directions (out)
  wire [`FLIT_PAYLOAD_W-1:0] n_out_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 n_out_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       n_out_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       n_out_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] s_out_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 s_out_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       s_out_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       s_out_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] e_out_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 e_out_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       e_out_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       e_out_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] w_out_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 w_out_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       w_out_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       w_out_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  // Credit signals (out)
  wire n_cr_out_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire n_cr_out_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire s_cr_out_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire s_cr_out_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire e_cr_out_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire e_cr_out_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire w_cr_out_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire w_cr_out_v1 [0:`MESH_Y-1][0:`MESH_X-1];

  // Flit payload + ftype split for all directions (in)
  wire [`FLIT_PAYLOAD_W-1:0] n_in_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 n_in_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       n_in_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       n_in_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] s_in_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 s_in_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       s_in_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       s_in_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] e_in_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 e_in_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       e_in_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       e_in_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  wire [`FLIT_PAYLOAD_W-1:0] w_in_dat_payload [0:`MESH_Y-1][0:`MESH_X-1];
  wire [1:0]                 w_in_dat_ftype   [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       w_in_vld         [0:`MESH_Y-1][0:`MESH_X-1];
  wire                       w_in_vc          [0:`MESH_Y-1][0:`MESH_X-1];

  // Credit signals (in)
  wire n_cr_in_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire n_cr_in_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire s_cr_in_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire s_cr_in_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire e_cr_in_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire e_cr_in_v1 [0:`MESH_Y-1][0:`MESH_X-1];
  wire w_cr_in_v0 [0:`MESH_Y-1][0:`MESH_X-1];
  wire w_cr_in_v1 [0:`MESH_Y-1][0:`MESH_X-1];

  genvar x, y;

  // ============================================================
  // Tile instantiation — outputs drive output wires, inputs from input wires
  // ============================================================
  generate
    for (y = 0; y < MESH_Y; y = y + 1) begin : row
      for (x = 0; x < MESH_X; x = x + 1) begin : col
        noc_tile #(
          .MESH_X(MESH_X), .MESH_Y(MESH_Y),
          .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
          .DATA_W(DATA_W), .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS),
          .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
        ) tile (
          .clk(clk),
          .rst_n(rst_n),
          .tile_x(x[3:0]),
          .tile_y(y[3:0]),

          // AXI4
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

          // Mesh links — outputs -> output wires
          .n_out_flit_payload(n_out_dat_payload[y][x]),
          .n_out_flit_ftype(n_out_dat_ftype[y][x]),
          .n_out_valid(n_out_vld[y][x]),
          .n_out_vc(n_out_vc[y][x]),
          .s_out_flit_payload(s_out_dat_payload[y][x]),
          .s_out_flit_ftype(s_out_dat_ftype[y][x]),
          .s_out_valid(s_out_vld[y][x]),
          .s_out_vc(s_out_vc[y][x]),
          .e_out_flit_payload(e_out_dat_payload[y][x]),
          .e_out_flit_ftype(e_out_dat_ftype[y][x]),
          .e_out_valid(e_out_vld[y][x]),
          .e_out_vc(e_out_vc[y][x]),
          .w_out_flit_payload(w_out_dat_payload[y][x]),
          .w_out_flit_ftype(w_out_dat_ftype[y][x]),
          .w_out_valid(w_out_vld[y][x]),
          .w_out_vc(w_out_vc[y][x]),
          .n_credit_v0(n_cr_out_v0[y][x]),
          .n_credit_v1(n_cr_out_v1[y][x]),
          .s_credit_v0(s_cr_out_v0[y][x]),
          .s_credit_v1(s_cr_out_v1[y][x]),
          .e_credit_v0(e_cr_out_v0[y][x]),
          .e_credit_v1(e_cr_out_v1[y][x]),
          .w_credit_v0(w_cr_out_v0[y][x]),
          .w_credit_v1(w_cr_out_v1[y][x]),

          // Mesh links — input wires -> inputs
          .n_in_flit_payload(n_in_dat_payload[y][x]),
          .n_in_flit_ftype(n_in_dat_ftype[y][x]),
          .n_in_valid(n_in_vld[y][x]),
          .n_in_vc(n_in_vc[y][x]),
          .s_in_flit_payload(s_in_dat_payload[y][x]),
          .s_in_flit_ftype(s_in_dat_ftype[y][x]),
          .s_in_valid(s_in_vld[y][x]),
          .s_in_vc(s_in_vc[y][x]),
          .e_in_flit_payload(e_in_dat_payload[y][x]),
          .e_in_flit_ftype(e_in_dat_ftype[y][x]),
          .e_in_valid(e_in_vld[y][x]),
          .e_in_vc(e_in_vc[y][x]),
          .w_in_flit_payload(w_in_dat_payload[y][x]),
          .w_in_flit_ftype(w_in_dat_ftype[y][x]),
          .w_in_valid(w_in_vld[y][x]),
          .w_in_vc(w_in_vc[y][x]),
          .n_credit_in_v0(n_cr_in_v0[y][x]),
          .n_credit_in_v1(n_cr_in_v1[y][x]),
          .s_credit_in_v0(s_cr_in_v0[y][x]),
          .s_credit_in_v1(s_cr_in_v1[y][x]),
          .e_credit_in_v0(e_cr_in_v0[y][x]),
          .e_credit_in_v1(e_cr_in_v1[y][x]),
          .w_credit_in_v0(w_cr_in_v0[y][x]),
          .w_credit_in_v1(w_cr_in_v1[y][x])
        );
      end
    end
  endgenerate

  // ============================================================
  // Inter-tile mesh wiring
  // Connect tile output wires -> neighboring tile input wires
  // Only valid connections are generated: no out-of-bounds indices
  // ============================================================
  generate
    for (y = 0; y < MESH_Y; y = y + 1) begin : w_y
      for (x = 0; x < MESH_X; x = x + 1) begin : w_x

        // ---- North input (y>0): from neighbor to the north ----
        if (y > 0) begin : n_in_conn
          assign n_in_dat_payload[y][x] = s_out_dat_payload[y-1][x];
          assign n_in_dat_ftype[y][x]   = s_out_dat_ftype[y-1][x];
          assign n_in_vld[y][x]         = s_out_vld[y-1][x];
          assign n_in_vc[y][x]          = s_out_vc[y-1][x];
          assign n_cr_in_v0[y][x]       = s_cr_out_v0[y-1][x];
          assign n_cr_in_v1[y][x]       = s_cr_out_v1[y-1][x];
        end else begin : n_in_zero
          assign n_in_dat_payload[y][x] = {`FLIT_PAYLOAD_W{1'b0}};
          assign n_in_dat_ftype[y][x]   = 2'b00;
          assign n_in_vld[y][x]         = 1'b0;
          assign n_in_vc[y][x]          = 1'b0;
          assign n_cr_in_v0[y][x]       = 1'b0;
          assign n_cr_in_v1[y][x]       = 1'b0;
        end

        // ---- South input (y<MESH_Y-1): from neighbor to the south ----
        if (y < MESH_Y-1) begin : s_in_conn
          assign s_in_dat_payload[y][x] = n_out_dat_payload[y+1][x];
          assign s_in_dat_ftype[y][x]   = n_out_dat_ftype[y+1][x];
          assign s_in_vld[y][x]         = n_out_vld[y+1][x];
          assign s_in_vc[y][x]          = n_out_vc[y+1][x];
          assign s_cr_in_v0[y][x]       = n_cr_out_v0[y+1][x];
          assign s_cr_in_v1[y][x]       = n_cr_out_v1[y+1][x];
        end else begin : s_in_zero
          assign s_in_dat_payload[y][x] = {`FLIT_PAYLOAD_W{1'b0}};
          assign s_in_dat_ftype[y][x]   = 2'b00;
          assign s_in_vld[y][x]         = 1'b0;
          assign s_in_vc[y][x]          = 1'b0;
          assign s_cr_in_v0[y][x]       = 1'b0;
          assign s_cr_in_v1[y][x]       = 1'b0;
        end

        // ---- East input (x<MESH_X-1): from neighbor to the east ----
        if (x < MESH_X-1) begin : e_in_conn
          assign e_in_dat_payload[y][x] = w_out_dat_payload[y][x+1];
          assign e_in_dat_ftype[y][x]   = w_out_dat_ftype[y][x+1];
          assign e_in_vld[y][x]         = w_out_vld[y][x+1];
          assign e_in_vc[y][x]          = w_out_vc[y][x+1];
          assign e_cr_in_v0[y][x]       = w_cr_out_v0[y][x+1];
          assign e_cr_in_v1[y][x]       = w_cr_out_v1[y][x+1];
        end else begin : e_in_zero
          assign e_in_dat_payload[y][x] = {`FLIT_PAYLOAD_W{1'b0}};
          assign e_in_dat_ftype[y][x]   = 2'b00;
          assign e_in_vld[y][x]         = 1'b0;
          assign e_in_vc[y][x]          = 1'b0;
          assign e_cr_in_v0[y][x]       = 1'b0;
          assign e_cr_in_v1[y][x]       = 1'b0;
        end

        // ---- West input (x>0): from neighbor to the west ----
        if (x > 0) begin : w_in_conn
          assign w_in_dat_payload[y][x] = e_out_dat_payload[y][x-1];
          assign w_in_dat_ftype[y][x]   = e_out_dat_ftype[y][x-1];
          assign w_in_vld[y][x]         = e_out_vld[y][x-1];
          assign w_in_vc[y][x]          = e_out_vc[y][x-1];
          assign w_cr_in_v0[y][x]       = e_cr_out_v0[y][x-1];
          assign w_cr_in_v1[y][x]       = e_cr_out_v1[y][x-1];
        end else begin : w_in_zero
          assign w_in_dat_payload[y][x] = {`FLIT_PAYLOAD_W{1'b0}};
          assign w_in_dat_ftype[y][x]   = 2'b00;
          assign w_in_vld[y][x]         = 1'b0;
          assign w_in_vc[y][x]          = 1'b0;
          assign w_cr_in_v0[y][x]       = 1'b0;
          assign w_cr_in_v1[y][x]       = 1'b0;
        end
      end
    end
  endgenerate

endmodule
