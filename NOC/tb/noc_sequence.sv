// noc_sequence.sv — NOC test sequence library
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_sanity_sequence extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(noc_sanity_sequence)

  function new(string name = "noc_sanity_sequence");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    int sx, sy, dx, dy;

    // Test: Neighbor writes across west→east tiles
    for (int y = 0; y < 8; y++) begin
      for (int x = 0; x < 7; x++) begin
        tx = axi_transaction::type_id::create("tx");
        tx.is_write = 1;
        tx.addr = {3'b0, y[2:0], x[2:0]+3'd1, 3'b0, y[2:0], x[2:0], 6'h00};
        tx.id   = {x[2:0], y[2:0]};
        tx.len  = 0;
        tx.burst = 2'b01;
        tx.size = 3'd6;
        tx.qos  = 4'b0010;
        start_item(tx);
        finish_item(tx);
        `uvm_info("SANITY", $sformatf("Tx(%0d,%0d)->(%0d,%0d)", x,y,x+1,y), UVM_MEDIUM)
      end
    end
  endtask
endclass

class noc_rr_sequence extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(noc_rr_sequence)

  function new(string name = "noc_rr_sequence");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    for (int i = 0; i < 1000; i++) begin
      tx = axi_transaction::type_id::create("tx");
      tx.is_write = $urandom_range(0,1);
      tx.addr = $urandom_range(0, 32'h1FFFFFF);
      tx.id   = $urandom_range(0, 255);
      tx.len  = $urandom_range(0, 15);
      tx.burst = 2'b01;
      tx.size = 3'd6;
      tx.qos  = $urandom_range(0, 15);
      start_item(tx);
      finish_item(tx);
    end
  endtask
endclass
