import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_slave_monitor extends uvm_monitor;

    `uvm_component_utils(axi_slave_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;
    int slave_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for slave monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_aw();
            monitor_ar();
        join
    endtask

    task monitor_aw();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                axi_transaction t = axi_transaction::type_id::create("t");
                t.is_write = 1'b1;
                t.awid = vif.mon_cb.awid;
                t.awaddr = vif.mon_cb.awaddr;
                t.awlen = vif.mon_cb.awlen;
                t.awsize = vif.mon_cb.awsize;
                t.awburst = vif.mon_cb.awburst;
                t.wdata_q.delete(); t.wstrb_q.delete();
                for (int i = 0; i <= t.awlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
                    t.wdata_q.push_back(vif.mon_cb.wdata);
                    t.wstrb_q.push_back(vif.mon_cb.wstrb);
                end
                do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
                t.bresp = vif.mon_cb.bresp;
                ap.write(t);
            end
        end
    endtask

    task monitor_ar();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                axi_transaction t = axi_transaction::type_id::create("t");
                t.is_write = 1'b0;
                t.arid = vif.mon_cb.arid;
                t.araddr = vif.mon_cb.araddr;
                t.arlen = vif.mon_cb.arlen;
                t.arsize = vif.mon_cb.arsize;
                t.arburst = vif.mon_cb.arburst;
                t.rdata_q.delete(); t.rresp_q.delete();
                for (int i = 0; i <= t.arlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
                    t.rdata_q.push_back(vif.mon_cb.rdata);
                    t.rresp_q.push_back(vif.mon_cb.rresp);
                end
                ap.write(t);
            end
        end
    endtask

endclass : axi_slave_monitor
