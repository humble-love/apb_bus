// output_port.sv — Single output port, single VC credit tracker
// Instantiated per-VC for VCS 2018 compatibility
module output_port #(
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // From crossbar
  input  noc_flit_pkg::flit_t        xbar_flit_in,
  input  logic        xbar_valid_in,
  input  noc_config_pkg::vc_id_t     xbar_vc_in,
  input  noc_config_pkg::vc_id_t     my_vc,      // this instance's VC ID
  output logic        xbar_ready_out_vc,          // credit available for this VC

  // Link output to downstream (shared across VCs — driven by VC with credit)
  output noc_flit_pkg::flit_t        link_flit_vc,
  output logic        link_valid_vc,

  // Credit input from downstream
  input  logic        credit_in,

  // Credit counter (for SA visibility)
  output logic [$clog2(VC_DEPTH):0] credit_count
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic [$clog2(VC_DEPTH):0] cnt;
  logic dec, inc;

  assign dec = xbar_valid_in && xbar_vc_in == my_vc && cnt > 0;
  assign inc = credit_in;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= VC_DEPTH;
    end else begin
      if (dec && !inc)
        cnt <= cnt - 1'b1;
      else if (!dec && inc)
        cnt <= cnt + 1'b1;
    end
  end

  assign credit_count = cnt;
  assign xbar_ready_out_vc = (cnt > 0);
  assign link_flit_vc  = xbar_flit_in;
  assign link_valid_vc = xbar_valid_in && xbar_vc_in == my_vc;
endmodule
