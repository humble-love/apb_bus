import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_master_monitor extends uvm_monitor;

    `uvm_component_utils(axi_master_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_aw_chan();
            monitor_ar_chan();
        join
    endtask

    task monitor_aw_chan();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                axi_transaction txn = axi_transaction::type_id::create("txn");
                txn.is_write  = 1'b1;
                txn.awid     = vif.mon_cb.awid;
                txn.awaddr   = vif.mon_cb.awaddr;
                txn.awlen    = vif.mon_cb.awlen;
                txn.awsize   = vif.mon_cb.awsize;
                txn.awburst  = vif.mon_cb.awburst;
                txn.awcache  = vif.mon_cb.awcache;
                txn.awprot   = vif.mon_cb.awprot;
                txn.awqos    = vif.mon_cb.awqos;
                // Collect W beats
                txn.wdata_q.delete();
                txn.wstrb_q.delete();
                for (int i = 0; i <= txn.awlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
                    txn.wdata_q.push_back(vif.mon_cb.wdata);
                    txn.wstrb_q.push_back(vif.mon_cb.wstrb);
                end
                // Collect B
                do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
                txn.bresp = vif.mon_cb.bresp;
                ap.write(txn);
                `uvm_info("MON", $sformatf("Observed WRITE AWID=%0d ADDR=0x%08h LEN=%0d",
                    txn.awid, txn.awaddr, txn.awlen), UVM_MEDIUM)
            end
        end
    endtask

    task monitor_ar_chan();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                axi_transaction txn = axi_transaction::type_id::create("txn");
                txn.is_write = 1'b0;
                txn.arid     = vif.mon_cb.arid;
                txn.araddr   = vif.mon_cb.araddr;
                txn.arlen    = vif.mon_cb.arlen;
                txn.arsize   = vif.mon_cb.arsize;
                txn.arburst  = vif.mon_cb.arburst;
                txn.arcache  = vif.mon_cb.arcache;
                txn.arprot   = vif.mon_cb.arprot;
                txn.arqos    = vif.mon_cb.arqos;
                // Collect R beats
                txn.rdata_q.delete();
                txn.rresp_q.delete();
                for (int i = 0; i <= txn.arlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
                    txn.rdata_q.push_back(vif.mon_cb.rdata);
                    txn.rresp_q.push_back(vif.mon_cb.rresp);
                end
                ap.write(txn);
                `uvm_info("MON", $sformatf("Observed READ ARID=%0d ADDR=0x%08h LEN=%0d",
                    txn.arid, txn.araddr, txn.arlen), UVM_MEDIUM)
            end
        end
    endtask

endclass : axi_master_monitor
