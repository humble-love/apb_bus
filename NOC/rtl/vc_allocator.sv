// vc_allocator.sv — VC allocation stage
// Determines which input port's VC gets to proceed to SA per output port
module vc_allocator #(
  parameter int VC_NUM = 2
) (
  input  logic        clk,
  input  logic        rst_n,

  // Request: [input_port][vc] — header flit ready at FIFO head
  input  logic        va_req    [5][VC_NUM],

  // Route compute result per input port (which output port it targets)
  input  noc_config_pkg::port_dir_t va_route [5],

  // Downstream credit availability: [output_port][vc]
  input  logic        downstream_credit_avail [5][VC_NUM],

  // Grant: [input_port][vc] — granted to proceed to SA
  output logic        va_grant  [5][VC_NUM]
);
  import noc_config_pkg::*;

  // Per output port: which input+v wins. Simple priority: port 0 > ... > port 4, VC0 > VC1.
  always_comb begin
    va_grant = '{default: '0};
    for (int out_p = 0; out_p < 5; out_p++) begin
      logic granted;
      granted = 1'b0;
      for (int in_p = 0; in_p < 5; in_p++) begin
        for (int v = 0; v < VC_NUM; v++) begin
          if (!granted && va_req[in_p][v] && va_route[in_p] == port_dir_t'(out_p) &&
              downstream_credit_avail[out_p][v]) begin
            va_grant[in_p][v] = 1'b1;
            granted = 1'b1;
          end
        end
      end
    end
  end
endmodule
