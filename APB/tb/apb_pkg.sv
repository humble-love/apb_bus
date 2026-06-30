// APB UVM Package — Transaction class and common types

package apb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------------------------------------------------------
    // APB Transaction
    // ---------------------------------------------------------------
    class apb_transaction extends uvm_sequence_item;

        rand bit [31:0] addr;
        rand bit [31:0] data;
        rand bit        rw;       // 1 = write, 0 = read

        // Valid slave address ranges
        constraint addr_range_c {
            addr[31:16] == 16'd0;
            addr[15:12] inside {4'h0, 4'h1};
        }

        // Word-aligned
        constraint addr_align_c {
            addr[1:0] == 2'b00;
        }

        `uvm_object_utils_begin(apb_transaction)
            `uvm_field_int(addr, UVM_DEFAULT)
            `uvm_field_int(data, UVM_DEFAULT)
            `uvm_field_int(rw,   UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "apb_transaction");
            super.new(name);
        endfunction

    endclass : apb_transaction

endpackage : apb_pkg
