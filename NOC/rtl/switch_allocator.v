// switch_allocator.v — QoS-aware switch arbitration with aging
`include "noc_config.vh"
`include "noc_flit.vh"

module switch_allocator #(
  parameter PRIO_LEVELS     = 4,
  parameter AGING_THRESHOLD = 64
) (
  input  wire        clk,
  input  wire        rst_n,

  // Request: [input_port] — per-port request from link_ctrl (VC already resolved)
  input  wire        sa_req   [0:4],
  input  wire [`QOS_W-1:0] sa_qos [0:4],
  input  wire [1:0]         sa_ftype [0:4],

  // Output port each input targets
  input  wire [`PORT_DIR_W-1:0] sa_dest [0:4],

  // Grant: [output_port][input_port] — which input wins each output
  output reg         sa_grant [0:4][0:4]
);

  // QoS value to priority level: bit[3]=P0, bit[2]=P1, bit[1]=P2, bit[0]=P3
  function [1:0] qos_to_prio;
    input [`QOS_W-1:0] q;
    begin
      if (q[3])      qos_to_prio = 2'd0;
      else if (q[2]) qos_to_prio = 2'd1;
      else if (q[1]) qos_to_prio = 2'd2;
      else           qos_to_prio = 2'd3;
    end
  endfunction

  // Aging counters for P3 requests
  reg [7:0] aging_cnt [0:4];
  // Per-output-port arbitration: strict-priority + round-robin within level
  reg [2:0] rr_ptr [0:4];

  // Loop variables
  integer i, out, in;
  integer plev, out_p, r, in_p;
  reg [1:0] eff_prio;
  reg done_sa [0:4];

  generate
    genvar pi;
    for (pi = 0; pi < 5; pi = pi + 1) begin : aging_p
      always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
          aging_cnt[pi] <= 8'd0;
        else if (sa_req[pi] && qos_to_prio(sa_qos[pi]) == 2'd3)
          aging_cnt[pi] <= aging_cnt[pi] + 1'b1;
        else if (!sa_req[pi])
          aging_cnt[pi] <= 8'd0;
      end
    end
  endgenerate

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 5; i = i + 1) rr_ptr[i] <= 3'd0;
    end else begin
      for (out = 0; out < 5; out = out + 1) begin
        for (in = 0; in < 5; in = in + 1) begin
          if (sa_grant[out][in])
            rr_ptr[out] <= rr_ptr[out] + 1'b1;
        end
      end
    end
  end

  always @(*) begin
    // Initialize all grants and done flags
    for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
      done_sa[out_p] = 1'b0;
      for (in_p = 0; in_p < 5; in_p = in_p + 1) begin
        sa_grant[out_p][in_p] = 1'b0;
      end
    end
    for (plev = 0; plev < 4; plev = plev + 1) begin
      for (out_p = 0; out_p < 5; out_p = out_p + 1) begin
        for (r = 0; r < 5; r = r + 1) begin
          in_p = (rr_ptr[out_p] + r) % 5;
          eff_prio = (aging_cnt[in_p] >= AGING_THRESHOLD && qos_to_prio(sa_qos[in_p]) == 2'd3) ?
                      2'd2 : qos_to_prio(sa_qos[in_p]);
          if (!done_sa[out_p] && sa_req[in_p] && sa_dest[in_p] == out_p[`PORT_DIR_W-1:0] &&
              eff_prio == plev[1:0]) begin
            sa_grant[out_p][in_p] = 1'b1;
            done_sa[out_p] = 1'b1;
          end
        end
      end
    end
  end
endmodule
