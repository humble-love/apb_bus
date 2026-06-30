# AXI4-Full + DDR5 DFI Bridge Framework Design Spec

## Overview

An industrial-grade AXI4-Full bus system with DDR5 DFI bridge and SRAM slave. RTL in pure Verilog/SystemVerilog, UVM verification. 256-bit data width, 2 masters, 2 slaves (SRAM + DDR5/DFI), crossbar interconnect with out-of-order read support.

## Architecture

### Top-Level Data Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                        axi_interconnect                          │
│                                                                  │
│  Master0 ──→ [WrFIFOs] ───┐    ┌──→ [AddrDec] → Slave0 SRAM    │
│            [RdFIFOs] ───┤    │    │                              │
│                         ├────→ [Crossbar Switch]                 │
│  Master1 ──→ [WrFIFOs] ──┤    │    │                              │
│            [RdFIFOs] ──┤    │    └──→ [AddrDec] → Slave1 DFI    │
│                         ──┘    │                                  │
│                                │                                  │
│  ┌─ ID-tagged response reorder ─┘                               │
│  └──────────────────────────────────────────────────────────────┘
└──────────────────────────────────────────────────────────────────┘
```

- **Masters** initiate AXI4-Full transactions with burst support, narrow transfers, and out-of-order IDs.
- **Crossbar** provides independent per-slave read/write arbitration (round-robin), W-channel locking, and ID-tagged R/B channel demux.
- **Decoder** maps address ranges to slave selects.
- **Slaves** respond with SRAM-like behavior or DFI-bridged DDR5 commands.

### AXI4 5-Channel Protocol

| Channel | Direction | Key Signals |
|---------|-----------|-------------|
| AW (Write Address) | M→S | AWID, AWADDR, AWLEN, AWSIZE, AWBURST, AWVALID/AWREADY |
| W (Write Data) | M→S | WDATA, WSTRB, WLAST, WVALID/WREADY |
| B (Write Response) | S→M | BID, BRESP, BVALID/BREADY |
| AR (Read Address) | M→S | ARID, ARADDR, ARLEN, ARSIZE, ARBURST, ARVALID/ARREADY |
| R (Read Data) | S→M | RID, RDATA, RRESP, RLAST, RVALID/RREADY |

## Component Specs

### RTL Modules (SystemVerilog)

| Module | Description |
|--------|-------------|
| `axi_master` | AXI4-Full master. FSM per channel, 16-entry transaction table, burst calc, narrow transfer support. |
| `axi_crossbar_wr` | Write crossbar: per-slave AW arbitration (round-robin), W mux + locking, B demux. |
| `axi_crossbar_rd` | Read crossbar: per-slave AR arbitration (round-robin), R demux with ID lookup table. |
| `axi_addr_decoder` | Maps AWADDR/ARADDR[31:28] to slave select. SRAM=0x0xxx_xxxx, DFI=0x1xxx_xxxx. |
| `axi_slave_sram` | Parameterized SRAM slave. Configurable depth (default 1024×256b), stall insertion, out-of-order R. |
| `axi_slave_dfi` | AXI-to-DFI bridge. Translates AXI read/write bursts to DFI commands with DDR5 timing. |
| `axi_interconnect` | Integration wrapper: crossbar + decoder + ID tracking. |
| `axi_top` | Top-level: 2 masters, interconnect, 2 slaves, clock/reset. |

### AXI Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| DATA_WIDTH | 256 | Data bus width in bits |
| ADDR_WIDTH | 32 | Address bus width |
| ID_WIDTH | 8 | Transaction ID width |
| MAX_OUTSTANDING | 16 | Max outstanding transactions per master |
| WSTRB_WIDTH | 32 | Write strobe width (DATA_WIDTH/8) |

### AXI Master FSM

Four independent per-channel FSMs coordinated by a top-level transaction sequencer:

**Top-Level Sequencer:**
```
IDLE → (txn_req) → AW_W_PHASE → B_PHASE → (if read) AR_PHASE → R_PHASE → DONE → IDLE
```
Writes: AW+W phase, then wait B. Reads: AR phase, then collect R.

**Per-Channel FSMs:**
- AW/AR: `IDLE → ARB_REQ → WAIT_GRANT → TRANSFER → DONE`
- W: `IDLE → SEND_BEATS → (WLAST) → DONE`
- B: `IDLE → WAIT_RESP → DONE`
- R: `IDLE → COLLECT_BEATS → (RLAST) → DONE`

**Transaction Table (16 entries):**

| Field | Width | Description |
|-------|-------|-------------|
| id (AWID/ARID) | 8 | Transaction ID |
| addr | 32 | Start address |
| len | 8 | Burst length (1-256) |
| size | 3 | Beat size (2=4B, 3=8B, 4=16B, 5=32B) |
| burst | 2 | 0=FIXED, 1=INCR, 2=WRAP |
| state | 2 | IDLE/ACTIVE/DONE |
| beat_cnt | 8 | Current beat number |
| resp | 2 | Accumulated response (OKAY/EXOKAY/SLVERR/DECERR) |

**Narrow Transfer Handling:**
- For AWSIZE/ARSIZE < 5 (less than 32B beat): WDATA is replicated on correct byte lanes, WSTRB masks inactive bytes.
- Read: RDATA extracted from correct byte lanes.
- Address increment: `addr += (1 << size)` per beat (INCR), or zero (FIXED), or wrap-boundary (WRAP).

### Crossbar: Write Path

**Per-Slave AW Arbitration:**
- Round-robin priority (configurable to fixed).
- Grant locked on AWVALID & AWREADY handshake.
- W channel routing follows AW grant until WLAST & WREADY.

**W Channel Mux:**
```
M0_WDATA/WSTRB ──┐
                 ├──→ [W Mux per slave] → Sx_WDATA/WSTRB
M1_WDATA/WSTRB ──┘
sel = latched AW grant owner for that slave
```

**B Channel Demux:**
```
S0_BID/BRESP ──→ [B Demux per master] → M0_B
S1_BID/BRESP ──→                       → M1_B
sel = current W owner for that slave → master
```

### Crossbar: Read Path

**Per-Slave AR Arbitration:**
- Round-robin, same pattern as AW.

**R Channel Demux with ID Lookup Table:**
- On AR handshake: `id_lut[ARID] = {master_id, 1'b1}` (valid bit set)
- On RLAST handshake: `id_lut[RID].valid = 0` (entry freed)
- R channel routing: `master = id_lut[RID].master` demuxes to correct master

ID LUT structure (per slave): 256 entries × (1-bit master_id + 1-bit valid).

**AXI Ordering Guarantee:**
- Same ARID → R responses arrive in order (AXI4 spec). No transaction-level reorder buffer needed.
- Different ARID → may arrive out-of-order. ID LUT naturally handles this.

### Address Decoder

```
AWADDR/ARADDR[31:28] = 4'h0 → Slave 0 (SRAM), 256KB
AWADDR/ARADDR[31:28] = 4'h1 → Slave 1 (DFI/DDR5), 256MB
Other → DECERR on response channel
```

### AXI Slave: SRAM

- Parameterized depth: 1024 entries × 256-bit (default 32KB)
- Supports all burst types (FIXED/INCR/WRAP)
- Configurable stall probability (parameter `STALL_PROB`, 0-255 out of 256)
- Out-of-order read response capability (tracks ARID→master mapping)
- Write: accepts W beats into internal BRAM, responds B with accumulated BRESP
- Read: fetches from BRAM, sends R beats with correct RID/RLAST

### AXI Slave: DFI Bridge (DDR5)

Converts AXI4 transactions to DFI (DDR PHY Interface) commands.

**DFI Interface (simplified for DDR5):**

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| dfi_address | 32 | M→S | Rank/bank/row/col address |
| dfi_bank | 4 | M→S | Bank address |
| dfi_wrdata | 256 | M→S | Write data |
| dfi_wrdata_mask | 32 | M→S | Write data mask |
| dfi_rddata | 256 | S→M | Read data |
| dfi_wrdata_valid | 1 | M→S | Write data valid |
| dfi_rddata_valid | 1 | S→M | Read data valid |
| dfi_cs_n | 1 | M→S | Chip select |
| dfi_ras_n | 1 | M→S | Row address strobe |
| dfi_cas_n | 1 | M→S | Column address strobe |
| dfi_we_n | 1 | M→S | Write enable |
| dfi_act_n | 1 | M→S | Activate command |
| dfi_cke | 1 | M→S | Clock enable |

**DFI Bridge FSM:**
```
IDLE → CMD_DECODE → (ACTIVATE) → RD/WR → PRECHARGE → IDLE
```

**DDR5 Timing Parameters (configurable):**
- tRCD: 14 cycles (ACTIVATE to RD/WR)
- tCL: 14 cycles (CAS to read data)
- tRAS: 32 cycles (min ACTIVE time)
- tRP: 14 cycles (PRECHARGE period)
- tWR: 14 cycles (write recovery)
- BL16: 16-beat burst per DDR5 access (matching 256-bit AXI beat = 16×16-bit DDR5)

**Transaction Queue:** 16-entry command queue, reordering for bank efficiency.

## Directory Structure

```
AXI/
├── rtl/
│   ├── axi_master.sv          # AXI4-Full master
│   ├── axi_crossbar_wr.sv     # Write crossbar (AW arb + W mux + B demux)
│   ├── axi_crossbar_rd.sv     # Read crossbar (AR arb + R demux + ID LUT)
│   ├── axi_addr_decoder.sv    # Address decoder
│   ├── axi_slave_sram.sv      # SRAM slave
│   ├── axi_slave_dfi.sv       # AXI-to-DFI bridge (DDR5)
│   ├── axi_interconnect.sv    # Crossbar + decoder integration
│   └── axi_top.sv             # Top-level integration
├── tb/
│   ├── axi_if.sv              # AXI4 interface + clocking blocks
│   ├── axi_pkg.sv             # UVM transaction + types
│   ├── axi_master_driver.sv   # UVM master driver
│   ├── axi_master_monitor.sv  # UVM master monitor
│   ├── axi_slave_monitor.sv   # UVM slave monitor
│   ├── axi_master_agent.sv    # UVM master agent
│   ├── axi_scoreboard.sv      # Scoreboard with reference models
│   ├── axi_env.sv             # UVM environment
│   ├── sequence_lib.sv        # Test sequences
│   ├── axi_test.sv            # Base test
│   └── tb_top.sv              # DUT + clock/reset + run_test()
├── scripts/
│   ├── compile.sh             # VCS compile script
│   ├── run.sh                 # Simulation run script
│   ├── verdi.sh               # Verdi waveform viewer
│   └── filelist.f             # File list for compilation
├── Makefile                   # Top-level convenience targets
└── waves/                     # FSDB waveform output
```

## UVM Verification

### Transaction (axi_transaction)

| Field | Width | Description |
|-------|-------|-------------|
| awid/arid | 8 | Transaction ID |
| awaddr/araddr | 32 | Address |
| awlen/arlen | 8 | Burst length (1-256) |
| awsize/arsize | 3 | Beat size |
| awburst/arburst | 2 | Burst type |
| awprot/arprot | 3 | Protection type |
| awcache/arcache | 4 | Cache type |
| wdata[] | 256×N | Write data queue |
| wstrb[] | 32×N | Write strobe queue |
| rdata[] | 256×N | Read data queue (response) |
| bresp/rresp[] | 2×N | Response per beat |

### UVM Component Hierarchy

```
tb_top
└── axi_env
    ├── axi_master_agent[0] (active)
    │   ├── sequencer
    │   ├── driver
    │   └── monitor
    ├── axi_master_agent[1] (active)
    │   ├── sequencer
    │   ├── driver
    │   └── monitor
    ├── axi_slave_monitor[0]
    ├── axi_slave_monitor[1]
    └── axi_scoreboard
        ├── sram_ref_model
        └── dfi_ref_model
```

### Test Sequences

| Sequence | Description |
|----------|-------------|
| `axi_sanity_seq` | One write + one read per slave, basic connectivity |
| `axi_random_seq` | Random addr/data/len/size/burst, constrained to valid ranges |
| `axi_burst_seq` | Full burst reads/writes (INCR, FIXED, WRAP), maximum length |
| `axi_narrow_seq` | Narrow transfers (4B, 8B, 16B) on 256-bit bus |
| `axi_out_of_order_seq` | Multiple outstanding reads with different IDs, verify OOO completion |
| `axi_concurrent_seq` | Both masters active, crossbar stress test |
| `axi_error_seq` | Unmapped address access, verify DECERR |
| `axi_dfi_timing_seq` | DFI slave timing parameter verification |

### Scoreboard

- **SRAM reference model**: Mirrors SRAM contents, checks read data per beat.
- **DFI reference model**: Tracks DDR5 bank state (open/closed), verifies DFI command timing and read data.
- **Out-of-order tracking**: Maintains per-ID expected data queue, matches by RID.

## Build & Run Flow

### compile.sh
```
vcs -sverilog -ntb_opts uvm-1.2 \
    -debug_access+all -kdb \
    -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
    $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a \
    -f scripts/filelist.f
```

### run.sh
```
./simv +UVM_TESTNAME=$TEST +fsdb+autoflush -cm line+cond+tgl
```

### Makefile targets
- `make compile` — compile all sources
- `make run TEST=<test>` — run simulation
- `make verdi` — open Verdi with FSDB
- `make clean` — remove build artifacts
