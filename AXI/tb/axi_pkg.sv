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

        // Read Address
        rand bit [7:0]  arid;
        rand bit [31:0] araddr;
        rand bit [7:0]  arlen;
        rand bit [2:0]  arsize;
        rand bit [1:0]  arburst;
        rand bit [3:0]  arcache;
        rand bit [2:0]  arprot;
        rand bit [3:0]  arqos;

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
            }
        }

        `uvm_object_utils_begin(axi_transaction)
            `uvm_field_int(awid,    UVM_DEFAULT)
            `uvm_field_int(awaddr,  UVM_DEFAULT)
            `uvm_field_int(awlen,   UVM_DEFAULT)
            `uvm_field_int(awsize,  UVM_DEFAULT)
            `uvm_field_int(awburst, UVM_DEFAULT)
            `uvm_field_int(arid,    UVM_DEFAULT)
            `uvm_field_int(araddr,  UVM_DEFAULT)
            `uvm_field_int(arlen,   UVM_DEFAULT)
            `uvm_field_int(arsize,  UVM_DEFAULT)
            `uvm_field_int(arburst, UVM_DEFAULT)
            `uvm_field_int(is_write, UVM_DEFAULT)
            `uvm_field_int(has_both, UVM_DEFAULT)
        `uvm_object_utils_end

        function new(string name = "axi_transaction");
            super.new(name);
        endfunction

    endclass : axi_transaction

endpackage : axi_pkg
