// noc_agent.sv — UVM agent for one NOC tile (sequencer + driver + monitor)
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_agent extends uvm_component;
  `uvm_component_utils(noc_agent)

  uvm_sequencer #(axi_transaction) sequencer;
  noc_driver                        driver;
  noc_monitor                        monitor;

  uvm_analysis_port #(axi_transaction) axi_tx_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = uvm_sequencer #(axi_transaction)::type_id::create("sequencer", this);
    driver    = noc_driver::type_id::create("driver", this);
    monitor   = noc_monitor::type_id::create("monitor", this);
    axi_tx_port = new("axi_tx_port", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
    monitor.axi_tx_port.connect(axi_tx_port);
  endfunction
endclass
