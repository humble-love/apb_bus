// APB UVM Environment — 2 master agents + scoreboard

class apb_env extends uvm_env;

    `uvm_component_utils(apb_env)

    apb_master_agent  agent_m0;
    apb_master_agent  agent_m1;
    apb_scoreboard    scb;

    virtual apb_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent_m0 = apb_master_agent::type_id::create("agent_m0", this);
        agent_m0.vif = vif;
        agent_m0.master_id = 0;
        agent_m0.is_active = UVM_ACTIVE;

        agent_m1 = apb_master_agent::type_id::create("agent_m1", this);
        agent_m1.vif = vif;
        agent_m1.master_id = 1;
        agent_m1.is_active = UVM_ACTIVE;

        scb = apb_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent_m0.ap.connect(scb.analysis_export);
        agent_m1.ap.connect(scb.analysis_export);
    endfunction

endclass : apb_env
