// AXI UVM Package — Transaction class and channel typedefs

package axi_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------------------------------------------------------
    // Channel packed structs (for RTL use via include)
    // ---------------------------------------------------------------
    `ifndef AXI_TYPES_SVH
    `define AXI_TYPES_SVH

    // Write Address Channel
    typedef struct packed {
        logic [7:0]  id;
        logic [31:0] addr;
        logic [7:0]  len;
        logic [2:0]  size;
        logic [1:0]  burst;
        logic        lock_;
        logic [3:0]  cache;
        logic [2:0]  prot;
        logic [3:0]  qos;
    } axi_aw_chan_t;

    // Write Data Channel
    typedef struct packed {
        logic [255:0] data;
        logic [31:0]  strb;
        logic         last;
    } axi_w_chan_t;

    // Write Response Channel
    typedef struct packed {
        logic [7:0] id;
        logic [1:0] resp;
    } axi_b_chan_t;

    // Read Address Channel
    typedef struct packed {
        logic [7:0]  id;
        logic [31:0] addr;
        logic [7:0]  len;
        logic [2:0]  size;
        logic [1:0]  burst;
        logic        lock_;
        logic [3:0]  cache;
        logic [2:0]  prot;
        logic [3:0]  qos;
    } axi_ar_chan_t;

    // Read Data Channel
    typedef struct packed {
        logic [7:0]   id;
        logic [255:0] data;
        logic [1:0]   resp;
        logic         last;
    } axi_r_chan_t;

    `endif // AXI_TYPES_SVH

    // ---------------------------------------------------------------
    // AXI Transaction (UVM sequence item)
    // ---------------------------------------------------------------
    class axi_transaction extends uvm_sequence_item;

        // Write Address
        rand bit [7:0]  awid;
        rand bit [31:0] awaddr;
        rand bit [7:0]  awlen;
        rand bit [2:0]  awsize;
        rand bit [1:0]  awburst;
        rand bit [3:0]  awcache;
        rand bit [2:0]  awprot;
        rand bit [3:0]  awqos;
        rand bit        awlock;

        // Read Address
        rand bit [7:0]  arid;
        rand bit [31:0] araddr;
        rand bit [7:0]  arlen;
        rand bit [2:0]  arsize;
        rand bit [1:0]  arburst;
        rand bit [3:0]  arcache;
        rand bit [2:0]  arprot;
        rand bit [3:0]  arqos;
        rand bit        arlock;

        // Write data queue (one entry per beat)
        rand bit [255:0] wdata_q[$];
        rand bit [31:0]  wstrb_q[$];

        // Read data queue (populated by monitor)
        bit [255:0] rdata_q[$];
        bit [1:0]   rresp_q[$];

        // Write response
        bit [1:0]  bresp;

        // Transaction type control
        rand bit    is_write;    // 1 = write, 0 = read
        rand bit    has_both;    // 1 = write then read in same txn

        // ---------------------------------------------------------------
        // Constraints
        // ---------------------------------------------------------------

        // Valid beat sizes: 2=4B, 3=8B, 4=16B, 5=32B (256-bit)
        constraint size_c {
            awsize inside {2, 3, 4, 5};
            arsize inside {2, 3, 4, 5};
        }

        // Burst type
        constraint burst_c {
            awburst inside {0, 1, 2};
            arburst inside {0, 1, 2};
        }

        // Burst length: 1-16 beats for sanity, up to 256 for burst test
        constraint len_c {
            awlen inside {[0:15]};
            arlen inside {[0:15]};
        }

        // Address map constraint (SRAM=0x0xxx_xxxx, DFI=0x1xxx_xxxx)
        constraint addr_map_c {
            awaddr[31:28] inside {4'h0, 4'h1};
            araddr[31:28] inside {4'h0, 4'h1};
        }

        // Word alignment for 256-bit bus (32-byte aligned for full-width)
        constraint addr_align_c {
            (awsize == 5) -> (awaddr[4:0] == 5'd0);
            (awsize == 4) -> (awaddr[3:0] == 4'd0);
            (awsize == 3) -> (awaddr[2:0] == 3'd0);
            (awsize == 2) -> (awaddr[1:0] == 2'd0);
            (arsize == 5) -> (araddr[4:0] == 5'd0);
            (arsize == 4) -> (araddr[3:0] == 4'd0);
            (arsize == 3) -> (araddr[2:0] == 3'd0);
            (arsize == 2) -> (araddr[1:0] == 2'd0);
        }

        // Write data queue must match burst length
        constraint wdata_q_size_c {
            if (is_write) {
                wdata_q.size() == awlen + 1;
                wstrb_q.size() == awlen + 1;
            } else {
                wdata_q.size() == 0;
                wstrb_q.size() == 0;
            }
        }

        // has_both is disabled by default; enable for combined write+read
        constraint has_both_c { has_both == 0; }

        // Lock access: default to normal (non-exclusive)
        constraint lock_c { awlock == 0; arlock == 0; }

        `uvm_object_utils_begin(axi_transaction)
            `uvm_field_int(awid,    UVM_DEFAULT)
            `uvm_field_int(awaddr,  UVM_DEFAULT)
            `uvm_field_int(awlen,   UVM_DEFAULT)
            `uvm_field_int(awsize,  UVM_DEFAULT)
            `uvm_field_int(awburst, UVM_DEFAULT)
            `uvm_field_int(awcache, UVM_DEFAULT)
            `uvm_field_int(awprot,  UVM_DEFAULT)
            `uvm_field_int(awqos,   UVM_DEFAULT)
            `uvm_field_int(awlock,  UVM_DEFAULT)
            `uvm_field_int(arid,    UVM_DEFAULT)
            `uvm_field_int(araddr,  UVM_DEFAULT)
            `uvm_field_int(arlen,   UVM_DEFAULT)
            `uvm_field_int(arsize,  UVM_DEFAULT)
            `uvm_field_int(arburst, UVM_DEFAULT)
            `uvm_field_int(arcache, UVM_DEFAULT)
            `uvm_field_int(arprot,  UVM_DEFAULT)
            `uvm_field_int(arqos,   UVM_DEFAULT)
            `uvm_field_int(arlock,  UVM_DEFAULT)
            `uvm_field_int(is_write, UVM_DEFAULT)
            `uvm_field_int(has_both, UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "axi_transaction");
            super.new(name);
        endfunction

        // ---------------------------------------------------------------
        // Manual do_copy for queue fields (UVM 1.2 lacks uvm_field_queue_int)
        // ---------------------------------------------------------------
        function void do_copy(uvm_object rhs);
            axi_transaction tx;
            $cast(tx, rhs);
            super.do_copy(rhs);
            awid       = tx.awid;
            awaddr     = tx.awaddr;
            awlen      = tx.awlen;
            awsize     = tx.awsize;
            awburst    = tx.awburst;
            awcache    = tx.awcache;
            awprot     = tx.awprot;
            awqos      = tx.awqos;
            awlock     = tx.awlock;
            arid       = tx.arid;
            araddr     = tx.araddr;
            arlen      = tx.arlen;
            arsize     = tx.arsize;
            arburst    = tx.arburst;
            arcache    = tx.arcache;
            arprot     = tx.arprot;
            arqos      = tx.arqos;
            arlock     = tx.arlock;
            wdata_q    = tx.wdata_q;
            wstrb_q    = tx.wstrb_q;
            rdata_q    = tx.rdata_q;
            rresp_q    = tx.rresp_q;
            bresp      = tx.bresp;
            is_write   = tx.is_write;
            has_both   = tx.has_both;
        endfunction

        // ---------------------------------------------------------------
        // Manual do_compare — uses compare_field_int (UVM 1.2 compat)
        // ---------------------------------------------------------------
        function bit do_compare(uvm_object rhs, uvm_comparer comparer);
            axi_transaction tx;
            bit result;
            $cast(tx, rhs);
            result = super.do_compare(rhs, comparer);
            result &= comparer.compare_field_int("awid",    awid,    tx.awid,    $bits(awid));
            result &= comparer.compare_field_int("awaddr",  awaddr,  tx.awaddr,  $bits(awaddr));
            result &= comparer.compare_field_int("awlen",   awlen,   tx.awlen,   $bits(awlen));
            result &= comparer.compare_field_int("awsize",  awsize,  tx.awsize,  $bits(awsize));
            result &= comparer.compare_field_int("awburst", awburst, tx.awburst, $bits(awburst));
            result &= comparer.compare_field_int("awcache", awcache, tx.awcache, $bits(awcache));
            result &= comparer.compare_field_int("awprot",  awprot,  tx.awprot,  $bits(awprot));
            result &= comparer.compare_field_int("awqos",   awqos,   tx.awqos,   $bits(awqos));
            result &= comparer.compare_field_int("awlock",  awlock,  tx.awlock,  $bits(awlock));
            result &= comparer.compare_field_int("arid",    arid,    tx.arid,    $bits(arid));
            result &= comparer.compare_field_int("araddr",  araddr,  tx.araddr,  $bits(araddr));
            result &= comparer.compare_field_int("arlen",   arlen,   tx.arlen,   $bits(arlen));
            result &= comparer.compare_field_int("arsize",  arsize,  tx.arsize,  $bits(arsize));
            result &= comparer.compare_field_int("arburst", arburst, tx.arburst, $bits(arburst));
            result &= comparer.compare_field_int("arcache", arcache, tx.arcache, $bits(arcache));
            result &= comparer.compare_field_int("arprot",  arprot,  tx.arprot,  $bits(arprot));
            result &= comparer.compare_field_int("arqos",   arqos,   tx.arqos,   $bits(arqos));
            result &= comparer.compare_field_int("arlock",  arlock,  tx.arlock,  $bits(arlock));
            result &= (wdata_q === tx.wdata_q);
            result &= (wstrb_q === tx.wstrb_q);
            result &= (rdata_q === tx.rdata_q);
            result &= (rresp_q === tx.rresp_q);
            result &= comparer.compare_field_int("bresp",   bresp,   tx.bresp,   $bits(bresp));
            result &= comparer.compare_field_int("is_write", is_write, tx.is_write, $bits(is_write));
            result &= comparer.compare_field_int("has_both", has_both, tx.has_both, $bits(has_both));
            return result;
        endfunction

        // ---------------------------------------------------------------
        // Manual do_print for queue fields
        // ---------------------------------------------------------------
        function void do_print(uvm_printer printer);
            super.do_print(printer);
            printer.print_field_int("awid",       awid,       $bits(awid));
            printer.print_field_int("awaddr",     awaddr,     $bits(awaddr));
            printer.print_field_int("awlen",      awlen,      $bits(awlen));
            printer.print_field_int("awsize",     awsize,     $bits(awsize));
            printer.print_field_int("awburst",    awburst,    $bits(awburst));
            printer.print_field_int("awcache",    awcache,    $bits(awcache));
            printer.print_field_int("awprot",     awprot,     $bits(awprot));
            printer.print_field_int("awqos",      awqos,      $bits(awqos));
            printer.print_field_int("awlock",     awlock,     $bits(awlock));
            printer.print_field_int("arid",       arid,       $bits(arid));
            printer.print_field_int("araddr",     araddr,     $bits(araddr));
            printer.print_field_int("arlen",      arlen,      $bits(arlen));
            printer.print_field_int("arsize",     arsize,     $bits(arsize));
            printer.print_field_int("arburst",    arburst,    $bits(arburst));
            printer.print_field_int("arcache",    arcache,    $bits(arcache));
            printer.print_field_int("arprot",     arprot,     $bits(arprot));
            printer.print_field_int("arqos",      arqos,      $bits(arqos));
            printer.print_field_int("arlock",     arlock,     $bits(arlock));
            printer.print_generic("wdata_q", "queue[$]", 0, $sformatf("%0d entries", wdata_q.size()));
            printer.print_generic("wstrb_q", "queue[$]", 0, $sformatf("%0d entries", wstrb_q.size()));
            printer.print_generic("rdata_q", "queue[$]", 0, $sformatf("%0d entries", rdata_q.size()));
            printer.print_generic("rresp_q", "queue[$]", 0, $sformatf("%0d entries", rresp_q.size()));
            printer.print_field_int("bresp",      bresp,      $bits(bresp));
            printer.print_field_int("is_write",   is_write,   $bits(is_write));
            printer.print_field_int("has_both",   has_both,   $bits(has_both));
        endfunction

    endclass : axi_transaction

endpackage : axi_pkg
