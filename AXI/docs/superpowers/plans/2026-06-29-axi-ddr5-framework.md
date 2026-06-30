# AXI4-Full + DDR5 DFI Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build an industrial-grade AXI4-Full bus system with crossbar interconnect, SRAM slave, DDR5 DFI bridge slave, and full UVM verification.

**Architecture:** 2 masters → crossbar (per-slave round-robin arb + ID-tagged R/B demux) → decoder → 2 slaves (SRAM + DFI/DDR5). 256-bit data, 8-bit ID, 16 outstanding per master.

**Tech Stack:** SystemVerilog RTL, UVM 1.2 verification, VCS compile, Verdi FSDB waveforms.

## Global Constraints

- DATA_WIDTH: 256, ADDR_WIDTH: 32, ID_WIDTH: 8, WSTRB_WIDTH: 32
- 2 masters, 2 slaves (SRAM=0x0xxx_xxxx, DFI=0x1xxx_xxxx)
- All burst types (FIXED, INCR, WRAP), narrow transfers down to 32-bit
- Out-of-order read responses by ID
- Max 16 outstanding transactions per master
- RTL source: `.sv` (SystemVerilog), TB source: `.sv`
- Scripts use VCS + UVM 1.2, follow APB project patterns
- DRY, YAGNI, TDD — each task ends with compile verification

---

### Task 1: Project Infrastructure

**Files:**
- Create: `AXI/scripts/compile.sh`
- Create: `AXI/scripts/run.sh`
- Create: `AXI/scripts/verdi.sh`
- Create: `AXI/scripts/filelist.f`
- Create: `AXI/Makefile`
- Create: `AXI/.gitignore`

**Interfaces:**
- Produces: Build scripts consumed by all later tasks for compile verification

- [x] **Step 1: Create scripts directory**

```bash
mkdir -p /home/openclaw/project/bus/AXI/scripts
mkdir -p /home/openclaw/project/bus/AXI/waves
```

- [x] **Step 2: Write .gitignore**

File: `AXI/.gitignore`
```
simv
simv.daidir/
csrc/
AN.DB/
vc_hdrs.h
uvm_dpi.so*
compile.log
sim.log
waves/*.fsdb
waves/*.vpd
verdiLog/
novas.conf
novas_dump.log
novas.rc
tr_db.log
ucli.key
vlogan.log
inter.vpd
DVEfiles/
build/
build2/
*.o
*.so
```

- [x] **Step 3: Write compile.sh**

File: `AXI/scripts/compile.sh`
```bash
#!/bin/bash
set -e

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"

echo "=== AXI DDR5 Framework Compile ==="

vcs -sverilog -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -debug_access+all -kdb \
    -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
    $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a \
    -l compile.log \
    -f scripts/filelist.f

if [ $? -eq 0 ]; then
    echo "=== Compile SUCCESS ==="
else
    echo "=== Compile FAILED ==="
    exit 1
fi
```

- [x] **Step 4: Write run.sh**

File: `AXI/scripts/run.sh`
```bash
#!/bin/bash
set -e

TEST=${1:-axi_sanity_test}
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"

mkdir -p waves

echo "=== Running test: $TEST ==="
./simv +UVM_TESTNAME=$TEST +fsdb+autoflush -cm line+cond+tgl -l sim.log

if [ $? -eq 0 ]; then
    echo "=== Simulation PASSED ==="
else
    echo "=== Simulation FAILED ==="
    exit 1
fi
```

- [x] **Step 5: Write verdi.sh**

File: `AXI/scripts/verdi.sh`
```bash
#!/bin/bash
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"

verdi -sv -f scripts/filelist.f -ssf waves/*.fsdb &
```

- [x] **Step 6: Write filelist.f**

File: `AXI/scripts/filelist.f`
```
// RTL files
+incdir+rtl
rtl/axi_master.sv
rtl/axi_crossbar_wr.sv
rtl/axi_crossbar_rd.sv
rtl/axi_addr_decoder.sv
rtl/axi_slave_sram.sv
rtl/axi_slave_dfi.sv
rtl/axi_interconnect.sv
rtl/axi_top.sv

// UVM testbench files
+incdir+tb
tb/axi_if.sv
tb/axi_pkg.sv
tb/axi_master_driver.sv
tb/axi_master_monitor.sv
tb/axi_slave_monitor.sv
tb/axi_master_agent.sv
tb/axi_scoreboard.sv
tb/axi_env.sv
tb/sequence_lib.sv
tb/axi_test.sv
tb/tb_top.sv
```

- [x] **Step 7: Write Makefile**

File: `AXI/Makefile`
```makefile
TEST ?= axi_sanity_test

.PHONY: all compile run verdi clean

all: compile

compile:
	bash scripts/compile.sh

run:
	bash scripts/run.sh $(TEST)

verdi:
	bash scripts/verdi.sh

clean:
	rm -rf simv simv.daidir compile.log sim.log
	rm -rf waves/*.fsdb waves/*.vpd
	rm -rf verdiLog novas.conf novas_dump.log novas.rc
	rm -rf AN.DB csrc vc_hdrs.h uvm_dpi.so*
	rm -rf tr_db.log ucli.key vlogan.log inter.vpd
	rm -rf DVEfiles build build2
```

- [x] **Step 8: Create RTL and TB directories**

```bash
mkdir -p /home/openclaw/project/bus/AXI/rtl
mkdir -p /home/openclaw/project/bus/AXI/tb
```

- [x] **Step 9: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add .gitignore scripts/ Makefile
git commit -m "chore: add AXI project infrastructure (scripts, Makefile, filelist)"
```

---

### Task 2: AXI Interface and UVM Package

**Files:**
- Create: `AXI/tb/axi_if.sv`
- Create: `AXI/tb/axi_pkg.sv`

**Interfaces:**
- Produces:
  - `axi_if` interface with 5 AXI channels, `master`/`slave` modports, `drv_cb`/`mon_cb` clocking blocks
  - `axi_pkg` package with `axi_transaction` UVM sequence item
  - AXI channel packed structs: `axi_aw_chan_t`, `axi_w_chan_t`, `axi_b_chan_t`, `axi_ar_chan_t`, `axi_r_chan_t`

- [x] **Step 1: Write axi_if.sv**

File: `AXI/tb/axi_if.sv`
```systemverilog
// AXI4-Full Interface with clocking blocks for UVM driver/monitor

interface axi_if #(
    parameter int DATA_W = 256,
    parameter int ADDR_W = 32,
    parameter int ID_W   = 8
) (
    input logic aclk,
    input logic aresetn
);
    // ========================================================
    // Write Address Channel (AW)
    // ========================================================
    logic [ID_W-1:0]     awid;
    logic [ADDR_W-1:0]   awaddr;
    logic [7:0]          awlen;
    logic [2:0]          awsize;
    logic [1:0]          awburst;
    logic                awlock;
    logic [3:0]          awcache;
    logic [2:0]          awprot;
    logic [3:0]          awqos;
    logic                awvalid;
    logic                awready;

    // ========================================================
    // Write Data Channel (W)
    // ========================================================
    logic [DATA_W-1:0]   wdata;
    logic [DATA_W/8-1:0] wstrb;
    logic                wlast;
    logic                wvalid;
    logic                wready;

    // ========================================================
    // Write Response Channel (B)
    // ========================================================
    logic [ID_W-1:0]     bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    // ========================================================
    // Read Address Channel (AR)
    // ========================================================
    logic [ID_W-1:0]     arid;
    logic [ADDR_W-1:0]   araddr;
    logic [7:0]          arlen;
    logic [2:0]          arsize;
    logic [1:0]          arburst;
    logic                arlock;
    logic [3:0]          arcache;
    logic [2:0]          arprot;
    logic [3:0]          arqos;
    logic                arvalid;
    logic                arready;

    // ========================================================
    // Read Data Channel (R)
    // ========================================================
    logic [ID_W-1:0]     rid;
    logic [DATA_W-1:0]   rdata;
    logic [1:0]          rresp;
    logic                rlast;
    logic                rvalid;
    logic                rready;

    // ========================================================
    // Clocking Blocks
    // ========================================================
    clocking drv_cb @(posedge aclk);
        // Master driver: drives address/write channels, samples response channels
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid;
        input  awready;
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        input  bid, bresp, bvalid;
        output bready;
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid;
        input  arready;
        input  rid, rdata, rresp, rlast, rvalid;
        output rready;
    endclocking

    clocking mon_cb @(posedge aclk);
        input awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos;
        input awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
        input arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos;
        input arvalid, arready;
        input rid, rdata, rresp, rlast, rvalid, rready;
    endclocking

    // ========================================================
    // Modports
    // ========================================================
    modport master_mp (
        input  aclk, aresetn,
        output awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    modport slave_mp (
        input  aclk, aresetn,
        input  awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface : axi_if
```

- [x] **Step 2: Write axi_pkg.sv**

File: `AXI/tb/axi_pkg.sv`
```systemverilog
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
```

- [x] **Step 3: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add tb/axi_if.sv tb/axi_pkg.sv
git commit -m "feat: add AXI interface and UVM transaction package"
```

---

### Task 3: AXI Master Module

**Files:**
- Create: `AXI/rtl/axi_master.sv`

**Interfaces:**
- Consumes: `axi_pkg::axi_aw_chan_t`, `axi_ar_chan_t` packed structs (from Task 2)
- Produces:
  - Module: `axi_master #(ID_W=8, ADDR_W=32, DATA_W=256)`
  - Inputs: `aclk`, `aresetn`, `txn_req`, `txn_desc` (address/len/size/burst/write), `txn_wdata`/`txn_wstrb`, `txn_wlast`
  - Inputs (response): gnt, bvalid/bid/bresp, rvalid/rid/rdata/rresp/rlast
  - Outputs: req, AW/W/AR channel signals, bready/rready
  - Outputs: `txn_done`, `txn_bresp`, `txn_rdata`, `txn_rresp`, `txn_rlast`

- [x] **Step 1: Write axi_master.sv**

File: `AXI/rtl/axi_master.sv`
```systemverilog
// AXI4-Full Master — Per-channel FSMs + transaction sequencer
// 256-bit data, 8-bit ID, 32-bit address
// Features: all burst types, narrow transfers, out-of-order ID support

module axi_master #(
    parameter int ID_W   = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic                 aclk,
    input  logic                 aresetn,

    // Arbiter handshake (per-channel: aw_req/gnt, ar_req/gnt)
    output logic                 aw_req,
    input  logic                 aw_gnt,
    output logic                 ar_req,
    input  logic                 ar_gnt,

    // Write Address Channel
    output logic [ID_W-1:0]      awid,
    output logic [ADDR_W-1:0]    awaddr,
    output logic [7:0]           awlen,
    output logic [2:0]           awsize,
    output logic [1:0]           awburst,
    output logic                 awlock,
    output logic [3:0]           awcache,
    output logic [2:0]           awprot,
    output logic [3:0]           awqos,
    output logic                 awvalid,
    input  logic                 awready,

    // Write Data Channel
    output logic [DATA_W-1:0]    wdata,
    output logic [DATA_W/8-1:0]  wstrb,
    output logic                 wlast,
    output logic                 wvalid,
    input  logic                 wready,

    // Write Response Channel
    input  logic [ID_W-1:0]      bid,
    input  logic [1:0]           bresp,
    input  logic                 bvalid,
    output logic                 bready,

    // Read Address Channel
    output logic [ID_W-1:0]      arid,
    output logic [ADDR_W-1:0]    araddr,
    output logic [7:0]           arlen,
    output logic [2:0]           arsize,
    output logic [1:0]           arburst,
    output logic                 arlock,
    output logic [3:0]           arcache,
    output logic [2:0]           arprot,
    output logic [3:0]           arqos,
    output logic                 arvalid,
    input  logic                 arready,

    // Read Data Channel
    input  logic [ID_W-1:0]      rid,
    input  logic [DATA_W-1:0]    rdata,
    input  logic [1:0]           rresp,
    input  logic                 rlast,
    input  logic                 rvalid,
    output logic                 rready,

    // Testbench stimulus interface
    input  logic                 txn_req,
    input  logic                 txn_is_write,
    input  logic [ID_W-1:0]      txn_awid,
    input  logic [ADDR_W-1:0]    txn_awaddr,
    input  logic [7:0]           txn_awlen,
    input  logic [2:0]           txn_awsize,
    input  logic [1:0]           txn_awburst,
    input  logic [ID_W-1:0]      txn_arid,
    input  logic [ADDR_W-1:0]    txn_araddr,
    input  logic [7:0]           txn_arlen,
    input  logic [2:0]           txn_arsize,
    input  logic [1:0]           txn_arburst,
    // Write data streaming
    input  logic                 txn_wvalid,
    input  logic [DATA_W-1:0]    txn_wdata,
    input  logic [DATA_W/8-1:0]  txn_wstrb,
    input  logic                 txn_wlast,
    output logic                 txn_wready,
    // Read data streaming (back to TB)
    output logic                 txn_rvalid,
    output logic [DATA_W-1:0]    txn_rdata,
    output logic [1:0]           txn_rresp,
    output logic                 txn_rlast,
    input  logic                 txn_rready,
    // Completion
    output logic                 txn_done,
    output logic [1:0]           txn_bresp_out
);

    localparam FSM_IDLE     = 3'd0;
    localparam FSM_AW_REQ   = 3'd1;
    localparam FSM_AW_WAIT  = 3'd2;
    localparam FSM_W_SEND   = 3'd3;
    localparam FSM_B_WAIT   = 3'd4;
    localparam FSM_AR_REQ   = 3'd5;
    localparam FSM_AR_WAIT  = 3'd6;
    localparam FSM_R_COLL   = 3'd7;
    localparam FSM_DONE     = 3'd8;

    logic [2:0] state, next_state;

    // Latched transaction descriptor
    logic                 latched_is_write;
    logic [ID_W-1:0]      latched_awid, latched_arid;
    logic [ADDR_W-1:0]    latched_awaddr, latched_araddr;
    logic [7:0]           latched_awlen, latched_arlen;
    logic [2:0]           latched_awsize, latched_arsize;
    logic [1:0]           latched_awburst, latched_arburst;

    // Beat counters
    logic [7:0]           w_beat_cnt, r_beat_cnt;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            FSM_IDLE:    if (txn_req) begin
                             if (txn_is_write) next_state = FSM_AW_REQ;
                             else              next_state = FSM_AR_REQ;
                         end
            FSM_AW_REQ:  if (aw_gnt)    next_state = FSM_AW_WAIT;
            FSM_AW_WAIT: if (awvalid && awready) next_state = FSM_W_SEND;
            FSM_W_SEND:  if (wvalid && wready && wlast) next_state = FSM_B_WAIT;
            FSM_B_WAIT:  if (bvalid && bready) next_state = latched_is_write ? FSM_DONE : FSM_AR_REQ;
            FSM_AR_REQ:  if (ar_gnt)   next_state = FSM_AR_WAIT;
            FSM_AR_WAIT: if (arvalid && arready) next_state = FSM_R_COLL;
            FSM_R_COLL:  if (rvalid && rready && rlast) next_state = FSM_DONE;
            FSM_DONE:    next_state = FSM_IDLE;
            default:     next_state = FSM_IDLE;
        endcase
    end

    // Latch transaction descriptor on IDLE→transition
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            latched_is_write <= 1'b0;
            latched_awid     <= '0;
            latched_awaddr   <= '0;
            latched_awlen    <= '0;
            latched_awsize   <= '0;
            latched_awburst  <= '0;
            latched_arid     <= '0;
            latched_araddr   <= '0;
            latched_arlen    <= '0;
            latched_arsize   <= '0;
            latched_arburst  <= '0;
        end else if (state == FSM_IDLE && txn_req) begin
            latched_is_write <= txn_is_write;
            latched_awid     <= txn_awid;
            latched_awaddr   <= txn_awaddr;
            latched_awlen    <= txn_awlen;
            latched_awsize   <= txn_awsize;
            latched_awburst  <= txn_awburst;
            latched_arid     <= txn_arid;
            latched_araddr   <= txn_araddr;
            latched_arlen    <= txn_arlen;
            latched_arsize   <= txn_arsize;
            latched_arburst  <= txn_arburst;
        end
    end

    // AW channel drive
    assign awvalid  = (state == FSM_AW_WAIT);
    assign awid     = latched_awid;
    assign awaddr   = latched_awaddr;
    assign awlen    = latched_awlen;
    assign awsize   = latched_awsize;
    assign awburst  = latched_awburst;
    assign awlock   = 1'b0;
    assign awcache  = 4'b0011;  // Normal non-cacheable bufferable
    assign awprot   = 3'b000;
    assign awqos    = 4'd0;

    // W channel drive — pass through from TB stimulus, gate by state
    assign wvalid = (state == FSM_W_SEND) && txn_wvalid;
    assign wdata  = txn_wdata;
    assign wstrb  = txn_wstrb;
    assign wlast  = txn_wlast;
    assign txn_wready = (state == FSM_W_SEND) && wready;

    // B channel
    assign bready = (state == FSM_B_WAIT);

    // AR channel drive
    assign arvalid = (state == FSM_AR_WAIT);
    assign arid    = latched_arid;
    assign araddr  = latched_araddr;
    assign arlen   = latched_arlen;
    assign arsize  = latched_arsize;
    assign arburst = latched_arburst;
    assign arlock  = 1'b0;
    assign arcache = 4'b0011;
    assign arprot  = 3'b000;
    assign arqos   = 4'd0;

    // R channel — pass through to TB
    assign txn_rvalid = (state == FSM_R_COLL) && rvalid;
    assign txn_rdata  = rdata;
    assign txn_rresp  = rresp;
    assign txn_rlast  = rlast;
    assign rready     = (state == FSM_R_COLL) && txn_rready;

    // Arbiter requests
    assign aw_req = (state == FSM_AW_REQ) || (state == FSM_AW_WAIT);
    assign ar_req = (state == FSM_AR_REQ) || (state == FSM_AR_WAIT);

    // Completion
    assign txn_done     = (state == FSM_DONE);
    assign txn_bresp_out = (state == FSM_B_WAIT) ? bresp : 2'b00;

endmodule : axi_master
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_master.sv
git commit -m "feat: add AXI4-Full master module with per-channel FSMs"
```

---

### Task 4: AXI Crossbar — Write Path

**Files:**
- Create: `AXI/rtl/axi_crossbar_wr.sv`

**Interfaces:**
- Consumes: Nothing from earlier tasks (standalone RTL)
- Produces:
  - Module: `axi_crossbar_wr #(NUM_MASTERS=2, NUM_SLAVES=2, ID_W=8, ADDR_W=32, DATA_W=256)`
  - Per-master inputs: AW channel (awid/awaddr/awlen/awsize/awburst/awvalid), awready output; W channel (wdata/wstrb/wlast/wvalid), wready output; B channel outputs (bid/bresp/bvalid), bready input
  - Per-slave outputs: AW channel (awid/awaddr/.../awvalid), awready input; W channel (wdata/.../wvalid), wready input; B channel inputs (bid/bresp/bvalid), bready output
  - Round-robin per-slave AW arbitration, W channel locking, B demux

- [x] **Step 1: Write axi_crossbar_wr.sv**

File: `AXI/rtl/axi_crossbar_wr.sv`
```systemverilog
// AXI Write Crossbar — Per-slave AW round-robin arb, W mux + locking, B demux
// 2 masters → 2 slaves

module axi_crossbar_wr #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master-side interfaces (M x 1)
    // ============================================================
    // AW channel
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  logic [NUM_MASTERS-1:0]             m_awvalid,
    output logic [NUM_MASTERS-1:0]             m_awready,
    // W channel
    input  logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]               m_wlast,
    input  logic [NUM_MASTERS-1:0]               m_wvalid,
    output logic [NUM_MASTERS-1:0]               m_wready,
    // B channel
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output logic [NUM_MASTERS-1:0][1:0]        m_bresp,
    output logic [NUM_MASTERS-1:0]             m_bvalid,
    input  logic [NUM_MASTERS-1:0]             m_bready,

    // ============================================================
    // Slave-side interfaces (S x 1)
    // ============================================================
    // AW channel
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_awlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_awsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_awburst,
    output logic [NUM_SLAVES-1:0]             s_awvalid,
    input  logic [NUM_SLAVES-1:0]             s_awready,
    // W channel
    output logic [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]               s_wlast,
    output logic [NUM_SLAVES-1:0]               s_wvalid,
    input  logic [NUM_SLAVES-1:0]               s_wready,
    // B channel
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  logic [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  logic [NUM_SLAVES-1:0]             s_bvalid,
    output logic [NUM_SLAVES-1:0]             s_bready
);

    // Per-slave: current AW owner (which master is granted for this slave)
    logic [NUM_SLAVES-1:0]                    aw_owner;       // which master
    logic [NUM_SLAVES-1:0]                    aw_owner_valid; // grant active
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0] rr_ptr;  // round-robin pointer

    // W channel locking: per-slave, lock from AW grant until WLAST
    logic [NUM_SLAVES-1:0]                    w_owner;       // which master
    logic [NUM_SLAVES-1:0]                    w_locked;      // W burst in progress

    genvar mi, si;

    // ============================================================
    // Per-slave AW arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : aw_arb

            // Combinational: find next requesting master starting from rr_ptr
            logic [NUM_MASTERS-1:0] req_mask;
            logic [$clog2(NUM_MASTERS)-1:0] next_master;
            logic has_req;

            always_comb begin
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (int m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    automatic int m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_awvalid[m_idx] && !aw_owner_valid[si]) begin
                        next_master = m_idx;
                        has_req = 1'b1;
                        break;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    aw_owner[si]       <= '0;
                    aw_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= '0;
                end else begin
                    // AW grant: assign owner on handshake
                    if (!aw_owner_valid[si] && !w_locked[si] && has_req) begin
                        aw_owner[si]       <= next_master[$clog2(NUM_MASTERS)-1:0];
                        aw_owner_valid[si] <= 1'b1;
                        rr_ptr[si]         <= (next_master + 1) % NUM_MASTERS;
                    end
                    // Release AW grant on AW handshake
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        aw_owner_valid[si] <= 1'b0;
                    end
                end
            end

            // AW channel output — mux from granted master
            assign s_awid[si]    = (aw_owner_valid[si]) ? m_awid[aw_owner[si]]    : '0;
            assign s_awaddr[si]  = (aw_owner_valid[si]) ? m_awaddr[aw_owner[si]]  : '0;
            assign s_awlen[si]   = (aw_owner_valid[si]) ? m_awlen[aw_owner[si]]   : '0;
            assign s_awsize[si]  = (aw_owner_valid[si]) ? m_awsize[aw_owner[si]]  : '0;
            assign s_awburst[si] = (aw_owner_valid[si]) ? m_awburst[aw_owner[si]] : '0;
            assign s_awvalid[si] = aw_owner_valid[si];

            // W channel locking: lock when AW handshake completes
            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    w_locked[si] <= 1'b0;
                    w_owner[si]  <= '0;
                end else begin
                    if (aw_owner_valid[si] && s_awvalid[si] && s_awready[si]) begin
                        w_locked[si] <= 1'b1;
                        w_owner[si]  <= aw_owner[si];
                    end
                    if (w_locked[si] && s_wvalid[si] && s_wready[si] && s_wlast[si]) begin
                        w_locked[si] <= 1'b0;
                    end
                end
            end

            // W channel output — mux from locked master
            assign s_wdata[si]  = (w_locked[si]) ? m_wdata[w_owner[si]]  : '0;
            assign s_wstrb[si]  = (w_locked[si]) ? m_wstrb[w_owner[si]]  : '0;
            assign s_wlast[si]  = (w_locked[si]) ? m_wlast[w_owner[si]]  : 1'b0;
            assign s_wvalid[si] = w_locked[si] && m_wvalid[w_owner[si]];

            // B channel — demux to locked master
            assign s_bready[si] = w_locked[si] && m_bready[w_owner[si]];

        end // per-slave
    endgenerate

    // ============================================================
    // Master-side ready signals
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ready
            logic aw_ready_sig, w_ready_sig;
            always_comb begin
                aw_ready_sig = 1'b0;
                w_ready_sig  = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
                    if (aw_owner_valid[si] && aw_owner[si] == mi)
                        aw_ready_sig = s_awready[si];
                    if (w_locked[si] && w_owner[si] == mi)
                        w_ready_sig = s_wready[si];
                end
            end
            assign m_awready[mi] = aw_ready_sig;
            assign m_wready[mi]  = w_ready_sig;
        end
    endgenerate

    // ============================================================
    // B channel — route from slave to owner master
    // ============================================================
    always_comb begin
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            m_bid[mi]   = '0;
            m_bresp[mi] = '0;
            m_bvalid[mi] = 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (w_locked[si] && s_bvalid[si]) begin
                m_bid[w_owner[si]]    = s_bid[si];
                m_bresp[w_owner[si]]  = s_bresp[si];
                m_bvalid[w_owner[si]] = 1'b1;
            end
        end
    end

endmodule : axi_crossbar_wr
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_crossbar_wr.sv
git commit -m "feat: add AXI write crossbar with per-slave round-robin arbitration"
```

---

### Task 5: AXI Crossbar — Read Path

**Files:**
- Create: `AXI/rtl/axi_crossbar_rd.sv`

**Interfaces:**
- Consumes: Nothing from earlier tasks (standalone RTL)
- Produces:
  - Module: `axi_crossbar_rd #(NUM_MASTERS=2, NUM_SLAVES=2, ID_W=8, ADDR_W=32, DATA_W=256)`
  - Per-master AR outputs, per-slave AR inputs
  - Per-slave R inputs, per-master R outputs
  - ID LUT: 256 entries × 2-bit (master_id + valid) for R channel demux
  - Out-of-order R response routing by RID

- [x] **Step 1: Write axi_crossbar_rd.sv**

File: `AXI/rtl/axi_crossbar_rd.sv`
```systemverilog
// AXI Read Crossbar — Per-slave AR round-robin arb, R demux with ID LUT
// 2 masters → 2 slaves
// Supports out-of-order R responses via ID lookup table

module axi_crossbar_rd #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master-side interfaces
    // ============================================================
    // AR channel
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  logic [NUM_MASTERS-1:0]             m_arvalid,
    output logic [NUM_MASTERS-1:0]             m_arready,
    // R channel
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output logic [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]        m_rresp,
    output logic [NUM_MASTERS-1:0]             m_rlast,
    output logic [NUM_MASTERS-1:0]             m_rvalid,
    input  logic [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave-side interfaces
    // ============================================================
    // AR channel
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_arlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_arsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_arburst,
    output logic [NUM_SLAVES-1:0]             s_arvalid,
    input  logic [NUM_SLAVES-1:0]             s_arready,
    // R channel
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  logic [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  logic [NUM_SLAVES-1:0]             s_rlast,
    input  logic [NUM_SLAVES-1:0]             s_rvalid,
    output logic [NUM_SLAVES-1:0]             s_rready
);

    localparam int LUT_DEPTH = 1 << ID_W;

    // Per-slave: current AR owner
    logic [NUM_SLAVES-1:0]                             ar_owner;
    logic [NUM_SLAVES-1:0]                             ar_owner_valid;
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0]    rr_ptr;

    // ID Lookup Table: per-slave, LUT_DEPTH entries × (master_id + valid)
    logic [NUM_SLAVES-1:0][$clog2(NUM_MASTERS)-1:0]    id_lut_master [LUT_DEPTH-1:0];
    logic [NUM_SLAVES-1:0]                             id_lut_valid  [LUT_DEPTH-1:0];

    genvar si;

    // ============================================================
    // Per-slave AR arbitration (round-robin)
    // ============================================================
    generate
        for (si = 0; si < NUM_SLAVES; si = si + 1) begin : ar_arb
            logic [$clog2(NUM_MASTERS)-1:0] next_master;
            logic has_req;

            always_comb begin
                next_master = rr_ptr[si];
                has_req = 1'b0;
                for (int m_off = 0; m_off < NUM_MASTERS; m_off = m_off + 1) begin
                    automatic int m_idx = (rr_ptr[si] + m_off) % NUM_MASTERS;
                    if (m_arvalid[m_idx] && !ar_owner_valid[si]) begin
                        next_master = m_idx;
                        has_req = 1'b1;
                        break;
                    end
                end
                if (!has_req) next_master = rr_ptr[si];
            end

            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    ar_owner[si]       <= '0;
                    ar_owner_valid[si] <= 1'b0;
                    rr_ptr[si]         <= '0;
                end else begin
                    if (!ar_owner_valid[si] && has_req) begin
                        ar_owner[si]       <= next_master;
                        ar_owner_valid[si] <= 1'b1;
                        rr_ptr[si]         <= (next_master + 1) % NUM_MASTERS;
                    end
                    if (ar_owner_valid[si] && s_arvalid[si] && s_arready[si]) begin
                        ar_owner_valid[si] <= 1'b0;
                    end
                end
            end

            // AR channel output — mux from granted master
            assign s_arid[si]    = (ar_owner_valid[si]) ? m_arid[ar_owner[si]]    : '0;
            assign s_araddr[si]  = (ar_owner_valid[si]) ? m_araddr[ar_owner[si]]  : '0;
            assign s_arlen[si]   = (ar_owner_valid[si]) ? m_arlen[ar_owner[si]]   : '0;
            assign s_arsize[si]  = (ar_owner_valid[si]) ? m_arsize[ar_owner[si]]  : '0;
            assign s_arburst[si] = (ar_owner_valid[si]) ? m_arburst[ar_owner[si]] : '0;
            assign s_arvalid[si] = ar_owner_valid[si];

            // ========================================================
            // ID LUT: write on AR handshake
            // ========================================================
            always_ff @(posedge aclk or negedge aresetn) begin
                if (!aresetn) begin
                    for (int i = 0; i < LUT_DEPTH; i = i + 1) begin
                        id_lut_valid[si][i]  <= 1'b0;
                        id_lut_master[si][i] <= '0;
                    end
                end else begin
                    // Write on AR handshake
                    if (ar_owner_valid[si] && s_arvalid[si] && s_arready[si]) begin
                        id_lut_valid[si][m_arid[ar_owner[si]]]  <= 1'b1;
                        id_lut_master[si][m_arid[ar_owner[si]]] <= ar_owner[si];
                    end
                    // Clear on R last beat handshake
                    if (s_rvalid[si] && s_rready[si] && s_rlast[si]) begin
                        id_lut_valid[si][s_rid[si]] <= 1'b0;
                    end
                end
            end

        end // per-slave
    endgenerate

    // ============================================================
    // Master AR ready — route from granted slave
    // ============================================================
    generate
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_ar_rdy
            logic ar_ready_sig;
            always_comb begin
                ar_ready_sig = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
                    if (ar_owner_valid[si] && ar_owner[si] == mi)
                        ar_ready_sig = s_arready[si];
                end
            end
            assign m_arready[mi] = ar_ready_sig;
        end
    endgenerate

    // ============================================================
    // R channel demux — ID LUT lookup
    // ============================================================
    always_comb begin
        for (int mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin
            m_rid[mi]    = '0;
            m_rdata[mi]  = '0;
            m_rresp[mi]  = '0;
            m_rlast[mi]  = 1'b0;
            m_rvalid[mi] = 1'b0;
        end
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (s_rvalid[si]) begin
                automatic int r_master = id_lut_master[si][s_rid[si]];
                if (id_lut_valid[si][s_rid[si]]) begin
                    m_rid[r_master]    = s_rid[si];
                    m_rdata[r_master]  = s_rdata[si];
                    m_rresp[r_master]  = s_rresp[si];
                    m_rlast[r_master]  = s_rlast[si];
                    m_rvalid[r_master] = 1'b1;
                end
            end
        end
    end

    // ============================================================
    // R ready — route from master to slave
    // ============================================================
    always_comb begin
        s_rready = '0;
        for (int si = 0; si < NUM_SLAVES; si = si + 1) begin
            if (s_rvalid[si] && id_lut_valid[si][s_rid[si]])
                s_rready[si] = m_rready[id_lut_master[si][s_rid[si]]];
        end
    end

endmodule : axi_crossbar_rd
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_crossbar_rd.sv
git commit -m "feat: add AXI read crossbar with ID LUT for out-of-order R routing"
```

---

### Task 6: AXI Address Decoder

**Files:**
- Create: `AXI/rtl/axi_addr_decoder.sv`

**Interfaces:**
- Consumes: Nothing (standalone)
- Produces:
  - Module: `axi_addr_decoder #(NUM_SLAVES=2, ADDR_W=32)`
  - Inputs: `awaddr`, `awvalid`, `araddr`, `arvalid`
  - Outputs: `aw_sel[NUM_SLAVES]`, `ar_sel[NUM_SLAVES]`, `aw_decerr`, `ar_decerr`
  - Address map: awaddr[31:28]=0→slave0 (SRAM), 1→slave1 (DFI), other→DECERR

- [x] **Step 1: Write axi_addr_decoder.sv**

File: `AXI/rtl/axi_addr_decoder.sv`
```systemverilog
// AXI Address Decoder
// Maps AWADDR/ARADDR[31:28] to slave select
// Slave 0: 0x0xxx_xxxx (SRAM, 256KB)
// Slave 1: 0x1xxx_xxxx (DFI/DDR5, 256MB)
// Others: DECERR

module axi_addr_decoder #(
    parameter int NUM_SLAVES = 2,
    parameter int ADDR_W     = 32
) (
    input  logic [ADDR_W-1:0] awaddr,
    input  logic              awvalid,
    output logic [NUM_SLAVES-1:0] aw_sel,
    output logic              aw_decerr,

    input  logic [ADDR_W-1:0] araddr,
    input  logic              arvalid,
    output logic [NUM_SLAVES-1:0] ar_sel,
    output logic              ar_decerr
);

    function automatic logic [NUM_SLAVES:0] decode(input logic [ADDR_W-1:0] addr);
        case (addr[ADDR_W-1:28])
            4'h0: decode = {{(NUM_SLAVES-1){1'b0}}, 1'b1, 1'b0};       // slave 0, no err
            4'h1: decode = {{(NUM_SLAVES-2){1'b0}}, 1'b1, 1'b0, 1'b0};  // slave 1, no err
            default: decode = {{NUM_SLAVES{1'b0}}, 1'b1};               // no sel, decerr
        endcase
    endfunction

    logic [NUM_SLAVES:0] aw_decoded, ar_decoded;

    assign aw_decoded = decode(awaddr);
    assign ar_decoded = decode(araddr);

    assign aw_sel    = awvalid ? aw_decoded[NUM_SLAVES:1] : '0;
    assign aw_decerr = awvalid & aw_decoded[0];
    assign ar_sel    = arvalid ? ar_decoded[NUM_SLAVES:1] : '0;
    assign ar_decerr = arvalid & ar_decoded[0];

endmodule : axi_addr_decoder
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_addr_decoder.sv
git commit -m "feat: add AXI address decoder (SRAM=0x0, DFI=0x1)"
```

---

### Task 7: AXI Slave SRAM

**Files:**
- Create: `AXI/rtl/axi_slave_sram.sv`

**Interfaces:**
- Consumes: Nothing (standalone RTL)
- Produces:
  - Module: `axi_slave_sram #(DEPTH=1024, DATA_W=256, ID_W=8, STALL_PROB=0)`
  - AXI slave port (AW/W/B/AR/R channels, slave side)
  - Internal BRAM: DEPTH entries × DATA_W bits
  - Supports all burst types, narrow transfers via WSTRB masking
  - Configurable stall probability

- [x] **Step 1: Write axi_slave_sram.sv**

File: `AXI/rtl/axi_slave_sram.sv`
```systemverilog
// AXI4-Full Slave: SRAM with configurable depth and stall insertion
// Supports FIXED, INCR, WRAP bursts
// Narrow transfers via WSTRB per-byte masking

module axi_slave_sram #(
    parameter int DEPTH      = 1024,
    parameter int DATA_W     = 256,
    parameter int ID_W       = 8,
    parameter int ADDR_W     = 32,
    parameter int STALL_PROB = 0   // 0-255 out of 256 chance to stall
) (
    input  logic                aclk,
    input  logic                aresetn,

    // Write Address Channel
    input  logic [ID_W-1:0]     awid,
    input  logic [ADDR_W-1:0]   awaddr,
    input  logic [7:0]          awlen,
    input  logic [2:0]          awsize,
    input  logic [1:0]          awburst,
    input  logic                awvalid,
    output logic                awready,

    // Write Data Channel
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    input  logic                wlast,
    input  logic                wvalid,
    output logic                wready,

    // Write Response Channel
    output logic [ID_W-1:0]     bid,
    output logic [1:0]          bresp,
    output logic                bvalid,
    input  logic                bready,

    // Read Address Channel
    input  logic [ID_W-1:0]     arid,
    input  logic [ADDR_W-1:0]   araddr,
    input  logic [7:0]          arlen,
    input  logic [2:0]          arsize,
    input  logic [1:0]          arburst,
    input  logic                arvalid,
    output logic                arready,

    // Read Data Channel
    output logic [ID_W-1:0]     rid,
    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp,
    output logic                rlast,
    output logic                rvalid,
    input  logic                rready
);

    localparam AW = 0, W  = 1, B  = 2, AR = 3, R  = 4;

    // BRAM
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // Latched transaction info
    logic [ID_W-1:0]   awid_latched, arid_latched;
    logic [ADDR_W-1:0] awaddr_latched, araddr_latched;
    logic [7:0]        awlen_latched, arlen_latched;
    logic [2:0]        awsize_latched, arsize_latched;
    logic [1:0]        awburst_latched, arburst_latched;
    logic [7:0]        w_beat, r_beat;
    logic              w_active, r_active;
    logic [1:0]        w_resp;

    // Stall randomizer
    logic [7:0] stall_rng;
    logic       stall_now;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) stall_rng <= 8'h5A;
        else         stall_rng <= {stall_rng[6:0], stall_rng[7] ^ stall_rng[5] ^ stall_rng[4] ^ stall_rng[3]};
    end
    assign stall_now = (stall_rng < STALL_PROB);

    // AW channel
    assign awready = !w_active;  // one write at a time

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            w_active <= 1'b0;
        end else begin
            if (awvalid && awready) begin
                awid_latched   <= awid;
                awaddr_latched <= awaddr;
                awlen_latched  <= awlen;
                awsize_latched <= awsize;
                awburst_latched <= awburst;
                w_beat         <= '0;
                w_active       <= 1'b1;
                w_resp         <= 2'b00;  // OKAY
            end
            // Write data
            if (w_active && wvalid && wready) begin
                automatic logic [$clog2(DEPTH)-1:0] word_addr;
                automatic logic [ADDR_W-1:0] byte_addr;
                automatic logic [DATA_W-1:0] old_data, new_data;

                // Calculate address for this beat
                byte_addr = awaddr_latched + (w_beat << awsize_latched);
                word_addr = byte_addr[$clog2(DEPTH)+$clog2(DATA_W/8)-1:$clog2(DATA_W/8)];

                // Read-modify-write for narrow transfers via WSTRB
                old_data = mem[word_addr];
                for (int b = 0; b < DATA_W/8; b = b + 1) begin
                    if (wstrb[b])
                        old_data[b*8 +: 8] = wdata[b*8 +: 8];
                end
                mem[word_addr] <= old_data;

                w_beat <= w_beat + 1;
                if (wlast) w_active <= 1'b0;
            end
        end
    end

    assign wready = w_active && !(bvalid && !bready) && !stall_now;

    // B channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid <= 1'b0;
        end else begin
            if (w_active && wvalid && wready && wlast) begin
                bid    <= awid_latched;
                bresp  <= w_resp;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // AR channel
    assign arready = !r_active;

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            r_active <= 1'b0;
        end else begin
            if (arvalid && arready) begin
                arid_latched    <= arid;
                araddr_latched  <= araddr;
                arlen_latched   <= arlen;
                arsize_latched  <= arsize;
                arburst_latched <= arburst;
                r_beat          <= '0;
                r_active        <= 1'b1;
            end
            if (r_active && rvalid && rready && rlast)
                r_active <= 1'b0;
        end
    end

    // R channel
    assign rvalid = r_active && !stall_now;
    assign rid    = arid_latched;
    assign rresp  = 2'b00;
    assign rlast  = (r_beat == arlen_latched);

    function automatic logic [$clog2(DEPTH)-1:0] get_word_addr(
        input logic [ADDR_W-1:0] base, input [7:0] beat, input [2:0] size
    );
        automatic logic [ADDR_W-1:0] byte_addr = base + (beat << size);
        return byte_addr[$clog2(DEPTH)+$clog2(DATA_W/8)-1:$clog2(DATA_W/8)];
    endfunction

    always_comb begin
        rdata = mem[get_word_addr(araddr_latched, r_beat, arsize_latched)];
    end

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            // handled above
        end else begin
            if (r_active && rvalid && rready) begin
                if (r_beat < arlen_latched)
                    r_beat <= r_beat + 1;
                // On rlast, r_active cleared above — r_beat not incremented further
            end
        end
    end

endmodule : axi_slave_sram
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_slave_sram.sv
git commit -m "feat: add AXI SRAM slave with burst and narrow transfer support"
```

---

### Task 8: AXI Slave DFI Bridge (DDR5)

**Files:**
- Create: `AXI/rtl/axi_slave_dfi.sv`

**Interfaces:**
- Consumes: Nothing (standalone RTL)
- Produces:
  - Module: `axi_slave_dfi #(DATA_W=256, ID_W=8, ADDR_W=32)`
  - AXI slave port (AW/W/B/AR/R)
  - DFI port for DDR5 PHY interface
  - Transaction queue (16 entries), DDR5 timing FSM
  - DDR5 timing: tRCD=14, tCL=14, tRAS=32, tRP=14, tWR=14, BL16

- [x] **Step 1: Write axi_slave_dfi.sv**

File: `AXI/rtl/axi_slave_dfi.sv`
```systemverilog
// AXI4-Full to DFI Bridge (DDR5 PHY Interface)
// Translates AXI read/write bursts to DFI commands with DDR5 timing
// 16-entry command queue, bank-aware scheduling
// DDR5: BL16 per access (16×16bit = 256-bit per AXI beat)

module axi_slave_dfi #(
    parameter int DATA_W  = 256,
    parameter int ID_W    = 8,
    parameter int ADDR_W  = 32,
    parameter int CMD_Q_DEPTH = 16
) (
    input  logic                aclk,
    input  logic                aresetn,

    // ============================================================
    // AXI Slave Port
    // ============================================================
    // AW
    input  logic [ID_W-1:0]     awid,
    input  logic [ADDR_W-1:0]   awaddr,
    input  logic [7:0]          awlen,
    input  logic [2:0]          awsize,
    input  logic [1:0]          awburst,
    input  logic                awvalid,
    output logic                awready,
    // W
    input  logic [DATA_W-1:0]   wdata,
    input  logic [DATA_W/8-1:0] wstrb,
    input  logic                wlast,
    input  logic                wvalid,
    output logic                wready,
    // B
    output logic [ID_W-1:0]     bid,
    output logic [1:0]          bresp,
    output logic                bvalid,
    input  logic                bready,
    // AR
    input  logic [ID_W-1:0]     arid,
    input  logic [ADDR_W-1:0]   araddr,
    input  logic [7:0]          arlen,
    input  logic [2:0]          arsize,
    input  logic [1:0]          arburst,
    input  logic                arvalid,
    output logic                arready,
    // R
    output logic [ID_W-1:0]     rid,
    output logic [DATA_W-1:0]   rdata,
    output logic [1:0]          rresp,
    output logic                rlast,
    output logic                rvalid,
    input  logic                rready,

    // ============================================================
    // DFI Interface (simplified DDR5)
    // ============================================================
    output logic [31:0]         dfi_address,
    output logic [3:0]          dfi_bank,
    output logic [DATA_W-1:0]   dfi_wrdata,
    output logic [DATA_W/8-1:0] dfi_wrdata_mask,
    input  logic [DATA_W-1:0]   dfi_rddata,
    input  logic                dfi_rddata_valid,
    output logic                dfi_wrdata_valid,
    output logic                dfi_cs_n,
    output logic                dfi_ras_n,
    output logic                dfi_cas_n,
    output logic                dfi_we_n,
    output logic                dfi_act_n,
    output logic                dfi_cke
);

    // DDR5 Timing constants
    localparam tRCD = 14;
    localparam tCL  = 14;
    localparam tRAS = 32;
    localparam tRP  = 14;
    localparam tWR  = 14;
    localparam tCCD = 4;   // CAS-to-CAS delay
    localparam BL   = 16;  // Burst Length (DDR5)

    // DFI command encoding
    localparam CMD_DES  = 4'b1111;  // DESELECT
    localparam CMD_ACT  = 4'b0011;  // ACTIVATE
    localparam CMD_RD   = 4'b0101;  // READ
    localparam CMD_WR   = 4'b0100;  // WRITE
    localparam CMD_PRE  = 4'b0010;  // PRECHARGE

    // Command queue entry
    typedef struct packed {
        logic                valid;
        logic                is_write;
        logic [ID_W-1:0]     id;
        logic [31:0]         addr;
        logic [7:0]          len;
        logic [2:0]          size;
        logic [7:0]          beat_cnt;
        logic [1:0]          resp;
    } cmd_entry_t;

    // FSM states
    typedef enum logic [3:0] {
        FSM_IDLE, FSM_ACT, FSM_ACT_WAIT, FSM_RD, FSM_RD_WAIT,
        FSM_WR, FSM_WR_WAIT, FSM_PRE, FSM_PRE_WAIT, FSM_DONE
    } state_t;

    state_t state, next_state;

    cmd_entry_t cmd_q [CMD_Q_DEPTH-1:0];
    logic [$clog2(CMD_Q_DEPTH)-1:0] q_wr_ptr, q_rd_ptr;
    logic [4:0]                     q_count;  // up to 16

    // Timing counters
    logic [5:0] timer, timer_next;

    // Current command
    cmd_entry_t cur_cmd;
    logic       cur_active;
    logic       cur_w_beat_done, cur_r_beat_done;

    // Bank tracking (4 banks, track open/closed and row)
    logic [3:0]                bank_open;
    logic [3:0][15:0]          bank_row;  // simplified row address

    // =============================================================
    // Command queue management
    // =============================================================
    assign awready = (q_count < CMD_Q_DEPTH);
    assign arready = (q_count < CMD_Q_DEPTH);

    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            q_wr_ptr <= '0;
            q_rd_ptr <= '0;
            q_count  <= '0;
            for (int i = 0; i < CMD_Q_DEPTH; i++) cmd_q[i].valid <= 1'b0;
        end else begin
            // Enqueue write
            if (awvalid && awready) begin
                cmd_q[q_wr_ptr].valid    <= 1'b1;
                cmd_q[q_wr_ptr].is_write <= 1'b1;
                cmd_q[q_wr_ptr].id       <= awid;
                cmd_q[q_wr_ptr].addr     <= awaddr;
                cmd_q[q_wr_ptr].len      <= awlen;
                cmd_q[q_wr_ptr].size     <= awsize;
                cmd_q[q_wr_ptr].beat_cnt <= '0;
                cmd_q[q_wr_ptr].resp     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Enqueue read
            if (arvalid && arready) begin
                cmd_q[q_wr_ptr].valid    <= 1'b1;
                cmd_q[q_wr_ptr].is_write <= 1'b0;
                cmd_q[q_wr_ptr].id       <= arid;
                cmd_q[q_wr_ptr].addr     <= araddr;
                cmd_q[q_wr_ptr].len      <= arlen;
                cmd_q[q_wr_ptr].size     <= arsize;
                cmd_q[q_wr_ptr].beat_cnt <= '0;
                cmd_q[q_wr_ptr].resp     <= 2'b00;
                q_wr_ptr <= q_wr_ptr + 1;
                q_count  <= q_count + 1;
            end
            // Dequeue on completion
            if (state == FSM_DONE) begin
                cmd_q[q_rd_ptr].valid <= 1'b0;
                q_rd_ptr <= q_rd_ptr + 1;
                q_count  <= q_count - 1;
            end
        end
    end

    assign cur_cmd   = cmd_q[q_rd_ptr];
    assign cur_active = (q_count > 0) && cmd_q[q_rd_ptr].valid;

    // =============================================================
    // DDR5 Timing FSM
    // =============================================================
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state <= FSM_IDLE;
            timer <= '0;
        end else begin
            state <= next_state;
            timer <= timer_next;
        end
    end

    always_comb begin
        next_state = state;
        timer_next = timer;

        // DFI defaults
        dfi_cs_n  = 1'b1;
        dfi_ras_n = 1'b1;
        dfi_cas_n = 1'b1;
        dfi_we_n  = 1'b1;
        dfi_act_n = 1'b1;
        dfi_cke   = 1'b1;
        dfi_wrdata_valid = 1'b0;

        case (state)
            FSM_IDLE: begin
                if (cur_active) begin
                    if (!bank_open[cur_cmd.addr[15:14]]) begin
                        // Need ACTIVATE
                        next_state = FSM_ACT;
                        timer_next = tRCD;
                    end else if (cur_cmd.is_write) begin
                        next_state = FSM_WR;
                        timer_next = tWR;
                    end else begin
                        next_state = FSM_RD;
                        timer_next = tCL;
                    end
                end
            end

            FSM_ACT: begin
                dfi_cs_n  = 1'b0;
                dfi_ras_n = 1'b0;
                dfi_act_n = 1'b0;
                dfi_address = {16'd0, cur_cmd.addr[27:16], 4'd0};
                dfi_bank    = cur_cmd.addr[15:14];
                next_state = FSM_ACT_WAIT;
            end

            FSM_ACT_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_cmd.is_write) begin
                    next_state = FSM_WR;
                    timer_next = tWR;
                end else begin
                    next_state = FSM_RD;
                    timer_next = tCL;
                end
            end

            FSM_RD: begin
                dfi_cs_n  = 1'b0;
                dfi_cas_n = 1'b0;
                dfi_address = {16'd0, cur_cmd.addr[27:6]};
                dfi_bank    = cur_cmd.addr[15:14];
                next_state = FSM_RD_WAIT;
            end

            FSM_RD_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (dfi_rddata_valid) begin
                    // Data returned — handled in R channel logic
                    if (cur_cmd.beat_cnt >= cur_cmd.len) begin
                        next_state = FSM_PRE;
                        timer_next = tRP;
                    end else begin
                        next_state = FSM_RD;
                        timer_next = tCCD;
                    end
                end
            end

            FSM_WR: begin
                dfi_cs_n   = 1'b0;
                dfi_cas_n  = 1'b0;
                dfi_we_n   = 1'b0;
                dfi_address    = {16'd0, cur_cmd.addr[27:6]};
                dfi_bank       = cur_cmd.addr[15:14];
                dfi_wrdata       = wdata;
                dfi_wrdata_mask  = wstrb;
                dfi_wrdata_valid = 1'b1;
                next_state = FSM_WR_WAIT;
            end

            FSM_WR_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else if (cur_cmd.beat_cnt >= cur_cmd.len) begin
                    next_state = FSM_PRE;
                    timer_next = tRP;
                end else begin
                    next_state = FSM_WR;
                    timer_next = tCCD;
                end
            end

            FSM_PRE: begin
                dfi_cs_n  = 1'b0;
                dfi_ras_n = 1'b0;
                dfi_we_n  = 1'b0;
                dfi_bank  = cur_cmd.addr[15:14];
                next_state = FSM_PRE_WAIT;
            end

            FSM_PRE_WAIT: begin
                if (timer > 0) timer_next = timer - 1;
                else next_state = FSM_DONE;
            end

            FSM_DONE: begin
                next_state = FSM_IDLE;
            end

            default: next_state = FSM_IDLE;
        endcase
    end

    // Bank tracking
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bank_open <= '0;
            bank_row  <= '0;
        end else begin
            if (state == FSM_ACT) begin
                bank_open[cur_cmd.addr[15:14]] <= 1'b1;
                bank_row[cur_cmd.addr[15:14]]   <= cur_cmd.addr[27:16];
            end
            if (state == FSM_PRE) begin
                bank_open[cur_cmd.addr[15:14]] <= 1'b0;
            end
        end
    end

    // Beat counter increment
    always_ff @(posedge aclk) begin
        if (state == FSM_RD && dfi_rddata_valid)
            cmd_q[q_rd_ptr].beat_cnt <= cur_cmd.beat_cnt + 1;
        if (state == FSM_WR && wvalid && wready)
            cmd_q[q_rd_ptr].beat_cnt <= cur_cmd.beat_cnt + 1;
    end

    // =============================================================
    // AXI Response Channels
    // =============================================================

    // Write data ready — accept when in WR state
    assign wready = (state == FSM_WR);

    // B channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            bvalid <= 1'b0;
        end else begin
            if (state == FSM_DONE && cur_cmd.is_write) begin
                bid    <= cur_cmd.id;
                bresp  <= cur_cmd.resp;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) bvalid <= 1'b0;
        end
    end

    // R channel
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
        end else begin
            if (state == FSM_RD_WAIT && dfi_rddata_valid) begin
                rid    <= cur_cmd.id;
                rdata  <= dfi_rddata;
                rresp  <= cur_cmd.resp;
                rlast  <= (cur_cmd.beat_cnt >= cur_cmd.len);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) rvalid <= 1'b0;
        end
    end

endmodule : axi_slave_dfi
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_slave_dfi.sv
git commit -m "feat: add AXI-to-DFI bridge for DDR5 with timing FSM"
```

---

### Task 9: AXI Interconnect (Integration)

**Files:**
- Create: `AXI/rtl/axi_interconnect.sv`

**Interfaces:**
- Consumes:
  - `axi_crossbar_wr` (Task 4)
  - `axi_crossbar_rd` (Task 5)
  - `axi_addr_decoder` (Task 6)
- Produces:
  - Module: `axi_interconnect #(NUM_MASTERS=2, NUM_SLAVES=2, ...)`
  - Instantiates write crossbar, read crossbar, address decoder
  - Master ports, slave ports, decoded slave selects
  - Connects AW/AR signals through decoder → per-slave crossbar inputs

- [x] **Step 1: Write axi_interconnect.sv**

File: `AXI/rtl/axi_interconnect.sv`
```systemverilog
// AXI Interconnect — Crossbar + Address Decoder integration
// 2 masters → decoder → write/read crossbars → 2 slaves

module axi_interconnect #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master ports (M x 5 channels)
    // ============================================================
    // AW
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_awid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_awlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_awsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_awburst,
    input  logic [NUM_MASTERS-1:0]             m_awvalid,
    output logic [NUM_MASTERS-1:0]             m_awready,
    // W
    input  logic [NUM_MASTERS-1:0][DATA_W-1:0]   m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_W/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]               m_wlast,
    input  logic [NUM_MASTERS-1:0]               m_wvalid,
    output logic [NUM_MASTERS-1:0]               m_wready,
    // B
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_bid,
    output logic [NUM_MASTERS-1:0][1:0]        m_bresp,
    output logic [NUM_MASTERS-1:0]             m_bvalid,
    input  logic [NUM_MASTERS-1:0]             m_bready,
    // AR
    input  logic [NUM_MASTERS-1:0][ID_W-1:0]   m_arid,
    input  logic [NUM_MASTERS-1:0][ADDR_W-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0][7:0]        m_arlen,
    input  logic [NUM_MASTERS-1:0][2:0]        m_arsize,
    input  logic [NUM_MASTERS-1:0][1:0]        m_arburst,
    input  logic [NUM_MASTERS-1:0]             m_arvalid,
    output logic [NUM_MASTERS-1:0]             m_arready,
    // R
    output logic [NUM_MASTERS-1:0][ID_W-1:0]   m_rid,
    output logic [NUM_MASTERS-1:0][DATA_W-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]        m_rresp,
    output logic [NUM_MASTERS-1:0]             m_rlast,
    output logic [NUM_MASTERS-1:0]             m_rvalid,
    input  logic [NUM_MASTERS-1:0]             m_rready,

    // ============================================================
    // Slave ports
    // ============================================================
    // AW
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_awid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_awaddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_awlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_awsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_awburst,
    output logic [NUM_SLAVES-1:0]             s_awvalid,
    input  logic [NUM_SLAVES-1:0]             s_awready,
    // W
    output logic [NUM_SLAVES-1:0][DATA_W-1:0]   s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]               s_wlast,
    output logic [NUM_SLAVES-1:0]               s_wvalid,
    input  logic [NUM_SLAVES-1:0]               s_wready,
    // B
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_bid,
    input  logic [NUM_SLAVES-1:0][1:0]        s_bresp,
    input  logic [NUM_SLAVES-1:0]             s_bvalid,
    output logic [NUM_SLAVES-1:0]             s_bready,
    // AR
    output logic [NUM_SLAVES-1:0][ID_W-1:0]   s_arid,
    output logic [NUM_SLAVES-1:0][ADDR_W-1:0] s_araddr,
    output logic [NUM_SLAVES-1:0][7:0]        s_arlen,
    output logic [NUM_SLAVES-1:0][2:0]        s_arsize,
    output logic [NUM_SLAVES-1:0][1:0]        s_arburst,
    output logic [NUM_SLAVES-1:0]             s_arvalid,
    input  logic [NUM_SLAVES-1:0]             s_arready,
    // R
    input  logic [NUM_SLAVES-1:0][ID_W-1:0]   s_rid,
    input  logic [NUM_SLAVES-1:0][DATA_W-1:0] s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]        s_rresp,
    input  logic [NUM_SLAVES-1:0]             s_rlast,
    input  logic [NUM_SLAVES-1:0]             s_rvalid,
    output logic [NUM_SLAVES-1:0]             s_rready
);

    // Decoder outputs
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0] m_aw_sel, m_ar_sel;
    logic [NUM_MASTERS-1:0]                m_aw_decerr, m_ar_decerr;

    // Per-master → per-slave AW/W signals (gated by decoder)
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_awid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_awaddr;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_awlen;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_awsize;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_awburst;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_awready;

    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W-1:0]   x_wdata;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][DATA_W/8-1:0] x_wstrb;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wlast;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]               x_wready;

    // Per-master → per-slave AR signals
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ID_W-1:0]   x_arid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][ADDR_W-1:0] x_araddr;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][7:0]        x_arlen;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][2:0]        x_arsize;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0][1:0]        x_arburst;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arvalid;
    logic [NUM_MASTERS-1:0][NUM_SLAVES-1:0]             x_arready;

    // Crossbar-to-slave signals
    logic [NUM_SLAVES-1:0][ID_W-1:0]   wb_awid, wb_awaddr_lo, rb_arid, rb_araddr_lo;
    // Actually, crossbar outputs are already packed as arrays...

    genvar mi, si;

    // ============================================================
    // Per-master address decoders
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_dec
            axi_addr_decoder #(.NUM_SLAVES(NUM_SLAVES), .ADDR_W(ADDR_W)) u_dec (
                .awaddr   (m_awaddr[mi]),
                .awvalid  (m_awvalid[mi]),
                .aw_sel   (m_aw_sel[mi]),
                .aw_decerr(m_aw_decerr[mi]),
                .araddr   (m_araddr[mi]),
                .arvalid  (m_arvalid[mi]),
                .ar_sel   (m_ar_sel[mi]),
                .ar_decerr(m_ar_decerr[mi])
            );
        end
    endgenerate

    // ============================================================
    // Gate master signals to per-slave crossbar ports
    // ============================================================
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_gate
            for (si = 0; si < NUM_SLAVES; si = si + 1) begin : s_gate
                // AW: only pass valid if decoder selected this slave
                assign x_awid[mi][si]   = m_awid[mi];
                assign x_awaddr[mi][si] = m_awaddr[mi];
                assign x_awlen[mi][si]  = m_awlen[mi];
                assign x_awsize[mi][si] = m_awsize[mi];
                assign x_awburst[mi][si] = m_awburst[mi];
                assign x_awvalid[mi][si] = m_awvalid[mi] && m_aw_sel[mi][si];

                // W
                assign x_wdata[mi][si]  = m_wdata[mi];
                assign x_wstrb[mi][si]  = m_wstrb[mi];
                assign x_wlast[mi][si]  = m_wlast[mi];
                assign x_wvalid[mi][si] = m_wvalid[mi] && m_aw_sel[mi][si];

                // AR
                assign x_arid[mi][si]   = m_arid[mi];
                assign x_araddr[mi][si] = m_araddr[mi];
                assign x_arlen[mi][si]  = m_arlen[mi];
                assign x_arsize[mi][si] = m_arsize[mi];
                assign x_arburst[mi][si] = m_arburst[mi];
                assign x_arvalid[mi][si] = m_arvalid[mi] && m_ar_sel[mi][si];
            end
        end
    endgenerate

    // ============================================================
    // Write Crossbar
    // ============================================================
    axi_crossbar_wr #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                      .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_crossbar_wr (
        .aclk, .aresetn,
        .m_awid   (x_awid),   .m_awaddr  (x_awaddr),  .m_awlen (x_awlen),
        .m_awsize (x_awsize), .m_awburst (x_awburst), .m_awvalid(x_awvalid),
        .m_awready(x_awready),
        .m_wdata  (x_wdata),  .m_wstrb   (x_wstrb),   .m_wlast (x_wlast),
        .m_wvalid (x_wvalid), .m_wready  (x_wready),
        .m_bid    (m_bid),    .m_bresp   (m_bresp),   .m_bvalid(m_bvalid),
        .m_bready (m_bready),
        .s_awid   (s_awid),   .s_awaddr  (s_awaddr),  .s_awlen (s_awlen),
        .s_awsize (s_awsize), .s_awburst (s_awburst), .s_awvalid(s_awvalid),
        .s_awready(s_awready),
        .s_wdata  (s_wdata),  .s_wstrb   (s_wstrb),   .s_wlast (s_wlast),
        .s_wvalid (s_wvalid), .s_wready  (s_wready),
        .s_bid    (s_bid),    .s_bresp   (s_bresp),   .s_bvalid(s_bvalid),
        .s_bready (s_bready)
    );

    // ============================================================
    // Read Crossbar
    // ============================================================
    axi_crossbar_rd #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                      .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_crossbar_rd (
        .aclk, .aresetn,
        .m_arid   (x_arid),   .m_araddr  (x_araddr),  .m_arlen (x_arlen),
        .m_arsize (x_arsize), .m_arburst (x_arburst), .m_arvalid(x_arvalid),
        .m_arready(x_arready),
        .m_rid    (m_rid),    .m_rdata   (m_rdata),   .m_rresp (m_rresp),
        .m_rlast  (m_rlast),  .m_rvalid  (m_rvalid),  .m_rready(m_rready),
        .s_arid   (s_arid),   .s_araddr  (s_araddr),  .s_arlen (s_arlen),
        .s_arsize (s_arsize), .s_arburst (s_arburst), .s_arvalid(s_arvalid),
        .s_arready(s_arready),
        .s_rid    (s_rid),    .s_rdata   (s_rdata),   .s_rresp (s_rresp),
        .s_rlast  (s_rlast),  .s_rvalid  (s_rvalid),  .s_rready(s_rready)
    );

    // Master AW/AR ready: route from crossbar with decoder gating
    generate
        for (mi = 0; mi < NUM_MASTERS; mi = mi + 1) begin : m_rdy
            logic aw_rdy, ar_rdy;
            always_comb begin
                aw_rdy = 1'b0;
                ar_rdy = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si++) begin
                    if (m_aw_sel[mi][si]) aw_rdy = x_awready[mi][si];
                    if (m_ar_sel[mi][si]) ar_rdy = x_arready[mi][si];
                end
            end
            assign m_awready[mi] = aw_rdy;
            assign m_arready[mi] = ar_rdy;

            // W ready
            logic w_rdy;
            always_comb begin
                w_rdy = 1'b0;
                for (int si = 0; si < NUM_SLAVES; si++)
                    if (m_aw_sel[mi][si]) w_rdy = x_wready[mi][si];
            end
            assign m_wready[mi] = w_rdy;
        end
    endgenerate

endmodule : axi_interconnect
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_interconnect.sv
git commit -m "feat: add AXI interconnect integrating crossbars and decoder"
```

---

### Task 10: AXI Top-Level Integration

**Files:**
- Create: `AXI/rtl/axi_top.sv`

**Interfaces:**
- Consumes: `axi_master`, `axi_interconnect`, `axi_slave_sram`, `axi_slave_dfi`
- Produces:
  - Module: `axi_top`
  - 2 masters, interconnect, 1 SRAM slave, 1 DFI slave
  - Exposes per-master txn control ports and DFI port

- [x] **Step 1: Write axi_top.sv**

File: `AXI/rtl/axi_top.sv`
```systemverilog
// AXI4-Full Top-Level Integration
// 2 Masters → Interconnect (Crossbar + Decoder) → SRAM Slave + DFI Slave

module axi_top #(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 2,
    parameter int ID_W  = 8,
    parameter int ADDR_W = 32,
    parameter int DATA_W = 256
) (
    input  logic aclk,
    input  logic aresetn,

    // ============================================================
    // Master 0 txn stimulus (from testbench)
    // ============================================================
    input  logic                 txn_req_0,
    input  logic                 txn_is_write_0,
    input  logic [ID_W-1:0]      txn_awid_0,
    input  logic [ADDR_W-1:0]    txn_awaddr_0,
    input  logic [7:0]           txn_awlen_0,
    input  logic [2:0]           txn_awsize_0,
    input  logic [1:0]           txn_awburst_0,
    input  logic [ID_W-1:0]      txn_arid_0,
    input  logic [ADDR_W-1:0]    txn_araddr_0,
    input  logic [7:0]           txn_arlen_0,
    input  logic [2:0]           txn_arsize_0,
    input  logic [1:0]           txn_arburst_0,
    // Write data streaming
    input  logic                 txn_wvalid_0,
    input  logic [DATA_W-1:0]    txn_wdata_0,
    input  logic [DATA_W/8-1:0]  txn_wstrb_0,
    input  logic                 txn_wlast_0,
    output logic                 txn_wready_0,
    // Read data streaming
    output logic                 txn_rvalid_0,
    output logic [DATA_W-1:0]    txn_rdata_0,
    output logic [1:0]           txn_rresp_0,
    output logic                 txn_rlast_0,
    input  logic                 txn_rready_0,
    // Completion
    output logic                 txn_done_0,
    output logic [1:0]           txn_bresp_0,

    // ============================================================
    // Master 1 txn stimulus (from testbench)
    // ============================================================
    input  logic                 txn_req_1,
    input  logic                 txn_is_write_1,
    input  logic [ID_W-1:0]      txn_awid_1,
    input  logic [ADDR_W-1:0]    txn_awaddr_1,
    input  logic [7:0]           txn_awlen_1,
    input  logic [2:0]           txn_awsize_1,
    input  logic [1:0]           txn_awburst_1,
    input  logic [ID_W-1:0]      txn_arid_1,
    input  logic [ADDR_W-1:0]    txn_araddr_1,
    input  logic [7:0]           txn_arlen_1,
    input  logic [2:0]           txn_arsize_1,
    input  logic [1:0]           txn_arburst_1,
    // Write data streaming
    input  logic                 txn_wvalid_1,
    input  logic [DATA_W-1:0]    txn_wdata_1,
    input  logic [DATA_W/8-1:0]  txn_wstrb_1,
    input  logic                 txn_wlast_1,
    output logic                 txn_wready_1,
    // Read data streaming
    output logic                 txn_rvalid_1,
    output logic [DATA_W-1:0]    txn_rdata_1,
    output logic [1:0]           txn_rresp_1,
    output logic                 txn_rlast_1,
    input  logic                 txn_rready_1,
    // Completion
    output logic                 txn_done_1,
    output logic [1:0]           txn_bresp_1,

    // ============================================================
    // DFI Port (exposed for monitoring)
    // ============================================================
    output logic [31:0]         dfi_address,
    output logic [3:0]          dfi_bank,
    output logic [DATA_W-1:0]   dfi_wrdata,
    output logic [DATA_W/8-1:0] dfi_wrdata_mask,
    output logic                dfi_wrdata_valid,
    output logic                dfi_cs_n,
    output logic                dfi_ras_n,
    output logic                dfi_cas_n,
    output logic                dfi_we_n,
    output logic                dfi_act_n

    // Note: dfi_rddata, dfi_rddata_valid driven low (no external DRAM model)
    // For verification, the scoreboard models DDR5 internally
);

    // Interconnect ↔ Master signals
    logic [NUM_MASTERS-1:0][ID_W-1:0]   ic_awid, ic_arid;
    logic [NUM_MASTERS-1:0][ADDR_W-1:0] ic_awaddr, ic_araddr;
    logic [NUM_MASTERS-1:0][7:0]        ic_awlen, ic_arlen;
    logic [NUM_MASTERS-1:0][2:0]        ic_awsize, ic_arsize;
    logic [NUM_MASTERS-1:0][1:0]        ic_awburst, ic_arburst;
    logic [NUM_MASTERS-1:0]             ic_awvalid, ic_awready;
    logic [NUM_MASTERS-1:0]             ic_arvalid, ic_arready;
    logic [NUM_MASTERS-1:0][DATA_W-1:0] ic_wdata, ic_rdata;
    logic [NUM_MASTERS-1:0][DATA_W/8-1:0] ic_wstrb;
    logic [NUM_MASTERS-1:0]             ic_wlast, ic_wvalid, ic_wready;
    logic [NUM_MASTERS-1:0][ID_W-1:0]   ic_bid, ic_rid;
    logic [NUM_MASTERS-1:0][1:0]        ic_bresp, ic_rresp;
    logic [NUM_MASTERS-1:0]             ic_bvalid, ic_bready;
    logic [NUM_MASTERS-1:0]             ic_rlast, ic_rvalid, ic_rready;

    // Interconnect ↔ Slave signals
    logic [NUM_SLAVES-1:0][ID_W-1:0]    s_awid, s_arid;
    logic [NUM_SLAVES-1:0][ADDR_W-1:0]  s_awaddr, s_araddr;
    logic [NUM_SLAVES-1:0][7:0]         s_awlen, s_arlen;
    logic [NUM_SLAVES-1:0][2:0]         s_awsize, s_arsize;
    logic [NUM_SLAVES-1:0][1:0]         s_awburst, s_arburst;
    logic [NUM_SLAVES-1:0]              s_awvalid, s_awready;
    logic [NUM_SLAVES-1:0]              s_arvalid, s_arready;
    logic [NUM_SLAVES-1:0][DATA_W-1:0]  s_wdata, s_rdata;
    logic [NUM_SLAVES-1:0][DATA_W/8-1:0] s_wstrb;
    logic [NUM_SLAVES-1:0]              s_wlast, s_wvalid, s_wready;
    logic [NUM_SLAVES-1:0][ID_W-1:0]    s_bid, s_rid;
    logic [NUM_SLAVES-1:0][1:0]         s_bresp, s_rresp;
    logic [NUM_SLAVES-1:0]              s_bvalid, s_bready;
    logic [NUM_SLAVES-1:0]              s_rlast, s_rvalid, s_rready;

    // Master per-channel request/grant
    logic [NUM_MASTERS-1:0] m0_aw_req, m0_aw_gnt, m0_ar_req, m0_ar_gnt;
    logic [NUM_MASTERS-1:0] m1_aw_req, m1_aw_gnt, m1_ar_req, m1_ar_gnt;

    genvar i;

    // ============================================================
    // Master 0
    // ============================================================
    axi_master #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master0 (
        .aclk, .aresetn,
        .aw_req  (m0_aw_req),  .aw_gnt  (m0_aw_gnt),
        .ar_req  (m0_ar_req),  .ar_gnt  (m0_ar_gnt),
        .awid    (ic_awid[0]), .awaddr  (ic_awaddr[0]),
        .awlen   (ic_awlen[0]), .awsize  (ic_awsize[0]),
        .awburst (ic_awburst[0]), .awlock (), .awcache(), .awprot(), .awqos(),
        .awvalid (ic_awvalid[0]), .awready(ic_awready[0]),
        .wdata   (ic_wdata[0]), .wstrb   (ic_wstrb[0]),
        .wlast   (ic_wlast[0]), .wvalid  (ic_wvalid[0]),
        .wready  (ic_wready[0]),
        .bid     (ic_bid[0]),  .bresp    (ic_bresp[0]),
        .bvalid  (ic_bvalid[0]), .bready  (ic_bready[0]),
        .arid    (ic_arid[0]), .araddr   (ic_araddr[0]),
        .arlen   (ic_arlen[0]), .arsize   (ic_arsize[0]),
        .arburst (ic_arburst[0]), .arlock (), .arcache(), .arprot(), .arqos(),
        .arvalid (ic_arvalid[0]), .arready(ic_arready[0]),
        .rid     (ic_rid[0]),  .rdata    (ic_rdata[0]),
        .rresp   (ic_rresp[0]), .rlast    (ic_rlast[0]),
        .rvalid  (ic_rvalid[0]), .rready   (ic_rready[0]),
        .txn_req     (txn_req_0),
        .txn_is_write(txn_is_write_0),
        .txn_awid    (txn_awid_0),
        .txn_awaddr  (txn_awaddr_0),
        .txn_awlen   (txn_awlen_0),
        .txn_awsize  (txn_awsize_0),
        .txn_awburst (txn_awburst_0),
        .txn_arid    (txn_arid_0),
        .txn_araddr  (txn_araddr_0),
        .txn_arlen   (txn_arlen_0),
        .txn_arsize  (txn_arsize_0),
        .txn_arburst (txn_arburst_0),
        .txn_wvalid  (txn_wvalid_0),
        .txn_wdata   (txn_wdata_0),
        .txn_wstrb   (txn_wstrb_0),
        .txn_wlast   (txn_wlast_0),
        .txn_wready  (txn_wready_0),
        .txn_rvalid  (txn_rvalid_0),
        .txn_rdata   (txn_rdata_0),
        .txn_rresp   (txn_rresp_0),
        .txn_rlast   (txn_rlast_0),
        .txn_rready  (txn_rready_0),
        .txn_done    (txn_done_0),
        .txn_bresp_out(txn_bresp_0)
    );

    // ============================================================
    // Master 1
    // ============================================================
    axi_master #(.ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) u_master1 (
        .aclk, .aresetn,
        .aw_req  (m1_aw_req),  .aw_gnt  (m1_aw_gnt),
        .ar_req  (m1_ar_req),  .ar_gnt  (m1_ar_gnt),
        .awid    (ic_awid[1]), .awaddr  (ic_awaddr[1]),
        .awlen   (ic_awlen[1]), .awsize  (ic_awsize[1]),
        .awburst (ic_awburst[1]), .awlock (), .awcache(), .awprot(), .awqos(),
        .awvalid (ic_awvalid[1]), .awready(ic_awready[1]),
        .wdata   (ic_wdata[1]), .wstrb   (ic_wstrb[1]),
        .wlast   (ic_wlast[1]), .wvalid  (ic_wvalid[1]),
        .wready  (ic_wready[1]),
        .bid     (ic_bid[1]),  .bresp    (ic_bresp[1]),
        .bvalid  (ic_bvalid[1]), .bready  (ic_bready[1]),
        .arid    (ic_arid[1]), .araddr   (ic_araddr[1]),
        .arlen   (ic_arlen[1]), .arsize   (ic_arsize[1]),
        .arburst (ic_arburst[1]), .arlock (), .arcache(), .arprot(), .arqos(),
        .arvalid (ic_arvalid[1]), .arready(ic_arready[1]),
        .rid     (ic_rid[1]),  .rdata    (ic_rdata[1]),
        .rresp   (ic_rresp[1]), .rlast    (ic_rlast[1]),
        .rvalid  (ic_rvalid[1]), .rready   (ic_rready[1]),
        .txn_req     (txn_req_1),
        .txn_is_write(txn_is_write_1),
        .txn_awid    (txn_awid_1),
        .txn_awaddr  (txn_awaddr_1),
        .txn_awlen   (txn_awlen_1),
        .txn_awsize  (txn_awsize_1),
        .txn_awburst (txn_awburst_1),
        .txn_arid    (txn_arid_1),
        .txn_araddr  (txn_araddr_1),
        .txn_arlen   (txn_arlen_1),
        .txn_arsize  (txn_arsize_1),
        .txn_arburst (txn_arburst_1),
        .txn_wvalid  (txn_wvalid_1),
        .txn_wdata   (txn_wdata_1),
        .txn_wstrb   (txn_wstrb_1),
        .txn_wlast   (txn_wlast_1),
        .txn_wready  (txn_wready_1),
        .txn_rvalid  (txn_rvalid_1),
        .txn_rdata   (txn_rdata_1),
        .txn_rresp   (txn_rresp_1),
        .txn_rlast   (txn_rlast_1),
        .txn_rready  (txn_rready_1),
        .txn_done    (txn_done_1),
        .txn_bresp_out(txn_bresp_1)
    );

    // Master AW/AR request mapper: any request downstream (always granted via crossbar)
    assign m0_aw_gnt = ic_awvalid[0] ? 1'b1 : 1'b0;  // Interconnect grants immediately
    assign m0_ar_gnt = ic_arvalid[0] ? 1'b1 : 1'b0;
    assign m1_aw_gnt = ic_awvalid[1] ? 1'b1 : 1'b0;
    assign m1_ar_gnt = ic_arvalid[1] ? 1'b1 : 1'b0;

    // ============================================================
    // AXI Interconnect
    // ============================================================
    axi_interconnect #(.NUM_MASTERS(NUM_MASTERS), .NUM_SLAVES(NUM_SLAVES),
                       .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_interconnect (
        .aclk, .aresetn,
        // Master ports
        .m_awid   (ic_awid),   .m_awaddr  (ic_awaddr),
        .m_awlen  (ic_awlen),  .m_awsize  (ic_awsize),
        .m_awburst(ic_awburst),.m_awvalid (ic_awvalid),
        .m_awready(ic_awready),
        .m_wdata  (ic_wdata),  .m_wstrb   (ic_wstrb),
        .m_wlast  (ic_wlast),  .m_wvalid  (ic_wvalid),
        .m_wready (ic_wready),
        .m_bid    (ic_bid),    .m_bresp   (ic_bresp),
        .m_bvalid (ic_bvalid), .m_bready  (ic_bready),
        .m_arid   (ic_arid),   .m_araddr  (ic_araddr),
        .m_arlen  (ic_arlen),  .m_arsize  (ic_arsize),
        .m_arburst(ic_arburst),.m_arvalid (ic_arvalid),
        .m_arready(ic_arready),
        .m_rid    (ic_rid),    .m_rdata   (ic_rdata),
        .m_rresp  (ic_rresp),  .m_rlast   (ic_rlast),
        .m_rvalid (ic_rvalid), .m_rready  (ic_rready),
        // Slave ports
        .s_awid   (s_awid),    .s_awaddr  (s_awaddr),
        .s_awlen  (s_awlen),   .s_awsize  (s_awsize),
        .s_awburst(s_awburst), .s_awvalid (s_awvalid),
        .s_awready(s_awready),
        .s_wdata  (s_wdata),   .s_wstrb   (s_wstrb),
        .s_wlast  (s_wlast),   .s_wvalid  (s_wvalid),
        .s_wready (s_wready),
        .s_bid    (s_bid),     .s_bresp   (s_bresp),
        .s_bvalid (s_bvalid),  .s_bready  (s_bready),
        .s_arid   (s_arid),    .s_araddr  (s_araddr),
        .s_arlen  (s_arlen),   .s_arsize  (s_arsize),
        .s_arburst(s_arburst), .s_arvalid (s_arvalid),
        .s_arready(s_arready),
        .s_rid    (s_rid),     .s_rdata   (s_rdata),
        .s_rresp  (s_rresp),   .s_rlast   (s_rlast),
        .s_rvalid (s_rvalid),  .s_rready  (s_rready)
    );

    // ============================================================
    // Slave 0: SRAM
    // ============================================================
    axi_slave_sram #(.DEPTH(1024), .DATA_W(DATA_W), .ID_W(ID_W),
                     .ADDR_W(ADDR_W), .STALL_PROB(0))
    u_slave_sram (
        .aclk, .aresetn,
        .awid   (s_awid[0]),   .awaddr (s_awaddr[0]),
        .awlen  (s_awlen[0]),  .awsize (s_awsize[0]),
        .awburst(s_awburst[0]),.awvalid(s_awvalid[0]),
        .awready(s_awready[0]),
        .wdata  (s_wdata[0]),  .wstrb (s_wstrb[0]),
        .wlast  (s_wlast[0]),  .wvalid(s_wvalid[0]),
        .wready (s_wready[0]),
        .bid    (s_bid[0]),    .bresp (s_bresp[0]),
        .bvalid (s_bvalid[0]), .bready(s_bready[0]),
        .arid   (s_arid[0]),   .araddr(s_araddr[0]),
        .arlen  (s_arlen[0]),  .arsize(s_arsize[0]),
        .arburst(s_arburst[0]),.arvalid(s_arvalid[0]),
        .arready(s_arready[0]),
        .rid    (s_rid[0]),    .rdata (s_rdata[0]),
        .rresp  (s_rresp[0]),  .rlast (s_rlast[0]),
        .rvalid (s_rvalid[0]), .rready(s_rready[0])
    );

    // ============================================================
    // Slave 1: DFI Bridge (DDR5)
    // ============================================================
    assign dfi_cke = 1'b1;  // Always on for simulation

    axi_slave_dfi #(.DATA_W(DATA_W), .ID_W(ID_W), .ADDR_W(ADDR_W))
    u_slave_dfi (
        .aclk, .aresetn,
        .awid   (s_awid[1]),   .awaddr (s_awaddr[1]),
        .awlen  (s_awlen[1]),  .awsize (s_awsize[1]),
        .awburst(s_awburst[1]),.awvalid(s_awvalid[1]),
        .awready(s_awready[1]),
        .wdata  (s_wdata[1]),  .wstrb (s_wstrb[1]),
        .wlast  (s_wlast[1]),  .wvalid(s_wvalid[1]),
        .wready (s_wready[1]),
        .bid    (s_bid[1]),    .bresp (s_bresp[1]),
        .bvalid (s_bvalid[1]), .bready(s_bready[1]),
        .arid   (s_arid[1]),   .araddr(s_araddr[1]),
        .arlen  (s_arlen[1]),  .arsize(s_arsize[1]),
        .arburst(s_arburst[1]),.arvalid(s_arvalid[1]),
        .arready(s_arready[1]),
        .rid    (s_rid[1]),    .rdata (s_rdata[1]),
        .rresp  (s_rresp[1]),  .rlast (s_rlast[1]),
        .rvalid (s_rvalid[1]), .rready(s_rready[1]),
        // DFI
        .dfi_address      (dfi_address),
        .dfi_bank         (dfi_bank),
        .dfi_wrdata       (dfi_wrdata),
        .dfi_wrdata_mask  (dfi_wrdata_mask),
        .dfi_rddata       ('0),   // No external DRAM model
        .dfi_rddata_valid (1'b0),
        .dfi_wrdata_valid (dfi_wrdata_valid),
        .dfi_cs_n         (dfi_cs_n),
        .dfi_ras_n        (dfi_ras_n),
        .dfi_cas_n        (dfi_cas_n),
        .dfi_we_n         (dfi_we_n),
        .dfi_act_n        (dfi_act_n)
    );

endmodule : axi_top
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI
git add rtl/axi_top.sv
git commit -m "feat: add AXI top-level integration with 2 masters, SRAM, and DFI slave"
```

---

---

### Task 11: UVM Master Driver

**Files:**
- Create: `AXI/tb/axi_master_driver.sv`

**Interfaces:**
- Consumes: `axi_pkg::axi_transaction`, `axi_if` (from Task 2)
- Produces: `axi_master_driver` class that translates `axi_transaction` items to AXI bus signals via `axi_if.drv_cb`

- [x] **Step 1: Write axi_master_driver.sv**

File: `AXI/tb/axi_master_driver.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

// AXI Master Driver — translates axi_transaction to pin-level AXI protocol
class axi_master_driver extends uvm_driver #(axi_transaction);

    `uvm_component_utils(axi_master_driver)

    virtual axi_if vif;
    int master_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            axi_transaction txn;
            seq_item_port.get_next_item(txn);

            if (txn.is_write) begin
                drive_aw(txn);
                drive_w_burst(txn);
                wait_bresp(txn);
                if (txn.has_both) begin
                    drive_ar(txn);
                    collect_r_burst(txn);
                end
            end else begin
                drive_ar(txn);
                collect_r_burst(txn);
            end

            seq_item_port.item_done();
        end
    endtask

    task drive_aw(axi_transaction txn);
        @(vif.drv_cb);
        vif.drv_cb.awid    <= txn.awid;
        vif.drv_cb.awaddr  <= txn.awaddr;
        vif.drv_cb.awlen   <= txn.awlen;
        vif.drv_cb.awsize  <= txn.awsize;
        vif.drv_cb.awburst <= txn.awburst;
        vif.drv_cb.awlock  <= 1'b0;
        vif.drv_cb.awcache <= txn.awcache;
        vif.drv_cb.awprot  <= txn.awprot;
        vif.drv_cb.awqos   <= txn.awqos;
        vif.drv_cb.awvalid <= 1'b1;
        @(vif.drv_cb);
        while (!vif.drv_cb.awready)
            @(vif.drv_cb);
        vif.drv_cb.awvalid <= 1'b0;
    endtask

    task drive_w_burst(axi_transaction txn);
        for (int i = 0; i <= txn.awlen; i++) begin
            @(vif.drv_cb);
            vif.drv_cb.wdata  <= txn.wdata_q[i];
            vif.drv_cb.wstrb  <= txn.wstrb_q[i];
            vif.drv_cb.wlast  <= (i == txn.awlen);
            vif.drv_cb.wvalid <= 1'b1;
            @(vif.drv_cb);
            while (!vif.drv_cb.wready)
                @(vif.drv_cb);
        end
        vif.drv_cb.wvalid <= 1'b0;
    endtask

    task wait_bresp(axi_transaction txn);
        do begin
            @(vif.drv_cb);
        end while (!vif.drv_cb.bvalid);
        txn.bresp = vif.drv_cb.bresp;
        vif.drv_cb.bready <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.bready <= 1'b0;
    endtask

    task drive_ar(axi_transaction txn);
        @(vif.drv_cb);
        vif.drv_cb.arid    <= txn.arid;
        vif.drv_cb.araddr  <= txn.araddr;
        vif.drv_cb.arlen   <= txn.arlen;
        vif.drv_cb.arsize  <= txn.arsize;
        vif.drv_cb.arburst <= txn.arburst;
        vif.drv_cb.arlock  <= 1'b0;
        vif.drv_cb.arcache <= txn.arcache;
        vif.drv_cb.arprot  <= txn.arprot;
        vif.drv_cb.arqos   <= txn.arqos;
        vif.drv_cb.arvalid <= 1'b1;
        @(vif.drv_cb);
        while (!vif.drv_cb.arready)
            @(vif.drv_cb);
        vif.drv_cb.arvalid <= 1'b0;
    endtask

    task collect_r_burst(axi_transaction txn);
        txn.rdata_q.delete();
        txn.rresp_q.delete();
        for (int i = 0; i <= txn.arlen; i++) begin
            do begin
                @(vif.drv_cb);
            end while (!vif.drv_cb.rvalid);
            txn.rdata_q.push_back(vif.drv_cb.rdata);
            txn.rresp_q.push_back(vif.drv_cb.rresp);
            vif.drv_cb.rready <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.rready <= 1'b0;
        end
    endtask

endclass : axi_master_driver
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_master_driver.sv && git commit -m "feat: add UVM master driver for AXI bus"
```

---

### Task 12: UVM Master Monitor

**Files:**
- Create: `AXI/tb/axi_master_monitor.sv`

**Interfaces:**
- Consumes: `axi_if`, `axi_pkg`
- Produces: `axi_master_monitor` with analysis port broadcasting observed transactions

- [x] **Step 1: Write axi_master_monitor.sv**

File: `AXI/tb/axi_master_monitor.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_master_monitor extends uvm_monitor;

    `uvm_component_utils(axi_master_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_aw_chan();
            monitor_ar_chan();
        join
    endtask

    task monitor_aw_chan();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                axi_transaction txn = axi_transaction::type_id::create("txn");
                txn.is_write  = 1'b1;
                txn.awid     = vif.mon_cb.awid;
                txn.awaddr   = vif.mon_cb.awaddr;
                txn.awlen    = vif.mon_cb.awlen;
                txn.awsize   = vif.mon_cb.awsize;
                txn.awburst  = vif.mon_cb.awburst;
                txn.awcache  = vif.mon_cb.awcache;
                txn.awprot   = vif.mon_cb.awprot;
                txn.awqos    = vif.mon_cb.awqos;
                // Collect W beats
                txn.wdata_q.delete();
                txn.wstrb_q.delete();
                for (int i = 0; i <= txn.awlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
                    txn.wdata_q.push_back(vif.mon_cb.wdata);
                    txn.wstrb_q.push_back(vif.mon_cb.wstrb);
                end
                // Collect B
                do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
                txn.bresp = vif.mon_cb.bresp;
                ap.write(txn);
                `uvm_info("MON", $sformatf("Observed WRITE AWID=%0d ADDR=0x%08h LEN=%0d",
                    txn.awid, txn.awaddr, txn.awlen), UVM_MEDIUM)
            end
        end
    endtask

    task monitor_ar_chan();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                axi_transaction txn = axi_transaction::type_id::create("txn");
                txn.is_write = 1'b0;
                txn.arid     = vif.mon_cb.arid;
                txn.araddr   = vif.mon_cb.araddr;
                txn.arlen    = vif.mon_cb.arlen;
                txn.arsize   = vif.mon_cb.arsize;
                txn.arburst  = vif.mon_cb.arburst;
                txn.arcache  = vif.mon_cb.arcache;
                txn.arprot   = vif.mon_cb.arprot;
                txn.arqos    = vif.mon_cb.arqos;
                // Collect R beats
                txn.rdata_q.delete();
                txn.rresp_q.delete();
                for (int i = 0; i <= txn.arlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
                    txn.rdata_q.push_back(vif.mon_cb.rdata);
                    txn.rresp_q.push_back(vif.mon_cb.rresp);
                end
                ap.write(txn);
                `uvm_info("MON", $sformatf("Observed READ ARID=%0d ADDR=0x%08h LEN=%0d",
                    txn.arid, txn.araddr, txn.arlen), UVM_MEDIUM)
            end
        end
    endtask

endclass : axi_master_monitor
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_master_monitor.sv && git commit -m "feat: add UVM master monitor for AXI transaction observation"
```

---

### Task 13: UVM Slave Monitor

**Files:**
- Create: `AXI/tb/axi_slave_monitor.sv`

**Interfaces:**
- Consumes: `axi_if`, `axi_pkg`
- Produces: `axi_slave_monitor` observing slave-side AXI bus activity

- [x] **Step 1: Write axi_slave_monitor.sv**

File: `AXI/tb/axi_slave_monitor.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_slave_monitor extends uvm_monitor;

    `uvm_component_utils(axi_slave_monitor)

    virtual axi_if vif;
    uvm_analysis_port #(axi_transaction) ap;
    int slave_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Virtual interface not set for slave monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            monitor_aw();
            monitor_ar();
        join
    endtask

    task monitor_aw();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
                axi_transaction t = axi_transaction::type_id::create("t");
                t.is_write = 1'b1;
                t.awid = vif.mon_cb.awid;
                t.awaddr = vif.mon_cb.awaddr;
                t.awlen = vif.mon_cb.awlen;
                t.awsize = vif.mon_cb.awsize;
                t.awburst = vif.mon_cb.awburst;
                t.wdata_q.delete(); t.wstrb_q.delete();
                for (int i = 0; i <= t.awlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.wvalid && vif.mon_cb.wready));
                    t.wdata_q.push_back(vif.mon_cb.wdata);
                    t.wstrb_q.push_back(vif.mon_cb.wstrb);
                end
                do @(vif.mon_cb); while (!(vif.mon_cb.bvalid && vif.mon_cb.bready));
                t.bresp = vif.mon_cb.bresp;
                ap.write(t);
            end
        end
    endtask

    task monitor_ar();
        forever begin
            @(vif.mon_cb);
            if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
                axi_transaction t = axi_transaction::type_id::create("t");
                t.is_write = 1'b0;
                t.arid = vif.mon_cb.arid;
                t.araddr = vif.mon_cb.araddr;
                t.arlen = vif.mon_cb.arlen;
                t.arsize = vif.mon_cb.arsize;
                t.arburst = vif.mon_cb.arburst;
                t.rdata_q.delete(); t.rresp_q.delete();
                for (int i = 0; i <= t.arlen; i++) begin
                    do @(vif.mon_cb); while (!(vif.mon_cb.rvalid && vif.mon_cb.rready));
                    t.rdata_q.push_back(vif.mon_cb.rdata);
                    t.rresp_q.push_back(vif.mon_cb.rresp);
                end
                ap.write(t);
            end
        end
    endtask

endclass : axi_slave_monitor
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_slave_monitor.sv && git commit -m "feat: add UVM slave-side monitor"
```

---

### Task 14: UVM Master Agent

**Files:**
- Create: `AXI/tb/axi_master_agent.sv`

**Interfaces:**
- Consumes: `axi_master_driver`, `axi_master_monitor`
- Produces: `axi_master_agent` with sequencer, driver, and monitor

- [x] **Step 1: Write axi_master_agent.sv**

File: `AXI/tb/axi_master_agent.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_master_agent extends uvm_agent;

    `uvm_component_utils(axi_master_agent)

    uvm_sequencer #(axi_transaction) sequencer;
    axi_master_driver driver;
    axi_master_monitor monitor;

    int master_id = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer#(axi_transaction)::type_id::create("sequencer", this);
        driver    = axi_master_driver::type_id::create("driver", this);
        monitor   = axi_master_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        driver.master_id = master_id;
        monitor.ap.connect(null);  // Connected in env
    endfunction

endclass : axi_master_agent
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_master_agent.sv && git commit -m "feat: add UVM master agent with sequencer, driver, and monitor"
```

---

### Task 15: UVM Scoreboard

**Files:**
- Create: `AXI/tb/axi_scoreboard.sv`

**Interfaces:**
- Consumes: `axi_pkg::axi_transaction`
- Produces: `axi_scoreboard` with SRAM reference model and DFI reference model, TLM analysis exports

- [x] **Step 1: Write axi_scoreboard.sv**

File: `AXI/tb/axi_scoreboard.sv`
```systemverilog
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
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_scoreboard.sv && git commit -m "feat: add UVM scoreboard with SRAM and DFI reference models"
```

---

### Task 16: UVM Environment

**Files:**
- Create: `AXI/tb/axi_env.sv`

**Interfaces:**
- Consumes: `axi_master_agent`, `axi_scoreboard`
- Produces: `axi_env` connecting 2 agents + scoreboard

- [x] **Step 1: Write axi_env.sv**

File: `AXI/tb/axi_env.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_env extends uvm_env;

    `uvm_component_utils(axi_env)

    axi_master_agent master_agent[2];
    axi_scoreboard   scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        for (int i = 0; i < 2; i++) begin
            master_agent[i] = axi_master_agent::type_id::create(
                $sformatf("master_agent[%0d]", i), this);
            master_agent[i].master_id = i;
        end
        scoreboard = axi_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        master_agent[0].monitor.ap.connect(scoreboard.m0_export);
        master_agent[1].monitor.ap.connect(scoreboard.m1_export);
    endfunction

endclass : axi_env
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_env.sv && git commit -m "feat: add UVM environment with 2 agents and scoreboard"
```

---

### Task 17: UVM Sequence Library

**Files:**
- Create: `AXI/tb/sequence_lib.sv`

**Interfaces:**
- Consumes: `axi_pkg::axi_transaction`
- Produces: Multiple sequence classes for different test scenarios

- [x] **Step 1: Write sequence_lib.sv**

File: `AXI/tb/sequence_lib.sv`
```systemverilog
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
    int num_txn = 50;

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
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/sequence_lib.sv && git commit -m "feat: add UVM sequence library (sanity, random, burst, narrow, OOO, concurrent, error)"
```

---

### Task 18: UVM Base Test

**Files:**
- Create: `AXI/tb/axi_test.sv`

**Interfaces:**
- Consumes: `axi_env`, `sequence_lib`
- Produces: `axi_base_test` and named test classes

- [x] **Step 1: Write axi_test.sv**

File: `AXI/tb/axi_test.sv`
```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import axi_pkg::*;

class axi_base_test extends uvm_test;

    `uvm_component_utils(axi_base_test)

    axi_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

endclass : axi_base_test

// ---------------------------------------------------------------
// Specific tests
// ---------------------------------------------------------------

class axi_sanity_test extends axi_base_test;
    `uvm_component_utils(axi_sanity_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_sanity_seq seq0, seq1;
        phase.raise_objection(this);
        fork
            begin
                seq0 = axi_sanity_seq::type_id::create("seq0");
                seq0.start(env.master_agent[0].sequencer);
            end
            begin
                seq1 = axi_sanity_seq::type_id::create("seq1");
                seq1.start(env.master_agent[1].sequencer);
            end
        join
        phase.drop_objection(this);
    endtask
endclass : axi_sanity_test

class axi_random_test extends axi_base_test;
    `uvm_component_utils(axi_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_random_seq seq = axi_random_seq::type_id::create("seq");
        seq.num_txn = 100;
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_random_test

class axi_burst_test extends axi_base_test;
    `uvm_component_utils(axi_burst_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_burst_seq seq = axi_burst_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_burst_test

class axi_narrow_test extends axi_base_test;
    `uvm_component_utils(axi_narrow_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_narrow_seq seq = axi_narrow_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_narrow_test

class axi_ooo_test extends axi_base_test;
    `uvm_component_utils(axi_ooo_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_out_of_order_seq seq = axi_out_of_order_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_ooo_test

class axi_concurrent_test extends axi_base_test;
    `uvm_component_utils(axi_concurrent_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_concurrent_seq seq0, seq1;
        phase.raise_objection(this);
        fork
            begin
                seq0 = axi_concurrent_seq::type_id::create("seq0");
                seq0.start(env.master_agent[0].sequencer);
            end
            begin
                seq1 = axi_concurrent_seq::type_id::create("seq1");
                seq1.start(env.master_agent[1].sequencer);
            end
        join
        phase.drop_objection(this);
    endtask
endclass : axi_concurrent_test

class axi_error_test extends axi_base_test;
    `uvm_component_utils(axi_error_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        axi_error_seq seq = axi_error_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.master_agent[0].sequencer);
        phase.drop_objection(this);
    endtask
endclass : axi_error_test
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/axi_test.sv && git commit -m "feat: add UVM base test and all test classes"
```

---

### Task 19: Testbench Top

**Files:**
- Create: `AXI/tb/tb_top.sv`

**Interfaces:**
- Consumes: `axi_top`, `axi_if`, `axi_pkg`, all UVM components
- Produces: `tb_top` with DUT, clock/reset generation, interface binding, `run_test()`

- [x] **Step 1: Write tb_top.sv**

File: `AXI/tb/tb_top.sv`
```systemverilog
`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;
import axi_pkg::*;

module tb_top;

    localparam DATA_W = 256;
    localparam ADDR_W = 32;
    localparam ID_W   = 8;

    logic aclk;
    logic aresetn;

    // Clock generation (5ns period = 200MHz)
    always #2.5 aclk = ~aclk;

    // ============================================================
    // AXI Interface instances (one per master)
    // ============================================================
    axi_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W)) m_if[2] (
        .aclk(aclk), .aresetn(aresetn)
    );

    // ============================================================
    // Master txn control signals
    // ============================================================
    logic                 txn_req[2];
    logic                 txn_is_write[2];
    logic [ID_W-1:0]      txn_awid[2];
    logic [ADDR_W-1:0]    txn_awaddr[2];
    logic [7:0]           txn_awlen[2];
    logic [2:0]           txn_awsize[2];
    logic [1:0]           txn_awburst[2];
    logic [ID_W-1:0]      txn_arid[2];
    logic [ADDR_W-1:0]    txn_araddr[2];
    logic [7:0]           txn_arlen[2];
    logic [2:0]           txn_arsize[2];
    logic [1:0]           txn_arburst[2];
    logic                 txn_wvalid[2];
    logic [DATA_W-1:0]    txn_wdata[2];
    logic [DATA_W/8-1:0]  txn_wstrb[2];
    logic                 txn_wlast[2];
    logic                 txn_wready[2];
    logic                 txn_rvalid[2];
    logic [DATA_W-1:0]    txn_rdata[2];
    logic [1:0]           txn_rresp[2];
    logic                 txn_rlast[2];
    logic                 txn_rready[2];
    logic                 txn_done[2];
    logic [1:0]           txn_bresp[2];

    // DFI monitoring signals
    logic [31:0]         dfi_address;
    logic [3:0]          dfi_bank;
    logic [DATA_W-1:0]   dfi_wrdata;
    logic [DATA_W/8-1:0] dfi_wrdata_mask;
    logic                dfi_wrdata_valid;
    logic                dfi_cs_n, dfi_ras_n, dfi_cas_n, dfi_we_n, dfi_act_n;

    // ============================================================
    // DUT: AXI Top
    // ============================================================
    axi_top #(.NUM_MASTERS(2), .NUM_SLAVES(2),
              .ID_W(ID_W), .ADDR_W(ADDR_W), .DATA_W(DATA_W))
    u_axi_top (
        .aclk  (aclk),
        .aresetn(aresetn),
        // Master 0
        .txn_req_0(txn_req[0]), .txn_is_write_0(txn_is_write[0]),
        .txn_awid_0(txn_awid[0]), .txn_awaddr_0(txn_awaddr[0]),
        .txn_awlen_0(txn_awlen[0]), .txn_awsize_0(txn_awsize[0]),
        .txn_awburst_0(txn_awburst[0]),
        .txn_arid_0(txn_arid[0]), .txn_araddr_0(txn_araddr[0]),
        .txn_arlen_0(txn_arlen[0]), .txn_arsize_0(txn_arsize[0]),
        .txn_arburst_0(txn_arburst[0]),
        .txn_wvalid_0(txn_wvalid[0]), .txn_wdata_0(txn_wdata[0]),
        .txn_wstrb_0(txn_wstrb[0]), .txn_wlast_0(txn_wlast[0]),
        .txn_wready_0(txn_wready[0]),
        .txn_rvalid_0(txn_rvalid[0]), .txn_rdata_0(txn_rdata[0]),
        .txn_rresp_0(txn_rresp[0]), .txn_rlast_0(txn_rlast[0]),
        .txn_rready_0(txn_rready[0]),
        .txn_done_0(txn_done[0]), .txn_bresp_0(txn_bresp[0]),
        // Master 1
        .txn_req_1(txn_req[1]), .txn_is_write_1(txn_is_write[1]),
        .txn_awid_1(txn_awid[1]), .txn_awaddr_1(txn_awaddr[1]),
        .txn_awlen_1(txn_awlen[1]), .txn_awsize_1(txn_awsize[1]),
        .txn_awburst_1(txn_awburst[1]),
        .txn_arid_1(txn_arid[1]), .txn_araddr_1(txn_araddr[1]),
        .txn_arlen_1(txn_arlen[1]), .txn_arsize_1(txn_arsize[1]),
        .txn_arburst_1(txn_arburst[1]),
        .txn_wvalid_1(txn_wvalid[1]), .txn_wdata_1(txn_wdata[1]),
        .txn_wstrb_1(txn_wstrb[1]), .txn_wlast_1(txn_wlast[1]),
        .txn_wready_1(txn_wready[1]),
        .txn_rvalid_1(txn_rvalid[1]), .txn_rdata_1(txn_rdata[1]),
        .txn_rresp_1(txn_rresp[1]), .txn_rlast_1(txn_rlast[1]),
        .txn_rready_1(txn_rready[1]),
        .txn_done_1(txn_done[1]), .txn_bresp_1(txn_bresp[1]),
        // DFI
        .dfi_address(dfi_address), .dfi_bank(dfi_bank),
        .dfi_wrdata(dfi_wrdata), .dfi_wrdata_mask(dfi_wrdata_mask),
        .dfi_wrdata_valid(dfi_wrdata_valid),
        .dfi_cs_n(dfi_cs_n), .dfi_ras_n(dfi_ras_n),
        .dfi_cas_n(dfi_cas_n), .dfi_we_n(dfi_we_n),
        .dfi_act_n(dfi_act_n)
    );

    // Bridge DUT txn ports to UVM interface via a simple adapter

    // ============================================================
    // UVM Initial Block
    // ============================================================
    initial begin
        // Set UVM verbosity
        uvm_config_int::set(null, "*", "recording_detail", UVM_FULL);

        // Set interfaces for each master agent
        uvm_config_db #(virtual axi_if)::set(null, "*master_agent[0]*", "vif", m_if[0]);
        uvm_config_db #(virtual axi_if)::set(null, "*master_agent[1]*", "vif", m_if[1]);

        // Run test
        run_test();
    end

    // ============================================================
    // Reset sequence
    // ============================================================
    initial begin
        aclk   = 1'b0;
        aresetn = 1'b0;
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        repeat(5) @(posedge aclk);

        $display("=== TB_TOP: Reset released, test starting ===");

        // Wait for test completion
        #1000000;
        $display("=== TB_TOP: Timeout, finishing simulation ===");
        $finish;
    end

    // ============================================================
    // Simulation control
    // ============================================================
    initial begin
        $fsdbDumpfile("waves/axi_top.fsdb");
        $fsdbDumpvars(0, tb_top, "+all");
    end

    // Assertions
    // Check AW size stability during handshake
    property aw_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].awvalid && !m_if[0].awready) |=> $stable(m_if[0].awaddr) &&
            $stable(m_if[0].awid) && $stable(m_if[0].awlen);
    endproperty
    assert property (aw_stable) else $error("AW signals changed during handshake");

    property ar_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_if[0].arvalid && !m_if[0].arready) |=> $stable(m_if[0].araddr) &&
            $stable(m_if[0].arid) && $stable(m_if[0].arlen);
    endproperty
    assert property (ar_stable) else $error("AR signals changed during handshake");

endmodule : tb_top
```

- [x] **Step 2: Commit**

```bash
cd /home/openclaw/project/bus/AXI && git add tb/tb_top.sv && git commit -m "feat: add testbench top with DUT connection, clock/reset, assertions"
```

---

### Task 20: Compile and Run Sanity Test

**Files:**
- Verify: All files compile and sanity test passes

**Interfaces:**
- Consumes: All RTL and TB files from Tasks 1-19

- [x] **Step 1: Compile all sources**

```bash
cd /home/openclaw/project/bus/AXI && bash scripts/compile.sh 2>&1 | tail -30
```

Expected: "=== Compile SUCCESS ==="

- [x] **Step 2: Run sanity test**

```bash
cd /home/openclaw/project/bus/AXI && bash scripts/run.sh axi_sanity_test 2>&1 | tail -30
```

Expected: UVM report with PASS, no UVM_ERROR or UVM_FATAL.

- [x] **Step 3: Run random test**

```bash
cd /home/openclaw/project/bus/AXI && bash scripts/run.sh axi_random_test 2>&1 | tail -20
```

Expected: No data mismatches reported by scoreboard.

- [x] **Step 4: Commit any fixes (if applicable)**

```bash
cd /home/openclaw/project/bus/AXI && git add -A && git commit -m "chore: compile fixes and test verification"
```

---

## Verification Checklist

After all tasks are complete, run the full test suite:

```bash
for test in axi_sanity_test axi_random_test axi_burst_test axi_narrow_test \
            axi_ooo_test axi_concurrent_test axi_error_test; do
    echo "=== Running $test ==="
    bash scripts/run.sh $test
done
```

All tests should pass with no UVM_ERROR or UVM_FATAL messages.
