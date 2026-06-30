// input_port.sv — Single input port, single VC FIFO with credit return
// Instantiated per-VC for VCS 2018 compatibility (avoids unpacked array-of-struct ports)
module input_port #(
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // Link input — this VC's slice
  input  noc_flit_pkg::flit_t        link_flit,
  input  logic        link_valid,
  input  noc_config_pkg::vc_id_t     link_vc,
  input  noc_config_pkg::vc_id_t     my_vc,     // this instance's VC ID

  // Flit output toward crossbar
  output noc_flit_pkg::flit_t        vc_flit_out,
  output logic        vc_valid_out,
  input  logic        vc_pop,

  // Credit return to upstream
  output logic        credit_out,

  // FIFO status
  output logic        fifo_full,
  output logic        fifo_empty
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  flit_t mem [VC_DEPTH];
  logic [$clog2(VC_DEPTH):0] wr_ptr, rd_ptr, count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      if (link_valid && link_vc == my_vc && count < VC_DEPTH) begin
        mem[wr_ptr] <= link_flit;
        wr_ptr <= wr_ptr + 1'b1;
        count  <= count + 1'b1;
      end
      if (vc_pop && count > 0) begin
        rd_ptr <= rd_ptr + 1'b1;
        count  <= count - 1'b1;
      end
    end
  end

  assign vc_flit_out  = mem[rd_ptr];
  assign vc_valid_out = (count > 0);
  assign fifo_full    = (count >= VC_DEPTH);
  assign fifo_empty   = (count == 0);
  assign credit_out   = vc_pop;
endmodule
