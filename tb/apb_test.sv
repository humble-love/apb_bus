// APB UVM Tests
import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;

// ---------------------------------------------------------------
// Base Test
// ---------------------------------------------------------------
class apb_base_test extends uvm_test;

    `uvm_component_utils(apb_base_test)

    apb_env env;
    virtual apb_if vif;

    function new(string name = "apb_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = apb_env::type_id::create("env", this);
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("TEST", "Virtual interface not set")
        env.vif = vif;
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

endclass : apb_base_test

// ---------------------------------------------------------------
// Sanity Test
// ---------------------------------------------------------------
class apb_sanity_test extends apb_base_test;

    `uvm_component_utils(apb_sanity_test)

    function new(string name = "apb_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_sanity_seq seq;
        phase.raise_objection(this);
        seq = apb_sanity_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_sanity_test

// ---------------------------------------------------------------
// Random Test
// ---------------------------------------------------------------
class apb_random_test extends apb_base_test;

    `uvm_component_utils(apb_random_test)

    function new(string name = "apb_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_random_seq seq;
        phase.raise_objection(this);
        seq = apb_random_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_random_test

// ---------------------------------------------------------------
// Burst Test
// ---------------------------------------------------------------
class apb_burst_test extends apb_base_test;

    `uvm_component_utils(apb_burst_test)

    function new(string name = "apb_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_burst_seq seq;
        phase.raise_objection(this);
        seq = apb_burst_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_burst_test

// ---------------------------------------------------------------
// Error Test
// ---------------------------------------------------------------
class apb_error_test extends apb_base_test;

    `uvm_component_utils(apb_error_test)

    function new(string name = "apb_error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_slave_err_seq seq;
        phase.raise_objection(this);
        seq = apb_slave_err_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_error_test
