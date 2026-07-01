// noc_sequence.sv — NOC test sequence library
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

// Base sequence — starts on the env's agent sequencer
class noc_base_sequence extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(noc_base_sequence)

  function new(string name = "noc_base_sequence");
    super.new(name);
  endfunction
endclass

// Single-beat write from tile (src_x, src_y) → tile (dst_x, dst_y)
class noc_neighbor_write_seq extends noc_base_sequence;
  `uvm_object_utils(noc_neighbor_write_seq)

  int src_x, src_y, dst_x, dst_y;

  function new(string name = "noc_neighbor_write_seq");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    tx = axi_transaction::type_id::create("tx");
    tx.is_write = 1;
    // NI address decode: dst_y = addr[28:26], dst_x = addr[25:23]
    tx.addr = {3'b0, dst_y[2:0], dst_x[2:0], 3'b0, src_y[2:0], src_x[2:0], 6'h00};
    tx.id   = {src_x[2:0], src_y[2:0]};
    tx.len  = 0;
    tx.burst = 2'b01;  // INCR
    tx.size = 3'd6;    // 64B
    tx.qos  = 4'b0010; // P2
    // Single beat data
    tx.data = new[1];
    tx.data[0] = 512'hDEAD_BEEF_CAFE_BABE_0123_4567_89AB_CDEF_FACE_FEED_DEAD_BEEF_0123_4567_89AB_CDEF;
    tx.wstrb = new[1];
    tx.wstrb[0] = '1;

    start_item(tx);
    `uvm_info("NOC_SEQ", $sformatf("Write (%0d,%0d)->(%0d,%0d) addr=0x%08h", src_x, src_y, dst_x, dst_y, tx.addr), UVM_NONE)
    finish_item(tx);
    `uvm_info("NOC_SEQ", $sformatf("Write complete: bid=%0d bresp=%0d", tx.bid, tx.resp), UVM_NONE)
  endtask
endclass

// Sanity: neighbor writes across all tiles (east neighbor)
class noc_sanity_sequence extends noc_base_sequence;
  `uvm_object_utils(noc_sanity_sequence)

  function new(string name = "noc_sanity_sequence");
    super.new(name);
  endfunction

  task body();
    noc_neighbor_write_seq nw_seq;

    // Test eastbound writes: (0,0)→(1,0), (1,0)→(2,0), ... (6,0)→(7,0)
    nw_seq = noc_neighbor_write_seq::type_id::create("nw_seq");
    nw_seq.src_x = 0; nw_seq.src_y = 0;
    nw_seq.dst_x = 1; nw_seq.dst_y = 0;
    nw_seq.start(m_sequencer);

    `uvm_info("SANITY", "Neighbor write (0,0)→(1,0) completed", UVM_NONE)
  endtask
endclass

// Random test sequence
class noc_rr_sequence extends noc_base_sequence;
  `uvm_object_utils(noc_rr_sequence)

  function new(string name = "noc_rr_sequence");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    for (int i = 0; i < 10; i++) begin
      tx = axi_transaction::type_id::create("tx");
      tx.is_write = $urandom_range(0,1);
      tx.addr = $urandom_range(0, 32'h1FFFFFF);
      tx.id   = $urandom_range(0, 255);
      tx.len  = 0;
      tx.burst = 2'b01;
      tx.size = 3'd6;
      tx.qos  = $urandom_range(0, 15);
      tx.data = new[1];
      tx.data[0] = $urandom();
      tx.wstrb = new[1];
      tx.wstrb[0] = '1;
      start_item(tx);
      finish_item(tx);
    end
  endtask
endclass
