// output_port.sv — Per-direction output port with credit tracking
module output_port #(
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // From crossbar
  input  noc_flit_pkg::flit_t       xbar_flit_in,
  input  logic        xbar_valid_in,
  input  noc_config_pkg::vc_id_t    xbar_vc_in,
  output logic        xbar_ready_out,

  // Link output to downstream
  output noc_flit_pkg::link_out_t   link_out,

  // Credit input from downstream
  input  noc_flit_pkg::credit_t     credit_in,

  // Credit counters (for SA visibility)
  output logic [$clog2(VC_DEPTH):0] credit_count [VC_NUM]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  logic [$clog2(VC_DEPTH):0] credit_cnt [VC_NUM];

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v++) begin : vc_credit
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          credit_cnt[v] <= VC_DEPTH;
        end else begin
          if (xbar_valid_in && xbar_ready_out && xbar_vc_in == vc_id_t'(v))
            credit_cnt[v] <= credit_cnt[v] - 1'b1;
          if (credit_in[v])
            credit_cnt[v] <= credit_cnt[v] + 1'b1;
        end
      end
      assign credit_count[v] = credit_cnt[v];
    end
  endgenerate

  assign xbar_ready_out = (credit_cnt[xbar_vc_in] > 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      link_out.flit  <= '0;
      link_out.valid <= 1'b0;
      link_out.vc    <= '0;
    end else begin
      if (xbar_valid_in && xbar_ready_out) begin
        link_out.flit  <= xbar_flit_in;
        link_out.valid <= 1'b1;
        link_out.vc    <= xbar_vc_in;
      end else begin
        link_out.valid <= 1'b0;
      end
    end
  end
endmodule
