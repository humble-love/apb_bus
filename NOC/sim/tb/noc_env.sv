// noc_env.sv — UVM environment for 64-tile NOC mesh
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_env extends uvm_env;
  `uvm_component_utils(noc_env)

  noc_agent      agent;
  noc_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = noc_agent::type_id::create("agent", this);
    scoreboard = noc_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.axi_tx_port.connect(scoreboard.axi_lstnr.imp);
  endfunction
endclass
