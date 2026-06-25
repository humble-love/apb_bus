import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;

// APB Master UVM Monitor
// Samples APB bus and sends observed transactions to analysis port

class apb_master_monitor extends uvm_monitor;

    `uvm_component_utils(apb_master_monitor)

    virtual apb_if vif;
    uvm_analysis_port #(apb_pkg::apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        apb_pkg::apb_transaction txn;

        forever begin
            @(vif.mon_cb);

            // Detect completed transfer: PSEL + PENABLE + PREADY
            if (vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
                txn = apb_pkg::apb_transaction::type_id::create("txn");
                txn.addr = vif.mon_cb.paddr;
                txn.rw   = vif.mon_cb.pwrite;
                if (vif.mon_cb.pwrite)
                    txn.data = vif.mon_cb.pwdata;
                else
                    txn.data = vif.mon_cb.prdata;
                ap.write(txn);
            end
        end
    endtask

endclass : apb_master_monitor
