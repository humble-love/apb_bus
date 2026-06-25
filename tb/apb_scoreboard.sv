import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;

// APB Scoreboard — Reference Model
// Maintains golden mirror of memory and GPIO registers
// Compares read data against expected value

class apb_scoreboard extends uvm_subscriber #(apb_pkg::apb_transaction);

    `uvm_component_utils(apb_scoreboard)

    // Reference memory
    bit [31:0] ref_mem [0:255];

    // Reference GPIO registers
    bit [31:0] ref_data       = 32'd0;
    bit [31:0] ref_dir        = 32'd0;
    bit [31:0] ref_int_en     = 32'd0;
    bit [31:0] ref_int_status = 32'd0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void write(apb_pkg::apb_transaction t);
        int word_idx;
        bit [31:0] expected;

        if (t.rw) begin
            // Write: update reference model
            case (t.addr[15:12])
                4'h0: begin
                    word_idx = t.addr[9:2];
                    ref_mem[word_idx] = t.data;
                end
                4'h1: begin
                    case (t.addr[3:2])
                        2'd0: ref_data       = t.data;
                        2'd1: ref_dir        = t.data;
                        2'd2: ref_int_en     = t.data;
                        2'd3: ref_int_status = t.data;
                    endcase
                end
            endcase
        end else begin
            // Read: compare
            case (t.addr[15:12])
                4'h0: begin
                    word_idx = t.addr[9:2];
                    expected = ref_mem[word_idx];
                end
                4'h1: begin
                    case (t.addr[3:2])
                        2'd0: expected = ref_data;
                        2'd1: expected = ref_dir;
                        2'd2: expected = ref_int_en;
                        2'd3: expected = ref_int_status;
                        default: expected = 32'd0;
                    endcase
                end
                default: expected = 32'd0;
            endcase

            if (expected !== t.data) begin
                `uvm_error("SCO", $sformatf(
                    "MISMATCH addr=0x%08x exp=0x%08x got=0x%08x",
                    t.addr, expected, t.data))
            end else begin
                `uvm_info("SCO", $sformatf(
                    "PASS addr=0x%08x data=0x%08x", t.addr, t.data), UVM_MEDIUM)
            end
        end
    endfunction

endclass : apb_scoreboard
