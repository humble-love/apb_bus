// input_port.sv — Single input port with 2 VC FIFOs
module input_port #(
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // Link input from upstream
  input  noc_flit_pkg::link_in_t    link_in,

  // Flit output toward crossbar (per VC)
  output noc_flit_pkg::flit_t       vc_flit_out [VC_NUM],
  output logic        vc_valid_out [VC_NUM],
  input  logic        vc_pop       [VC_NUM],

  // Credit return to upstream
  output noc_flit_pkg::credit_t     credit_out,

  // FIFO status
  output logic        fifo_full  [VC_NUM],
  output logic        fifo_empty [VC_NUM]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // VC FIFOs — register-based (small depth)
  flit_t vc_fifo [VC_NUM][VC_DEPTH];
  logic [$clog2(VC_DEPTH):0] fifo_wr_ptr [VC_NUM];
  logic [$clog2(VC_DEPTH):0] fifo_rd_ptr [VC_NUM];
  logic [$clog2(VC_DEPTH):0] fifo_count [VC_NUM];

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v++) begin : vc_gen
      // Write side: accept flit if matching VC, valid, and not full
      // Read side: pop when granted
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          fifo_wr_ptr[v] <= '0;
          fifo_rd_ptr[v] <= '0;
          fifo_count[v]  <= '0;
        end else begin
          if (link_in.valid && link_in.vc == vc_id_t'(v) && fifo_count[v] < VC_DEPTH) begin
            vc_fifo[v][fifo_wr_ptr[v]] <= link_in.flit;
            fifo_wr_ptr[v] <= fifo_wr_ptr[v] + 1'b1;
            fifo_count[v]  <= fifo_count[v] + 1'b1;
          end
          if (vc_pop[v] && fifo_count[v] > 0) begin
            fifo_rd_ptr[v] <= fifo_rd_ptr[v] + 1'b1;
            fifo_count[v]  <= fifo_count[v] - 1'b1;
          end
        end
      end

      assign vc_flit_out[v] = vc_fifo[v][fifo_rd_ptr[v]];
      assign vc_valid_out[v] = (fifo_count[v] > 0);
      assign fifo_full[v]    = (fifo_count[v] >= VC_DEPTH);
      assign fifo_empty[v]   = (fifo_count[v] == 0);
      assign credit_out[v]   = vc_pop[v];  // one credit per pop
    end
  endgenerate
endmodule
