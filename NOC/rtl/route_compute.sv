// route_compute.sv — XY dimension-order routing
module route_compute #(
  parameter int MESH_X = 8,
  parameter int MESH_Y = 8
) (
  input  logic [3:0] src_x,
  input  logic [3:0] src_y,
  input  logic [3:0] dst_x,
  input  logic [3:0] dst_y,
  input  logic       port_disable [5],  // per-port disable for boundary tiles
  output logic [4:0] next_port           // one-hot: {L,W,E,S,N}
);
  import noc_config_pkg::*;

  logic signed [4:0] dx, dy;

  assign dx = dst_x - src_x;
  assign dy = dst_y - src_y;

  always_comb begin
    next_port = 5'b00000;
    if (dx == 0 && dy == 0)
      next_port[PORT_LOCAL] = 1'b1;
    else if (dx > 0)
      next_port[PORT_EAST]  = 1'b1;
    else if (dx < 0)
      next_port[PORT_WEST]  = 1'b1;
    else if (dy > 0)
      next_port[PORT_NORTH] = 1'b1;
    else if (dy < 0)
      next_port[PORT_SOUTH] = 1'b1;
  end
endmodule
