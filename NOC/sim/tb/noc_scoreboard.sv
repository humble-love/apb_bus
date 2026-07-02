// noc_scoreboard.sv — NOC scoreboard with flit tracking
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

// Forward declare to resolve circular dependency: listener ↔ scoreboard
typedef class noc_scoreboard;

class axi_tx_listener extends uvm_component;
  `uvm_component_utils(axi_tx_listener)
  uvm_analysis_imp #(axi_transaction, axi_tx_listener) imp;
  noc_scoreboard sb;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
    // sb set by scoreboard in build_phase
  endfunction
  function void write(axi_transaction tx);
    if (sb != null) sb.write_axi_tx(tx);
  endfunction
endclass

class flit_tx_listener extends uvm_component;
  `uvm_component_utils(flit_tx_listener)
  uvm_analysis_imp #(flit_transaction, flit_tx_listener) imp;
  noc_scoreboard sb;
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    imp = new("imp", this);
  endfunction
  function void write(flit_transaction ftx);
    if (sb != null) sb.write_flit_tx(ftx);
  endfunction
endclass

class noc_scoreboard extends uvm_component;
  `uvm_component_utils(noc_scoreboard)

  axi_tx_listener   axi_lstnr;
  flit_tx_listener  flit_lstnr;

  axi_transaction expected_q[$];
  int matched, mismatched;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_lstnr  = axi_tx_listener::type_id::create("axi_lstnr", this);
    flit_lstnr = flit_tx_listener::type_id::create("flit_lstnr", this);
    axi_lstnr.sb  = this;
    flit_lstnr.sb = this;
  endfunction

  function void write_axi_tx(axi_transaction tx);
    expected_q.push_back(tx);
  endfunction

  function void write_flit_tx(flit_transaction ftx);
    foreach (expected_q[i]) begin
      if (expected_q[i].id == ftx.src_id) begin
        matched++;
        expected_q.delete(i);
        return;
      end
    end
    mismatched++;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_name(), $sformatf("Scoreboard: matched=%0d mismatched=%0d pending=%0d",
             matched, mismatched, expected_q.size()), UVM_LOW)
  endfunction
endclass
