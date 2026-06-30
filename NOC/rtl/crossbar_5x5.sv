// crossbar_5x5.sv — 5x5 crossbar switch (combinational)
module crossbar_5x5 #(
  parameter int DATA_W = 512
) (
  // 5 inputs
  input  noc_flit_pkg::flit_t        flit_in   [5],
  input  logic        valid_in [5],
  input  noc_config_pkg::vc_id_t     vc_in     [5],

  // Grant: [output][input] — one-hot connection
  input  logic        grant    [5][5],

  // 5 outputs
  output noc_flit_pkg::flit_t        flit_out  [5],
  output logic        valid_out [5],
  output noc_config_pkg::vc_id_t     vc_out    [5]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  always_comb begin
    for (int out = 0; out < 5; out++) begin
      flit_out[out]  = '0;
      valid_out[out] = 1'b0;
      vc_out[out]    = '0;
      for (int in = 0; in < 5; in++) begin
        if (grant[out][in]) begin
          flit_out[out]  = flit_in[in];
          valid_out[out] = valid_in[in];
          vc_out[out]    = vc_in[in];
        end
      end
    end
  end
endmodule
