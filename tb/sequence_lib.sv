// APB Sequence Library
import apb_pkg::*;

// ---------------------------------------------------------------
// Base Sequence — helper tasks
// ---------------------------------------------------------------
class apb_base_sequence extends uvm_sequence #(apb_transaction);

    `uvm_object_utils(apb_base_sequence)

    function new(string name = "apb_base_sequence");
        super.new(name);
    endfunction

    task write(bit [31:0] addr, bit [31:0] data);
        apb_transaction txn;
        txn = apb_transaction::type_id::create("txn");
        start_item(txn);
        txn.addr = addr;
        txn.data = data;
        txn.rw   = 1'b1;
        finish_item(txn);
    endtask

    task read(bit [31:0] addr, output bit [31:0] data);
        apb_transaction txn;
        txn = apb_transaction::type_id::create("txn");
        start_item(txn);
        txn.addr = addr;
        txn.rw   = 1'b0;
        finish_item(txn);
        data = txn.data;
    endtask

endclass : apb_base_sequence

// ---------------------------------------------------------------
// Sanity Sequence
// ---------------------------------------------------------------
class apb_sanity_seq extends apb_base_sequence;

    `uvm_object_utils(apb_sanity_seq)

    function new(string name = "apb_sanity_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        `uvm_info("SEQ", "Sanity sequence started", UVM_LOW)
        write(32'h0000_0000, 32'hDEAD_BEEF);
        read (32'h0000_0000, rd);
        write(32'h0000_1000, 32'hAAAA_5555);
        read (32'h0000_1000, rd);
        `uvm_info("SEQ", "Sanity sequence done", UVM_LOW)
    endtask

endclass : apb_sanity_seq

// ---------------------------------------------------------------
// Random Sequence — 20 random transactions
// ---------------------------------------------------------------
class apb_random_seq extends apb_base_sequence;

    `uvm_object_utils(apb_random_seq)

    function new(string name = "apb_random_seq");
        super.new(name);
    endfunction

    task body();
        apb_transaction txn;
        `uvm_info("SEQ", "Random sequence started", UVM_LOW)
        repeat (20) begin
            txn = apb_transaction::type_id::create("txn");
            start_item(txn);
            if (!txn.randomize())
                `uvm_error("SEQ", "Randomization failed")
            finish_item(txn);
        end
        `uvm_info("SEQ", "Random sequence done", UVM_LOW)
    endtask

endclass : apb_random_seq

// ---------------------------------------------------------------
// Burst Sequence — 10 back-to-back writes + reads
// ---------------------------------------------------------------
class apb_burst_seq extends apb_base_sequence;

    `uvm_object_utils(apb_burst_seq)

    function new(string name = "apb_burst_seq");
        super.new(name);
    endfunction

    task body();
        int i;
        bit [31:0] rd;
        `uvm_info("SEQ", "Burst sequence started", UVM_LOW)
        for (i = 0; i < 10; i++)
            write(32'h0000_0000 + (i*4), 32'hA5A5_0000 + i);
        for (i = 0; i < 10; i++) begin
            read(32'h0000_0000 + (i*4), rd);
            `uvm_info("SEQ", $sformatf("Burst read[%0d]=0x%08x", i, rd), UVM_LOW)
        end
        `uvm_info("SEQ", "Burst sequence done", UVM_LOW)
    endtask

endclass : apb_burst_seq

// ---------------------------------------------------------------
// Slave Error Sequence — access unmapped address 0x2000
// ---------------------------------------------------------------
class apb_slave_err_seq extends apb_base_sequence;

    `uvm_object_utils(apb_slave_err_seq)

    function new(string name = "apb_slave_err_seq");
        super.new(name);
    endfunction

    task body();
        apb_transaction txn;
        `uvm_info("SEQ", "Error sequence started (unmapped addr)", UVM_LOW)
        txn = apb_transaction::type_id::create("txn");
        start_item(txn);
        txn.addr = 32'h0000_2000;
        txn.rw   = 1'b0;
        txn.addr_range_c.constraint_mode(0);
        finish_item(txn);
        `uvm_info("SEQ", "Error sequence done", UVM_LOW)
    endtask

endclass : apb_slave_err_seq
