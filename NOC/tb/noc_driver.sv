// noc_driver.sv — AXI4 master driver (BFM) for NOC mesh
import uvm_pkg::*;
import noc_pkg::*;
`include "uvm_macros.svh"

class noc_driver extends uvm_driver #(axi_transaction);
  `uvm_component_utils(noc_driver)

  virtual noc_axi_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual noc_axi_if)::get(this, "", "axi_vif", vif))
      `uvm_fatal("NOC_DRV", "Virtual interface not found in config DB")
  endfunction

  task run_phase(uvm_phase phase);
    axi_transaction tx;
    forever begin
      seq_item_port.get_next_item(tx);
      if (tx.is_write)
        drive_write(tx);
      else
        drive_read(tx);
      seq_item_port.item_done();
    end
  endtask

  task drive_write(axi_transaction tx);
    `uvm_info("NOC_DRV", "drive_write: starting AW+W", UVM_NONE)
    // Wait for reset to be deasserted
    @(posedge vif.rst_n);
    @(posedge vif.clk);
    // Drive AW and W channels in parallel
    // awready is initially 1 (aw_buf_empty), so AW handshake completes on first posedge
    vif.awvalid <= 1'b1;
    vif.awaddr  <= tx.addr;
    vif.awid    <= tx.id;
    vif.awlen   <= tx.len;
    vif.awburst <= tx.burst;
    vif.awsize  <= tx.size;
    vif.awlock  <= 4'h0;
    vif.awcache <= 2'h0;
    vif.awqos   <= tx.qos;
    vif.wvalid <= 1'b1;
    if (tx.data.size() > 0)
      vif.wdata <= tx.data[0];
    else
      vif.wdata <= '0;
    if (tx.wstrb.size() > 0)
      vif.wstrb <= tx.wstrb[0];
    else
      vif.wstrb <= '1;
    vif.wlast  <= 1'b1;

    // AW handshake: awready was 1, so it completes on the first posedge
    @(posedge vif.clk);
    vif.awvalid <= 1'b0;

    // Wait for W handshake (wready goes high when FSM reaches ST_BODY)
    while (!vif.wready) @(posedge vif.clk);
    `uvm_info("NOC_DRV", "drive_write: W handshake done", UVM_NONE)
    vif.wvalid <= 1'b0;
    vif.wlast  <= 1'b0;

    // B channel — wait for response
    vif.bready <= 1'b1;
    `uvm_info("NOC_DRV", "drive_write: waiting for bvalid", UVM_NONE)
    while (!vif.bvalid) @(posedge vif.clk);
    `uvm_info("NOC_DRV", "drive_write: B response received", UVM_NONE)
    tx.bid   = vif.bid;
    tx.resp = vif.bresp;
    vif.bready <= 1'b0;
  endtask

  task drive_read(axi_transaction tx);
    // AR channel
    vif.arvalid <= 1'b1;
    vif.araddr  <= tx.addr;
    vif.arid    <= tx.id;
    vif.arlen   <= tx.len;
    vif.arburst <= tx.burst;
    vif.arsize  <= tx.size;
    vif.arlock  <= 4'h0;
    vif.arcache <= 2'h0;
    vif.arqos   <= tx.qos;
    @(posedge vif.clk iff (vif.arready));
    vif.arvalid <= 1'b0;

    // R channel
    vif.rready <= 1'b1;
    @(posedge vif.clk iff (vif.rvalid));
    tx.bid   = vif.rid;
    tx.rdata = new[1];
    tx.rdata[0] = vif.rdata;
    if (!vif.rlast) begin
      `uvm_warning("NOC_DRV", "Multi-beat reads not yet supported")
    end
    vif.rready <= 1'b0;
  endtask
endclass
