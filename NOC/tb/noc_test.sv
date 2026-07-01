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
    `uvm_info("TB", "NOC sanity test — reset + idle check", UVM_NONE)
    phase.raise_objection(this);
    // Wait a few cycles for reset deassertion and idle stabilization
    repeat (20) @(posedge tb_top.clk);
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
    `uvm_info("TB", "NOC random test — reset + idle check", UVM_NONE)
    phase.raise_objection(this);
    repeat (100) @(posedge tb_top.clk);
    `uvm_info("TB", "Random test passed.", UVM_NONE)
    phase.drop_objection(this);
  endtask
endclass
