// ni_read_unpacker.v — Flit stream to AXI4 R channel
// Receives read response: HEADER (is_read=1) -> captures axid/rid
// followed by BODY/TAIL flits -> captures data -> drives R channel
`include "noc_config.vh"
`include "noc_flit.vh"

module ni_read_unpacker #(
  parameter DATA_W   = 512,
  parameter AXI_ID_W = 8
) (
  input  wire        clk,
  input  wire        rst_n,

  input  wire [`FLIT_PAYLOAD_W-1:0] flit_in_payload,
  input  wire [1:0]                 flit_in_ftype,
  input  wire        flit_valid,
  output wire        flit_ready,

  output wire        rvalid,
  input  wire        rready,
  output wire [AXI_ID_W-1:0] rid,
  output wire [DATA_W-1:0]   rdata,
  output wire [1:0]          rresp,
  output wire                rlast
);

  reg r_pending;
  reg [7:0] r_id;
  reg [DATA_W-1:0] r_data;
  reg r_last;

  assign flit_ready = !r_pending || rready;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_pending <= 1'b0;
      r_id      <= {8{1'b0}};
      r_data    <= {DATA_W{1'b0}};
      r_last    <= 1'b0;
    end else begin
      // HEADER: capture response transaction ID
      if (flit_valid && flit_ready && flit_in_ftype == `FLIT_HEADER) begin
        r_id <= `FLIT_HDR_AXID(flit_in_payload);
      end
      // BODY/TAIL: capture read data from payload
      if (flit_valid && flit_ready &&
          (flit_in_ftype == `FLIT_BODY || flit_in_ftype == `FLIT_TAIL)) begin
        r_data    <= {2'b00, flit_in_payload};  // 510-bit payload -> 512-bit rdata
        r_last    <= (flit_in_ftype == `FLIT_TAIL);
        r_pending <= 1'b1;
      end else if (rready && r_pending) begin
        r_pending <= 1'b0;
      end
    end
  end

  assign rvalid = r_pending;
  assign rid    = r_id;
  assign rdata  = r_data;
  assign rresp  = 2'b00;
  assign rlast  = r_last;
endmodule
