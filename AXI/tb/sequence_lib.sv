import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

// ---------------------------------------------------------------
// Sanity Sequence — Simple single-beat write + read per slave
// ---------------------------------------------------------------
class axi_sanity_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_sanity_seq)
    function new(string name = "axi_sanity_seq"); super.new(name); endfunction

    task body();
        axi_transaction txn;

        // Write + read to SRAM (slave 0)
        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 1; awlen == 0; awsize == 5;
            awaddr[31:28] == 4'h0; awaddr[4:0] == 0;
            wdata_q.size() == 1; wstrb_q.size() == 1;
            wstrb_q[0] == 32'hFFFFFFFF;
        });
        finish_item(txn);

        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 0; arlen == 0; arsize == 5;
            araddr[31:28] == 4'h0; araddr[4:0] == 0;
        });
        finish_item(txn);

        // Write + read to DFI (slave 1)
        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 1; awlen == 0; awsize == 5;
            awaddr[31:28] == 4'h1; awaddr[4:0] == 0;
            wdata_q.size() == 1; wstrb_q.size() == 1;
            wstrb_q[0] == 32'hFFFFFFFF;
        });
        finish_item(txn);

        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 0; arlen == 0; arsize == 5;
            araddr[31:28] == 4'h1; araddr[4:0] == 0;
        });
        finish_item(txn);
    endtask
endclass

// ---------------------------------------------------------------
// Random Sequence
// ---------------------------------------------------------------
class axi_random_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_random_seq)
    int num_txn = 10;

    function new(string name = "axi_random_seq"); super.new(name); endfunction

    task body();
        for (int i = 0; i < num_txn; i++) begin
            axi_transaction txn = axi_transaction::type_id::create("txn");
            start_item(txn);
            assert(txn.randomize());
            finish_item(txn);
        end
    endtask
endclass

// ---------------------------------------------------------------
// Burst Sequence — Full burst transfers
// ---------------------------------------------------------------
class axi_burst_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_burst_seq)
    function new(string name = "axi_burst_seq"); super.new(name); endfunction

    task body();
        // INCR burst write + read
        axi_transaction txn;
        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 1; awlen == 7; awsize == 5; awburst == 1;
            awaddr[31:28] == 4'h0; awaddr[4:0] == 0;
            wdata_q.size() == 8; wstrb_q.size() == 8;
            foreach (wstrb_q[i]) wstrb_q[i] == 32'hFFFFFFFF;
        });
        finish_item(txn);

        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 0; arlen == 7; arsize == 5; arburst == 1;
            araddr[31:28] == 4'h0; araddr[4:0] == 0;
        });
        finish_item(txn);

        // WRAP burst
        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 1; awlen == 3; awsize == 5; awburst == 2;
            awaddr[31:28] == 4'h1; awaddr[6:0] == 0;
            wdata_q.size() == 4; wstrb_q.size() == 4;
            foreach (wstrb_q[i]) wstrb_q[i] == 32'hFFFFFFFF;
        });
        finish_item(txn);
    endtask
endclass

// ---------------------------------------------------------------
// Narrow Transfer Sequence — 4B, 8B, 16B on 256-bit bus
// ---------------------------------------------------------------
class axi_narrow_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_narrow_seq)
    function new(string name = "axi_narrow_seq"); super.new(name); endfunction

    task body();
        bit [2:0] sizes[] = '{2, 3, 4}; // 4B, 8B, 16B
        foreach (sizes[i]) begin
            axi_transaction txn;
            // Write
            txn = axi_transaction::type_id::create("txn");
            start_item(txn);
            assert(txn.randomize() with {
                is_write == 1; awlen == 3; awsize == sizes[i];
                awburst == 1; awaddr[31:28] == 4'h0;
            });
            finish_item(txn);
            // Read
            txn = axi_transaction::type_id::create("txn");
            start_item(txn);
            assert(txn.randomize() with {
                is_write == 0; arlen == 3; arsize == sizes[i];
                arburst == 1; araddr[31:28] == 4'h0;
            });
            finish_item(txn);
        end
    endtask
endclass

// ---------------------------------------------------------------
// Out-of-Order Sequence — Multiple outstanding reads
// ---------------------------------------------------------------
class axi_out_of_order_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_out_of_order_seq)
    function new(string name = "axi_out_of_order_seq"); super.new(name); endfunction

    task body();
        axi_transaction txn;
        // Send 4 reads with different IDs, don't wait for responses
        for (int id = 0; id < 4; id++) begin
            txn = axi_transaction::type_id::create("txn");
            start_item(txn);
            assert(txn.randomize() with {
                is_write == 0; arid == id; arlen == 3;
                arsize == 5; arburst == 1;
                araddr[31:28] inside {4'h0, 4'h1};
            });
            finish_item(txn);
        end
    endtask
endclass

// ---------------------------------------------------------------
// Concurrent Sequence — Both masters active
// ---------------------------------------------------------------
class axi_concurrent_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_concurrent_seq)
    function new(string name = "axi_concurrent_seq"); super.new(name); endfunction

    task body();
        axi_transaction txn;
        // Master 0 writes SRAM, Master 1 writes DFI
        for (int i = 0; i < 10; i++) begin
            txn = axi_transaction::type_id::create("txn");
            start_item(txn);
            assert(txn.randomize() with {
                is_write == (i % 2 == 0);
                awlen inside {[0:3]}; arlen inside {[0:3]};
                awsize == 5; arsize == 5;
                awaddr[31:28] == 4'h0; araddr[31:28] == 4'h0;
            });
            finish_item(txn);
        end
    endtask
endclass

// ---------------------------------------------------------------
// Error Sequence — Unmapped address
// ---------------------------------------------------------------
class axi_error_seq extends uvm_sequence #(axi_transaction);
    `uvm_object_utils(axi_error_seq)
    function new(string name = "axi_error_seq"); super.new(name); endfunction

    task body();
        axi_transaction txn;
        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 1; awlen == 0; awsize == 5;
            awaddr[31:28] == 4'hF;
            wdata_q.size() == 1; wstrb_q.size() == 1;
            wstrb_q[0] == 32'hFFFFFFFF;
        });
        finish_item(txn);

        txn = axi_transaction::type_id::create("txn");
        start_item(txn);
        assert(txn.randomize() with {
            is_write == 0; arlen == 0; arsize == 5;
            araddr[31:28] == 4'hF;
        });
        finish_item(txn);
    endtask
endclass
