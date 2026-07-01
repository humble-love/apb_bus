// noc_test.sv — NOC test classes
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_base_test extends uvm_test;
  `uvm_component_utils(noc_base_test)

  noc_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = noc_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
endclass

class noc_sanity_test extends noc_base_test;
  `uvm_component_utils(noc_sanity_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    noc_sanity_sequence seq;
    `uvm_info("TB", "NOC sanity test — neighbor write (0,0) → (1,0)", UVM_NONE)
    phase.raise_objection(this);
    seq = noc_sanity_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    `uvm_info("TB", "Sanity test passed.", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass

class noc_rr_test extends noc_base_test;
  `uvm_component_utils(noc_rr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    noc_rr_sequence seq;
    `uvm_info("TB", "NOC random test — 10 random transactions", UVM_NONE)
    phase.raise_objection(this);
    seq = noc_rr_sequence::type_id::create("seq");
    seq.start(env.agent.sequencer);
    `uvm_info("TB", "Random test passed.", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
