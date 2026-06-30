// switch_allocator.sv — QoS-aware switch arbitration with aging
module switch_allocator #(
  parameter int PRIO_LEVELS     = 4,
  parameter int AGING_THRESHOLD = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // Request: [input_port] — per-port request from link_ctrl (VC already resolved)
  input  logic        sa_req   [5],
  input  noc_config_pkg::qos_t sa_qos [5],
  input  noc_flit_pkg::flit_type_t sa_ftype [5],

  // Output port each input targets
  input  noc_config_pkg::port_dir_t sa_dest [5],

  // Grant: [output_port][input_port] — which input wins each output
  output logic        sa_grant [5][5]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // QoS value to priority level: bit[3]=P0, bit[2]=P1, bit[1]=P2, bit[0]=P3
  function automatic logic [1:0] qos_to_prio(qos_t q);
    if (q[3])      return 2'd0;
    else if (q[2]) return 2'd1;
    else if (q[1]) return 2'd2;
    else           return 2'd3;
  endfunction

  // Aging counters for P3 requests
  logic [7:0] aging_cnt [5];

  genvar pi;
  generate
    for (pi = 0; pi < 5; pi++) begin : aging_p
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
          aging_cnt[pi] <= '0;
        else if (sa_req[pi] && qos_to_prio(sa_qos[pi]) == 2'd3)
          aging_cnt[pi] <= aging_cnt[pi] + 1'b1;
        else if (!sa_req[pi])
          aging_cnt[pi] <= '0;
      end
    end
  endgenerate

  // Per-output-port arbitration: strict-priority + round-robin within level
  logic [2:0] rr_ptr [5];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 5; i++) rr_ptr[i] <= '0;
    end else begin
      for (int out = 0; out < 5; out++) begin
        for (int in = 0; in < 5; in++) begin
          if (sa_grant[out][in])
            rr_ptr[out] <= rr_ptr[out] + 1'b1;
        end
      end
    end
  end

  always_comb begin
    logic done_sa [5];
    sa_grant = '{default: '0};
    done_sa = '{default: '0};
    for (int plev = 0; plev < 4; plev++) begin
      for (int out_p = 0; out_p < 5; out_p++) begin
        for (int r = 0; r < 5; r++) begin
          automatic int in_p = (rr_ptr[out_p] + r) % 5;
          logic [1:0] eff_prio;
          eff_prio = (aging_cnt[in_p] >= AGING_THRESHOLD && qos_to_prio(sa_qos[in_p]) == 2'd3) ?
                      2'd2 : qos_to_prio(sa_qos[in_p]);
          if (!done_sa[out_p] && sa_req[in_p] && sa_dest[in_p] == port_dir_t'(out_p) &&
              eff_prio == plev[1:0]) begin
            sa_grant[out_p][in_p] = 1'b1;
            done_sa[out_p] = 1'b1;
          end
        end
      end
    end
  end
endmodule
