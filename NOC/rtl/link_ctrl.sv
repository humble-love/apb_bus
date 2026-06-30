// link_ctrl.sv — Per-direction link controller with per-VC IP/OP instances
module link_ctrl #(
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // Facing upstream router (flat signals — VCS 2018 compatible)
  input  noc_flit_pkg::flit_t        link_in_flit,
  input  logic        link_in_valid,
  input  noc_config_pkg::vc_id_t     link_in_vc,

  // Credit return to upstream (per VC)
  output logic        credit_out [VC_NUM],

  // Crossbar-bound flit output (single — wormhole follows header VC)
  output noc_flit_pkg::flit_t        xbar_flit_out,
  output logic        xbar_valid_out,
  output noc_config_pkg::vc_id_t     xbar_vc_out,
  input  logic        xbar_pop,

  // Crossbar-sourced flit input
  input  noc_flit_pkg::flit_t        xbar_flit_in,
  input  logic        xbar_valid_in,
  input  noc_config_pkg::vc_id_t     xbar_vc_in,
  output logic        xbar_ready_out,

  // Facing downstream router (flat)
  output noc_flit_pkg::flit_t        link_out_flit,
  output logic        link_out_valid,
  output noc_config_pkg::vc_id_t     link_out_vc,

  // Credit input from downstream (per VC)
  input  logic        credit_in [VC_NUM],

  // Credit status for SA/VA visibility
  output logic [$clog2(VC_DEPTH):0] credit_count [VC_NUM]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Per-VC input port signals
  flit_t  ip_flit  [VC_NUM];
  logic   ip_valid [VC_NUM];
  logic   ip_pop   [VC_NUM];
  logic   ip_full  [VC_NUM];
  logic   ip_empty [VC_NUM];

  // Per-VC output port signals
  flit_t  op_flit  [VC_NUM];
  logic   op_valid [VC_NUM];
  logic   op_ready [VC_NUM];

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v++) begin : vc_gen
      localparam vc_id_t VC_ID = vc_id_t'(v);

      input_port #(.VC_DEPTH(VC_DEPTH)) ip (
        .clk, .rst_n,
        .link_flit(link_in_flit),
        .link_valid(link_in_valid),
        .link_vc(link_in_vc),
        .my_vc(VC_ID),
        .vc_flit_out(ip_flit[v]),
        .vc_valid_out(ip_valid[v]),
        .vc_pop(ip_pop[v]),
        .credit_out(credit_out[v]),
        .fifo_full(ip_full[v]),
        .fifo_empty(ip_empty[v])
      );

      output_port #(.VC_DEPTH(VC_DEPTH)) op (
        .clk, .rst_n,
        .xbar_flit_in,
        .xbar_valid_in,
        .xbar_vc_in,
        .my_vc(VC_ID),
        .xbar_ready_out_vc(op_ready[v]),
        .link_flit_vc(op_flit[v]),
        .link_valid_vc(op_valid[v]),
        .credit_in(credit_in[v]),
        .credit_count(credit_count[v])
      );
    end
  endgenerate

  // VC mux for crossbar output: VC0 has priority
  assign xbar_flit_out  = ip_valid[0] ? ip_flit[0] : ip_flit[1];
  assign xbar_valid_out = ip_valid[0] || ip_valid[1];
  assign xbar_vc_out    = ip_valid[0] ? vc_id_t'(0) : vc_id_t'(1);

  // Pop the VC that was selected (propagates to SA grant)
  assign ip_pop[0] = xbar_pop && ip_valid[0];
  assign ip_pop[1] = xbar_pop && !ip_valid[0] && ip_valid[1];

  // Combine per-VC output signals to link
  assign link_out_flit  = op_valid[0] ? op_flit[0] : op_flit[1];
  assign link_out_valid = op_valid[0] || op_valid[1];
  assign link_out_vc    = op_valid[0] ? vc_id_t'(0) : vc_id_t'(1);

  // Crossbar ready when target VC's output port has credit
  assign xbar_ready_out = op_ready[0] || op_ready[1];

endmodule
