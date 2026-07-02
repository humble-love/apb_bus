// route_compute.v — XY dimension-order routing
`include "noc_config.vh"

module route_compute #(
  parameter MESH_X = 8,
  parameter MESH_Y = 8
) (
  input  wire [3:0]             src_x,
  input  wire [3:0]             src_y,
  input  wire [3:0]             dst_x,
  input  wire [3:0]             dst_y,
  output reg  [`PORT_DIR_W-1:0] next_port
);

  wire signed [4:0] dx, dy;

  assign dx = dst_x - src_x;
  assign dy = dst_y - src_y;

  always @(*) begin
    if (dx == 0 && dy == 0)
      next_port = `PORT_LOCAL;
    else if (dx > 0)
      next_port = `PORT_EAST;
    else if (dx < 0)
      next_port = `PORT_WEST;
    else if (dy > 0)
      next_port = `PORT_SOUTH;   // larger Y = going down
    else
      next_port = `PORT_NORTH;   // smaller Y = going up
  end
endmodule
