import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_master_agent extends uvm_agent;

    `uvm_component_utils(axi_master_agent)

    uvm_sequencer #(axi_transaction) sequencer;
    axi_master_driver driver;
    axi_master_monitor monitor;

    int master_id = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer#(axi_transaction)::type_id::create("sequencer", this);
        driver    = axi_master_driver::type_id::create("driver", this);
        monitor   = axi_master_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        driver.master_id = master_id;
        monitor.ap.connect(null);  // Connected in env
    endfunction

endclass : axi_master_agent
