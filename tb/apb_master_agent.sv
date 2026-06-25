import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;

// APB Master UVM Agent — Sequencer + Driver + Monitor for one master

class apb_master_agent extends uvm_agent;

    `uvm_component_utils(apb_master_agent)

    apb_master_driver                                 driver;
    apb_master_monitor                                monitor;
    uvm_sequencer #(apb_pkg::apb_transaction)         sequencer;

    virtual apb_if vif;
    int master_id = 0;

    uvm_analysis_port #(apb_pkg::apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        monitor = apb_master_monitor::type_id::create("monitor", this);
        monitor.vif = vif;
        ap = monitor.ap;

        if (get_is_active() == UVM_ACTIVE) begin
            driver = apb_master_driver::type_id::create("driver", this);
            sequencer = uvm_sequencer #(apb_pkg::apb_transaction)::type_id::create("sequencer", this);
            driver.vif = vif;
            driver.master_id = master_id;
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass : apb_master_agent
