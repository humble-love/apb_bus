// crossbar_5x5.v — 5x5 crossbar switch (combinational)
`include "noc_config.vh"
`include "noc_flit.vh"

module crossbar_5x5 #(
  parameter DATA_W = 512
) (
  // 5 inputs
  input  wire [`FLIT_PAYLOAD_W-1:0] flit_in_payload [0:4],
  input  wire [1:0]                 flit_in_ftype  [0:4],
  input  wire        valid_in [0:4],
  input  wire        vc_in     [0:4],

  // Grant: [output][input] — one-hot connection
  input  wire        grant    [0:4][0:4],

  // 5 outputs
  output reg  [`FLIT_PAYLOAD_W-1:0] flit_out_payload [0:4],
  output reg  [1:0]                 flit_out_ftype  [0:4],
  output reg         valid_out [0:4],
  output reg         vc_out    [0:4]
);

  integer out, in;

  always @(*) begin
    for (out = 0; out < 5; out = out + 1) begin
      flit_out_payload[out] = {`FLIT_PAYLOAD_W{1'b0}};
      flit_out_ftype[out]  = `FLIT_IDLE;
      valid_out[out] = 1'b0;
      vc_out[out]    = 1'b0;
      for (in = 0; in < 5; in = in + 1) begin
        if (grant[out][in]) begin
          flit_out_payload[out] = flit_in_payload[in];
          flit_out_ftype[out]  = flit_in_ftype[in];
          valid_out[out] = valid_in[in];
          vc_out[out]    = vc_in[in];
        end
      end
    end
  end
endmodule
