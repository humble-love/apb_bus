// noc_pkg.sv — UVM package for NOC verification
package noc_pkg;
  import uvm_pkg::*;
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  `include "uvm_macros.svh"

  // AXI4 transaction
  class axi_transaction extends uvm_sequence_item;
    rand bit        is_write;
    rand bit [31:0] addr;
    rand bit [7:0]  id;
    rand bit [7:0]  len;
    rand bit [1:0]  burst;
    rand bit [3:0]  size;
    rand bit [3:0]  qos;
    rand bit [DATA_W-1:0] data[];
    rand bit [(DATA_W/8)-1:0] wstrb[];
    bit [1:0]  resp;
    bit [7:0]  bid;
    bit [DATA_W-1:0] rdata[];

    constraint valid_len   { len inside {[0:15]}; }
    constraint data_size   { data.size() == len + 1; }
    constraint wstrb_size  { wstrb.size() == len + 1; }
    constraint addr_align  { size inside {3,4,5,6}; }

    `uvm_object_utils_begin(axi_transaction)
      `uvm_field_int(is_write, UVM_DEFAULT)
      `uvm_field_int(addr, UVM_DEFAULT)
      `uvm_field_int(id, UVM_DEFAULT)
      `uvm_field_int(len, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "axi_transaction");
      super.new(name);
    endfunction
  endclass

  // Flit transaction
  class flit_transaction extends uvm_sequence_item;
    flit_t      flit;
    flit_type_t ftype;
    node_id_t   src_id;
    node_id_t   dst_id;

    `uvm_object_utils_begin(flit_transaction)
      `uvm_field_int(src_id, UVM_DEFAULT)
      `uvm_field_int(dst_id, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "flit_transaction");
      super.new(name);
    endfunction
  endclass
endpackage
