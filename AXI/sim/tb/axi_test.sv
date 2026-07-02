import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_base_test extends uvm_test;

    `uvm_component_utils(axi_base_test)

    axi_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

endclass : axi_base_test

// ---------------------------------------------------------------
// Specific tests
// ---------------------------------------------------------------

class axi_sanity_test extends axi_base_test;
    `uvm_component_utils(axi_sanity_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_sanity_seq seq0, seq1;
        `uvm_info("TEST", "axi_sanity_test run_phase starting", UVM_NONE)
        phase.raise_objection(this);
        `uvm_info("TEST", "Objection raised, starting sequences", UVM_NONE)
        fork
            begin
                seq0 = axi_sanity_seq::type_id::create("seq0");
                `uvm_info("TEST", "Starting seq0 on agent[0]", UVM_NONE)
                seq0.start(env.master_agent[0].sequencer);
                `uvm_info("TEST", "seq0 completed", UVM_NONE)
            end
            begin
                seq1 = axi_sanity_seq::type_id::create("seq1");
                `uvm_info("TEST", "Starting seq1 on agent[1]", UVM_NONE)
                seq1.start(env.master_agent[1].sequencer);
                `uvm_info("TEST", "seq1 completed", UVM_NONE)
            end
        join
        `uvm_info("TEST", "Both sequences done, dropping objection", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass : axi_sanity_test

class axi_random_test extends axi_base_test;
    `uvm_component_utils(axi_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_random_seq seq = axi_random_seq::type_id::create("seq");
        seq.num_txn = 20;
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_random_test

class axi_burst_test extends axi_base_test;
    `uvm_component_utils(axi_burst_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_burst_seq seq = axi_burst_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_burst_test

class axi_narrow_test extends axi_base_test;
    `uvm_component_utils(axi_narrow_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_narrow_seq seq = axi_narrow_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_narrow_test

class axi_ooo_test extends axi_base_test;
    `uvm_component_utils(axi_ooo_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_out_of_order_seq seq = axi_out_of_order_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_ooo_test

class axi_concurrent_test extends axi_base_test;
    `uvm_component_utils(axi_concurrent_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_concurrent_seq seq0, seq1;
        phase.raise_objection(this);
        fork
            begin
                seq0 = axi_concurrent_seq::type_id::create("seq0");
                seq0.start(env.master_agent[0].sequencer);
            end
            begin
                seq1 = axi_concurrent_seq::type_id::create("seq1");
                seq1.start(env.master_agent[1].sequencer);
            end
        join
        phase.drop_objection(this);
    endtask
endclass : axi_concurrent_test

class axi_error_test extends axi_base_test;
    `uvm_component_utils(axi_error_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_error_seq seq = axi_error_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_error_test
