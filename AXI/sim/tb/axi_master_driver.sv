import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

// AXI Master Driver — translates axi_transaction to pin-level AXI protocol
class axi_master_driver extends uvm_driver #(axi_transaction);

    `uvm_component_utils(axi_master_driver)

    virtual axi_if vif;
    int master_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        `uvm_info("DRV", $sformatf("M%0d driver run_phase started", master_id), UVM_NONE)
        forever begin
            axi_transaction txn;
            `uvm_info("DRV", $sformatf("M%0d waiting for item", master_id), UVM_NONE)
            seq_item_port.get_next_item(txn);
            `uvm_info("DRV", $sformatf("M%0d got item is_write=%0d addr=0x%08h",
                master_id, txn.is_write, txn.is_write ? txn.awaddr : txn.araddr), UVM_NONE)

            if (txn.is_write) begin
                drive_aw(txn);
                drive_w_burst(txn);
                wait_bresp(txn);
                if (txn.has_both) begin
                    drive_ar(txn);
                    collect_r_burst(txn);
                end
            end else begin
                drive_ar(txn);
                collect_r_burst(txn);
            end

            seq_item_port.item_done();
        end
    endtask

    task drive_aw(axi_transaction txn);
        `uvm_info("DRV", $sformatf("M%0d drive_aw addr=0x%08h", master_id, txn.awaddr), UVM_NONE)
        @(vif.drv_cb);
        vif.drv_cb.awid    <= txn.awid;
        vif.drv_cb.awaddr  <= txn.awaddr;
        vif.drv_cb.awlen   <= txn.awlen;
        vif.drv_cb.awsize  <= txn.awsize;
        vif.drv_cb.awburst <= txn.awburst;
        vif.drv_cb.awlock  <= 1'b0;
        vif.drv_cb.awcache <= txn.awcache;
        vif.drv_cb.awprot  <= txn.awprot;
        vif.drv_cb.awqos   <= txn.awqos;
        vif.drv_cb.awvalid <= 1'b1;
        `uvm_info("DRV", $sformatf("M%0d awvalid set, waiting for awready", master_id), UVM_NONE)
        @(vif.drv_cb);
        while (!vif.drv_cb.awready) begin
            `uvm_info("DRV", $sformatf("M%0d still waiting for awready (awready=%0d)",
                master_id, vif.drv_cb.awready), UVM_NONE)
            @(vif.drv_cb);
        end
        `uvm_info("DRV", $sformatf("M%0d awready received", master_id), UVM_NONE)
        vif.drv_cb.awvalid <= 1'b0;
    endtask

    task drive_w_burst(axi_transaction txn);
        `uvm_info("DRV", $sformatf("M%0d drive_w_burst len=%0d", master_id, txn.awlen), UVM_NONE)
        for (int i = 0; i <= txn.awlen; i++) begin
            @(vif.drv_cb);
            vif.drv_cb.wdata  <= txn.wdata_q[i];
            vif.drv_cb.wstrb  <= txn.wstrb_q[i];
            vif.drv_cb.wlast  <= (i == txn.awlen);
            vif.drv_cb.wvalid <= 1'b1;
            `uvm_info("DRV", $sformatf("M%0d wvalid set, waiting wready (beat=%0d)", master_id, i), UVM_NONE)
            @(vif.drv_cb);
            while (!vif.drv_cb.wready) begin
                `uvm_info("DRV", $sformatf("M%0d still waiting wready=%0d", master_id, vif.drv_cb.wready), UVM_NONE)
                @(vif.drv_cb);
            end
            `uvm_info("DRV", $sformatf("M%0d wready received (beat=%0d)", master_id, i), UVM_NONE)
        end
        vif.drv_cb.wvalid <= 1'b0;
        `uvm_info("DRV", $sformatf("M%0d drive_w_burst done", master_id), UVM_NONE)
    endtask

    task wait_bresp(axi_transaction txn);
        `uvm_info("DRV", $sformatf("M%0d waiting for bvalid", master_id), UVM_NONE)
        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.bvalid);
        `uvm_info("DRV", $sformatf("M%0d bvalid received bresp=%0d", master_id, vif.drv_cb.bresp), UVM_NONE)
        txn.bresp = vif.drv_cb.bresp;
        vif.drv_cb.bready <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.bready <= 1'b0;
    endtask

    task drive_ar(axi_transaction txn);
        `uvm_info("DRV", $sformatf("M%0d drive_ar addr=0x%08h", master_id, txn.araddr), UVM_NONE)
        @(vif.drv_cb);
        vif.drv_cb.arid    <= txn.arid;
        vif.drv_cb.araddr  <= txn.araddr;
        vif.drv_cb.arlen   <= txn.arlen;
        vif.drv_cb.arsize  <= txn.arsize;
        vif.drv_cb.arburst <= txn.arburst;
        vif.drv_cb.arlock  <= 1'b0;
        vif.drv_cb.arcache <= txn.arcache;
        vif.drv_cb.arprot  <= txn.arprot;
        vif.drv_cb.arqos   <= txn.arqos;
        vif.drv_cb.arvalid <= 1'b1;
        `uvm_info("DRV", $sformatf("M%0d arvalid set, waiting arready", master_id), UVM_NONE)
        @(vif.drv_cb);
        while (!vif.drv_cb.arready) begin
            `uvm_info("DRV", $sformatf("M%0d still waiting arready=%0d", master_id, vif.drv_cb.arready), UVM_NONE)
            @(vif.drv_cb);
        end
        `uvm_info("DRV", $sformatf("M%0d arready received", master_id), UVM_NONE)
        vif.drv_cb.arvalid <= 1'b0;
    endtask

    task collect_r_burst(axi_transaction txn);
        `uvm_info("DRV", $sformatf("M%0d collect_r_burst len=%0d", master_id, txn.arlen), UVM_NONE)
        txn.rdata_q.delete();
        txn.rresp_q.delete();
        for (int i = 0; i <= txn.arlen; i++) begin
            do begin
                @(vif.drv_cb);
            end while (!vif.drv_cb.rvalid);
            txn.rdata_q.push_back(vif.drv_cb.rdata);
            txn.rresp_q.push_back(vif.drv_cb.rresp);
            vif.drv_cb.rready <= 1'b1;
            `uvm_info("DRV", $sformatf("M%0d rbeat received (i=%0d)", master_id, i), UVM_NONE)
            @(vif.drv_cb);
            vif.drv_cb.rready <= 1'b0;
        end
        `uvm_info("DRV", $sformatf("M%0d collect_r_burst done", master_id), UVM_NONE)
    endtask

endclass : axi_master_driver
