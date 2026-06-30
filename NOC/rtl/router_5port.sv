// router_5port.sv — 5-port wormhole router with XY routing and QoS
module router_5port #(
  parameter int MESH_X      = 8,
  parameter int MESH_Y      = 8,
  parameter int VC_NUM      = 2,
  parameter int VC_DEPTH    = 8,
  parameter int QOS_W       = 4,
  parameter int PRIO_LEVELS = 4
) (
  input  logic        clk,
  input  logic        rst_n,

  // 5 link interfaces — flat signals: N(0), S(1), E(2), W(3), L(4)
  input  noc_flit_pkg::flit_t        link_in_flit  [5],
  input  logic        link_in_valid [5],
  input  noc_config_pkg::vc_id_t     link_in_vc    [5],
  output logic        credit_out_v0 [5],        // per-port VC0 credit
  output logic        credit_out_v1 [5],        // per-port VC1 credit

  output noc_flit_pkg::flit_t        link_out_flit  [5],
  output logic        link_out_valid [5],
  output noc_config_pkg::vc_id_t     link_out_vc    [5],
  input  logic        credit_in_v0  [5],
  input  logic        credit_in_v1  [5],

  // Local port coordinate
  input  noc_config_pkg::coord_t     local_coord
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // --- Per-port signals from link_ctrl ---
  flit_t   xbar_in_flit  [5];
  logic    xbar_in_valid [5];
  vc_id_t  xbar_in_vc    [5];
  logic    xbar_in_pop   [5];

  flit_t   xbar_out_flit  [5];
  logic    xbar_out_valid [5];
  vc_id_t  xbar_out_vc    [5];
  logic    xbar_out_ready [5];

  // Credit: [port][VC] — credit count per port per VC
  logic [$clog2(VC_DEPTH):0] credit_cnt [5][VC_NUM];

  // Route results
  port_dir_t route_result [5];

  // VA: [port][VC] request/grant
  logic va_req  [5][VC_NUM];
  logic va_grant [5][VC_NUM];

  // SA: [output][input] grant matrix, plus per-input-port requests
  logic sa_grant [5][5];
  logic sa_req   [5];
  qos_t sa_qos   [5];
  flit_type_t sa_ftype [5];
  port_dir_t sa_dest [5];

  // --- Instantiate 5 link controllers ---
  genvar g, v;
  generate
    for (g = 0; g < 5; g++) begin : link_gen
      logic credit_out_arr [VC_NUM];
      logic credit_in_arr  [VC_NUM];

      assign credit_out_v0[g] = credit_out_arr[0];
      assign credit_out_v1[g] = credit_out_arr[1];
      assign credit_in_arr[0] = credit_in_v0[g];
      assign credit_in_arr[1] = credit_in_v1[g];

      link_ctrl #(.VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH)) lc (
        .clk, .rst_n,
        .link_in_flit(link_in_flit[g]),
        .link_in_valid(link_in_valid[g]),
        .link_in_vc(link_in_vc[g]),
        .credit_out(credit_out_arr),
        .xbar_flit_out(xbar_in_flit[g]),
        .xbar_valid_out(xbar_in_valid[g]),
        .xbar_vc_out(xbar_in_vc[g]),
        .xbar_pop(xbar_in_pop[g]),
        .xbar_flit_in(xbar_out_flit[g]),
        .xbar_valid_in(xbar_out_valid[g]),
        .xbar_vc_in(xbar_out_vc[g]),
        .xbar_ready_out(xbar_out_ready[g]),
        .link_out_flit(link_out_flit[g]),
        .link_out_valid(link_out_valid[g]),
        .link_out_vc(link_out_vc[g]),
        .credit_in(credit_in_arr),
        .credit_count(credit_cnt[g])
      );

      // Route compute: extract destination from header
      logic [3:0] hdr_dst_x_4b;
      logic [3:0] hdr_dst_y_4b;
      flit_header_t hdr;
      assign hdr = unpack_header(xbar_in_flit[g].payload);
      assign hdr_dst_x_4b = {1'b0, hdr.dst_x};
      assign hdr_dst_y_4b = {1'b0, hdr.dst_y};

      route_compute #(.MESH_X(MESH_X), .MESH_Y(MESH_Y)) rc (
        .src_x({1'b0, local_coord.x}),
        .src_y({1'b0, local_coord.y}),
        .dst_x(hdr_dst_x_4b),
        .dst_y(hdr_dst_y_4b),
        .port_disable('{default: '0}),
        .next_port(route_result[g])
      );
    end
  endgenerate

  // --- VA: per-port VC requests from valid header flits ---
  generate
    for (g = 0; g < 5; g++) begin : va_gen
      for (v = 0; v < VC_NUM; v++) begin : va_vc
        assign va_req[g][v] = xbar_in_valid[g] &&
                               xbar_in_flit[g].ftype == FLIT_HEADER &&
                               xbar_in_vc[g] == vc_id_t'(v);
      end
    end
  endgenerate

  // VC Allocator: grant header-bearing VC when downstream has credit space
  always_comb begin
    logic done_va [5];
    va_grant = '{default: '0};
    done_va = '{default: '0};
    for (int out_p = 0; out_p < 5; out_p++) begin
      for (int in_p = 0; in_p < 5; in_p++) begin
        for (int vc = 0; vc < VC_NUM; vc++) begin
          if (!done_va[out_p] && va_req[in_p][vc] && route_result[in_p] == port_dir_t'(out_p) &&
              credit_cnt[out_p][vc] > 0) begin
            va_grant[in_p][vc] = 1'b1;
            done_va[out_p] = 1'b1;
          end
        end
      end
    end
  end

  // --- SA: build per-port request (granted header or following body/tail) ---
  generate
    for (g = 0; g < 5; g++) begin : sa_gen
      assign sa_req[g]   = xbar_in_valid[g] && xbar_in_flit[g].ftype != FLIT_IDLE;
      assign sa_dest[g]  = route_result[g];
      assign sa_qos[g]   = '0;  // placeholder — extract from header in full impl
      assign sa_ftype[g] = xbar_in_flit[g].ftype;
    end
  endgenerate

  // Switch Allocator with QoS
  switch_allocator #(.PRIO_LEVELS(PRIO_LEVELS)) sa_inst (
    .clk, .rst_n,
    .sa_req,
    .sa_qos,
    .sa_ftype,
    .sa_dest,
    .sa_grant
  );

  // --- Crossbar ---
  crossbar_5x5 xbar (
    .flit_in(xbar_in_flit),
    .valid_in(xbar_in_valid),
    .vc_in(xbar_in_vc),
    .grant(sa_grant),
    .flit_out(xbar_out_flit),
    .valid_out(xbar_out_valid),
    .vc_out(xbar_out_vc)
  );

  // --- Pop logic ---
  generate
    for (g = 0; g < 5; g++) begin : pop_gen
      // Pop input when SA allows and target output port is ready
      always_comb begin
        xbar_in_pop[g] = 1'b0;
        for (int o = 0; o < 5; o++) begin
          if (sa_grant[o][g] && xbar_out_ready[o])
            xbar_in_pop[g] = 1'b1;
        end
      end
    end
  endgenerate

endmodule
