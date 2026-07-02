// noc_monitor.sv — AXI4 monitor for NOC mesh verification
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_monitor extends uvm_monitor;
  `uvm_component_utils(noc_monitor)

  virtual noc_axi_if vif;
  uvm_analysis_port #(axi_transaction) axi_tx_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_tx_port = new("axi_tx_port", this);
    if (!uvm_config_db #(virtual noc_axi_if)::get(this, "", "axi_vif", vif))
      `uvm_warning("NOC_MON", "Virtual interface not found in config DB")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      axi_transaction tx;
      @(posedge vif.clk);

      // Detect write (AW valid + W valid)
      if (vif.awvalid && vif.awready) begin
        tx = axi_transaction::type_id::create("tx");
        tx.is_write = 1;
        tx.addr  = vif.awaddr;
        tx.id    = vif.awid;
        tx.len   = vif.awlen;
        tx.burst = vif.awburst;
        tx.size  = vif.awsize;
        tx.qos   = vif.awqos;
        `uvm_info("NOC_MON", $sformatf("Write AW: addr=%08h id=%0d", tx.addr, tx.id), UVM_MEDIUM)
        // Wait for W handshake
        while (!(vif.wvalid && vif.wready)) @(posedge vif.clk);
        tx.data = new[1];
        tx.data[0] = vif.wdata;
        tx.wstrb = new[1];
        tx.wstrb[0] = vif.wstrb;
        // Wait for B response
        while (!(vif.bvalid && vif.bready)) @(posedge vif.clk);
        tx.resp = vif.bresp;
        tx.bid   = vif.bid;
        axi_tx_port.write(tx);
        `uvm_info("NOC_MON", $sformatf("Write complete: bid=%0d bresp=%0d", tx.bid, tx.resp), UVM_MEDIUM)
      end

      // Detect read (AR valid)
      if (vif.arvalid && vif.arready) begin
        tx = axi_transaction::type_id::create("tx");
        tx.is_write = 0;
        tx.addr  = vif.araddr;
        tx.id    = vif.arid;
        tx.len   = vif.arlen;
        tx.burst = vif.arburst;
        tx.size  = vif.arsize;
        tx.qos   = vif.arqos;
        `uvm_info("NOC_MON", $sformatf("Read AR: addr=%08h id=%0d", tx.addr, tx.id), UVM_MEDIUM)
        // Wait for R response
        while (!(vif.rvalid && vif.rready)) @(posedge vif.clk);
        tx.rdata = new[1];
        tx.rdata[0] = vif.rdata;
        axi_tx_port.write(tx);
        `uvm_info("NOC_MON", $sformatf("Read complete: rid=%0d", vif.rid), UVM_MEDIUM)
      end
    end
  endtask
endclass
