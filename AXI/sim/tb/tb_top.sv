// AXI4-Full UVM Testbench Top
// DUT: axi_interconnect + axi_slave_sram + axi_slave_dfi
// UVM agents drive AXI interfaces -> bridge to packed interconnect ports
// 256-bit data, 32-bit address, 8-bit ID, 2 masters, 2 slaves

`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_pkg::*;

module tb_top;

    localparam int DATA_W     = 256;
    localparam int ADDR_W     = 32;
    localparam int ID_W       = 8;
    localparam int NUM_MASTERS = 2;
    localparam int NUM_SLAVES  = 2;

    // Clock/Reset
    logic aclk;
    logic aresetn;

    initial aclk = 1'b0;
    always #2.5 aclk = ~aclk;  // 200 MHz

    // ============================================================
    // AXI Interface instances - one per UVM master agent
    // ============================================================
    axi_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W))
        m_if [NUM_MASTERS] (.aclk(aclk), .aresetn(aresetn));

    // ============================================================
    // Packed signal arrays -> interconnect ports
    // Interconnect uses [NUM_MASTERS-1:0][WIDTH-1:0] packed arrays
    // ============================================================

    // Master-side AW
    logic [NUM_MASTERS-1:0][ID_W-1:0]     m_awid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0]   m_awaddr;
    logic [NUM_MASTERS-1:0][7:0]          m_awlen;
    logic [NUM_MASTERS-1:0][2:0]          m_awsize;
    logic [NUM_MASTERS-1:0][1:0]          m_awburst;
    logic [NUM_MASTERS-1:0]               m_awvalid;
    logic [NUM_MASTERS-1:0]               m_awready;
    // Master-side W
    logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata;
    logic [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb;
    logic [NUM_MASTERS-1:0]               m_wlast;
    logic [NUM_MASTERS-1:0]               m_wvalid;
    logic [NUM_MASTERS-1:0]               m_wready;
    // Master-side B
    logic [NUM_MASTERS-1:0][ID_W-1:0]     m_bid;
    logic [NUM_MASTERS-1:0][1:0]          m_bresp;
    logic [NUM_MASTERS-1:0]               m_bvalid;
    logic [NUM_MASTERS-1:0]               m_bready;
    // Master-side AR
    logic [NUM_MASTERS-1:0][ID_W-1:0]     m_arid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0]   m_araddr;
    logic [NUM_MASTERS-1:0][7:0]          m_arlen;
    logic [NUM_MASTERS-1:0][2:0]          m_arsize;
    logic [NUM_MASTERS-1:0][1:0]          m_arburst;
    logic [NUM_MASTERS-1:0]               m_arvalid;
    logic [NUM_MASTERS-1:0]               m_arready;
    // Master-side R
    logic [NUM_MASTERS-1:0][ID_W-1:0]     m_rid;
    logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_rdata;
    logic [NUM_MASTERS-1:0][1:0]          m_rresp;
    logic [NUM_MASTERS-1:0]               m_rlast;
    logic [NUM_MASTERS-1:0]               m_rvalid;
    logic [NUM_MASTERS-1:0]               m_rready;

    // Slave-side packed arrays
    logic [NUM_SLAVES-1:0][ID_W-1:0]      s_awid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]    s_awaddr;
    logic [NUM_SLAVES-1:0][7:0]           s_awlen;
    logic [NUM_SLAVES-1:0][2:0]           s_awsize;
    logic [NUM_SLAVES-1:0][1:0]           s_awburst;
    logic [NUM_SLAVES-1:0]                s_awvalid;
    logic [NUM_SLAVES-1:0]                s_awready;
    logic [NUM_SLAVES-1:0][DATA_W-1:0]    s_wdata;
    logic [NUM_SLAVES-1:0][DATA_W/8-1:0]  s_wstrb;
    logic [NUM_SLAVES-1:0]                s_wlast;
    logic [NUM_SLAVES-1:0]                s_wvalid;
    logic [NUM_SLAVES-1:0]                s_wready;
    logic [NUM_SLAVES-1:0][ID_W-1:0]      s_bid;
    logic [NUM_SLAVES-1:0][1:0]           s_bresp;
    logic [NUM_SLAVES-1:0]                s_bvalid;
    logic [NUM_SLAVES-1:0]                s_bready;
    logic [NUM_SLAVES-1:0][ID_W-1:0]      s_arid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]    s_araddr;
    logic [NUM_SLAVES-1:0][7:0]           s_arlen;
    logic [NUM_SLAVES-1:0][2:0]           s_arsize;
    logic [NUM_SLAVES-1:0][1:0]           s_arburst;
    logic [NUM_SLAVES-1:0]                s_arvalid;
    logic [NUM_SLAVES-1:0]                s_arready;
    logic [NUM_SLAVES-1:0][ID_W-1:0]      s_rid;
    logic [NUM_SLAVES-1:0][DATA_W-1:0]    s_rdata;
    logic [NUM_SLAVES-1:0][1:0]           s_rresp;
    logic [NUM_SLAVES-1:0]                s_rlast;
    logic [NUM_SLAVES-1:0]                s_rvalid;
    logic [NUM_SLAVES-1:0]                s_rready;

    // ============================================================
    // Connect UVM interfaces <-> packed arrays
    // Direction: master drives AW/W/AR, interconnect drives B/R
    // ============================================================
    generate
        genvar mi;
        for (mi = 0; mi < NUM_MASTERS; mi++) begin : m_conn
            // AW: master -> interconnect
            assign m_awid[mi]   = m_if[mi].awid;
            assign m_awaddr[mi] = m_if[mi].awaddr;
            assign m_awlen[mi]  = m_if[mi].awlen;
            assign m_awsize[mi] = m_if[mi].awsize;
            assign m_awburst[mi]= m_if[mi].awburst;
            assign m_awvalid[mi]= m_if[mi].awvalid;
            assign m_if[mi].awready = m_awready[mi];

            // W: master -> interconnect
            assign m_wdata[mi]  = m_if[mi].wdata;
            assign m_wstrb[mi]  = m_if[mi].wstrb;
            assign m_wlast[mi]  = m_if[mi].wlast;
            assign m_wvalid[mi] = m_if[mi].wvalid;
            assign m_if[mi].wready = m_wready[mi];

            // B: interconnect -> master
            assign m_if[mi].bid    = m_bid[mi];
            assign m_if[mi].bresp  = m_bresp[mi];
            assign m_if[mi].bvalid = m_bvalid[mi];
            assign m_bready[mi]    = m_if[mi].bready;

            // AR: master -> interconnect
            assign m_arid[mi]   = m_if[mi].arid;
            assign m_araddr[mi] = m_if[mi].araddr;
            assign m_arlen[mi]  = m_if[mi].arlen;
            assign m_arsize[mi] = m_if[mi].arsize;
            assign m_arburst[mi]= m_if[mi].arburst;
            assign m_arvalid[mi]= m_if[mi].arvalid;
            assign m_if[mi].arready = m_arready[mi];

            // R: interconnect -> master
            assign m_if[mi].rid    = m_rid[mi];
            assign m_if[mi].rdata  = m_rdata[mi];
            assign m_if[mi].rresp  = m_rresp[mi];
            assign m_if[mi].rlast  = m_rlast[mi];
            assign m_if[mi].rvalid = m_rvalid[mi];
            assign m_rready[mi]    = m_if[mi].rready;
        end
    endgenerate

    // ============================================================
    // DFI signals
    // ============================================================
    logic [31:0]            dfi_address;
    logic [3:0]             dfi_bank;
    logic [DATA_W-1:0]      dfi_wrdata;
    logic [DATA_W/8-1:0]    dfi_wrdata_mask;
    logic                   dfi_wrdata_valid;
    logic                   dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n, dfi_act_n;
    logic [DATA_W-1:0]      dfi_rddata;
    logic                   dfi_rddata_valid;

    // ============================================================
    // DUT: AXI Interconnect
    // ============================================================
    axi_interconnect #(
        .NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
        .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)
    ) u_interconnect (
        .aclk, .aresetn,
        .m_awid, .m_awaddr, .m_awlen, .m_awsize, .m_awburst,
        .m_awvalid, .m_awready,
        .m_wdata, .m_wstrb, .m_wlast, .m_wvalid, .m_wready,
        .m_bid, .m_bresp, .m_bvalid, .m_bready,
        .m_arid, .m_araddr, .m_arlen, .m_arsize, .m_arburst,
        .m_arvalid, .m_arready,
        .m_rid, .m_rdata, .m_rresp, .m_rlast, .m_rvalid, .m_rready,
        .s_awid, .s_awaddr, .s_awlen, .s_awsize, .s_awburst,
        .s_awvalid, .s_awready,
        .s_wdata, .s_wstrb, .s_wlast, .s_wvalid, .s_wready,
        .s_bid, .s_bresp, .s_bvalid, .s_bready,
        .s_arid, .s_araddr, .s_arlen, .s_arsize, .s_arburst,
        .s_arvalid, .s_arready,
        .s_rid, .s_rdata, .s_rresp, .s_rlast, .s_rvalid, .s_rready
    );

    // ============================================================
    // Slave 0: SRAM (0x0xxx_xxxx)
    // ============================================================
    axi_slave_sram #(
        .DEPTH(1024), .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W), .STALL_PROB(0)
    ) u_slave_sram (
        .aclk, .aresetn,
        .awid(s_awid[0]), .awaddr(s_awaddr[0]),
        .awlen(s_awlen[0]), .awsize(s_awsize[0]), .awburst(s_awburst[0]),
        .awvalid(s_awvalid[0]), .awready(s_awready[0]),
        .wdata(s_wdata[0]), .wstrb(s_wstrb[0]), .wlast(s_wlast[0]),
        .wvalid(s_wvalid[0]), .wready(s_wready[0]),
        .bid(s_bid[0]), .bresp(s_bresp[0]),
        .bvalid(s_bvalid[0]), .bready(s_bready[0]),
        .arid(s_arid[0]), .araddr(s_araddr[0]),
        .arlen(s_arlen[0]), .arsize(s_arsize[0]), .arburst(s_arburst[0]),
        .arvalid(s_arvalid[0]), .arready(s_arready[0]),
        .rid(s_rid[0]), .rdata(s_rdata[0]), .rresp(s_rresp[0]),
        .rlast(s_rlast[0]), .rvalid(s_rvalid[0]), .rready(s_rready[0])
    );

    // ============================================================
    // Slave 1: DFI Bridge (0x1xxx_xxxx)
    // ============================================================
    axi_slave_dfi #(
        .ADDR_W(ADDR_W), .DATA_W(DATA_W), .ID_W(ID_W)
    ) u_slave_dfi (
        .aclk, .aresetn,
        .awid(s_awid[1]), .awaddr(s_awaddr[1]),
        .awlen(s_awlen[1]), .awsize(s_awsize[1]), .awburst(s_awburst[1]),
        .awvalid(s_awvalid[1]), .awready(s_awready[1]),
        .wdata(s_wdata[1]), .wstrb(s_wstrb[1]), .wlast(s_wlast[1]),
        .wvalid(s_wvalid[1]), .wready(s_wready[1]),
        .bid(s_bid[1]), .bresp(s_bresp[1]),
        .bvalid(s_bvalid[1]), .bready(s_bready[1]),
        .arid(s_arid[1]), .araddr(s_araddr[1]),
        .arlen(s_arlen[1]), .arsize(s_arsize[1]), .arburst(s_arburst[1]),
        .arvalid(s_arvalid[1]), .arready(s_arready[1]),
        .rid(s_rid[1]), .rdata(s_rdata[1]), .rresp(s_rresp[1]),
        .rlast(s_rlast[1]), .rvalid(s_rvalid[1]), .rready(s_rready[1]),
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_wrdata_valid(dfi_wrdata_valid),
        .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n), .dfi_act_n(dfi_act_n),
        .dfi_cke(),
        .dfi_rddata(dfi_rddata),
        .dfi_rddata_valid(dfi_rddata_valid)
    );

    // ============================================================
    // Simple DFI PHY Responder — write-backing memory + read response
    // ============================================================
    localparam DFI_tCL = 14;
    localparam DFI_MEM_DEPTH = 1024;
    logic [DATA_W-1:0] dfi_mem [0:DFI_MEM_DEPTH-1];
    logic              dfi_rd_req;
    logic              dfi_wr_cmd;
    logic [4:0]        dfi_rd_cnt;
    logic              dfi_rd_active;

    assign dfi_rd_req = !dfi_cs_n && !dfi_cas_n &&  dfi_we_n && dfi_ras_n;
    assign dfi_wr_cmd = !dfi_cs_n && !dfi_cas_n && !dfi_we_n && dfi_ras_n;

    // Write capture: store data on DFI write command
    always_ff @(posedge aclk) begin
        if (dfi_wr_cmd && dfi_wrdata_valid)
            dfi_mem[dfi_address[11:2]] <= dfi_wrdata;
    end

    // Read response timing
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            dfi_rd_active <= 1'b0;
            dfi_rd_cnt    <= '0;
        end else begin
            if (dfi_rd_req) begin
                dfi_rd_active <= 1'b1;
                dfi_rd_cnt    <= DFI_tCL;  // align with FSM timer which starts at tCL
            end else if (dfi_rd_active) begin
                if (dfi_rd_cnt > 0)
                    dfi_rd_cnt <= dfi_rd_cnt - 1;
                else
                    dfi_rd_active <= 1'b0;
            end
        end
    end

    assign dfi_rddata_valid = dfi_rd_active && (dfi_rd_cnt == 0);
    assign dfi_rddata       = dfi_mem[dfi_address[11:2]];  // read from write-backed memory

    // ============================================================
    // UVM config
    // ============================================================
    initial begin
        uvm_config_db #(virtual axi_if)::set(null, "*master_agent[0]*", "vif", m_if[0]);
        uvm_config_db #(virtual axi_if)::set(null, "*master_agent[1]*", "vif", m_if[1]);
        run_test();
    end

    // ============================================================
    // Reset
    // ============================================================
    initial begin
        aresetn = 1'b0;
        repeat (10) @(posedge aclk);
        aresetn = 1'b1;
        $display("=== TB_TOP: Reset released, test starting ===");
    end

    // ============================================================
    // Debug monitor
    // ============================================================
    always @(posedge aclk) begin
        if (aresetn) begin
            if (m_awvalid[0] || m_awvalid[1] || m_awready[0] || m_awready[1] ||
                s_awvalid[0] || s_awvalid[1] || s_awready[0] || s_awready[1])
                $display("DEBUG %0t: AW m0_v=%0d m1_v=%0d m0_r=%0d m1_r=%0d | s0_v=%0d s1_v=%0d s0_r=%0d s1_r=%0d",
                    $time, m_awvalid[0], m_awvalid[1], m_awready[0], m_awready[1],
                    s_awvalid[0], s_awvalid[1], s_awready[0], s_awready[1]);
        end
    end

    // ============================================================
    // Timeout
    // ============================================================
    initial begin
        #2000000;
        $display("=== TB_TOP: Timeout (2 us), finishing simulation ===");
        $finish;
    end

    // ============================================================
    // FSDB dump
    // ============================================================
    initial begin
        $fsdbDumpfile("waves/axi_top.fsdb");
        $fsdbDumpvars(0, tb_top, "+all");
    end

    // ============================================================
    // Protocol assertions - AXI4 compliance checks
    // ============================================================
    property aw_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].awvalid && !m_if[0].awready)
        |=> $stable(m_if[0].awaddr) && $stable(m_if[0].awid) && $stable(m_if[0].awlen);
    endproperty
    assert property (aw_stable) else $error("AW[0]: signals changed during handshake");

    property ar_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].arvalid && !m_if[0].arready)
        |=> $stable(m_if[0].araddr) && $stable(m_if[0].arid) && $stable(m_if[0].arlen);
    endproperty
    assert property (ar_stable) else $error("AR[0]: signals changed during handshake");

endmodule : tb_top
