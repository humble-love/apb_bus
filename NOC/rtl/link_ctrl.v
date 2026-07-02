// link_ctrl.v — Per-direction link controller with per-VC IP/OP instances
`include "noc_config.vh"
`include "noc_flit.vh"

module link_ctrl #(
  parameter VC_NUM   = 2,
  parameter VC_DEPTH = 8
) (
  input  wire        clk,
  input  wire        rst_n,

  // Facing upstream router (flat signals — VCS 2018 compatible)
  input  wire [`FLIT_PAYLOAD_W-1:0] link_in_flit_payload,
  input  wire [1:0]                 link_in_flit_ftype,
  input  wire        link_in_valid,
  input  wire        link_in_vc,

  // Credit return to upstream (per VC)
  output wire        credit_out [0:`VC_NUM-1],

  // Crossbar-bound flit output (single — wormhole follows header VC)
  output wire [`FLIT_PAYLOAD_W-1:0] xbar_flit_out_payload,
  output wire [1:0]                 xbar_flit_out_ftype,
  output wire        xbar_valid_out,
  output wire        xbar_vc_out,
  input  wire        xbar_pop,

  // Crossbar-sourced flit input
  input  wire [`FLIT_PAYLOAD_W-1:0] xbar_flit_in_payload,
  input  wire [1:0]                 xbar_flit_in_ftype,
  input  wire        xbar_valid_in,
  input  wire        xbar_vc_in,
  output wire        xbar_ready_out,

  // Facing downstream router (flat)
  output wire [`FLIT_PAYLOAD_W-1:0] link_out_flit_payload,
  output wire [1:0]                 link_out_flit_ftype,
  output wire        link_out_valid,
  output wire        link_out_vc,

  // Credit input from downstream (per VC)
  input  wire        credit_in [0:`VC_NUM-1],

  // Credit status for SA/VA visibility
  output wire [3:0] credit_count [0:`VC_NUM-1]
);

  // Per-VC input port signals
  wire [`FLIT_PAYLOAD_W-1:0] ip_flit_payload  [0:`VC_NUM-1];
  wire [1:0]                 ip_flit_ftype    [0:`VC_NUM-1];
  wire   ip_valid [0:`VC_NUM-1];
  wire   ip_pop   [0:`VC_NUM-1];
  wire   ip_full  [0:`VC_NUM-1];
  wire   ip_empty [0:`VC_NUM-1];

  // Per-VC output port signals
  wire [`FLIT_PAYLOAD_W-1:0] op_flit_payload  [0:`VC_NUM-1];
  wire [1:0]                 op_flit_ftype    [0:`VC_NUM-1];
  wire   op_valid [0:`VC_NUM-1];
  wire   op_ready [0:`VC_NUM-1];

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v = v + 1) begin : vc_gen
      localparam VC_ID = v;

      input_port #(.VC_DEPTH(VC_DEPTH)) ip (
        .clk(clk),
        .rst_n(rst_n),
        .link_flit_payload(link_in_flit_payload),
        .link_flit_ftype(link_in_flit_ftype),
        .link_valid(link_in_valid),
        .link_vc(link_in_vc),
        .my_vc(VC_ID),
        .vc_flit_out_payload(ip_flit_payload[v]),
        .vc_flit_out_ftype(ip_flit_ftype[v]),
        .vc_valid_out(ip_valid[v]),
        .vc_pop(ip_pop[v]),
        .credit_out(credit_out[v]),
        .fifo_full(ip_full[v]),
        .fifo_empty(ip_empty[v])
      );

      output_port #(.VC_DEPTH(VC_DEPTH)) op (
        .clk(clk),
        .rst_n(rst_n),
        .xbar_flit_in_payload(xbar_flit_in_payload),
        .xbar_flit_in_ftype(xbar_flit_in_ftype),
        .xbar_valid_in(xbar_valid_in),
        .xbar_vc_in(xbar_vc_in),
        .my_vc(VC_ID),
        .xbar_ready_out_vc(op_ready[v]),
        .link_flit_vc_payload(op_flit_payload[v]),
        .link_flit_vc_ftype(op_flit_ftype[v]),
        .link_valid_vc(op_valid[v]),
        .credit_in(credit_in[v]),
        .credit_count(credit_count[v])
      );
    end
  endgenerate

  // VC mux for crossbar output: VC0 has priority
  assign xbar_flit_out_payload = ip_valid[0] ? ip_flit_payload[0] : ip_flit_payload[1];
  assign xbar_flit_out_ftype   = ip_valid[0] ? ip_flit_ftype[0]   : ip_flit_ftype[1];
  assign xbar_valid_out = ip_valid[0] || ip_valid[1];
  assign xbar_vc_out    = ip_valid[0] ? 1'b0 : 1'b1;

  // Pop the VC that was selected (propagates to SA grant)
  assign ip_pop[0] = xbar_pop && ip_valid[0];
  assign ip_pop[1] = xbar_pop && !ip_valid[0] && ip_valid[1];

  // Combine per-VC output signals to link
  assign link_out_flit_payload = op_valid[0] ? op_flit_payload[0] : op_flit_payload[1];
  assign link_out_flit_ftype   = op_valid[0] ? op_flit_ftype[0]   : op_flit_ftype[1];
  assign link_out_valid = op_valid[0] || op_valid[1];
  assign link_out_vc    = op_valid[0] ? 1'b0 : 1'b1;

  // Crossbar ready when target VC's output port has credit
  assign xbar_ready_out = op_ready[0] || op_ready[1];

endmodule
