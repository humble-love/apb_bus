// output_port.v — Single output port, single VC credit tracker
// Instantiated per-VC for VCS 2018 compatibility
`include "noc_config.vh"
`include "noc_flit.vh"

module output_port #(
  parameter VC_DEPTH = 8
) (
  input  wire        clk,
  input  wire        rst_n,

  // From crossbar
  input  wire [`FLIT_PAYLOAD_W-1:0] xbar_flit_in_payload,
  input  wire [1:0]                 xbar_flit_in_ftype,
  input  wire        xbar_valid_in,
  input  wire        xbar_vc_in,
  input  wire        my_vc,         // this instance's VC ID
  output wire        xbar_ready_out_vc,  // credit available for this VC

  // Link output to downstream (shared across VCs — driven by VC with credit)
  output wire [`FLIT_PAYLOAD_W-1:0] link_flit_vc_payload,
  output wire [1:0]                 link_flit_vc_ftype,
  output wire        link_valid_vc,

  // Credit input from downstream
  input  wire        credit_in,

  // Credit counter (for SA visibility)
  output wire [3:0] credit_count
);

  reg [3:0] cnt;
  wire dec, inc;

  assign dec = xbar_valid_in && xbar_vc_in == my_vc && cnt > 0;
  assign inc = credit_in;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= `VC_DEPTH;
    end else begin
      if (dec && !inc)
        cnt <= cnt - 1'b1;
      else if (!dec && inc)
        cnt <= cnt + 1'b1;
    end
  end

  assign credit_count = cnt;
  assign xbar_ready_out_vc = (cnt > 0);
  assign link_flit_vc_payload  = xbar_flit_in_payload;
  assign link_flit_vc_ftype    = xbar_flit_in_ftype;
  assign link_valid_vc = xbar_valid_in && xbar_vc_in == my_vc;
endmodule
