import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_env extends uvm_env;

    `uvm_component_utils(axi_env)

    axi_master_agent master_agent[2];
    axi_scoreboard   scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 2; i++) begin
            master_agent[i] = axi_master_agent::type_id::create(
                $sformatf("master_agent[%0d]", i), this);
            master_agent[i].master_id = i;
        end
        scoreboard = axi_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        master_agent[0].monitor.ap.connect(scoreboard.m0_export);
        master_agent[1].monitor.ap.connect(scoreboard.m1_export);
    endfunction

endclass : axi_env
