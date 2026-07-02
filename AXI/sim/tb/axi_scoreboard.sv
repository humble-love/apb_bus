import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(axi_scoreboard)

    uvm_analysis_export #(axi_transaction) m0_export;
    uvm_analysis_export #(axi_transaction) m1_export;
    uvm_tlm_analysis_fifo #(axi_transaction) m0_fifo;
    uvm_tlm_analysis_fifo #(axi_transaction) m1_fifo;

    // Reference models
    bit [255:0] sram_mem [0:1023];
    bit [255:0] dfi_mem  [0:16383]; // 16K entries for DDR5

    int sram_writes, sram_reads, dfi_writes, dfi_reads;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m0_export = new("m0_export", this);
        m1_export = new("m1_export", this);
        m0_fifo   = new("m0_fifo", this);
        m1_fifo   = new("m1_fifo", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        m0_export.connect(m0_fifo.analysis_export);
        m1_export.connect(m1_fifo.analysis_export);
    endfunction

    task run_phase(uvm_phase phase);
        fork
            process_master(0, m0_fifo);
            process_master(1, m1_fifo);
        join
    endtask

    task process_master(int mid, uvm_tlm_analysis_fifo #(axi_transaction) fifo);
        forever begin
            axi_transaction txn;
            fifo.get(txn);

            if (txn.is_write) begin
                for (int i = 0; i <= txn.awlen; i++) begin
                    automatic logic [31:0] addr;
                    automatic logic [$clog2(16384)-1:0] word_idx;

                    addr = txn.awaddr + (i << txn.awsize);

                    if (addr[31:28] == 4'h0) begin
                        // SRAM
                        word_idx = addr[$clog2(1024)+$clog2(32)-1:$clog2(32)];
                        for (int b = 0; b < 32; b++)
                            if (txn.wstrb_q[i][b])
                                sram_mem[word_idx][b*8 +: 8] = txn.wdata_q[i][b*8 +: 8];
                        sram_writes++;
                    end else if (addr[31:28] == 4'h1) begin
                        // DFI/DDR5
                        word_idx = addr[$clog2(16384)+$clog2(32)-1:$clog2(32)];
                        for (int b = 0; b < 32; b++)
                            if (txn.wstrb_q[i][b])
                                dfi_mem[word_idx][b*8 +: 8] = txn.wdata_q[i][b*8 +: 8];
                        dfi_writes++;
                    end
                end
            end else begin
                // Read: verify
                for (int i = 0; i <= txn.arlen; i++) begin
                    automatic logic [31:0] addr;
                    automatic logic [$clog2(16384)-1:0] word_idx;
                    automatic bit [255:0] expected;

                    addr = txn.araddr + (i << txn.arsize);

                    if (addr[31:28] == 4'h0) begin
                        word_idx = addr[$clog2(1024)+$clog2(32)-1:$clog2(32)];
                        expected = sram_mem[word_idx];
                        sram_reads++;
                    end else begin
                        word_idx = addr[$clog2(16384)+$clog2(32)-1:$clog2(32)];
                        expected = dfi_mem[word_idx];
                        dfi_reads++;
                    end

                    if (expected !== txn.rdata_q[i]) begin
                        `uvm_error("SCO", $sformatf(
                            "M%0d READ MISMATCH addr=0x%08h beat=%0d exp=0x%064h got=0x%064h",
                            mid, addr, i, expected, txn.rdata_q[i]))
                    end else begin
                        `uvm_info("SCO", $sformatf(
                            "M%0d READ PASS addr=0x%08h beat=%0d data=0x%064h",
                            mid, addr, i, txn.rdata_q[i]), UVM_MEDIUM)
                    end
                end
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("SCO", $sformatf(
            "Scoreboard stats: SRAM: W=%0d R=%0d, DFI: W=%0d R=%0d",
            sram_writes, sram_reads, dfi_writes, dfi_reads), UVM_NONE)
    endfunction

endclass : axi_scoreboard
