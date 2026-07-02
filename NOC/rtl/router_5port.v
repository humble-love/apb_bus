// router_5port.v — 5-port wormhole router with XY routing and QoS
`include "noc_config.vh"
`include "noc_flit.vh"

module router_5port #(
  parameter MESH_X      = 8,
  parameter MESH_Y      = 8,
  parameter VC_NUM      = 2,
  parameter VC_DEPTH    = 8,
  parameter QOS_W       = 4,
  parameter PRIO_LEVELS = 4
) (
  input  wire        clk,
  input  wire        rst_n,

  // 5 link interfaces — flat signals: N(0), S(1), E(2), W(3), L(4)
  input  wire [`FLIT_PAYLOAD_W-1:0] link_in_flit_payload  [0:4],
  input  wire [1:0]                 link_in_flit_ftype    [0:4],
  input  wire        link_in_valid [0:4],
  input  wire        link_in_vc    [0:4],
  output wire        credit_out_v0 [0:4],        // per-port VC0 credit
  output wire        credit_out_v1 [0:4],        // per-port VC1 credit

  output wire [`FLIT_PAYLOAD_W-1:0] link_out_flit_payload  [0:4],
  output wire [1:0]                 link_out_flit_ftype    [0:4],
  output wire        link_out_valid [0:4],
  output wire        link_out_vc    [0:4],
  input  wire        credit_in_v0  [0:4],
  input  wire        credit_in_v1  [0:4],

  // Local port coordinate
  input  wire [`COORD_W-1:0] local_coord
);

  // --- Per-port signals from link_ctrl ---
  wire [`FLIT_PAYLOAD_W-1:0] xbar_in_payload  [0:4];
  wire [1:0]                 xbar_in_ftype    [0:4];
  wire   xbar_in_valid [0:4];
  wire   xbar_in_vc    [0:4];
  reg    xbar_in_pop   [0:4];

  wire [`FLIT_PAYLOAD_W-1:0] xbar_out_payload  [0:4];
  wire [1:0]                 xbar_out_ftype    [0:4];
  wire   xbar_out_valid [0:4];
  wire   xbar_out_vc    [0:4];
  wire   xbar_out_ready [0:4];

  // Credit: [port][VC] — credit count per port per VC
  reg [3:0] credit_cnt [0:4][0:`VC_NUM-1];

  // Route results
  wire [`PORT_DIR_W-1:0] route_result [0:4];

  // Locked route per (input, VC) — body/tail flits follow header's route
  reg [`PORT_DIR_W-1:0] locked_route [0:4][0:`VC_NUM-1];

  // VA: [port][VC] request/grant
  wire   va_req   [0:4][0:`VC_NUM-1];
  reg    va_grant [0:4][0:`VC_NUM-1];

  // SA: [output][input] grant matrix, plus per-input-port requests
  wire   sa_grant [0:4][0:4];     // driven by switch_allocator
  wire   sa_req   [0:4];
  wire [`QOS_W-1:0]       sa_qos   [0:4];
  wire [1:0]               sa_ftype [0:4];
  wire [`PORT_DIR_W-1:0]  sa_dest  [0:4];

  // Loop variables
  integer out_p, in_p, vc_idx;
  integer o;

  // --- Instantiate 5 link controllers ---
  genvar g, v;
  generate
    for (g = 0; g < 5; g = g + 1) begin : link_gen
      wire credit_out_arr [0:`VC_NUM-1];
      wire credit_in_arr  [0:`VC_NUM-1];

      assign credit_out_v0[g] = credit_out_arr[0];
      assign credit_out_v1[g] = credit_out_arr[1];
      assign credit_in_arr[0] = credit_in_v0[g];
      assign credit_in_arr[1] = credit_in_v1[g];

      link_ctrl #(.VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH)) lc (
        .clk(clk),
        .rst_n(rst_n),
        .link_in_flit_payload(link_in_flit_payload[g]),
        .link_in_flit_ftype(link_in_flit_ftype[g]),
        .link_in_valid(link_in_valid[g]),
        .link_in_vc(link_in_vc[g]),
        .credit_out(credit_out_arr),
        .xbar_flit_out_payload(xbar_in_payload[g]),
        .xbar_flit_out_ftype(xbar_in_ftype[g]),
        .xbar_valid_out(xbar_in_valid[g]),
        .xbar_vc_out(xbar_in_vc[g]),
        .xbar_pop(xbar_in_pop[g]),
        .xbar_flit_in_payload(xbar_out_payload[g]),
        .xbar_flit_in_ftype(xbar_out_ftype[g]),
        .xbar_valid_in(xbar_out_valid[g]),
        .xbar_vc_in(xbar_out_vc[g]),
        .xbar_ready_out(xbar_out_ready[g]),
        .link_out_flit_payload(link_out_flit_payload[g]),
        .link_out_flit_ftype(link_out_flit_ftype[g]),
        .link_out_valid(link_out_valid[g]),
        .link_out_vc(link_out_vc[g]),
        .credit_in(credit_in_arr),
        .credit_count(credit_cnt[g])
      );

      // Route compute: extract destination from header
      wire [3:0] hdr_dst_x_4b;
      wire [3:0] hdr_dst_y_4b;
      assign hdr_dst_x_4b = {1'b0, `FLIT_HDR_DST_X(xbar_in_payload[g])};
      assign hdr_dst_y_4b = {1'b0, `FLIT_HDR_DST_Y(xbar_in_payload[g])};

      wire [3:0] rc_src_x, rc_src_y;
      assign rc_src_x = {1'b0, `COORD_X(local_coord)};
      assign rc_src_y = {1'b0, `COORD_Y(local_coord)};

      route_compute #(.MESH_X(MESH_X), .MESH_Y(MESH_Y)) rc (
        .src_x(rc_src_x),
        .src_y(rc_src_y),
        .dst_x(hdr_dst_x_4b),
        .dst_y(hdr_dst_y_4b),
        .next_port(route_result[g])
      );

    end
  endgenerate

  // --- VA: per-port VC requests from valid header flits ---
  generate
    for (g = 0; g < 5; g = g + 1) begin : va_gen
      for (v = 0; v < VC_NUM; v = v + 1) begin : va_vc
        assign va_req[g][v] = xbar_in_valid[g] &&
                               xbar_in_ftype[g] == `FLIT_HEADER &&
                               xbar_in_vc[g] == v;
      end
    end
  endgenerate

  // VC Allocator: grant header-bearing VC when downstream has credit space
  reg done_va [0:4];

  always @(*) begin
    // Initialize
    for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
      for (vc_idx = 0; vc_idx < VC_NUM; vc_idx = vc_idx + 1) begin
        va_grant[in_p][vc_idx] = 1'b0;
      end
    end
    for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
      done_va[out_p] = 1'b0;
    end

    for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        for (vc_idx = 0; vc_idx < VC_NUM; vc_idx = vc_idx + 1) begin
          if (!done_va[out_p] && va_req[in_p][vc_idx] &&
              route_result[in_p] == out_p[`PORT_DIR_W-1:0] &&
              credit_cnt[out_p][vc_idx] > 0) begin
            va_grant[in_p][vc_idx] = 1'b1;
            done_va[out_p] = 1'b1;
          end
        end
      end
    end
  end

  // --- Lock route on VA grant, release on tail pop ---
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        for (vc_idx = 0; vc_idx < VC_NUM; vc_idx = vc_idx + 1) begin
          locked_route[in_p][vc_idx] <= {`PORT_DIR_W{1'b0}};
        end
      end
    end else begin
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        for (vc_idx = 0; vc_idx < VC_NUM; vc_idx = vc_idx + 1) begin
          // Lock route when header gets VA grant
          if (xbar_in_valid[in_p] && xbar_in_ftype[in_p] == `FLIT_HEADER &&
              xbar_in_vc[in_p] == vc_idx && va_grant[in_p][vc_idx])
            locked_route[in_p][vc_idx] <= route_result[in_p];
          // Release on tail pop (sampled at posedge before FIFO advances)
          else if (xbar_in_pop[in_p] && xbar_in_ftype[in_p] == `FLIT_TAIL &&
                   xbar_in_vc[in_p] == vc_idx)
            locked_route[in_p][vc_idx] <= {`PORT_DIR_W{1'b0}};
        end
      end
    end
  end

  // Effective route: header uses route_compute, body/tail uses locked route
  wire [`PORT_DIR_W-1:0] eff_route [0:4];
  generate
    for (g = 0; g < 5; g = g + 1) begin : route_eff
      assign eff_route[g] = (xbar_in_ftype[g] == `FLIT_HEADER) ?
                              route_result[g] : locked_route[g][xbar_in_vc[g]];
    end
  endgenerate

  // --- SA: build per-port request (granted header or following body/tail) ---
  generate
    for (g = 0; g < 5; g = g + 1) begin : sa_gen
      assign sa_req[g]   = xbar_in_valid[g] && xbar_in_ftype[g] != `FLIT_IDLE;
      assign sa_dest[g]  = eff_route[g];
      assign sa_qos[g]   = {`QOS_W{1'b0}};  // placeholder — extract from header in full impl
      assign sa_ftype[g] = xbar_in_ftype[g];
    end
  endgenerate

  // Switch Allocator with QoS
  switch_allocator #(.PRIO_LEVELS(PRIO_LEVELS)) sa_inst (
    .clk(clk),
    .rst_n(rst_n),
    .sa_req(sa_req),
    .sa_qos(sa_qos),
    .sa_ftype(sa_ftype),
    .sa_dest(sa_dest),
    .sa_grant(sa_grant)
  );


  // --- Crossbar ---
  crossbar_5x5 xbar (
    .flit_in_payload(xbar_in_payload),
    .flit_in_ftype(xbar_in_ftype),
    .valid_in(xbar_in_valid),
    .vc_in(xbar_in_vc),
    .grant(sa_grant),
    .flit_out_payload(xbar_out_payload),
    .flit_out_ftype(xbar_out_ftype),
    .valid_out(xbar_out_valid),
    .vc_out(xbar_out_vc)
  );

  // --- Pop logic ---
  generate
    for (g = 0; g < 5; g = g + 1) begin : pop_gen
      // Pop input when SA allows and target output port is ready
      always @(*) begin
        xbar_in_pop[g] = 1'b0;
        for (o = 0; o < 5; o = o + 1) begin
          if (sa_grant[o][g] && xbar_out_ready[o])
            xbar_in_pop[g] = 1'b1;
        end
      end
    end
  endgenerate

endmodule
