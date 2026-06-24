// APB UVM Testbench Top
`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import apb_pkg::*;

module tb_top;

    reg pclk;
    reg presetn;

    // APB interface
    apb_if #(.NUM_MASTERS(2)) apb_if_inst (
        .pclk   (pclk),
        .presetn(presetn)
    );

    // DUT wires
    wire        req_0, gnt_0, req_1, gnt_1;
    wire [31:0] paddr, pwdata, prdata;
    wire        pwrite, psel, penable, pready;
    wire [1:0]  psel_slv;
    wire        gpio_int;

    // DUT instantiation
    apb_top u_dut (
        .pclk        (pclk),
        .presetn     (presetn),

        .txn_req_0   (apb_if_inst.txn_req[0]),
        .txn_addr_0  (apb_if_inst.txn_addr[0]),
        .txn_wdata_0 (apb_if_inst.txn_wdata[0]),
        .txn_write_0 (apb_if_inst.txn_write[0]),

        .txn_req_1   (apb_if_inst.txn_req[1]),
        .txn_addr_1  (apb_if_inst.txn_addr[1]),
        .txn_wdata_1 (apb_if_inst.txn_wdata[1]),
        .txn_write_1 (apb_if_inst.txn_write[1]),

        .req_0       (req_0),
        .gnt_0       (gnt_0),
        .req_1       (req_1),
        .gnt_1       (gnt_1),

        .paddr       (paddr),
        .pwdata      (pwdata),
        .prdata      (prdata),
        .pwrite      (pwrite),
        .psel        (psel),
        .penable     (penable),
        .pready      (pready),

        .psel_slv    (psel_slv),
        .gpio_int    (gpio_int)
    );

    // Connect DUT outputs → interface (for UVM to observe)
    assign apb_if_inst.req[0]  = req_0;
    assign apb_if_inst.req[1]  = req_1;
    assign apb_if_inst.gnt[0]  = gnt_0;
    assign apb_if_inst.gnt[1]  = gnt_1;
    assign apb_if_inst.paddr   = paddr;
    assign apb_if_inst.pwdata  = pwdata;
    assign apb_if_inst.prdata  = prdata;
    assign apb_if_inst.pwrite  = pwrite;
    assign apb_if_inst.psel    = psel;
    assign apb_if_inst.penable = penable;
    assign apb_if_inst.pready  = pready;

    // Clock — 100MHz (10ns period)
    initial pclk = 0;
    always #5 pclk = ~pclk;

    // Reset — active low, deassert after 50ns
    initial begin
        presetn = 1'b0;
        #50 presetn = 1'b1;
    end

    // FSDB dump for Verdi
    initial begin
        $fsdbDumpfile("waves/apb.fsdb");
        $fsdbDumpvars(0, tb_top);
        $fsdbDumpFlush;
    end

    // Set virtual interface in config DB and run test
    initial begin
        uvm_config_db #(virtual apb_if)::set(null, "*", "vif", apb_if_inst);
        run_test();
    end

    // Timeout — 1ms
    initial begin
        #1000000;
        `uvm_fatal("TIMEOUT", "Simulation timed out after 1ms")
    end

endmodule
