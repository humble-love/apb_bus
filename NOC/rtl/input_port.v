// input_port.v — Single input port, single VC FIFO with credit return
// Instantiated per-VC for VCS 2018 compatibility (avoids unpacked array-of-struct ports)
`include "noc_config.vh"
`include "noc_flit.vh"

module input_port #(
  parameter VC_DEPTH = 8
) (
  input  wire        clk,
  input  wire        rst_n,

  // Link input — this VC's slice
  input  wire [`FLIT_PAYLOAD_W-1:0] link_flit_payload,
  input  wire [1:0]                 link_flit_ftype,
  input  wire        link_valid,
  input  wire        link_vc,
  input  wire        my_vc,         // this instance's VC ID

  // Flit output toward crossbar
  output wire [`FLIT_PAYLOAD_W-1:0] vc_flit_out_payload,
  output wire [1:0]                 vc_flit_out_ftype,
  output wire        vc_valid_out,
  input  wire        vc_pop,

  // Credit return to upstream
  output wire        credit_out,

  // FIFO status
  output wire        fifo_full,
  output wire        fifo_empty
);

  reg [`FLIT_W-1:0] mem [0:`VC_DEPTH-1];
  reg [3:0] wr_ptr, rd_ptr, count;
  reg do_write, do_pop;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= 4'd0;
      rd_ptr <= 4'd0;
      count  <= 4'd0;
    end else begin
      do_write = link_valid && link_vc == my_vc && count < `VC_DEPTH;
      do_pop   = vc_pop && count > 0;
      if (do_write && !do_pop) begin
        mem[wr_ptr] <= {link_flit_payload, link_flit_ftype};
        wr_ptr <= wr_ptr + 1'b1;
        count  <= count + 1'b1;
      end else if (!do_write && do_pop) begin
        rd_ptr <= rd_ptr + 1'b1;
        count  <= count - 1'b1;
      end else if (do_write && do_pop) begin
        mem[wr_ptr] <= {link_flit_payload, link_flit_ftype};
        wr_ptr <= wr_ptr + 1'b1;
        rd_ptr <= rd_ptr + 1'b1;
        // count unchanged: +1 for write, -1 for pop
      end
    end
  end

  assign vc_flit_out_payload = mem[rd_ptr][`FLIT_W-1:`FLIT_TYPE_W];
  assign vc_flit_out_ftype   = mem[rd_ptr][`FLIT_TYPE_W-1:0];
  assign vc_valid_out = (count > 0);
  assign fifo_full    = (count >= `VC_DEPTH);
  assign fifo_empty   = (count == 0);
  assign credit_out   = vc_pop;
endmodule
