# APB Bus Practice Framework Design Spec

## Overview

A practice framework for RTL bus programming using the AMBA APB3 protocol.
RTL in pure Verilog, verification in SystemVerilog with UVM.
Compile with VCS, view waveforms with Verdi (FSDB).

## Architecture

### Top-Level Data Flow

```
Master(0..N) --[req/gnt]--> Arbiter --[granted bus]--> Decoder --[PSELx]--> Slave(0..M)
```

- **Masters** raise `req` to the arbiter when they want to perform a transaction.
- **Arbiter** grants the bus to one master per cycle (fixed priority: lower index = higher priority).
- **Decoder** asserts the correct `PSELx` based on `PADDR` high bits.
- **Slaves** respond on the APB bus with `PREADY` and `PRDATA`.

### APB3 State Machine (per transfer)

```
IDLE → SETUP (PSEL=1, PENABLE=0) → ACCESS (PSEL=1, PENABLE=1) → [wait PREADY] → IDLE
```

A transfer requires 2 cycles minimum. PREADY=0 stalls the ACCESS phase.

## Component Specs

### RTL Modules (Verilog)

| Module | File | Description |
|--------|------|-------------|
| `apb_master` | `rtl/apb_master.v` | Parameterized N masters. Drives req, accepts gnt, generates APB bus transactions. |
| `apb_arbiter` | `rtl/apb_arbiter.v` | Fixed-priority arbiter. FSM: IDLE → GRANT → BUSY → IDLE. Outputs muxed master bus onto single APB bus. |
| `apb_decoder` | `rtl/apb_decoder.v` | Address decoder. Maps PADDR[15:12] to PSELx. Address map: Slave0=0x0xxx, Slave1=0x1xxx. |
| `apb_slave_mem` | `rtl/apb_slave_mem.v` | 256-depth memory slave. Supports PREADY stall insertion (parameterizable probability). Address range 0x0000-0x0FFF. |
| `apb_slave_gpio` | `rtl/apb_slave_gpio.v` | GPIO register slave. 4 registers: DATA, DIR, INT_EN, INT_STATUS. Generates interrupt when INT_STATUS & INT_EN != 0. Address range 0x1000-0x1FFF. |
| `apb_top` | `rtl/apb_top.v` | Top-level integration. 2 masters, 1 arbiter, 1 decoder, 2 slaves. |

### APB Interface Signals

| Signal | Width | Direction | Description |
|--------|-------|-----------|-------------|
| PCLK | 1 | input | Clock |
| PRESETn | 1 | input | Active-low reset |
| PADDR | 32 | master→slave | Address |
| PWDATA | 32 | master→slave | Write data |
| PRDATA | 32 | slave→master | Read data |
| PWRITE | 1 | master→slave | 1=write, 0=read |
| PSEL | 1 | master→slave | Slave select |
| PENABLE | 1 | master→slave | Enable (ACCESS phase) |
| PREADY | 1 | slave→master | Slave ready |

Master-side: `req` (output), `gnt` (input) per master.

### UVM Verification (SystemVerilog)

| Component | File | Description |
|-----------|------|-------------|
| `apb_transaction` | `apb_pkg.sv` | UVM sequence item. Fields: addr, data, rw, delay. Constraints for valid ranges. |
| `apb_if` | `tb/apb_if.sv` | SystemVerilog interface wrapping all APB signals + req/gnt per master. |
| `apb_master_driver` | `tb/apb_master_driver.sv` | Drives req, waits gnt, executes APB transfer via vif. |
| `apb_master_monitor` | `tb/apb_master_monitor.sv` | Samples APB bus on posedge PCLK, sends transactions to analysis port. |
| `apb_master_agent` | `tb/apb_master_agent.sv` | Contains driver + monitor + sequencer. Analysis port for monitor output. |
| `apb_scoreboard` | `tb/apb_scoreboard.sv` | Reference model mirrors memory and GPIO state. Compares expected vs actual read data. Reports UVM_ERROR on mismatch. |
| `apb_env` | `tb/apb_env.sv` | Instantiates N agents and 1 scoreboard. TLM analysis ports connected. |
| Sequence library | `tb/sequence_lib.sv` | `apb_sanity_seq`, `apb_random_seq`, `apb_burst_seq`, `apb_slave_err_seq`. |
| `apb_base_test` | `tb/apb_test.sv` | Sets default sequence, builds env, manages phases. |
| `tb_top` | `tb/tb_top.sv` | DUT instantiation, clock/reset generation, interface binding, `run_test()`. |

## Directory Structure

```
bus/
├── rtl/                        # Pure Verilog RTL
├── tb/                         # UVM testbench (SystemVerilog)
├── scripts/
│   ├── compile.sh              # VCS compile + elaborate
│   ├── run.sh                  # Run simulation
│   └── verdi.sh                # Open Verdi with FSDB
├── Makefile                    # Top-level convenience targets
└── waves/                      # FSDB waveform output
```

## Build & Run Flow

### compile.sh
- `vcs -sverilog -ntb_opts uvm` to compile all RTL + TB files
- `-debug_access+all -kdb` for Verdi debug and FSDB dump
- Link Verdi PLI: `-P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a`
- Output: `simv` executable

### run.sh
- `./simv +UVM_TESTNAME=<test> +fsdb+autoflush -cm line+cond+tgl`
- FSDB dumped to `waves/`

### verdi.sh
- `verdi -sv -f scripts/filelist.f -ssf waves/*.fsdb &`

## Test Scenarios

| Test | Sequence | What it verifies |
|------|----------|-----------------|
| sanity | `apb_sanity_seq` | One read + one write per slave, basic connectivity |
| random | `apb_random_seq` | Random addr/data/rw, constrained to valid slave ranges |
| burst | `apb_burst_seq` | Back-to-back transfers, pipeline behavior |
| error | `apb_slave_err_seq` | Access unmapped address, verify PREADY=0 / error response |

## File List

`scripts/filelist.f` contains all source files in compile order:
1. RTL files (top-down or bottom-up)
2. UVM package
3. UVM components
4. tb_top
