// route_compute.sv — XY dimension-order routing
module route_compute #(
  parameter int MESH_X = 8,
  parameter int MESH_Y = 8
) (
  input  logic [3:0]                 src_x,
  input  logic [3:0]                 src_y,
  input  logic [3:0]                 dst_x,
  input  logic [3:0]                 dst_y,
  output noc_config_pkg::port_dir_t  next_port
);
  import noc_config_pkg::*;

  logic signed [4:0] dx, dy;

  assign dx = dst_x - src_x;
  assign dy = dst_y - src_y;

  always_comb begin
    if (dx == 0 && dy == 0)
      next_port = PORT_LOCAL;
    else if (dx > 0)
      next_port = PORT_EAST;
    else if (dx < 0)
      next_port = PORT_WEST;
    else if (dy > 0)
      next_port = PORT_SOUTH;   // larger Y = going down
    else
      next_port = PORT_NORTH;   // smaller Y = going up
  end
endmodule
