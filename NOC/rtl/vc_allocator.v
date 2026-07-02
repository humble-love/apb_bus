// vc_allocator.v — VC allocation stage
// Determines which input port's VC gets to proceed to SA per output port
`include "noc_config.vh"

module vc_allocator #(
  parameter VC_NUM = 2
) (
  input  wire        clk,
  input  wire        rst_n,

  // Request: [input_port][vc] — header flit ready at FIFO head
  input  wire        va_req    [0:4][0:VC_NUM-1],

  // Route compute result per input port (which output port it targets)
  input  wire [`PORT_DIR_W-1:0] va_route [0:4],

  // Downstream credit availability: [output_port][vc]
  input  wire        downstream_credit_avail [0:4][0:VC_NUM-1],

  // Grant: [input_port][vc] — granted to proceed to SA
  output reg         va_grant  [0:4][0:VC_NUM-1]
);

  integer out_p, in_p, v;
  reg granted;

  // Per output port: which input+v wins. Simple priority: port 0 > ... > port 4, VC0 > VC1.
  always @(*) begin
    // Clear all grants first
    for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        for (v = 0; v < VC_NUM; v = v + 1) begin
          va_grant[in_p][v] = 1'b0;
        end
      end
    end
    // Then assign grants
    for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
      granted = 1'b0;
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        for (v = 0; v < VC_NUM; v = v + 1) begin
          if (!granted && va_req[in_p][v] && va_route[in_p] == out_p[`PORT_DIR_W-1:0] &&
              downstream_credit_avail[out_p][v]) begin
            va_grant[in_p][v] = 1'b1;
            granted = 1'b1;
          end
        end
      end
    end
  end
endmodule
