# APB Bus Practice Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-master, multi-slave APB3 bus framework with UVM verification, VCS compilation, and Verdi waveform viewing.

**Architecture:** 2 masters → fixed-priority arbiter → address decoder → 2 slaves (memory + GPIO register file). RTL in pure Verilog, verification in SystemVerilog UVM. Masters assert `req` to arbiter, arbiter grants one master via `gnt` and muxes its bus signals onto shared APB bus, decoder drives `PSELx` based on address, slaves respond with `PREADY`/`PRDATA`.

**Tech Stack:** Verilog (RTL), SystemVerilog + UVM (verification), VCS (simulation), Verdi (waveform)

## Global Constraints

- RTL modules in pure Verilog (`*.v`), verification in SystemVerilog (`*.sv`)
- APB3 protocol: IDLE → SETUP → ACCESS state machine per transfer
- FSDB waveform dump enabled for all simulations
- `timescale 1ns/1ps` throughout
- No generate blocks — explicit instantiation for readability

---

## File Map

| File | Responsibility |
|------|---------------|
| `tb/apb_if.sv` | SV interface: APB signals + req/gnt per master |
| `rtl/apb_master.v` | Parameterized APB master: drives req, waits gnt, executes APB FSM |
| `rtl/apb_arbiter.v` | Fixed-priority arbiter: IDLE→GRANT→BUSY FSM, muxes master bus to APB |
| `rtl/apb_decoder.v` | Address decoder: PADDR[15:12] → PSELx |
| `rtl/apb_slave_mem.v` | 256×32 memory slave with randomized PREADY stall |
| `rtl/apb_slave_gpio.v` | GPIO register file slave with interrupt output |
| `rtl/apb_top.v` | Top-level integration: 2 masters, arbiter, decoder, 2 slaves |
| `tb/apb_pkg.sv` | UVM package: transaction class, typedefs |
| `tb/apb_master_driver.sv` | UVM driver: seq_item → pin-level APB + req/gnt protocol |
| `tb/apb_master_monitor.sv` | UVM monitor: pin-level → analysis port transaction |
| `tb/apb_master_agent.sv` | UVM agent: sequencer + driver + monitor, active/passive |
| `tb/apb_scoreboard.sv` | UVM subscriber: reference model for memory + GPIO |
| `tb/apb_env.sv` | UVM env: N agents + scoreboard, TLM connections |
| `tb/sequence_lib.sv` | Sequence library: sanity, random, burst, error |
| `tb/apb_test.sv` | UVM tests: base_test + concrete tests |
| `tb/tb_top.sv` | Top-level testbench: clock/reset gen, DUT, interface bind, run_test() |
| `scripts/filelist.f` | File list for VCS compilation |
| `scripts/compile.sh` | VCS compile + elaborate script |
| `scripts/run.sh` | Simulation run script |
| `scripts/verdi.sh` | Verdi waveform viewer launch script |
| `Makefile` | Top-level convenience targets |

---

### Task 1: Directory Setup and APB Interface

**Files:**
- Create: `tb/apb_if.sv`

**Interfaces:**
- Produces: `apb_if` — SV interface with modports, used by all UVM components and connected to DUT pins

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p /home/openclaw/project/bus/{rtl,tb,scripts,waves}
```

- [ ] **Step 2: Write `tb/apb_if.sv`**

```systemverilog
// APB3 Bus Interface
// Connects UVM testbench to DUT. Uses clocking blocks for proper timing.

interface apb_if #(
    parameter int NUM_MASTERS = 2
) (
    input logic pclk,
    input logic presetn
);
    // Standard APB3 signals
    logic [31:0]  paddr;
    logic [31:0]  pwdata;
    logic [31:0]  prdata;
    logic         pwrite;
    logic         psel;
    logic         penable;
    logic         pready;

    // Master-side request/grant signals
    logic [NUM_MASTERS-1:0] req;
    logic [NUM_MASTERS-1:0] gnt;

    // Clocking block for driver (output with skew)
    clocking drv_cb @(posedge pclk);
        output paddr, pwdata, pwrite, psel, penable;
        output req;
        input  gnt;
        input  prdata, pready, presetn;
    endclocking

    // Clocking block for monitor (input with skew)
    clocking mon_cb @(posedge pclk);
        input paddr, pwdata, prdata, pwrite, psel, penable, pready;
        input req, gnt;
        input presetn;
    endclocking

    // Driver modport — for apb_master_driver
    modport drv_mp (
        input  pclk, presetn,
        output paddr, pwdata, pwrite, psel, penable,
        output req,
        input  gnt, prdata, pready
    );

    // Monitor modport — for apb_master_monitor
    modport mon_mp (
        input pclk, presetn,
        input paddr, pwdata, prdata, pwrite, psel, penable, pready, req, gnt
    );

endinterface
```

---

### Task 2: RTL — APB Master

**Files:**
- Create: `rtl/apb_master.v`

**Interfaces:**
- Produces: `apb_master` module
- Ports: `pclk, presetn, req, gnt, paddr, pwdata, prdata, pwrite, psel, penable, pready`
- Internal registers `txn_req, txn_addr, txn_wdata, txn_write` for testbench stimulus

- [ ] **Step 1: Write `rtl/apb_master.v`**

```verilog
// APB3 Master Module
// FSM: IDLE → REQ → SETUP → ACCESS → IDLE
// Drives APB bus only when granted by arbiter

module apb_master #(
    parameter MASTER_ID = 0
) (
    input  wire         pclk,
    input  wire         presetn,

    // Arbiter handshake
    output reg          req,
    input  wire         gnt,

    // APB bus (driven when granted)
    output reg  [31:0]  paddr,
    output reg  [31:0]  pwdata,
    input  wire [31:0]  prdata,
    output reg          pwrite,
    output reg          psel,
    output reg          penable,
    input  wire         pready
);

    // Transaction request from stimulus (driven by UVM driver via DUT ports,
    // or tied to constants for RTL-level standalone testing)
    reg         txn_req;
    reg [31:0]  txn_addr;
    reg [31:0]  txn_wdata;
    reg         txn_write;

    localparam FSM_IDLE   = 3'd0;
    localparam FSM_REQ    = 3'd1;
    localparam FSM_SETUP  = 3'd2;
    localparam FSM_ACCESS = 3'd3;

    reg [2:0] state, next_state;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state <= FSM_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            FSM_IDLE:   if (txn_req)  next_state = FSM_REQ;
            FSM_REQ:    if (gnt)      next_state = FSM_SETUP;
            FSM_SETUP:                next_state = FSM_ACCESS;
            FSM_ACCESS: if (pready)   next_state = FSM_IDLE;
            default:                  next_state = FSM_IDLE;
        endcase
    end

    always @(*) begin
        req     = (state == FSM_REQ);
        psel    = (state == FSM_SETUP) || (state == FSM_ACCESS);
        penable = (state == FSM_ACCESS);
        pwrite  = txn_write;
        paddr   = txn_addr;
        pwdata  = txn_wdata;
    end

endmodule
```

---

### Task 3: RTL — APB Arbiter and Address Decoder

**Files:**
- Create: `rtl/apb_arbiter.v`, `rtl/apb_decoder.v`

**Interfaces:**
- `apb_arbiter`: Consumes `req[1:0]` + per-master APB bus → Produces `gnt[1:0]`, muxed APB bus
- `apb_decoder`: Consumes `paddr[15:12]`, `psel_in` → Produces `psel_o[1:0]`

- [ ] **Step 1: Write `rtl/apb_arbiter.v`**

```verilog
// APB3 Arbiter — Fixed Priority (Master 0 > Master 1)
// FSM: IDLE → GRANT → BUSY → IDLE
// Muxes one granted master's APB signals onto shared bus

module apb_arbiter (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0
    input  wire         req_0,
    output wire         gnt_0,
    input  wire [31:0]  paddr_0,
    input  wire [31:0]  pwdata_0,
    input  wire         pwrite_0,
    input  wire         psel_0,
    input  wire         penable_0,

    // Master 1
    input  wire         req_1,
    output wire         gnt_1,
    input  wire [31:0]  paddr_1,
    input  wire [31:0]  pwdata_1,
    input  wire         pwrite_1,
    input  wire         psel_1,
    input  wire         penable_1,

    // Shared APB bus
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,

    input  wire         pready
);

    localparam IDLE  = 2'd0;
    localparam GRANT = 2'd1;
    localparam BUSY  = 2'd2;

    reg [1:0] state, next_state;
    reg       granted_master, granted_master_next;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state          <= IDLE;
            granted_master <= 1'b0;
        end else begin
            state          <= next_state;
            granted_master <= granted_master_next;
        end
    end

    always @(*) begin
        next_state          = state;
        granted_master_next = granted_master;
        case (state)
            IDLE: begin
                if (req_0) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b0;
                end else if (req_1) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b1;
                end
            end
            GRANT:  next_state = BUSY;
            BUSY:   if (pready) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    assign gnt_0 = (state == GRANT) && (granted_master == 1'b0);
    assign gnt_1 = (state == GRANT) && (granted_master == 1'b1);

    assign paddr   = (granted_master == 1'b0) ? paddr_0   : paddr_1;
    assign pwdata  = (granted_master == 1'b0) ? pwdata_0  : pwdata_1;
    assign pwrite  = (granted_master == 1'b0) ? pwrite_0  : pwrite_1;
    assign psel    = (granted_master == 1'b0) ? psel_0    : psel_1;
    assign penable = (granted_master == 1'b0) ? penable_0 : penable_1;

endmodule
```

- [ ] **Step 2: Write `rtl/apb_decoder.v`**

```verilog
// APB Address Decoder
// PADDR[15:12] = 0x0 → Slave 0 (Memory)
// PADDR[15:12] = 0x1 → Slave 1 (GPIO)

module apb_decoder (
    input  wire [31:0] paddr,
    input  wire        psel_in,
    output wire [1:0]  psel_o
);

    assign psel_o[0] = psel_in && (paddr[15:12] == 4'h0);
    assign psel_o[1] = psel_in && (paddr[15:12] == 4'h1);

endmodule
```

---

### Task 4: RTL — Memory Slave and GPIO Slave

**Files:**
- Create: `rtl/apb_slave_mem.v`, `rtl/apb_slave_gpio.v`

**Interfaces:**
- `apb_slave_mem`: APB slave — 256×32 memory, randomized PREADY stall via LFSR
- `apb_slave_gpio`: APB slave — 4 registers (DATA, DIR, INT_EN, INT_STATUS), interrupt output

- [ ] **Step 1: Write `rtl/apb_slave_mem.v`**

```verilog
// APB3 Memory Slave
// 256 x 32-bit memory
// Address range: 0x0000-0x0FFF (word-aligned: 0x000-0x3FC)
// Randomized PREADY stall: STALL_PROB / 256 chance

module apb_slave_mem #(
    parameter STALL_PROB = 64   // 64/256 = 25% stall probability
) (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    output reg  [31:0]  prdata,
    output reg          pready
);

    reg [31:0] mem [0:255];
    reg [7:0]  lfsr;
    integer    word_idx;

    // PREADY with randomized stall (LFSR-based, only during ACCESS)
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pready <= 1'b1;
            lfsr   <= 8'h5A;
        end else begin
            if (penable && psel) begin
                lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
                pready <= (lfsr >= STALL_PROB);
            end else begin
                pready <= 1'b1;
            end
        end
    end

    // Write
    always @(posedge pclk) begin
        if (psel && penable && pready && pwrite) begin
            mem[paddr[9:2]] <= pwdata;
        end
    end

    // Read (combinational for APB spec)
    always @(*) begin
        prdata = mem[paddr[9:2]];
    end

endmodule
```

- [ ] **Step 2: Write `rtl/apb_slave_gpio.v`**

```verilog
// APB3 GPIO Register Slave
// 4 registers:
//   0x00: DATA        — GPIO output data
//   0x04: DIR         — Direction (1=output)
//   0x08: INT_EN      — Interrupt enable
//   0x0C: INT_STATUS  — Interrupt status
// Address range: 0x1000-0x1FFF

module apb_slave_gpio (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    output reg  [31:0]  prdata,
    output reg          pready,
    output wire         gpio_int
);

    reg [31:0] reg_data;
    reg [31:0] reg_dir;
    reg [31:0] reg_int_en;
    reg [31:0] reg_int_status;

    assign gpio_int = |(reg_int_status & reg_int_en);

    // APB write
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_data       <= 32'd0;
            reg_dir        <= 32'd0;
            reg_int_en     <= 32'd0;
            reg_int_status <= 32'd0;
        end else if (psel && penable && pwrite) begin
            case (paddr[3:2])
                2'd0: reg_data       <= pwdata;
                2'd1: reg_dir        <= pwdata;
                2'd2: reg_int_en     <= pwdata;
                2'd3: reg_int_status <= pwdata;
            endcase
        end
    end

    // APB read
    always @(*) begin
        case (paddr[3:2])
            2'd0: prdata = reg_data;
            2'd1: prdata = reg_dir;
            2'd2: prdata = reg_int_en;
            2'd3: prdata = reg_int_status;
            default: prdata = 32'd0;
        endcase
    end

    // PREADY — always ready
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            pready <= 1'b1;
        else if (psel && penable)
            pready <= 1'b1;
        else
            pready <= 1'b1;
    end

endmodule
```

---

### Task 5: RTL — Top-Level Integration

**Files:**
- Create: `rtl/apb_top.v`

**Interfaces:**
- Consumes: `apb_master`, `apb_arbiter`, `apb_decoder`, `apb_slave_mem`, `apb_slave_gpio`
- Produces: `apb_top` — single DUT module with all master/slave/bus ports exposed

- [ ] **Step 1: Write `rtl/apb_top.v`**

```verilog
// APB3 Bus System — Top Level
// 2 Masters → Arbiter → Decoder → 2 Slaves (Memory + GPIO)

module apb_top (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 — per-master APB signals (driven by master, exposed for testbench)
    output wire         req_0,
    input  wire         gnt_0,
    input  wire [31:0]  paddr_0,
    input  wire [31:0]  pwdata_0,
    input  wire         pwrite_0,
    input  wire         psel_0,
    input  wire         penable_0,

    // Master 1
    output wire         req_1,
    input  wire         gnt_1,
    input  wire [31:0]  paddr_1,
    input  wire [31:0]  pwdata_1,
    input  wire         pwrite_1,
    input  wire         psel_1,
    input  wire         penable_1,

    // Shared APB bus (exposed for monitoring)
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire [31:0]  prdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,
    output wire         pready,

    // Slave selects
    output wire [1:0]   psel_slv,

    // GPIO interrupt
    output wire         gpio_int
);

    // Internal connections
    wire [31:0] arb_paddr, arb_pwdata;
    wire        arb_pwrite, arb_psel, arb_penable;
    wire [31:0] prdata_slv0, prdata_slv1;
    wire        pready_slv0, pready_slv1;
    wire        arb_pready;

    // Master 0
    apb_master #(.MASTER_ID(0)) u_master0 (
        .pclk    (pclk),
        .presetn (presetn),
        .req     (req_0),
        .gnt     (gnt_0),
        .paddr   (paddr_0),
        .pwdata  (pwdata_0),
        .prdata  (prdata),
        .pwrite  (pwrite_0),
        .psel    (psel_0),
        .penable (penable_0),
        .pready  (pready)
    );

    // Master 1
    apb_master #(.MASTER_ID(1)) u_master1 (
        .pclk    (pclk),
        .presetn (presetn),
        .req     (req_1),
        .gnt     (gnt_1),
        .paddr   (paddr_1),
        .pwdata  (pwdata_1),
        .prdata  (prdata),
        .pwrite  (pwrite_1),
        .psel    (psel_1),
        .penable (penable_1),
        .pready  (pready)
    );

    // Arbiter
    apb_arbiter u_arbiter (
        .pclk      (pclk),
        .presetn   (presetn),
        .req_0     (req_0),
        .gnt_0     (gnt_0),
        .paddr_0   (paddr_0),
        .pwdata_0  (pwdata_0),
        .pwrite_0  (pwrite_0),
        .psel_0    (psel_0),
        .penable_0 (penable_0),
        .req_1     (req_1),
        .gnt_1     (gnt_1),
        .paddr_1   (paddr_1),
        .pwdata_1  (pwdata_1),
        .pwrite_1  (pwrite_1),
        .psel_1    (psel_1),
        .penable_1 (penable_1),
        .paddr     (arb_paddr),
        .pwdata    (arb_pwdata),
        .pwrite    (arb_pwrite),
        .psel      (arb_psel),
        .penable   (arb_penable),
        .pready    (arb_pready)
    );

    // Decoder
    apb_decoder u_decoder (
        .paddr   (arb_paddr),
        .psel_in (arb_psel),
        .psel_o  (psel_slv)
    );

    // Slave 0: Memory
    apb_slave_mem #(.STALL_PROB(64)) u_slave_mem (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel_slv[0]),
        .penable (arb_penable),
        .pwrite  (arb_pwrite),
        .paddr   (arb_paddr),
        .pwdata  (arb_pwdata),
        .prdata  (prdata_slv0),
        .pready  (pready_slv0)
    );

    // Slave 1: GPIO
    apb_slave_gpio u_slave_gpio (
        .pclk     (pclk),
        .presetn  (presetn),
        .psel     (psel_slv[1]),
        .penable  (arb_penable),
        .pwrite   (arb_pwrite),
        .paddr    (arb_paddr),
        .pwdata   (arb_pwdata),
        .prdata   (prdata_slv1),
        .pready   (pready_slv1),
        .gpio_int (gpio_int)
    );

    // PRDATA and PREADY mux from slaves back to shared bus
    assign prdata     = psel_slv[0] ? prdata_slv0 :
                        psel_slv[1] ? prdata_slv1 : 32'd0;
    assign arb_pready = psel_slv[0] ? pready_slv0 :
                        psel_slv[1] ? pready_slv1 : 1'b1;

    // Drive shared bus outputs
    assign paddr   = arb_paddr;
    assign pwdata  = arb_pwdata;
    assign pwrite  = arb_pwrite;
    assign psel    = arb_psel;
    assign penable = arb_penable;
    assign pready  = arb_pready;

endmodule
```

Wait — there's a port direction issue. `apb_top` has per-master `paddr_0`, `pwdata_0`, etc. as `input` (driven from outside), but `apb_master` has these as `output`. The master module drives these, not the testbench. The testbench only controls `req`, `addr`, `wdata`, `write` through the `txn_*` internal registers.

Actually, looking at my `apb_master.v` design again: the UVM driver needs to control `txn_req`, `txn_addr`, `txn_wdata`, `txn_write` — but these are internal registers inside the master, not ports. The master drives `req`, `paddr`, `pwdata`, etc. as outputs.

So the flow is:
1. UVM driver drives `req` on the interface
2. Arbiter grants → `gnt` goes high
3. Master FSM advances, driving `paddr`, `pwdata`, `psel`, `penable` onto its port
4. These get muxed through arbiter to shared bus

But wait — how does the UVM driver set the address and data? The master module has `txn_addr`, `txn_wdata`, etc. as internal registers, not ports. The UVM driver can't set these.

I need to make `txn_*` signals as ports on `apb_master` so the testbench can control them. OR I need to make the master not drive `paddr`, `pwdata` etc. internally but instead accept them as inputs and just pass-through when granted.

The simplest approach: make the master's per-transfer control signals (`txn_addr`, `txn_wdata`, `txn_write`, `txn_req`) into ports that the testbench drives directly. The master module becomes a "thin" FSM controller that:
- Takes `txn_req` as input → asserts `req`
- Takes `gnt` as input → enters SETUP/ACCESS
- Drives `psel`, `penable` as FSM outputs
- Passes through `txn_addr` → `paddr`, `txn_wdata` → `pwdata`, `txn_write` → `pwrite`

Let me rethink `apb_master.v` to have these as input ports, not internal registers. Let me also rethink `apb_top.v` to expose them properly.

Actually, let me take a step back. The cleanest design for UVM-driven testing is:

**apb_master.v** — FSM controller only:
- Inputs: `pclk, presetn, txn_req, txn_addr, txn_wdata, txn_write, gnt, prdata, pready`
- Outputs: `req, paddr, pwdata, pwrite, psel, penable`
- When `txn_req` is high, the FSM starts requesting the bus
- `paddr/pwdata/pwrite` just pass through from `txn_*` inputs (gated by FSM state)

**apb_top.v** — exposes `txn_req/addr/wdata/write` as top-level ports for the testbench to drive

Let me fix the plan. I need to update `apb_master.v` in Task 2 and `apb_top.v` in Task 5. Let me rewrite the plan file.

Actually, this is getting complex. Let me just rewrite the key parts correctly. The plan file is already written - let me fix it.

Let me take a completely different approach. Rather than editing the massive plan, let me just proceed with implementation and get things right in the actual code. The plan documents the intent, and I'll fix the signal directions during implementation.

Let me proceed to present the plan, offer execution, and fix things when writing actual code.<｜end▁of▁thinking｜>Now let me write the plan file properly:

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="Write">
<｜｜DSML｜｜parameter name="content" string="true"># APB Bus Practice Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a multi-master, multi-slave APB3 bus framework with UVM verification, VCS compilation, and Verdi waveform viewing.

**Architecture:** 2 masters → fixed-priority arbiter → address decoder → 2 slaves (memory + GPIO register file). RTL in pure Verilog, verification in SystemVerilog UVM. Masters accept txn_* stimulus from testbench, run req/gnt handshake with arbiter, arbiter muxes granted master's bus onto shared APB, decoder drives PSELx, slaves respond with PREADY/PRDATA.

**Tech Stack:** Verilog (RTL), SystemVerilog + UVM (verification), VCS (simulation), Verdi (waveform)

## Global Constraints

- RTL modules in pure Verilog (`*.v`), verification in SystemVerilog (`*.sv`)
- APB3 protocol: IDLE → SETUP → ACCESS state machine per transfer
- FSDB waveform dump enabled for all simulations
- `timescale 1ns/1ps` throughout
- No generate blocks — explicit instantiation for readability
- Master modules are "thin" FSM controllers: txn_* stimulus ports are inputs, APB bus signals are outputs

---

## File Map

| File | Responsibility |
|------|---------------|
| `tb/apb_if.sv` | SV interface: APB signals + req/gnt per master |
| `rtl/apb_master.v` | APB master FSM: txn_stimulus input → req/gnt handshake → APB bus output |
| `rtl/apb_arbiter.v` | Fixed-priority arbiter: IDLE→GRANT→BUSY, muxes master bus to APB |
| `rtl/apb_decoder.v` | Address decoder: PADDR[15:12] → PSELx |
| `rtl/apb_slave_mem.v` | 256×32 memory slave with LFSR PREADY stall |
| `rtl/apb_slave_gpio.v` | GPIO register file slave with interrupt output |
| `rtl/apb_top.v` | Top-level integration: 2 masters, arbiter, decoder, 2 slaves |
| `tb/apb_pkg.sv` | UVM package: transaction, typedefs |
| `tb/apb_master_driver.sv` | UVM driver: seq_item → pin-level stimulus + req/gnt protocol |
| `tb/apb_master_monitor.sv` | UVM monitor: pin-level → analysis port transaction |
| `tb/apb_master_agent.sv` | UVM agent: sequencer + driver + monitor |
| `tb/apb_scoreboard.sv` | UVM subscriber: reference model for memory + GPIO |
| `tb/apb_env.sv` | UVM env: N agents + scoreboard, TLM connections |
| `tb/sequence_lib.sv` | Sequence library: sanity, random, burst, error |
| `tb/apb_test.sv` | UVM tests: base_test + concrete tests per scenario |
| `tb/tb_top.sv` | Top-level testbench: clock/reset, DUT, interface bind, run_test() |
| `scripts/filelist.f` | File list for VCS compilation |
| `scripts/compile.sh` | VCS compile + elaborate with Verdi FSDB support |
| `scripts/run.sh` | Simulation run script |
| `scripts/verdi.sh` | Verdi waveform viewer launch script |
| `Makefile` | Top-level convenience targets |

---

### Task 1: Directory Setup and APB Interface

**Files:**
- Create: `tb/apb_if.sv`

**Interfaces:**
- Produces: `apb_if` — SV interface with clocking blocks and modports (drv_mp, mon_mp)

- [ ] **Step 1: Create directories**

```bash
mkdir -p /home/openclaw/project/bus/{rtl,tb,scripts,waves}
```

- [ ] **Step 2: Write `tb/apb_if.sv`**

```systemverilog
// APB3 Bus Interface with clocking blocks for UVM driver/monitor

interface apb_if #(
    parameter int NUM_MASTERS = 2
) (
    input logic pclk,
    input logic presetn
);
    // APB3 signals
    logic [31:0]  paddr;
    logic [31:0]  pwdata;
    logic [31:0]  prdata;
    logic         pwrite;
    logic         psel;
    logic         penable;
    logic         pready;

    // Master request/grant (per master)
    logic [NUM_MASTERS-1:0] req;
    logic [NUM_MASTERS-1:0] gnt;

    // Per-master txn stimulus (driven by UVM driver, connected to apb_master ports)
    logic [NUM_MASTERS-1:0]        txn_req;
    logic [31:0] txn_addr [NUM_MASTERS];
    logic [31:0] txn_wdata [NUM_MASTERS];
    logic        txn_write [NUM_MASTERS];

    // Driver clocking block
    clocking drv_cb @(posedge pclk);
        output txn_req, txn_addr, txn_wdata, txn_write;
        input  gnt;
        input  prdata, pready;
    endclocking

    // Monitor clocking block
    clocking mon_cb @(posedge pclk);
        input paddr, pwdata, prdata, pwrite, psel, penable, pready;
        input req, gnt;
    endclocking

    // Driver modport
    modport drv_mp (
        input  pclk, presetn,
        output txn_req, txn_addr, txn_wdata, txn_write,
        input  gnt, prdata, pready
    );

    // Monitor modport
    modport mon_mp (
        input pclk, presetn,
        input paddr, pwdata, prdata, pwrite, psel, penable, pready,
        input req, gnt
    );

endinterface
```

---

### Task 2: RTL — APB Master

**Files:**
- Create: `rtl/apb_master.v`

**Interfaces:**
- Produces: `apb_master` module
- Inputs: `pclk, presetn, gnt, prdata, pready, txn_req, txn_addr, txn_wdata, txn_write`
- Outputs: `req, paddr, pwdata, pwrite, psel, penable`
- FSM: IDLE → REQ (assert req) → SETUP (got gnt, drive addr/data) → ACCESS (assert penable) → IDLE (pready)

- [ ] **Step 1: Write `rtl/apb_master.v`**

```verilog
// APB3 Master — Thin FSM Controller
// txn_* inputs: driven by testbench (UVM driver)
// req: asserted to arbiter when txn_req is high
// APB bus outputs: pass-through from txn_* when in SETUP/ACCESS
// prdata: fed back to testbench via shared bus

module apb_master #(
    parameter MASTER_ID = 0
) (
    input  wire         pclk,
    input  wire         presetn,

    // Arbiter handshake
    output reg          req,
    input  wire         gnt,

    // APB bus outputs (driven in SETUP/ACCESS)
    output reg  [31:0]  paddr,
    output reg  [31:0]  pwdata,
    input  wire [31:0]  prdata,
    output reg          pwrite,
    output reg          psel,
    output reg          penable,
    input  wire         pready,

    // Txn stimulus from testbench
    input  wire         txn_req,
    input  wire [31:0]  txn_addr,
    input  wire [31:0]  txn_wdata,
    input  wire         txn_write
);

    localparam FSM_IDLE   = 3'd0;
    localparam FSM_REQ    = 3'd1;
    localparam FSM_SETUP  = 3'd2;
    localparam FSM_ACCESS = 3'd3;

    reg [2:0] state, next_state;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            state <= FSM_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            FSM_IDLE:   if (txn_req)  next_state = FSM_REQ;
            FSM_REQ:    if (gnt)      next_state = FSM_SETUP;
            FSM_SETUP:                next_state = FSM_ACCESS;
            FSM_ACCESS: if (pready)   next_state = FSM_IDLE;
            default:                  next_state = FSM_IDLE;
        endcase
    end

    always @(*) begin
        req     = (state == FSM_REQ);
        psel    = (state == FSM_SETUP) || (state == FSM_ACCESS);
        penable = (state == FSM_ACCESS);
        pwrite  = txn_write;
        paddr   = txn_addr;
        pwdata  = txn_wdata;
    end

endmodule
```

---

### Task 3: RTL — APB Arbiter and Address Decoder

**Files:**
- Create: `rtl/apb_arbiter.v`, `rtl/apb_decoder.v`

**Interfaces:**
- `apb_arbiter`: per-master APB + req/gnt → muxed APB bus. FSM: IDLE → GRANT → BUSY
- `apb_decoder`: paddr[15:12] + psel_in → psel_o[1:0]

- [ ] **Step 1: Write `rtl/apb_arbiter.v`**

```verilog
// APB3 Arbiter — Fixed Priority (Master 0 > Master 1)
// FSM: IDLE → GRANT → BUSY → IDLE
// Muxes the granted master's APB bus onto the shared APB bus

module apb_arbiter (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 APB bus
    input  wire         req_0,
    output wire         gnt_0,
    input  wire [31:0]  paddr_0,
    input  wire [31:0]  pwdata_0,
    input  wire         pwrite_0,
    input  wire         psel_0,
    input  wire         penable_0,

    // Master 1 APB bus
    input  wire         req_1,
    output wire         gnt_1,
    input  wire [31:0]  paddr_1,
    input  wire [31:0]  pwdata_1,
    input  wire         pwrite_1,
    input  wire         psel_1,
    input  wire         penable_1,

    // Shared APB bus output
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,

    input  wire         pready
);

    localparam IDLE  = 2'd0;
    localparam GRANT = 2'd1;
    localparam BUSY  = 2'd2;

    reg [1:0] state, next_state;
    reg       granted_master, granted_master_next;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            state          <= IDLE;
            granted_master <= 1'b0;
        end else begin
            state          <= next_state;
            granted_master <= granted_master_next;
        end
    end

    always @(*) begin
        next_state          = state;
        granted_master_next = granted_master;
        case (state)
            IDLE: begin
                if (req_0) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b0;
                end else if (req_1) begin
                    next_state          = GRANT;
                    granted_master_next = 1'b1;
                end
            end
            GRANT:  next_state = BUSY;
            BUSY:   if (pready) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    assign gnt_0 = (state == GRANT) && (granted_master == 1'b0);
    assign gnt_1 = (state == GRANT) && (granted_master == 1'b1);

    assign paddr   = (granted_master == 1'b0) ? paddr_0   : paddr_1;
    assign pwdata  = (granted_master == 1'b0) ? pwdata_0  : pwdata_1;
    assign pwrite  = (granted_master == 1'b0) ? pwrite_0  : pwrite_1;
    assign psel    = (granted_master == 1'b0) ? psel_0    : psel_1;
    assign penable = (granted_master == 1'b0) ? penable_0 : penable_1;

endmodule
```

- [ ] **Step 2: Write `rtl/apb_decoder.v`**

```verilog
// APB Address Decoder
// PADDR[15:12] = 0x0 → Slave 0 (Memory)
// PADDR[15:12] = 0x1 → Slave 1 (GPIO)

module apb_decoder (
    input  wire [31:0] paddr,
    input  wire        psel_in,
    output wire [1:0]  psel_o
);

    assign psel_o[0] = psel_in && (paddr[15:12] == 4'h0);
    assign psel_o[1] = psel_in && (paddr[15:12] == 4'h1);

endmodule
```

---

### Task 4: RTL — Memory Slave and GPIO Slave

**Files:**
- Create: `rtl/apb_slave_mem.v`, `rtl/apb_slave_gpio.v`

**Interfaces:**
- `apb_slave_mem`: 256×32 memory, LFSR-based PREADY stall, addr range 0x0000-0x0FFF
- `apb_slave_gpio`: 4 registers (DATA/DIR/INT_EN/INT_STATUS), gpio_int output, addr range 0x1000-0x1FFF

- [ ] **Step 1: Write `rtl/apb_slave_mem.v`**

```verilog
// APB3 Memory Slave — 256 × 32-bit
// Address range: 0x0000-0x0FFF
// Randomized PREADY stall using 8-bit LFSR

module apb_slave_mem #(
    parameter STALL_PROB = 64   // 64/256 = 25% stall chance
) (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    output reg  [31:0]  prdata,
    output reg          pready
);

    reg [31:0] mem [0:255];
    reg [7:0]  lfsr;

    // PREADY with LFSR-based randomized stall
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            pready <= 1'b1;
            lfsr   <= 8'h5A;
        end else begin
            if (penable && psel) begin
                lfsr   <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
                pready <= (lfsr >= STALL_PROB);
            end else begin
                pready <= 1'b1;
            end
        end
    end

    // Write
    always @(posedge pclk) begin
        if (psel && penable && pready && pwrite)
            mem[paddr[9:2]] <= pwdata;
    end

    // Read (combinational — APB spec)
    always @(*) begin
        prdata = mem[paddr[9:2]];
    end

endmodule
```

- [ ] **Step 2: Write `rtl/apb_slave_gpio.v`**

```verilog
// APB3 GPIO Register Slave
// 4 registers: DATA(0x00), DIR(0x04), INT_EN(0x08), INT_STATUS(0x0C)
// Address range: 0x1000-0x1FFF
// Interrupt: gpio_int = |(INT_STATUS & INT_EN)

module apb_slave_gpio (
    input  wire         pclk,
    input  wire         presetn,
    input  wire         psel,
    input  wire         penable,
    input  wire         pwrite,
    input  wire [31:0]  paddr,
    input  wire [31:0]  pwdata,
    output reg  [31:0]  prdata,
    output reg          pready,
    output wire         gpio_int
);

    reg [31:0] reg_data;
    reg [31:0] reg_dir;
    reg [31:0] reg_int_en;
    reg [31:0] reg_int_status;

    assign gpio_int = |(reg_int_status & reg_int_en);

    // APB write
    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_data       <= 32'd0;
            reg_dir        <= 32'd0;
            reg_int_en     <= 32'd0;
            reg_int_status <= 32'd0;
        end else if (psel && penable && pwrite) begin
            case (paddr[3:2])
                2'd0: reg_data       <= pwdata;
                2'd1: reg_dir        <= pwdata;
                2'd2: reg_int_en     <= pwdata;
                2'd3: reg_int_status <= pwdata;
            endcase
        end
    end

    // APB read
    always @(*) begin
        case (paddr[3:2])
            2'd0: prdata = reg_data;
            2'd1: prdata = reg_dir;
            2'd2: prdata = reg_int_en;
            2'd3: prdata = reg_int_status;
            default: prdata = 32'd0;
        endcase
    end

    // PREADY — always ready
    always @(posedge pclk or negedge presetn) begin
        if (!presetn)
            pready <= 1'b1;
        else if (psel && penable)
            pready <= 1'b1;
        else
            pready <= 1'b1;
    end

endmodule
```

---

### Task 5: RTL — Top-Level Integration

**Files:**
- Create: `rtl/apb_top.v`

**Interfaces:**
- Consumes: `apb_master`×2, `apb_arbiter`, `apb_decoder`, `apb_slave_mem`, `apb_slave_gpio`
- Produces: `apb_top` DUT — exposes txn_* stimulus ports and APB bus monitor ports

- [ ] **Step 1: Write `rtl/apb_top.v`**

```verilog
// APB3 Bus System — Top Level
// 2 Masters → Arbiter → Decoder → 2 Slaves (Memory + GPIO)

module apb_top (
    input  wire         pclk,
    input  wire         presetn,

    // Master 0 txn stimulus (from testbench)
    input  wire         txn_req_0,
    input  wire [31:0]  txn_addr_0,
    input  wire [31:0]  txn_wdata_0,
    input  wire         txn_write_0,

    // Master 1 txn stimulus (from testbench)
    input  wire         txn_req_1,
    input  wire [31:0]  txn_addr_1,
    input  wire [31:0]  txn_wdata_1,
    input  wire         txn_write_1,

    // Per-master req/gnt (exposed for monitoring)
    output wire         req_0,
    output wire         gnt_0,
    output wire         req_1,
    output wire         gnt_1,

    // Shared APB bus (exposed for monitoring)
    output wire [31:0]  paddr,
    output wire [31:0]  pwdata,
    output wire [31:0]  prdata,
    output wire         pwrite,
    output wire         psel,
    output wire         penable,
    output wire         pready,

    // Slave selects
    output wire [1:0]   psel_slv,

    // GPIO interrupt
    output wire         gpio_int
);

    // Internal connections
    wire [31:0] m0_paddr, m0_pwdata, m1_paddr, m1_pwdata;
    wire        m0_pwrite, m0_psel, m0_penable;
    wire        m1_pwrite, m1_psel, m1_penable;

    wire [31:0] arb_paddr, arb_pwdata;
    wire        arb_pwrite, arb_psel, arb_penable;
    wire        arb_pready;

    wire [31:0] prdata_slv0, prdata_slv1;
    wire        pready_slv0, pready_slv1;

    // Master 0
    apb_master #(.MASTER_ID(0)) u_master0 (
        .pclk      (pclk),
        .presetn   (presetn),
        .req       (req_0),
        .gnt       (gnt_0),
        .paddr     (m0_paddr),
        .pwdata    (m0_pwdata),
        .prdata    (prdata),
        .pwrite    (m0_pwrite),
        .psel      (m0_psel),
        .penable   (m0_penable),
        .pready    (pready),
        .txn_req   (txn_req_0),
        .txn_addr  (txn_addr_0),
        .txn_wdata (txn_wdata_0),
        .txn_write (txn_write_0)
    );

    // Master 1
    apb_master #(.MASTER_ID(1)) u_master1 (
        .pclk      (pclk),
        .presetn   (presetn),
        .req       (req_1),
        .gnt       (gnt_1),
        .paddr     (m1_paddr),
        .pwdata    (m1_pwdata),
        .prdata    (prdata),
        .pwrite    (m1_pwrite),
        .psel      (m1_psel),
        .penable   (m1_penable),
        .pready    (pready),
        .txn_req   (txn_req_1),
        .txn_addr  (txn_addr_1),
        .txn_wdata (txn_wdata_1),
        .txn_write (txn_write_1)
    );

    // Arbiter
    apb_arbiter u_arbiter (
        .pclk      (pclk),
        .presetn   (presetn),
        .req_0     (req_0),
        .gnt_0     (gnt_0),
        .paddr_0   (m0_paddr),
        .pwdata_0  (m0_pwdata),
        .pwrite_0  (m0_pwrite),
        .psel_0    (m0_psel),
        .penable_0 (m0_penable),
        .req_1     (req_1),
        .gnt_1     (gnt_1),
        .paddr_1   (m1_paddr),
        .pwdata_1  (m1_pwdata),
        .pwrite_1  (m1_pwrite),
        .psel_1    (m1_psel),
        .penable_1 (m1_penable),
        .paddr     (arb_paddr),
        .pwdata    (arb_pwdata),
        .pwrite    (arb_pwrite),
        .psel      (arb_psel),
        .penable   (arb_penable),
        .pready    (arb_pready)
    );

    // Decoder
    apb_decoder u_decoder (
        .paddr   (arb_paddr),
        .psel_in (arb_psel),
        .psel_o  (psel_slv)
    );

    // Slave 0: Memory
    apb_slave_mem #(.STALL_PROB(64)) u_slave_mem (
        .pclk    (pclk),
        .presetn (presetn),
        .psel    (psel_slv[0]),
        .penable (arb_penable),
        .pwrite  (arb_pwrite),
        .paddr   (arb_paddr),
        .pwdata  (arb_pwdata),
        .prdata  (prdata_slv0),
        .pready  (pready_slv0)
    );

    // Slave 1: GPIO
    apb_slave_gpio u_slave_gpio (
        .pclk     (pclk),
        .presetn  (presetn),
        .psel     (psel_slv[1]),
        .penable  (arb_penable),
        .pwrite   (arb_pwrite),
        .paddr    (arb_paddr),
        .pwdata   (arb_pwdata),
        .prdata   (prdata_slv1),
        .pready   (pready_slv1),
        .gpio_int (gpio_int)
    );

    // PRDATA + PREADY mux from slaves to shared bus
    assign prdata     = psel_slv[0] ? prdata_slv0 :
                        psel_slv[1] ? prdata_slv1 : 32'd0;
    assign arb_pready = psel_slv[0] ? pready_slv0 :
                        psel_slv[1] ? pready_slv1 : 1'b1;

    // Drive shared bus outputs
    assign paddr   = arb_paddr;
    assign pwdata  = arb_pwdata;
    assign pwrite  = arb_pwrite;
    assign psel    = arb_psel;
    assign penable = arb_penable;
    assign pready  = arb_pready;

endmodule
```

---

### Task 6: UVM — Package and Transaction

**Files:**
- Create: `tb/apb_pkg.sv`

**Interfaces:**
- Produces: `apb_pkg` — imported by all UVM components
- Contains: `apb_transaction` (extends `uvm_sequence_item`), constrained randomization

- [ ] **Step 1: Write `tb/apb_pkg.sv`**

```systemverilog
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
```

---

### Task 7: UVM — Driver, Monitor, Agent

**Files:**
- Create: `tb/apb_master_driver.sv`, `tb/apb_master_monitor.sv`, `tb/apb_master_agent.sv`

**Interfaces:**
- `apb_master_driver`: get_next_item() → drives txn_req/addr/wdata/write via vif, waits gnt/pready
- `apb_master_monitor`: samples shared APB bus → writes transactions to analysis port
- `apb_master_agent`: contains sequencer + driver + monitor; configurable master_id

- [ ] **Step 1: Write `tb/apb_master_driver.sv`**

```systemverilog
// APB Master UVM Driver
// Gets transactions from sequencer, drives txn_* stimulus and req/gnt handshake

class apb_master_driver extends uvm_driver #(apb_pkg::apb_transaction);

    `uvm_component_utils(apb_master_driver)

    virtual apb_if vif;
    int master_id;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_pkg::apb_transaction txn;

        forever begin
            seq_item_port.get_next_item(txn);

            // Drive stimulus
            vif.drv_cb.txn_addr[master_id]  <= txn.addr;
            vif.drv_cb.txn_wdata[master_id] <= txn.data;
            vif.drv_cb.txn_write[master_id] <= txn.rw;
            vif.drv_cb.txn_req[master_id]   <= 1'b1;

            // Wait for gnt
            while (!vif.drv_cb.gnt[master_id])
                @(vif.drv_cb);

            // Clear txn_req after grant
            vif.drv_cb.txn_req[master_id] <= 1'b0;

            // Wait for pready (transaction complete)
            while (!vif.drv_cb.pready)
                @(vif.drv_cb);

            // Capture read data
            if (!txn.rw)
                txn.data = vif.drv_cb.prdata;

            @(vif.drv_cb);  // one extra cycle between transactions
            seq_item_port.item_done();
        end
    endtask

endclass : apb_master_driver
```

- [ ] **Step 2: Write `tb/apb_master_monitor.sv`**

```systemverilog
// APB Master UVM Monitor
// Samples APB bus and sends observed transactions to analysis port

class apb_master_monitor extends uvm_monitor;

    `uvm_component_utils(apb_master_monitor)

    virtual apb_if vif;
    uvm_analysis_port #(apb_pkg::apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    task run_phase(uvm_phase phase);
        apb_pkg::apb_transaction txn;

        forever begin
            @(vif.mon_cb);

            // Detect completed transfer: PSEL + PENABLE + PREADY
            if (vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
                txn = apb_pkg::apb_transaction::type_id::create("txn");
                txn.addr = vif.mon_cb.paddr;
                txn.rw   = vif.mon_cb.pwrite;
                if (vif.mon_cb.pwrite)
                    txn.data = vif.mon_cb.pwdata;
                else
                    txn.data = vif.mon_cb.prdata;
                ap.write(txn);
            end
        end
    endtask

endclass : apb_master_monitor
```

- [ ] **Step 3: Write `tb/apb_master_agent.sv`**

```systemverilog
// APB Master UVM Agent — Sequencer + Driver + Monitor for one master

class apb_master_agent extends uvm_agent;

    `uvm_component_utils(apb_master_agent)

    apb_master_driver                                 driver;
    apb_master_monitor                                monitor;
    uvm_sequencer #(apb_pkg::apb_transaction)         sequencer;

    virtual apb_if vif;
    int master_id = 0;

    uvm_analysis_port #(apb_pkg::apb_transaction) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        monitor = apb_master_monitor::type_id::create("monitor", this);
        monitor.vif = vif;
        ap = monitor.ap;

        if (get_is_active() == UVM_ACTIVE) begin
            driver = apb_master_driver::type_id::create("driver", this);
            sequencer = uvm_sequencer #(apb_pkg::apb_transaction)::type_id::create("sequencer", this);
            driver.vif = vif;
            driver.master_id = master_id;
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        if (get_is_active() == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass : apb_master_agent
```

---

### Task 8: UVM — Scoreboard and Environment

**Files:**
- Create: `tb/apb_scoreboard.sv`, `tb/apb_env.sv`

**Interfaces:**
- `apb_scoreboard`: `uvm_subscriber #(apb_transaction)` — reference model mirroring memory + GPIO
- `apb_env`: Instantiates 2 agents + scoreboard, connects analysis ports → scoreboard

- [ ] **Step 1: Write `tb/apb_scoreboard.sv`**

```systemverilog
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
```

- [ ] **Step 2: Write `tb/apb_env.sv`**

```systemverilog
// APB UVM Environment — 2 master agents + scoreboard

class apb_env extends uvm_env;

    `uvm_component_utils(apb_env)

    apb_master_agent  agent_m0;
    apb_master_agent  agent_m1;
    apb_scoreboard    scb;

    virtual apb_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        agent_m0 = apb_master_agent::type_id::create("agent_m0", this);
        agent_m0.vif = vif;
        agent_m0.master_id = 0;
        agent_m0.is_active = UVM_ACTIVE;

        agent_m1 = apb_master_agent::type_id::create("agent_m1", this);
        agent_m1.vif = vif;
        agent_m1.master_id = 1;
        agent_m1.is_active = UVM_ACTIVE;

        scb = apb_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        agent_m0.ap.connect(scb.analysis_export);
        agent_m1.ap.connect(scb.analysis_export);
    endfunction

endclass : apb_env
```

---

### Task 9: UVM — Sequences and Tests

**Files:**
- Create: `tb/sequence_lib.sv`, `tb/apb_test.sv`

**Interfaces:**
- Sequences: `apb_base_sequence` with write/read helpers, `apb_sanity_seq`, `apb_random_seq`, `apb_burst_seq`, `apb_slave_err_seq`
- Tests: `apb_base_test`, `apb_sanity_test`, `apb_random_test`, `apb_burst_test`, `apb_error_test`

- [ ] **Step 1: Write `tb/sequence_lib.sv`**

```systemverilog
// APB Sequence Library

// ---------------------------------------------------------------
// Base Sequence — helper tasks
// ---------------------------------------------------------------
class apb_base_sequence extends uvm_sequence #(apb_pkg::apb_transaction);

    `uvm_object_utils(apb_base_sequence)

    function new(string name = "apb_base_sequence");
        super.new(name);
    endfunction

    task write(bit [31:0] addr, bit [31:0] data);
        apb_pkg::apb_transaction txn;
        txn = apb_pkg::apb_transaction::type_id::create("txn");
        start_item(txn);
        txn.addr = addr;
        txn.data = data;
        txn.rw   = 1'b1;
        finish_item(txn);
    endtask

    task read(bit [31:0] addr, output bit [31:0] data);
        apb_pkg::apb_transaction txn;
        txn = apb_pkg::apb_transaction::type_id::create("txn");
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

        // Write + read mem
        write(32'h0000_0000, 32'hDEAD_BEEF);
        read (32'h0000_0000, rd);

        // Write + read GPIO DATA reg
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
        apb_pkg::apb_transaction txn;
        `uvm_info("SEQ", "Random sequence started", UVM_LOW)

        repeat (20) begin
            txn = apb_pkg::apb_transaction::type_id::create("txn");
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
        apb_pkg::apb_transaction txn;
        `uvm_info("SEQ", "Error sequence started (unmapped addr)", UVM_LOW)

        txn = apb_pkg::apb_transaction::type_id::create("txn");
        start_item(txn);
        txn.addr = 32'h0000_2000;
        txn.rw   = 1'b0;
        // Disable address constraint to allow unmapped address
        txn.addr_range_c.constraint_mode(0);
        finish_item(txn);

        `uvm_info("SEQ", "Error sequence done", UVM_LOW)
    endtask

endclass : apb_slave_err_seq
```

- [ ] **Step 2: Write `tb/apb_test.sv`**

```systemverilog
// APB UVM Tests

// ---------------------------------------------------------------
// Base Test
// ---------------------------------------------------------------
class apb_base_test extends uvm_test;

    `uvm_component_utils(apb_base_test)

    apb_env env;
    virtual apb_if vif;

    function new(string name = "apb_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = apb_env::type_id::create("env", this);
        if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
            `uvm_fatal("TEST", "Virtual interface not set")
        env.vif = vif;
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_top.print_topology();
    endfunction

endclass : apb_base_test

// ---------------------------------------------------------------
// Sanity Test
// ---------------------------------------------------------------
class apb_sanity_test extends apb_base_test;

    `uvm_component_utils(apb_sanity_test)

    function new(string name = "apb_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_sanity_seq seq;
        phase.raise_objection(this);
        seq = apb_sanity_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_sanity_test

// ---------------------------------------------------------------
// Random Test
// ---------------------------------------------------------------
class apb_random_test extends apb_base_test;

    `uvm_component_utils(apb_random_test)

    function new(string name = "apb_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_random_seq seq;
        phase.raise_objection(this);
        seq = apb_random_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_random_test

// ---------------------------------------------------------------
// Burst Test
// ---------------------------------------------------------------
class apb_burst_test extends apb_base_test;

    `uvm_component_utils(apb_burst_test)

    function new(string name = "apb_burst_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_burst_seq seq;
        phase.raise_objection(this);
        seq = apb_burst_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_burst_test

// ---------------------------------------------------------------
// Error Test
// ---------------------------------------------------------------
class apb_error_test extends apb_base_test;

    `uvm_component_utils(apb_error_test)

    function new(string name = "apb_error_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        apb_slave_err_seq seq;
        phase.raise_objection(this);
        seq = apb_slave_err_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask

endclass : apb_error_test
```

---

### Task 10: UVM — Testbench Top

**Files:**
- Create: `tb/tb_top.sv`

**Interfaces:**
- Consumes: `apb_top` DUT, all UVM components
- Produces: Self-contained testbench with clock, reset, interface binding, FSDB dump, run_test()

- [ ] **Step 1: Write `tb/tb_top.sv`**

```systemverilog
// APB UVM Testbench Top
`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import apb_pkg::*;

module tb_top;

    reg pclk;
    reg presetn;

    // APB interface
    apb_if #(.NUM_MASTERS(2)) apb_if_inst (
        .pclk   (pclk),
        .presetn(presetn)
    );

    // DUT wires
    wire        req_0, gnt_0, req_1, gnt_1;
    wire [31:0] paddr, pwdata, prdata;
    wire        pwrite, psel, penable, pready;
    wire [1:0]  psel_slv;
    wire        gpio_int;

    // DUT instantiation
    apb_top u_dut (
        .pclk        (pclk),
        .presetn     (presetn),

        .txn_req_0   (apb_if_inst.txn_req[0]),
        .txn_addr_0  (apb_if_inst.txn_addr[0]),
        .txn_wdata_0 (apb_if_inst.txn_wdata[0]),
        .txn_write_0 (apb_if_inst.txn_write[0]),

        .txn_req_1   (apb_if_inst.txn_req[1]),
        .txn_addr_1  (apb_if_inst.txn_addr[1]),
        .txn_wdata_1 (apb_if_inst.txn_wdata[1]),
        .txn_write_1 (apb_if_inst.txn_write[1]),

        .req_0       (req_0),
        .gnt_0       (gnt_0),
        .req_1       (req_1),
        .gnt_1       (gnt_1),

        .paddr       (paddr),
        .pwdata      (pwdata),
        .prdata      (prdata),
        .pwrite      (pwrite),
        .psel        (psel),
        .penable     (penable),
        .pready      (pready),

        .psel_slv    (psel_slv),
        .gpio_int    (gpio_int)
    );

    // Connect DUT APB bus to interface
    assign apb_if_inst.paddr   = paddr;
    assign apb_if_inst.pwdata  = pwdata;
    assign apb_if_inst.prdata  = prdata;
    assign apb_if_inst.pwrite  = pwrite;
    assign apb_if_inst.psel    = psel;
    assign apb_if_inst.penable = penable;
    assign apb_if_inst.pready  = pready;

    // Connect req/gnt to interface
    assign apb_if_inst.req = {req_1, req_0};
    assign gnt_0 = apb_if_inst.gnt[0];
    assign gnt_1 = apb_if_inst.gnt[1];

    // Clock — 100MHz
    initial pclk = 0;
    always #5 pclk = ~pclk;

    // Reset
    initial begin
        presetn = 1'b0;
        #50 presetn = 1'b1;
    end

    // FSDB dump
    initial begin
        $fsdbDumpfile("waves/apb.fsdb");
        $fsdbDumpvars(0, tb_top);
        $fsdbDumpFlush;
    end

    // Set vif in config DB
    initial begin
        uvm_config_db #(virtual apb_if)::set(null, "*", "vif", apb_if_inst);
        run_test();
    end

    // Timeout
    initial begin
        #1000000;
        `uvm_fatal("TIMEOUT", "Simulation timed out after 1ms")
    end

endmodule
```

---

### Task 11: Build Scripts — File List, Compile, Run, Verdi, Makefile

**Files:**
- Create: `scripts/filelist.f`, `scripts/compile.sh`, `scripts/run.sh`, `scripts/verdi.sh`, `Makefile`

- [ ] **Step 1: Write `scripts/filelist.f`**

```
// RTL files (pure Verilog)
rtl/apb_master.v
rtl/apb_arbiter.v
rtl/apb_decoder.v
rtl/apb_slave_mem.v
rtl/apb_slave_gpio.v
rtl/apb_top.v

// UVM testbench files (SystemVerilog)
tb/apb_if.sv
tb/apb_pkg.sv
tb/apb_master_driver.sv
tb/apb_master_monitor.sv
tb/apb_master_agent.sv
tb/apb_scoreboard.sv
tb/apb_env.sv
tb/sequence_lib.sv
tb/apb_test.sv
tb/tb_top.sv
```

- [ ] **Step 2: Write `scripts/compile.sh`**

```bash
#!/bin/bash
# VCS Compile Script for APB Bus Framework
# Compiles all RTL + UVM files, generates simv with FSDB/Verde support

set -e

# Configuration — adjust these to your environment
VCS_HOME=${VCS_HOME:-/opt/synopsys/vcs}
VERDI_HOME=${VERDI_HOME:-/opt/synopsys/verdi}
PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))

cd $PROJ_ROOT

mkdir -p waves

echo "========================================="
echo " VCS Compilation for APB Bus Framework"
echo "========================================="

# --- Step 1: Analyze (vlogan) ---
echo "[1/3] Analyzing Verilog/SystemVerilog files..."

vlogan \
    -full64 \
    -sverilog \
    -ntb_opts uvm-1.2 \
    +v2k \
    -f scripts/filelist.f

# --- Step 2: Elaborate (vcs) ---
echo "[2/3] Elaborating design..."

vcs \
    -full64 \
    -sverilog \
    -ntb_opts uvm-1.2 \
    -debug_access+all \
    -kdb \
    -lca \
    -fsdb \
    -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
    $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a \
    +vcs+lic+wait \
    -timescale=1ns/1ps \
    -o simv \
    -l compile.log \
    apb_top \
    tb_top

# --- Step 3: Check result ---
echo "[3/3] Build complete."
echo ""
echo "simv generated successfully."
echo ""
echo "  Run simulation:  ./scripts/run.sh"
echo "  View waveforms:  ./scripts/verdi.sh"
```

- [ ] **Step 3: Write `scripts/run.sh`**

```bash
#!/bin/bash
# Run APB Simulation
# Usage: ./scripts/run.sh [TEST_NAME]
# Default test: apb_sanity_test

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

TEST=${1:-apb_sanity_test}

echo "========================================="
echo " Running Test: $TEST"
echo "========================================="

./simv \
    +UVM_TESTNAME=$TEST \
    +fsdb+autoflush \
    -l sim.log \
    +vcs+lic+wait
```

- [ ] **Step 4: Write `scripts/verdi.sh`**

```bash
#!/bin/bash
# Launch Verdi for Waveform Viewing
# Usage: ./scripts/verdi.sh

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

echo "========================================="
echo " Launching Verdi..."
echo "========================================="

verdi \
    -sv \
    -f scripts/filelist.f \
    -ssf waves/apb.fsdb \
    -nologo \
    &
```

- [ ] **Step 5: Write `Makefile`**

```makefile
# APB Bus Framework Makefile

TEST ?= apb_sanity_test

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
	rm -rf waves/*.fsdb
	rm -rf verdiLog novas.*
	rm -rf AN.DB csrc vc_hdrs.h uvm_dpi.so*
	rm -rf DVEfiles inter.vpd
```

- [ ] **Step 6: Make scripts executable**

```bash
chmod +x /home/openclaw/project/bus/scripts/{compile.sh,run.sh,verdi.sh}
```

---

### Task 12: Verify Compilation

**Files:**
- Verify: All files exist and can be compiled (requires VCS/Verdi availability)

- [ ] **Step 1: Verify all files exist**

```bash
cd /home/openclaw/project/bus
echo "=== RTL ===" && ls -la rtl/
echo "=== TB ===" && ls -la tb/
echo "=== Scripts ===" && ls -la scripts/
```

Expected: 6 RTL files, 10 TB files, 3+ scripts + 1 Makefile + 1 filelist

- [ ] **Step 2: If VCS is available, test compilation**

```bash
cd /home/openclaw/project/bus && make compile
```

Expected: `simv` generated and `compile.log` without errors.

- [ ] **Step 3: If VCS is available, run sanity test**

```bash
cd /home/openclaw/project/bus && make run TEST=apb_sanity_test
```

Expected: Simulation passes, `waves/apb.fsdb` generated.
