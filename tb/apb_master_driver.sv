// APB Master UVM Driver
// Gets transactions from sequencer, drives txn_* stimulus and req/gnt handshake

class apb_master_driver extends uvm_driver #(apb_pkg::apb_transaction);

    `uvm_component_utils(apb_master_driver)

    virtual apb_if vif;
    int master_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_pkg::apb_transaction txn;

        forever begin
            seq_item_port.get_next_item(txn);

            // Drive stimulus
            vif.drv_cb.txn_addr[master_id]  <= txn.addr;
            vif.drv_cb.txn_wdata[master_id] <= txn.data;
            vif.drv_cb.txn_write[master_id] <= txn.rw;
            vif.drv_cb.txn_req[master_id]   <= 1'b1;

            // Wait for gnt
            while (!vif.drv_cb.gnt[master_id])
                @(vif.drv_cb);

            // Clear txn_req after grant
            vif.drv_cb.txn_req[master_id] <= 1'b0;

            // Wait for pready (transaction complete)
            while (!vif.drv_cb.pready)
                @(vif.drv_cb);

            // Capture read data
            if (!txn.rw)
                txn.data = vif.drv_cb.prdata;

            @(vif.drv_cb);  // one extra cycle between transactions
            seq_item_port.item_done();
        end
    endtask

endclass : apb_master_driver
