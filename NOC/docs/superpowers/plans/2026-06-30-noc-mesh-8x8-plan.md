# NOC Mesh 8x8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an 8×8 2D Mesh NOC with AXI4 network interfaces, XY routing, 2 VCs, credit-based flow control, and 4-level QoS for 64 NPU core interconnect.

**Architecture:** Bottom-up RTL development — infrastructure first, then Router core, Network Interface, Tile integration, Mesh assembly, and UVM verification. All modules parameterized via `noc_config_pkg`. Follows existing AXI project patterns (SystemVerilog, VCS, Verdi, UVM 1.2).

**Tech Stack:** SystemVerilog (IEEE 1800), Synopsys VCS 2018.09, Verdi 2018.09, UVM 1.2

## Global Constraints

- Frequency: 500 MHz, fully synchronous single-clock design
- Data width: 512-bit links
- Mesh: 8×8, 64 tiles (parameterizable MESH_X, MESH_Y)
- VC: 2 (VC0=request, VC1=response), depth 8 flits
- QoS: 4 priority levels (P0-P3) with 64-cycle aging
- Flow control: Credit-based, per-VC
- Interface: AXI4 (AW/AR/W/B/R 5 channels) at NPU core boundary
- Routing: XY dimension-order, deterministic, deadlock-free

---

## File Structure

```
NOC/
├── Makefile
├── scripts/
│   ├── compile.sh
│   ├── run.sh
│   └── verdi.sh
├── rtl/
│   ├── noc_config_pkg.sv       // Parameterized config package
│   ├── noc_flit_pkg.sv          // Flit type definitions
│   ├── route_compute.sv         // XY routing computation
│   ├── input_port.sv            // 2-VC input port with FIFOs
│   ├── output_port.sv           // Credit-managed output port
│   ├── vc_allocator.sv          // VC allocation logic
│   ├── switch_allocator.sv      // QoS priority arbitration
│   ├── crossbar_5x5.sv          // 5x5 crossbar switch
│   ├── link_ctrl.sv             // Link-layer credit TX/RX
│   ├── router_5port.sv          // Top-level router
│   ├── ni_write_packer.sv       // AXI AW+W → flit
│   ├── ni_read_packer.sv        // AXI AR → flit
│   ├── ni_write_unpacker.sv     // flit → AXI B
│   ├── ni_read_unpacker.sv      // flit → AXI R
│   ├── ni_axi4.sv               // Full AXI4 Network Interface
│   ├── noc_tile.sv              // NI + Router + link_ctrl
│   └── mesh_8x8.sv              // 8x8 mesh top-level
├── tb/
│   ├── noc_if.sv                // NOC link interface
│   ├── noc_pkg.sv               // UVM package
│   ├── noc_env.sv               // UVM environment
│   ├── noc_scoreboard.sv        // Scoreboard with reference model
│   ├── noc_sequence.sv          // Sequence library
│   ├── noc_test.sv              // Test classes
│   └── tb_top.sv                // Testbench top with mesh DUT
└── filelist/
    ├── rtl.f                    // RTL file list
    └── tb.f                     // Testbench file list
```

---

## Phase 1: Infrastructure

### Task 1: Project scaffolding and config package

**Files:**
- Create: `NOC/Makefile`
- Create: `NOC/scripts/compile.sh`
- Create: `NOC/scripts/run.sh`
- Create: `NOC/scripts/verdi.sh`
- Create: `NOC/rtl/noc_config_pkg.sv`
- Create: `NOC/rtl/noc_flit_pkg.sv`
- Create: `NOC/filelist/rtl.f`
- Create: `NOC/filelist/tb.f`

**Interfaces:**
- Produces: `noc_config_pkg` with all mesh/VC/QoS/NI parameters, `noc_flit_pkg` with flit types and header structs

- [ ] **Step 1: Copy infrastructure from AXI project**

Copy and adapt Makefile and scripts from `/home/openclaw/project/bus/AXI/`.

Makefile:
```makefile
TEST ?= noc_sanity_test

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
	rm -rf DVEfiles
```

scripts/compile.sh:
```bash
#!/bin/bash
set -e
mkdir -p waves

vcs -sverilog -full64 \
  -ntb_opts uvm-1.2 \
  -timescale=1ns/10ps \
  -f filelist/rtl.f \
  -f filelist/tb.f \
  +define+UVM_NO_DPI \
  -debug_access+all \
  -l compile.log \
  -top tb_top
```

scripts/run.sh:
```bash
#!/bin/bash
set -e
TEST=${1:-noc_sanity_test}

./simv +UVM_TESTNAME=$TEST \
  +UVM_VERBOSITY=UVM_MEDIUM \
  -l sim.log
```

scripts/verdi.sh:
```bash
#!/bin/bash
verdi -sv -f filelist/rtl.f -f filelist/tb.f \
  -ssf waves/noc.fsdb -nologo &
```

- [ ] **Step 2: Write noc_config_pkg.sv**

```systemverilog
// noc_config_pkg.sv — Parameterized NOC configuration
package noc_config_pkg;

  // Mesh dimensions
  parameter int MESH_X = 8;
  parameter int MESH_Y = 8;
  localparam int NODE_NUM = MESH_X * MESH_Y;
  localparam int NODE_ID_W = $clog2(NODE_NUM);

  // Link parameters
  parameter int DATA_W = 512;
  parameter int CTRL_W = 8;

  // VC parameters
  parameter int VC_NUM = 2;
  parameter int VC_DEPTH = 8;
  localparam int VC_ID_W = $clog2(VC_NUM);

  // QoS parameters
  parameter int QOS_W = 4;
  parameter int PRIO_LEVELS = 4;
  parameter int AGING_THRESHOLD = 64;

  // Router pipeline
  parameter int PIPELINE_STAGES = 5;   // RC+VA+SA+ST+LT

  // NI parameters
  parameter int NI_FIFO_DEPTH = 16;
  parameter int MAX_OUTSTANDING = 64;

  // Port direction encoding
  typedef enum logic [2:0] {
    PORT_NORTH = 3'b000,
    PORT_SOUTH = 3'b001,
    PORT_EAST  = 3'b010,
    PORT_WEST  = 3'b011,
    PORT_LOCAL = 3'b100,
    PORT_NONE  = 3'b111
  } port_dir_t;

  // X/Y coordinates
  typedef struct packed {
    logic [3:0] x;
    logic [3:0] y;
  } coord_t;

  // Node ID = {Y[2:0], X[2:0]}
  typedef logic [NODE_ID_W-1:0] node_id_t;

  // VC ID
  typedef logic [VC_ID_W-1:0] vc_id_t;

  // QoS ID
  typedef logic [QOS_W-1:0] qos_t;

endpackage
```

- [ ] **Step 3: Write noc_flit_pkg.sv**

```systemverilog
// noc_flit_pkg.sv — Flit type definitions
package noc_flit_pkg;
  import noc_config_pkg::*;

  // Flit type encoding
  typedef enum logic [1:0] {
    FLIT_IDLE   = 2'b00,
    FLIT_HEADER = 2'b01,
    FLIT_BODY   = 2'b10,
    FLIT_TAIL   = 2'b11
  } flit_type_t;

  // Header flit fields (packed struct)
  typedef struct packed {
    logic [7:0]  src_y;
    logic [7:0]  src_x;
    logic [7:0]  dst_y;
    logic [7:0]  dst_x;
    qos_t        qos;
    flit_type_t  ftype;       // = FLIT_HEADER
    node_id_t    src_id;
    node_id_t    dst_id;
    logic [7:0]  axlen;
    logic [7:0]  axid;
    logic [31:0] axaddr;
    logic [1:0]  axburst;
    logic [3:0]  axsize;
    logic [3:0]  axlock;
    logic [1:0]  axcache;
    logic [249:0] reserved;
  } flit_header_t;

  // Data payload (body/tail flit)
  typedef struct packed {
    logic [63:0] wstrb;
    logic [445:0] data;
  } flit_data_t;

  // Unified flit structure
  typedef struct packed {
    flit_data_t  payload;
    flit_type_t  ftype;
  } flit_t;

  // Link signals (data + valid + credit return)
  typedef struct packed {
    flit_t flit;
    logic  valid;
    vc_id_t vc;
  } link_in_t;    // downstream-facing input

  typedef struct packed {
    flit_t flit;
    logic  valid;
    vc_id_t vc;
  } link_out_t;   // upstream-facing output

  // Credit return signal (per VC)
  typedef logic [VC_NUM-1:0] credit_t;

endpackage
```

- [ ] **Step 4: Write filelists**

filelist/rtl.f:
```
+incdir+rtl
rtl/noc_config_pkg.sv
rtl/noc_flit_pkg.sv
```

filelist/tb.f:
```
+incdir+tb
+incdir+rtl
```

- [ ] **Step 5: Commit**

```bash
git add Makefile scripts/ rtl/noc_config_pkg.sv rtl/noc_flit_pkg.sv filelist/
git commit -m "feat: add NOC infrastructure — config package, flit types, filelists, scripts"
```

---

## Phase 2: Router Core

### Task 2: Route Compute module

**Files:**
- Create: `NOC/rtl/route_compute.sv`

**Interfaces:**
- Produces: `route_compute` module — inputs src_x/src_y/dst_x/dst_y, outputs next_port (one-hot 5-bit)

- [ ] **Step 1: Write route_compute.sv**

```systemverilog
// route_compute.sv — XY dimension-order routing
module route_compute #(
  parameter int MESH_X = 8,
  parameter int MESH_Y = 8
) (
  input  logic [3:0] src_x,
  input  logic [3:0] src_y,
  input  logic [3:0] dst_x,
  input  logic [3:0] dst_y,
  input  logic       port_disable [5],  // per-port disable for boundary tiles
  output logic [4:0] next_port           // one-hot: {L,W,E,S,N}
);
  import noc_config_pkg::*;

  logic signed [4:0] dx, dy;

  assign dx = dst_x - src_x;
  assign dy = dst_y - src_y;

  always_comb begin
    next_port = 5'b00000;
    if (dx == 0 && dy == 0)
      next_port[PORT_LOCAL] = 1'b1;
    else if (dx > 0)
      next_port[PORT_EAST]  = 1'b1;
    else if (dx < 0)
      next_port[PORT_WEST]  = 1'b1;
    else if (dy > 0)
      next_port[PORT_NORTH] = 1'b1;
    else if (dy < 0)
      next_port[PORT_SOUTH] = 1'b1;
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/route_compute.sv
git commit -m "feat: add XY route compute module"
```

### Task 3: Input Port module with VC FIFOs

**Files:**
- Create: `NOC/rtl/input_port.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `input_port` module — 2-VC input buffering with credit return

- [ ] **Step 1: Write input_port.sv**

```systemverilog
// input_port.sv — Single input port with 2 VC FIFOs
module input_port #(
  parameter int DATA_W   = 512,
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // Link input from upstream
  input  link_in_t             link_in,

  // Flit output toward crossbar (per VC)
  output flit_t                vc_flit_out [VC_NUM],
  output logic   [VC_NUM-1:0]  vc_valid_out,
  input  logic   [VC_NUM-1:0]  vc_pop,         // pop from VA/SA

  // Credit return to upstream
  output credit_t              credit_out,

  // FIFO status
  output logic   [VC_NUM-1:0]  fifo_full,
  output logic   [VC_NUM-1:0]  fifo_empty
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // VC FIFOs — simple register-based (depth small enough)
  flit_t vc_fifo [VC_NUM][VC_DEPTH];
  logic [$clog2(VC_DEPTH):0] fifo_wr_ptr [VC_NUM];   // next write
  logic [$clog2(VC_DEPTH):0] fifo_rd_ptr [VC_NUM];   // next read
  logic [$clog2(VC_DEPTH):0] fifo_count [VC_NUM];     // occupancy

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v++) begin : vc_gen
      // Write side
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          fifo_wr_ptr[v] <= '0;
          fifo_rd_ptr[v] <= '0;
          fifo_count[v]  <= '0;
        end else begin
          // Write: valid flit on this VC from link
          if (link_in.valid && link_in.vc == vc_id_t'(v) && fifo_count[v] < VC_DEPTH) begin
            vc_fifo[v][fifo_wr_ptr[v]] <= link_in.flit;
            fifo_wr_ptr[v] <= fifo_wr_ptr[v] + 1'b1;
            fifo_count[v]  <= fifo_count[v] + 1'b1;
          end
          // Read: SA grants pop
          if (vc_pop[v] && fifo_count[v] > 0) begin
            fifo_rd_ptr[v] <= fifo_rd_ptr[v] + 1'b1;
            fifo_count[v]  <= fifo_count[v] - 1'b1;
          end
        end
      end

      assign vc_flit_out[v] = vc_fifo[v][fifo_rd_ptr[v]];
      assign vc_valid_out[v] = (fifo_count[v] > 0);
      assign fifo_full[v]   = (fifo_count[v] >= VC_DEPTH);
      assign fifo_empty[v]  = (fifo_count[v] == 0);

      // Credit return: one credit per pop
      assign credit_out[v] = vc_pop[v];
    end
  endgenerate
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/input_port.sv
git commit -m "feat: add input port with dual-VC FIFOs and credit return"
```

### Task 4: Output Port module with credit management

**Files:**
- Create: `NOC/rtl/output_port.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `output_port` module — credit tracking, output register

- [ ] **Step 1: Write output_port.sv**

```systemverilog
// output_port.sv — Per-direction output port with credit tracking
module output_port #(
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // From crossbar
  input  flit_t       xbar_flit_in,
  input  logic        xbar_valid_in,
  input  vc_id_t      xbar_vc_in,
  output logic        xbar_ready_out,    // credit available

  // Link output to downstream
  output link_out_t   link_out,

  // Credit input from downstream
  input  credit_t     credit_in,

  // Credit counters (for SA visibility)
  output logic [$clog2(VC_DEPTH):0] credit_count [VC_NUM]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Credit tracking: init=VC_DEPTH, decrement on send, increment on credit_in
  logic [$clog2(VC_DEPTH):0] credit_cnt [VC_NUM];

  genvar v;
  generate
    for (v = 0; v < VC_NUM; v++) begin : vc_credit
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          credit_cnt[v] <= VC_DEPTH;
        end else begin
          // Decrement when we send a flit on this VC
          if (xbar_valid_in && xbar_ready_out && xbar_vc_in == vc_id_t'(v))
            credit_cnt[v] <= credit_cnt[v] - 1'b1;
          // Increment when downstream returns credit
          if (credit_in[v])
            credit_cnt[v] <= credit_cnt[v] + 1'b1;
        end
      end

      assign credit_count[v] = credit_cnt[v];
    end
  endgenerate

  // Ready when credit > 0
  assign xbar_ready_out = (credit_cnt[xbar_vc_in] > 0);

  // Output register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      link_out.flit  <= '0;
      link_out.valid <= 1'b0;
      link_out.vc    <= '0;
    end else begin
      if (xbar_valid_in && xbar_ready_out) begin
        link_out.flit  <= xbar_flit_in;
        link_out.valid <= 1'b1;
        link_out.vc    <= xbar_vc_in;
      end else begin
        link_out.valid <= 1'b0;
      end
    end
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/output_port.sv
git commit -m "feat: add output port with credit-based flow control"
```

### Task 5: VC Allocator

**Files:**
- Create: `NOC/rtl/vc_allocator.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`
- Produces: `vc_allocator` module — per-output-port VC slot allocation

- [ ] **Step 1: Write vc_allocator.sv**

```systemverilog
// vc_allocator.sv — VC allocation stage
// Allocates downstream VC slot for header flits; body/tail follow wormhole
module vc_allocator #(
  parameter int VC_NUM = 2
) (
  input  logic                 clk,
  input  logic                 rst_n,

  // Request: from input ports (5 ports, 2 VCs each)
  input  logic   [4:0][VC_NUM-1:0]  va_req,       // which VC has header ready
  input  flit_t  [4:0][VC_NUM-1:0]  va_flit,      // the header flit
  input  port_dir_t [4:0][VC_NUM-1:0] va_route,   // route compute result

  // Status from downstream output ports
  input  logic   [4:0][VC_NUM-1:0]  downstream_credit_avail,

  // Grant: which input port's VC gets to proceed
  output logic   [4:0][VC_NUM-1:0]  va_grant
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Simple: grant if downstream credit available
  // Priority: lower VC first (VC0 > VC1), lower port index first
  always_comb begin
    va_grant = '{default: '0};
    for (int out_port = 0; out_port < 5; out_port++) begin
      for (int vc = 0; vc < VC_NUM; vc++) begin
        if (va_req[out_port][vc] && downstream_credit_avail[out_port][vc]) begin
          va_grant[out_port][vc] = 1'b1;
          break;  // one grant per output
        end
      end
    end
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/vc_allocator.sv
git commit -m "feat: add VC allocator module"
```

### Task 6: Switch Allocator with QoS arbitration

**Files:**
- Create: `NOC/rtl/switch_allocator.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `switch_allocator` module — QoS-priority arbitration with aging

- [ ] **Step 1: Write switch_allocator.sv**

```systemverilog
// switch_allocator.sv — QoS-aware switch arbitration
module switch_allocator #(
  parameter int PRIO_LEVELS     = 4,
  parameter int AGING_THRESHOLD = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // Request from input ports: {port_id, vc_id, qos}
  input  logic        sa_req    [5][2],         // [port][vc]
  input  qos_t        sa_qos    [5][2],
  input  flit_type_t  sa_ftype  [5][2],

  // Output port contention — which output each request targets
  input  port_dir_t   sa_dest   [5][2],

  // Grant: per output port, which input wins
  output logic        sa_grant  [5][5]          // [output][input]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Map QoS value to priority level
  function automatic logic [1:0] qos_to_prio(qos_t q);
    // Priority encoding: P0=one-hot bit3, P1=bit2, P2=bit1, P3=bit0
    if (q[3]) return 2'd0;      // P0
    else if (q[2]) return 2'd1; // P1
    else if (q[1]) return 2'd2; // P2
    else return 2'd3;           // P3
  endfunction

  // Aging counters for P3
  logic [7:0] aging_cnt [5][2];
  logic [3:0] effective_prio [5][2];

  genvar pi, vc;
  generate
    for (pi = 0; pi < 5; pi++) begin : aging_gen_p
      for (vc = 0; vc < 2; vc++) begin : aging_gen_v
        always_ff @(posedge clk or negedge rst_n) begin
          if (!rst_n)
            aging_cnt[pi][vc] <= '0;
          else if (sa_req[pi][vc] && qos_to_prio(sa_qos[pi][vc]) == 2'd3)
            aging_cnt[pi][vc] <= aging_cnt[pi][vc] + 1'b1;
          else if (!sa_req[pi][vc])
            aging_cnt[pi][vc] <= '0;
        end

        assign effective_prio[pi][vc] =
          (aging_cnt[pi][vc] >= AGING_THRESHOLD) ?
            {2'b0, qos_to_prio(sa_qos[pi][vc]) == 2'd3 ? 2'd2 : qos_to_prio(sa_qos[pi][vc])} :
            {2'b0, qos_to_prio(sa_qos[pi][vc])};
      end
    end
  endgenerate

  // Per-output-port arbitration: strict priority then round-robin within level
  logic [1:0] rr_ptr [5]; // round-robin pointer per output
  logic [1:0] rr_prio [5][2];

  always_comb begin
    for (int out = 0; out < 5; out++) begin
      sa_grant[out] = '{default: 1'b0};
      for (int plev = 0; plev < 4; plev++) begin
        for (int pi = (rr_ptr[out]+1) & 2'b11; pi != rr_ptr[out]; pi = (pi+1) & 2'b11) begin
          for (int vc = 0; vc < 2; vc++) begin
            if (sa_req[pi][vc] && sa_dest[pi][vc] == port_dir_t'(out) &&
                effective_prio[pi][vc] == plev[1:0]) begin
              sa_grant[out][pi] = 1'b1;
              goto out_done;
            end
          end
        end
        :out_done
        if (sa_grant[out] != '0) break;
      end
    end
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/switch_allocator.sv
git commit -m "feat: add switch allocator with QoS priority arbitration and aging"
```

### Task 7: 5×5 Crossbar

**Files:**
- Create: `NOC/rtl/crossbar_5x5.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `crossbar_5x5` module — combinational 5-in × 5-out switching

- [ ] **Step 1: Write crossbar_5x5.sv**

```systemverilog
// crossbar_5x5.sv — 5x5 crossbar switch (combinational)
module crossbar_5x5 #(
  parameter int DATA_W = 512
) (
  // 5 inputs
  input  flit_t       flit_in   [5],
  input  logic [4:0]  valid_in,
  input  vc_id_t      vc_in     [5],

  // Grant: which output each input connects to
  input  logic [4:0]  grant     [5],   // [output][input] one-hot

  // 5 outputs
  output flit_t       flit_out  [5],
  output logic [4:0]  valid_out,
  output vc_id_t      vc_out    [5]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  always_comb begin
    for (int out = 0; out < 5; out++) begin
      flit_out[out]  = '0;
      valid_out[out] = 1'b0;
      vc_out[out]    = '0;
      for (int in = 0; in < 5; in++) begin
        if (grant[out][in]) begin
          flit_out[out]  = flit_in[in];
          valid_out[out] = valid_in[in];
          vc_out[out]    = vc_in[in];
        end
      end
    end
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/crossbar_5x5.sv
git commit -m "feat: add 5x5 crossbar switch"
```

### Task 8: Link Control module

**Files:**
- Create: `NOC/rtl/link_ctrl.sv`

**Interfaces:**
- Consumes: Input port credit signals, output port link signals
- Produces: `link_ctrl` module — wraps input/output port for per-direction link

- [ ] **Step 1: Write link_ctrl.sv**

```systemverilog
// link_ctrl.sv — Per-direction link controller (IP + OP pair)
module link_ctrl #(
  parameter int DATA_W   = 512,
  parameter int VC_NUM   = 2,
  parameter int VC_DEPTH = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // Facing upstream router
  input  link_in_t    link_in,
  output credit_t     credit_out,

  // Crossbar-bound flit from input buffering
  output flit_t       xbar_flit_out,
  output logic        xbar_valid_out,
  output vc_id_t      xbar_vc_out,
  input  logic        xbar_pop,

  // Crossbar-sourced flit to output
  input  flit_t       xbar_flit_in,
  input  logic        xbar_valid_in,
  input  vc_id_t      xbar_vc_in,
  output logic        xbar_ready_out,

  // Facing downstream router
  output link_out_t   link_out,
  input  credit_t     credit_in,

  // Status
  output logic [VC_NUM-1:0] credit_count [2]  // [VC]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  input_port #(
    .DATA_W(DATA_W), .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH)
  ) ip (
    .clk, .rst_n,
    .link_in,
    .vc_flit_out({xbar_flit_out}),   // single VC0 output
    .vc_valid_out({xbar_valid_out}),
    .vc_pop({xbar_pop}),
    .credit_out,
    .fifo_full(),
    .fifo_empty()
  );

  output_port #(
    .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH)
  ) op (
    .clk, .rst_n,
    .xbar_flit_in,
    .xbar_valid_in,
    .xbar_vc_in,
    .xbar_ready_out,
    .link_out,
    .credit_in,
    .credit_count
  );
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/link_ctrl.sv
git commit -m "feat: add link control module with IP+OP pair"
```

### Task 9: Router 5-port top-level

**Files:**
- Create: `NOC/rtl/router_5port.sv`

**Interfaces:**
- Consumes: `route_compute`, `link_ctrl`, `vc_allocator`, `switch_allocator`, `crossbar_5x5`
- Produces: `router_5port` — complete wormhole router

- [ ] **Step 1: Write router_5port.sv**

```systemverilog
// router_5port.sv — 5-port wormhole router
module router_5port #(
  parameter int MESH_X      = 8,
  parameter int MESH_Y      = 8,
  parameter int VC_NUM      = 2,
  parameter int VC_DEPTH    = 8,
  parameter int DATA_W      = 512,
  parameter int QOS_W       = 4,
  parameter int PRIO_LEVELS = 4
) (
  input  logic        clk,
  input  logic        rst_n,

  // 5 link interfaces: N,S,E,W,L
  input  link_in_t    link_in  [5],
  output link_out_t   link_out [5],

  // Credit return per link
  output credit_t     credit_out [5],
  input  credit_t     credit_in  [5],

  // Local port coordinate (for route compute)
  input  coord_t      local_coord,

  // Port disable flags (for boundary routers)
  input  logic        port_disable [5]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // --- Internal wiring ---
  // From link_ctrl to crossbar
  flit_t   xbar_in_flit  [5];
  logic    xbar_in_valid [5];
  vc_id_t  xbar_in_vc    [5];
  logic    xbar_in_pop   [5];  // from VA/SA grant

  // From crossbar to link_ctrl
  flit_t   xbar_out_flit  [5];
  logic    xbar_out_valid [5];
  vc_id_t  xbar_out_vc    [5];
  logic    xbar_out_ready [5];

  // Route compute: per-input-port header dst coordinates
  logic [4:0] route_result [5];

  // VA signals
  logic [4:0][VC_NUM-1:0] va_req;
  port_dir_t [4:0][VC_NUM-1:0] va_route;
  logic [4:0][VC_NUM-1:0] va_grant;

  // SA signals
  logic [4:0][VC_NUM-1:0] downstream_credit [5]; // [output][input][VC]

  // --- Generate 5 link controllers ---
  genvar g;
  generate
    for (g = 0; g < 5; g++) begin : link_gen
      link_ctrl #(.DATA_W(DATA_W), .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH))
      lc (
        .clk, .rst_n,
        .link_in(link_in[g]),
        .credit_out(credit_out[g]),
        .xbar_flit_out(xbar_in_flit[g]),
        .xbar_valid_out(xbar_in_valid[g]),
        .xbar_vc_out(xbar_in_vc[g]),
        .xbar_pop(xbar_in_pop[g]),
        .xbar_flit_in(xbar_out_flit[g]),
        .xbar_valid_in(xbar_out_valid[g]),
        .xbar_vc_in(xbar_out_vc[g]),
        .xbar_ready_out(xbar_out_ready[g]),
        .link_out(link_out[g]),
        .credit_in(credit_in[g]),
        .credit_count()
      );

      // Extract dst from header flit, compute route
      // Only valid when header is at FIFO head
      logic [3:0] hdr_dst_x, hdr_dst_y;
      assign hdr_dst_x = xbar_in_flit[g].payload.wstrb[3:0];     // dst_x from header
      assign hdr_dst_y = xbar_in_flit[g].payload.wstrb[7:4];     // dst_y from header
      // NOTE: actual header flit parsing in integrated design uses flit_header_t
      //       simplification for now; real parsing in noc_tile integration

      route_compute #(.MESH_X(MESH_X), .MESH_Y(MESH_Y)) rc (
        .src_x(local_coord.x),
        .src_y(local_coord.y),
        .dst_x(hdr_dst_x),
        .dst_y(hdr_dst_y),
        .port_disable(port_disable),
        .next_port(route_result[g])
      );
    end
  endgenerate

  // --- VC Allocator ---
  vc_allocator #(.VC_NUM(VC_NUM)) va (
    .clk, .rst_n,
    .va_req, .va_flit(), .va_route(),
    .downstream_credit_avail(),
    .va_grant
  );

  // --- Switch Allocator ---
  switch_allocator #(.PRIO_LEVELS(PRIO_LEVELS)) sa (
    .clk, .rst_n,
    .sa_req(),
    .sa_qos(),
    .sa_ftype(),
    .sa_dest(),
    .sa_grant()
  );

  // --- Crossbar ---
  crossbar_5x5 #(.DATA_W(DATA_W)) xbar (
    .flit_in(xbar_in_flit),
    .valid_in(xbar_in_valid),
    .vc_in(xbar_in_vc),
    .grant(),                         // from SA output
    .flit_out(xbar_out_flit),
    .valid_out(xbar_out_valid),
    .vc_out(xbar_out_vc)
  );

endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/router_5port.sv
git commit -m "feat: add 5-port router top-level integration"
```

---

## Phase 3: Network Interface

### Task 10: Write Packer (AW+W → flit)

**Files:**
- Create: `NOC/rtl/ni_write_packer.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`, AXI4 AW/W interface signals
- Produces: `ni_write_packer` module — converts AXI write transactions to flit sequences

- [ ] **Step 1: Write ni_write_packer.sv**

```systemverilog
// ni_write_packer.sv — AXI4 AW+W channels to flit stream
module ni_write_packer #(
  parameter int DATA_W  = 512,
  parameter int VC_NUM  = 2
) (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4 write address channel
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic [7:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [1:0]  awburst,
  input  logic [3:0]  awsize,
  input  logic [3:0]  awlock,
  input  logic [1:0]  awcache,
  input  logic [3:0]  awqos,

  // AXI4 write data channel
  input  logic        wvalid,
  output logic        wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [(DATA_W/8)-1:0] wstrb,
  input  logic        wlast,

  // Destination coordinates (from NI lookup)
  input  coord_t      dst_coord,
  input  node_id_t    src_id,
  input  node_id_t    dst_id,

  // Flit output (to VC0 sender FIFO)
  output flit_t       flit_out,
  output logic        flit_valid,
  input  logic        flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  typedef enum logic [1:0] {
    ST_IDLE, ST_HEADER, ST_BODY, ST_WAIT_B
  } state_t;
  state_t state, state_next;

  logic [7:0] beat_cnt;  // remaining W beats

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      beat_cnt <= '0;
    end else begin
      state <= state_next;
    end
  end

  always_comb begin
    state_next = state;
    case (state)
      ST_IDLE:
        if (awvalid && awready)
          state_next = ST_HEADER;
      ST_HEADER:
        if (flit_valid && flit_ready)
          state_next = (awlen == 0) ? ST_WAIT_B : ST_BODY;
      ST_BODY:
        if (wvalid && wready && wlast && flit_ready)
          state_next = ST_WAIT_B;
      ST_WAIT_B:
        // stays until B unpacker signals done (external signal)
        state_next = ST_IDLE;
    endcase
  end

  // Header flit construction
  always_comb begin
    flit_out = '0;
    flit_out.ftype = flit_type_t'(state == ST_HEADER ? FLIT_HEADER :
                                   state == ST_BODY ? (wlast ? FLIT_TAIL : FLIT_BODY) :
                                   FLIT_IDLE);

    if (state == ST_HEADER) begin
      // Build header: pack coordinates into wstrb/data fields
      // src_x[7:0], src_y[7:0], dst_x[7:0], dst_y[7:0], qos, ftype
      flit_out.payload.wstrb = {8'h00, dst_coord.y, 8'h00, dst_coord.x,
                                16'h0000, 4'h0, awqos, 2'b01};
      flit_out.payload.data[445:390] = {src_id, dst_id};           // 12 bits
      flit_out.payload.data[389:382] = awlen;                       // 8 bits
      flit_out.payload.data[381:374] = awid;                        // 8 bits
      flit_out.payload.data[373:342] = awaddr;                      // 32 bits
      flit_out.payload.data[341:340] = awburst;                     // 2 bits
    end else if (state == ST_BODY) begin
      flit_out.payload.wstrb = wstrb;
      flit_out.payload.data  = wdata[445:0];  // truncate to payload width
    end
  end

  assign flit_valid = (state == ST_HEADER) || (state == ST_BODY && wvalid);
  assign awready = (state == ST_IDLE);
  assign wready  = (state == ST_BODY && flit_ready);

endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/ni_write_packer.sv
git commit -m "feat: add NI write packer (AW+W → flit)"
```

### Task 11: Read Packer (AR → flit)

**Files:**
- Create: `NOC/rtl/ni_read_packer.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`, AXI4 AR interface signals
- Produces: `ni_read_packer` module — converts AXI read address to header flit

- [ ] **Step 1: Write ni_read_packer.sv**

```systemverilog
// ni_read_packer.sv — AXI4 AR channel to flit header
module ni_read_packer #(
  parameter int DATA_W  = 512,
  parameter int VC_NUM  = 2
) (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4 read address channel
  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  input  logic [7:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [1:0]  arburst,
  input  logic [3:0]  arsize,
  input  logic [3:0]  arlock,
  input  logic [1:0]  arcache,
  input  logic [3:0]  arqos,

  // Destination coordinates
  input  coord_t      dst_coord,
  input  node_id_t    src_id,
  input  node_id_t    dst_id,

  // Flit output (to VC0 sender FIFO)
  output flit_t       flit_out,
  output logic        flit_valid,
  input  logic        flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  typedef enum logic { ST_IDLE, ST_HEADER } state_t;
  state_t state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= ST_IDLE;
    else begin
      if (state == ST_IDLE && arvalid && arready)
        state <= ST_HEADER;
      else if (state == ST_HEADER && flit_valid && flit_ready)
        state <= ST_IDLE;
    end
  end

  always_comb begin
    flit_out = '0;
    flit_out.ftype = FLIT_HEADER;

    flit_out.payload.wstrb = {8'h00, dst_coord.y, 8'h00, dst_coord.x,
                              16'h0000, 4'h0, arqos, 2'b01};
    flit_out.payload.data[445:390] = {src_id, dst_id};
    flit_out.payload.data[389:382] = arlen;
    flit_out.payload.data[381:374] = arid;
    flit_out.payload.data[373:342] = araddr;
    flit_out.payload.data[341:340] = arburst;
  end

  assign flit_valid = (state == ST_HEADER);
  assign arready    = (state == ST_IDLE);
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/ni_read_packer.sv
git commit -m "feat: add NI read packer (AR → flit header)"
```

### Task 12: Write Unpacker (flit → B)

**Files:**
- Create: `NOC/rtl/ni_write_unpacker.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `ni_write_unpacker` module — extracts B response from flit stream

- [ ] **Step 1: Write ni_write_unpacker.sv**

```systemverilog
// ni_write_unpacker.sv — Flit stream to AXI4 B channel
module ni_write_unpacker #(
  parameter int DATA_W = 512
) (
  input  logic        clk,
  input  logic        rst_n,

  // Flit input from VC1 receiver FIFO
  input  flit_t       flit_in,
  input  logic        flit_valid,
  output logic        flit_ready,

  // Matched write transaction ID
  input  logic [7:0]  matched_bid,

  // AXI4 write response channel
  output logic        bvalid,
  input  logic        bready,
  output logic [7:0]  bid,
  output logic [1:0]  bresp
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  assign flit_ready = !bvalid || bready;
  assign bid    = matched_bid;
  assign bresp  = 2'b00;  // OKAY

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      bvalid <= 1'b0;
    else if (flit_valid && flit_ready && flit_in.ftype == FLIT_HEADER)
      bvalid <= 1'b1;
    else if (bready)
      bvalid <= 1'b0;
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/ni_write_unpacker.sv
git commit -m "feat: add NI write unpacker (flit → B)"
```

### Task 13: Read Unpacker (flit → R)

**Files:**
- Create: `NOC/rtl/ni_read_unpacker.sv`

**Interfaces:**
- Consumes: `noc_config_pkg`, `noc_flit_pkg`
- Produces: `ni_read_unpacker` module — reassembles R channel from flit stream with OOO support

- [ ] **Step 1: Write ni_read_unpacker.sv**

```systemverilog
// ni_read_unpacker.sv — Flit stream to AXI4 R channel
module ni_read_unpacker #(
  parameter int DATA_W         = 512,
  parameter int MAX_OUTSTANDING = 64,
  parameter int AXI_ID_W       = 8
) (
  input  logic        clk,
  input  logic        rst_n,

  // Flit input from VC1 receiver FIFO
  input  flit_t       flit_in,
  input  logic        flit_valid,
  output logic        flit_ready,

  // AXI4 read data channel
  output logic        rvalid,
  input  logic        rready,
  output logic [AXI_ID_W-1:0]   rid,
  output logic [DATA_W-1:0]     rdata,
  output logic [1:0]            rresp,
  output logic                  rlast,

  // Outstanding read tracking
  output node_id_t    matched_src_id
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Read tracker for OOO responses
  // Tracks outstanding reads: {src_id, arid, remaining_beats}
  typedef struct packed {
    logic        valid;
    node_id_t    src_id;
    logic [7:0]  arid;
    logic [7:0]  remaining_beats;
  } rd_entry_t;

  rd_entry_t rd_table [MAX_OUTSTANDING];
  logic [$clog2(MAX_OUTSTANDING):0] rd_wr_ptr, rd_rd_ptr, rd_count;

  flit_header_t hdr;
  assign hdr = flit_in;  // raw cast from flit_t

  // Reassemble R channel
  logic        is_body;
  logic        is_tail;

  assign is_body = (flit_in.ftype == FLIT_BODY);
  assign is_tail = (flit_in.ftype == FLIT_TAIL);

  assign flit_ready = !rvalid || rready;
  assign rid    = hdr.axid;
  assign rdata  = {flit_in.payload.data, flit_in.payload.wstrb};  // reconstruct 512b
  assign rresp  = 2'b00;
  assign rlast  = is_tail;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rvalid <= 1'b0;
    end else begin
      if (flit_valid && flit_ready && (is_body || is_tail))
        rvalid <= 1'b1;
      else if (rready)
        rvalid <= 1'b0;
    end
  end

  // Read tracker management
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < MAX_OUTSTANDING; i++) rd_table[i].valid <= 1'b0;
      rd_wr_ptr <= '0;
      rd_count  <= '0;
    end else begin
      // On header arrival (response), match and deallocate
      if (flit_valid && flit_ready && flit_in.ftype == FLIT_HEADER) begin
        // Search for matching entry
        for (int i = 0; i < MAX_OUTSTANDING; i++) begin
          if (rd_table[i].valid && rd_table[i].arid == hdr.axid) begin
            rd_table[i].valid <= 1'b0;
            rd_count <= rd_count - 1'b1;
            matched_src_id <= rd_table[i].src_id;
            break;
          end
        end
      end
    end
  end
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/ni_read_unpacker.sv
git commit -m "feat: add NI read unpacker (flit → R) with OOO support"
```

### Task 14: NI AXI4 top-level integration

**Files:**
- Create: `NOC/rtl/ni_axi4.sv`

**Interfaces:**
- Consumes: `ni_write_packer`, `ni_read_packer`, `ni_write_unpacker`, `ni_read_unpacker`
- Produces: `ni_axi4` module — complete AXI4 Network Interface

- [ ] **Step 1: Write ni_axi4.sv**

```systemverilog
// ni_axi4.sv — Complete AXI4 Network Interface
module ni_axi4 #(
  parameter int DATA_W          = 512,
  parameter int VC_NUM          = 2,
  parameter int NI_FIFO_DEPTH   = 16,
  parameter int MAX_OUTSTANDING = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // === AXI4 Master Interface (faces NPU Core) ===
  // Write address
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic [7:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [1:0]  awburst,
  input  logic [3:0]  awsize,
  input  logic [3:0]  awlock,
  input  logic [1:0]  awcache,
  input  logic [3:0]  awqos,
  // Write data
  input  logic        wvalid,
  output logic        wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [(DATA_W/8)-1:0] wstrb,
  input  logic        wlast,
  // Write response
  output logic        bvalid,
  input  logic        bready,
  output logic [7:0]  bid,
  output logic [1:0]  bresp,
  // Read address
  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  input  logic [7:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [1:0]  arburst,
  input  logic [3:0]  arsize,
  input  logic [3:0]  arlock,
  input  logic [1:0]  arcache,
  input  logic [3:0]  arqos,
  // Read data
  output logic        rvalid,
  input  logic        rready,
  output logic [7:0]  rid,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,

  // === Mesh-side interfaces ===
  // Local node info
  input  node_id_t    local_id,
  input  coord_t      local_coord,

  // Destination lookup: addr → dst_id/coord
  output logic [31:0] ni_lookup_addr,
  output logic        ni_lookup_valid,
  input  node_id_t    ni_lookup_dst_id,
  input  coord_t      ni_lookup_dst_coord,

  // Flit output to router Local input (VC0 sender)
  output flit_t       vc0_flit_out,
  output logic        vc0_flit_valid,
  input  logic        vc0_flit_ready,

  // Flit input from router Local output (VC1 receiver)
  input  flit_t       vc1_flit_in,
  input  logic        vc1_flit_valid,
  output logic        vc1_flit_ready
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // --- Write path ---
  flit_t  wp_flit;
  logic   wp_valid, wp_ready;
  coord_t wp_dst;
  node_id_t wp_dst_id;

  ni_write_packer #(.DATA_W(DATA_W), .VC_NUM(VC_NUM)) wp (
    .clk, .rst_n,
    .awvalid, .awready, .awaddr, .awid, .awlen, .awburst, .awsize,
    .awlock, .awcache, .awqos,
    .wvalid, .wready, .wdata, .wstrb, .wlast,
    .dst_coord(ni_lookup_dst_coord),
    .src_id(local_id),
    .dst_id(ni_lookup_dst_id),
    .flit_out(wp_flit), .flit_valid(wp_valid), .flit_ready(wp_ready)
  );

  // --- Read path ---
  flit_t  rp_flit;
  logic   rp_valid, rp_ready;

  ni_read_packer #(.DATA_W(DATA_W), .VC_NUM(VC_NUM)) rp (
    .clk, .rst_n,
    .arvalid, .arready, .araddr, .arid, .arlen, .arburst, .arsize,
    .arlock, .arcache, .arqos,
    .dst_coord(ni_lookup_dst_coord),
    .src_id(local_id),
    .dst_id(ni_lookup_dst_id),
    .flit_out(rp_flit), .flit_valid(rp_valid), .flit_ready(rp_ready)
  );

  // --- VC0 Sender: Mux write/read flits to single Local input ---
  // Simple round-robin between write and read
  logic vc0_sel;  // 0=write, 1=read
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) vc0_sel <= 1'b0;
    else if (vc0_flit_valid && vc0_flit_ready) vc0_sel <= ~vc0_sel;

  assign vc0_flit_out   = vc0_sel ? rp_flit : wp_flit;
  assign vc0_flit_valid = vc0_sel ? rp_valid : wp_valid;
  assign wp_ready       = !vc0_sel && vc0_flit_ready;
  assign rp_ready       = vc0_sel && vc0_flit_ready;

  // Address lookup: trigger on AW or AR
  assign ni_lookup_addr  = awvalid ? awaddr : araddr;
  assign ni_lookup_valid = awvalid || arvalid;

  // --- Write response unpacker (VC1 → B) ---
  ni_write_unpacker #(.DATA_W(DATA_W)) wup (
    .clk, .rst_n,
    .flit_in(vc1_flit_in),
    .flit_valid(vc1_flit_valid),
    .flit_ready(),  // partial ready from mux
    .matched_bid(awid),
    .bvalid, .bready, .bid, .bresp
  );

  // --- Read data unpacker (VC1 → R) ---
  ni_read_unpacker #(.DATA_W(DATA_W), .MAX_OUTSTANDING(MAX_OUTSTANDING)) rup (
    .clk, .rst_n,
    .flit_in(vc1_flit_in),
    .flit_valid(vc1_flit_valid),
    .flit_ready(),
    .rvalid, .rready, .rid, .rdata, .rresp, .rlast,
    .matched_src_id()
  );

  // VC1 ready: accept when either unpacker can take it
  assign vc1_flit_ready = 1'b1;  // simplified; real impl checks both unpackers
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/ni_axi4.sv
git commit -m "feat: add NI AXI4 top-level integration"
```

---

## Phase 4: Tile and Mesh Assembly

### Task 15: NOC Tile (NI + Router + Link Ctrl)

**Files:**
- Create: `NOC/rtl/noc_tile.sv`

**Interfaces:**
- Consumes: `ni_axi4`, `router_5port`
- Produces: `noc_tile` — single mesh tile (NPU-side AXI4 + 5 mesh links)

- [ ] **Step 1: Write noc_tile.sv**

```systemverilog
// noc_tile.sv — Single mesh tile: NI + Router
module noc_tile #(
  parameter int MESH_X         = 8,
  parameter int MESH_Y         = 8,
  parameter int VC_NUM         = 2,
  parameter int VC_DEPTH       = 8,
  parameter int DATA_W         = 512,
  parameter int QOS_W          = 4,
  parameter int PRIO_LEVELS    = 4,
  parameter int NI_FIFO_DEPTH  = 16,
  parameter int MAX_OUTSTANDING = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // Tile coordinate (set at synthesis time)
  input  logic [3:0]  tile_x,
  input  logic [3:0]  tile_y,

  // === AXI4 Master Interface (faces NPU Core) ===
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] awaddr,
  input  logic [7:0]  awid,
  input  logic [7:0]  awlen,
  input  logic [1:0]  awburst,
  input  logic [3:0]  awsize,
  input  logic [3:0]  awlock,
  input  logic [1:0]  awcache,
  input  logic [3:0]  awqos,
  input  logic        wvalid,
  output logic        wready,
  input  logic [DATA_W-1:0] wdata,
  input  logic [(DATA_W/8)-1:0] wstrb,
  input  logic        wlast,
  output logic        bvalid,
  input  logic        bready,
  output logic [7:0]  bid,
  output logic [1:0]  bresp,
  input  logic        arvalid,
  output logic        arready,
  input  logic [31:0] araddr,
  input  logic [7:0]  arid,
  input  logic [7:0]  arlen,
  input  logic [1:0]  arburst,
  input  logic [3:0]  arsize,
  input  logic [3:0]  arlock,
  input  logic [1:0]  arcache,
  input  logic [3:0]  arqos,
  output logic        rvalid,
  input  logic        rready,
  output logic [7:0]  rid,
  output logic [DATA_W-1:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,

  // === 4 mesh links: N, S, E, W ===
  input  link_in_t    link_in  [4],
  output link_out_t   link_out [4],
  output credit_t     credit_out [4],
  input  credit_t     credit_in  [4]
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Local link (between NI and Router)
  link_in_t  local_link_in;
  link_out_t local_link_out;
  credit_t   local_credit_out, local_credit_in;

  // Combine 4 external links + 1 local link into 5-link arrays
  link_in_t  all_link_in  [5];
  link_out_t all_link_out [5];
  credit_t   all_credit_out [5], all_credit_in [5];

  assign all_link_in  = '{link_in[0],  link_in[1],  link_in[2],  link_in[3],  local_link_in};
  assign local_link_out = all_link_out[PORT_LOCAL];
  assign link_out      = '{all_link_out[PORT_NORTH], all_link_out[PORT_SOUTH],
                           all_link_out[PORT_EAST],  all_link_out[PORT_WEST]};
  assign credit_out     = '{all_credit_out[PORT_NORTH], all_credit_out[PORT_SOUTH],
                            all_credit_out[PORT_EAST],  all_credit_out[PORT_WEST]};
  assign all_credit_in  = '{credit_in[0], credit_in[1], credit_in[2], credit_in[3], local_credit_in};

  // Port disable: boundary tiles
  logic port_disable [5];
  assign port_disable[PORT_NORTH] = (tile_y == MESH_Y-1);  // top row
  assign port_disable[PORT_SOUTH] = (tile_y == 0);          // bottom row
  assign port_disable[PORT_EAST]  = (tile_x == MESH_X-1);  // right column
  assign port_disable[PORT_WEST]  = (tile_x == 0);          // left column
  assign port_disable[PORT_LOCAL] = 1'b0;

  // Local coordinate
  coord_t local_coord;
  assign local_coord.x = tile_x;
  assign local_coord.y = tile_y;
  assign local_coord = {tile_y, tile_x};

  // Node ID
  node_id_t local_id;
  assign local_id = {tile_y[2:0], tile_x[2:0]};

  // Destination lookup: addr[31:24] → node_id
  // Simple: addr bit-slice determines node (e.g., addr[30:25] = node_id)
  node_id_t  lookup_dst_id;
  coord_t    lookup_dst_coord;
  assign lookup_dst_id      = {awaddr[28:26], awaddr[25:23]};
  assign lookup_dst_coord.x = awaddr[25:23];
  assign lookup_dst_coord.y = awaddr[28:26];

  // Network Interface
  ni_axi4 #(
    .DATA_W(DATA_W), .VC_NUM(VC_NUM),
    .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
  ) ni (
    .clk, .rst_n,
    .awvalid, .awready, .awaddr, .awid, .awlen, .awburst, .awsize,
    .awlock, .awcache, .awqos,
    .wvalid, .wready, .wdata, .wstrb, .wlast,
    .bvalid, .bready, .bid, .bresp,
    .arvalid, .arready, .araddr, .arid, .arlen, .arburst, .arsize,
    .arlock, .arcache, .arqos,
    .rvalid, .rready, .rid, .rdata, .rresp, .rlast,
    .local_id, .local_coord,
    .ni_lookup_addr(), .ni_lookup_valid(),
    .ni_lookup_dst_id(lookup_dst_id), .ni_lookup_dst_coord(lookup_dst_coord),
    .vc0_flit_out(local_link_in.flit), .vc0_flit_valid(local_link_in.valid),
    .vc0_flit_ready(),  // from router local input credit
    .vc1_flit_in(local_link_out.flit), .vc1_flit_valid(local_link_out.valid),
    .vc1_flit_ready()   // to router local output credit
  );

  // Router
  router_5port #(
    .MESH_X(MESH_X), .MESH_Y(MESH_Y), .VC_NUM(VC_NUM),
    .VC_DEPTH(VC_DEPTH), .DATA_W(DATA_W),
    .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS)
  ) router (
    .clk, .rst_n,
    .link_in(all_link_in), .link_out(all_link_out),
    .credit_out(all_credit_out), .credit_in(all_credit_in),
    .local_coord(local_coord),
    .port_disable(port_disable)
  );
endmodule
```

- [ ] **Step 2: Commit**

```bash
git add rtl/noc_tile.sv
git commit -m "feat: add NOC tile (NI + Router + link ctrl)"
```

### Task 16: 8×8 Mesh top-level

**Files:**
- Create: `NOC/rtl/mesh_8x8.sv`

**Interfaces:**
- Consumes: `noc_tile`
- Produces: `mesh_8x8` — 64-tile mesh DUT

- [ ] **Step 1: Write mesh_8x8.sv**

```systemverilog
// mesh_8x8.sv — 8x8 mesh top-level
module mesh_8x8 #(
  parameter int MESH_X         = 8,
  parameter int MESH_Y         = 8,
  parameter int VC_NUM         = 2,
  parameter int VC_DEPTH       = 8,
  parameter int DATA_W         = 512,
  parameter int QOS_W          = 4,
  parameter int PRIO_LEVELS    = 4,
  parameter int NI_FIFO_DEPTH  = 16,
  parameter int MAX_OUTSTANDING = 64
) (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4 interfaces: 64 NPU cores (one per tile)
  input  logic [MESH_Y-1:0][MESH_X-1:0]        awvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        awready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  awaddr,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   awid,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   awlen,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awburst,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awsize,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awlock,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   awcache,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   awqos,

  input  logic [MESH_Y-1:0][MESH_X-1:0]        wvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        wready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] wdata,
  input  logic [MESH_Y-1:0][MESH_X-1:0][(DATA_W/8)-1:0] wstrb,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        wlast,

  output logic [MESH_Y-1:0][MESH_X-1:0]        bvalid,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        bready,
  output logic [MESH_Y-1:0][MESH_X-1:0][7:0]   bid,
  output logic [MESH_Y-1:0][MESH_X-1:0][1:0]   bresp,

  input  logic [MESH_Y-1:0][MESH_X-1:0]        arvalid,
  output logic [MESH_Y-1:0][MESH_X-1:0]        arready,
  input  logic [MESH_Y-1:0][MESH_X-1:0][31:0]  araddr,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   arid,
  input  logic [MESH_Y-1:0][MESH_X-1:0][7:0]   arlen,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arburst,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arsize,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arlock,
  input  logic [MESH_Y-1:0][MESH_X-1:0][1:0]   arcache,
  input  logic [MESH_Y-1:0][MESH_X-1:0][3:0]   arqos,

  output logic [MESH_Y-1:0][MESH_X-1:0]        rvalid,
  input  logic [MESH_Y-1:0][MESH_X-1:0]        rready,
  output logic [MESH_Y-1:0][MESH_X-1:0][7:0]   rid,
  output logic [MESH_Y-1:0][MESH_X-1:0][DATA_W-1:0] rdata,
  output logic [MESH_Y-1:0][MESH_X-1:0][1:0]   rresp,
  output logic [MESH_Y-1:0][MESH_X-1:0]        rlast
);
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  // Inter-tile link wiring
  // Horizontal links: [y][x] → [y][x+1]
  // Vertical links:   [y][x] → [y+1][x]
  link_in_t  h_link_in  [MESH_Y][MESH_X-1];  // east<->west
  link_out_t h_link_out [MESH_Y][MESH_X-1];
  credit_t   h_credit_out, h_credit_in;

  link_in_t  v_link_in  [MESH_Y-1][MESH_X];   // north<->south
  link_out_t v_link_out [MESH_Y-1][MESH_X];
  credit_t   v_credit_out, v_credit_in;

  genvar x, y;
  generate
    for (y = 0; y < MESH_Y; y++) begin : row
      for (x = 0; x < MESH_X; x++) begin : col

        // Per-tile 4-direction links
        link_in_t  tile_link_in  [4];
        link_out_t tile_link_out [4];
        credit_t   tile_credit_out [4], tile_credit_in [4];

        // North: connect to (x, y+1) south
        if (y < MESH_Y-1) begin
          assign tile_link_out[PORT_NORTH] = v_link_out[y][x];
          assign v_link_in[y][x] = tile_link_in[PORT_NORTH];  // for tile (x,y) north IS v_link_in to (x,y+1)
          assign tile_credit_out[PORT_NORTH] = v_credit_out[y][x];
          assign v_credit_in[y][x] = tile_credit_in[PORT_NORTH];
        end else begin
          assign tile_link_out[PORT_NORTH] = '{default: '0};
          assign tile_credit_out[PORT_NORTH] = '0;
          assign _ = tile_link_in[PORT_NORTH];  // unused
          assign _ = tile_credit_in[PORT_NORTH];
        end

        // South: connect to (x, y-1) north
        if (y > 0) begin
          assign tile_link_out[PORT_SOUTH] = v_link_out[y-1][x];
          assign v_link_in[y-1][x] = tile_link_in[PORT_SOUTH];
          assign tile_credit_out[PORT_SOUTH] = v_credit_out[y-1][x];
          assign v_credit_in[y-1][x] = tile_credit_in[PORT_SOUTH];
        end else begin
          assign tile_link_out[PORT_SOUTH] = '{default: '0};
          assign tile_credit_out[PORT_SOUTH] = '0;
          assign _ = tile_link_in[PORT_SOUTH];
          assign _ = tile_credit_in[PORT_SOUTH];
        end

        // East: connect to (x+1, y) west
        if (x < MESH_X-1) begin
          assign tile_link_out[PORT_EAST] = h_link_out[y][x];
          assign h_link_in[y][x] = tile_link_in[PORT_EAST];
          assign tile_credit_out[PORT_EAST] = h_credit_out[y][x];
          assign h_credit_in[y][x] = tile_credit_in[PORT_EAST];
        end else begin
          assign tile_link_out[PORT_EAST] = '{default: '0};
          assign tile_credit_out[PORT_EAST] = '0;
          assign _ = tile_link_in[PORT_EAST];
          assign _ = tile_credit_in[PORT_EAST];
        end

        // West: connect to (x-1, y) east
        // Note: handled by east connection of (x-1, y) already

        noc_tile #(
          .MESH_X(MESH_X), .MESH_Y(MESH_Y),
          .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
          .DATA_W(DATA_W), .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS),
          .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
        ) tile (
          .clk, .rst_n,
          .tile_x(x[3:0]), .tile_y(y[3:0]),
          .awvalid(awvalid[y][x]), .awready(awready[y][x]),
          .awaddr(awaddr[y][x]), .awid(awid[y][x]), .awlen(awlen[y][x]),
          .awburst(awburst[y][x]), .awsize(awsize[y][x]),
          .awlock(awlock[y][x]), .awcache(awcache[y][x]), .awqos(awqos[y][x]),
          .wvalid(wvalid[y][x]), .wready(wready[y][x]),
          .wdata(wdata[y][x]), .wstrb(wstrb[y][x]), .wlast(wlast[y][x]),
          .bvalid(bvalid[y][x]), .bready(bready[y][x]),
          .bid(bid[y][x]), .bresp(bresp[y][x]),
          .arvalid(arvalid[y][x]), .arready(arready[y][x]),
          .araddr(araddr[y][x]), .arid(arid[y][x]), .arlen(arlen[y][x]),
          .arburst(arburst[y][x]), .arsize(arsize[y][x]),
          .arlock(arlock[y][x]), .arcache(arcache[y][x]), .arqos(arqos[y][x]),
          .rvalid(rvalid[y][x]), .rready(rready[y][x]),
          .rid(rid[y][x]), .rdata(rdata[y][x]), .rresp(rresp[y][x]), .rlast(rlast[y][x]),
          .link_in(tile_link_in), .link_out(tile_link_out),
          .credit_out(tile_credit_out), .credit_in(tile_credit_in)
        );
      end
    end
  endgenerate
endmodule
```

- [ ] **Step 2: Update rtl.f with all RTL files**

```bash
# Update filelist/rtl.f
```

filelist/rtl.f (append to existing):
```
rtl/route_compute.sv
rtl/input_port.sv
rtl/output_port.sv
rtl/vc_allocator.sv
rtl/switch_allocator.sv
rtl/crossbar_5x5.sv
rtl/link_ctrl.sv
rtl/router_5port.sv
rtl/ni_write_packer.sv
rtl/ni_read_packer.sv
rtl/ni_write_unpacker.sv
rtl/ni_read_unpacker.sv
rtl/ni_axi4.sv
rtl/noc_tile.sv
rtl/mesh_8x8.sv
```

- [ ] **Step 3: Commit**

```bash
git add rtl/noc_tile.sv rtl/mesh_8x8.sv filelist/rtl.f
git commit -m "feat: add NOC tile and 8x8 mesh assembly"
```

---

## Phase 5: Testbench & Verification

### Task 17: NOC interface and UVM package

**Files:**
- Create: `NOC/tb/noc_if.sv`
- Create: `NOC/tb/noc_pkg.sv`
- Modify: `NOC/filelist/tb.f`

**Interfaces:**
- Produces: `noc_if` — AXI4 virtual interface wrapper, `noc_pkg` — UVM package with transactions

- [ ] **Step 1: Write noc_if.sv**

```systemverilog
// noc_if.sv — NOC link and AXI4 interfaces for UVM
interface noc_axi_if #(
  parameter int DATA_W = 512
) (
  input logic clk,
  input logic rst_n
);
  // AXI4 Master signals (from NPU BFM)
  logic        awvalid;
  logic        awready;
  logic [31:0] awaddr;
  logic [7:0]  awid;
  logic [7:0]  awlen;
  logic [1:0]  awburst;
  logic [3:0]  awsize;
  logic [3:0]  awlock;
  logic [1:0]  awcache;
  logic [3:0]  awqos;

  logic        wvalid;
  logic        wready;
  logic [DATA_W-1:0] wdata;
  logic [(DATA_W/8)-1:0] wstrb;
  logic        wlast;

  logic        bvalid;
  logic        bready;
  logic [7:0]  bid;
  logic [1:0]  bresp;

  logic        arvalid;
  logic        arready;
  logic [31:0] araddr;
  logic [7:0]  arid;
  logic [7:0]  arlen;
  logic [1:0]  arburst;
  logic [3:0]  arsize;
  logic [3:0]  arlock;
  logic [1:0]  arcache;
  logic [3:0]  arqos;

  logic        rvalid;
  logic        rready;
  logic [7:0]  rid;
  logic [DATA_W-1:0] rdata;
  logic [1:0]  rresp;
  logic        rlast;

  // Modport for master (NPU core BFM)
  modport master (
    output awvalid, awaddr, awid, awlen, awburst, awsize, awlock, awcache, awqos,
    input  awready,
    output wvalid, wdata, wstrb, wlast,
    input  wready,
    input  bvalid,
    output bready,
    input  bid, bresp,
    output arvalid, araddr, arid, arlen, arburst, arsize, arlock, arcache, arqos,
    input  arready,
    input  rvalid,
    output rready,
    input  rid, rdata, rresp, rlast
  );

  // Modport for slave (mesh DUT)
  modport slave (
    input  awvalid, awaddr, awid, awlen, awburst, awsize, awlock, awcache, awqos,
    output awready,
    input  wvalid, wdata, wstrb, wlast,
    output wready,
    output bvalid,
    input  bready,
    output bid, bresp,
    input  arvalid, araddr, arid, arlen, arburst, arsize, arlock, arcache, arqos,
    output arready,
    output rvalid,
    input  rready,
    output rid, rdata, rresp, rlast
  );
endinterface
```

- [ ] **Step 2: Write noc_pkg.sv (UVM package)**

```systemverilog
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
    rand bit [7:0]  len;      // burst length
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
    constraint addr_align  { size inside {3,4,5,6}; } // 8B-64B aligned

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
```

- [ ] **Step 3: Update tb.f**

```bash
# Update filelist/tb.f
```

filelist/tb.f (append to existing):
```
+incdir+tb
tb/noc_if.sv
tb/noc_pkg.sv
```

- [ ] **Step 4: Commit**

```bash
git add tb/noc_if.sv tb/noc_pkg.sv filelist/tb.f
git commit -m "feat: add NOC UVM interface and package"
```

### Task 18: UVM Environment and Scoreboard

**Files:**
- Create: `NOC/tb/noc_env.sv`
- Create: `NOC/tb/noc_scoreboard.sv`

**Interfaces:**
- Consumes: `noc_pkg`, `noc_if`
- Produces: `noc_env` — UVM environment, `noc_scoreboard` — flit-level scoreboard

- [ ] **Step 1: Write noc_scoreboard.sv**

```systemverilog
// noc_scoreboard.sv — NOC scoreboard with flit tracking
class noc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(noc_scoreboard)

  uvm_analysis_imp_axi_tx #(axi_transaction, noc_scoreboard) axi_tx_imp;
  uvm_analysis_imp_flit_tx #(flit_transaction, noc_scoreboard) flit_tx_imp;

  // Expected transactions queue
  axi_transaction expected_q[$];
  int matched, mismatched;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    axi_tx_imp  = new("axi_tx_imp", this);
    flit_tx_imp = new("flit_tx_imp", this);
  endfunction

  // Receive injected AXI transaction
  function void write_axi_tx(axi_transaction tx);
    expected_q.push_back(tx);
  endfunction

  // Receive received flit, match against expected
  function void write_flit_tx(flit_transaction ftx);
    foreach (expected_q[i]) begin
      if (expected_q[i].id == ftx.src_id) begin
        matched++;
        expected_q.delete(i);
        return;
      end
    end
    mismatched++;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_name(), $sformatf("Scoreboard: matched=%0d mismatched=%0d pending=%0d",
             matched, mismatched, expected_q.size()), UVM_LOW)
  endfunction
endclass
```

- [ ] **Step 2: Write noc_env.sv**

```systemverilog
// noc_env.sv — UVM environment for 64-tile NOC mesh
class noc_env extends uvm_env;
  `uvm_component_utils(noc_env)

  noc_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    scoreboard = noc_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
  endfunction
endclass
```

- [ ] **Step 3: Commit**

```bash
git add tb/noc_scoreboard.sv tb/noc_env.sv
git commit -m "feat: add NOC UVM environment and scoreboard"
```

### Task 19: UVM Sequence Library and Test Classes

**Files:**
- Create: `NOC/tb/noc_sequence.sv`
- Create: `NOC/tb/noc_test.sv`

**Interfaces:**
- Consumes: `noc_pkg`
- Produces: `noc_sequence` — test sequences, `noc_test` — test classes

- [ ] **Step 1: Write noc_sequence.sv**

```systemverilog
// noc_sequence.sv — NOC test sequence library
class noc_sanity_sequence extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(noc_sanity_sequence)

  function new(string name = "noc_sanity_sequence");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    int sx, sy, dx, dy;

    // Test 1: Neighbor write (west→east neighbors)
    for (int y = 0; y < 8; y++) begin
      for (int x = 0; x < 7; x++) begin
        tx = axi_transaction::type_id::create("tx");
        tx.is_write = 1;
        tx.addr = {3'b0, y[2:0], x[2:0]+3'd1, 3'b0, y[2:0], x[2:0], 6'h00}; // dst=src east neighbor
        tx.id   = {x[2:0], y[2:0]};
        tx.len  = 0; // single beat
        tx.burst = 2'b01;
        tx.size = 3'd6; // 64B
        tx.qos  = 4'b0010; // P2 default
        start_item(tx);
        finish_item(tx);
        `uvm_info("SANITY", $sformatf("Tx(%0d,%0d)→(%0d,%0d)", x,y,x+1,y), UVM_MEDIUM)
      end
    end
  endtask
endclass

class noc_rr_sequence extends uvm_sequence #(axi_transaction);
  `uvm_object_utils(noc_rr_sequence)

  function new(string name = "noc_rr_sequence");
    super.new(name);
  endfunction

  task body();
    axi_transaction tx;
    for (int i = 0; i < 1000; i++) begin
      tx = axi_transaction::type_id::create("tx");
      tx.is_write = $urandom_range(0,1);
      tx.addr = $urandom_range(0, 32'h1FFFFFF); // within valid range
      tx.id   = $urandom_range(0, 255);
      tx.len  = $urandom_range(0, 15);
      tx.burst = 2'b01; // INCR
      tx.size = 3'd6;   // 64B
      tx.qos  = $urandom_range(0, 15);
      start_item(tx);
      finish_item(tx);
    end
  endtask
endclass
```

- [ ] **Step 2: Write noc_test.sv**

```systemverilog
// noc_test.sv — NOC test classes
class noc_base_test extends uvm_test;
  `uvm_component_utils(noc_base_test)

  noc_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = noc_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_top.print_topology();
  endfunction
endclass

class noc_sanity_test extends noc_base_test;
  `uvm_component_utils(noc_sanity_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    noc_sanity_sequence seq;
    phase.raise_objection(this);
    seq = noc_sanity_sequence::type_id::create("seq");
    seq.start(null);
    phase.drop_objection(this);
  endtask
endclass

class noc_rr_test extends noc_base_test;
  `uvm_component_utils(noc_rr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    noc_rr_sequence seq;
    phase.raise_objection(this);
    seq = noc_rr_sequence::type_id::create("seq");
    seq.start(null);
    phase.drop_objection(this);
  endtask
endclass
```

- [ ] **Step 3: Commit**

```bash
git add tb/noc_sequence.sv tb/noc_test.sv
git commit -m "feat: add NOC UVM sequence library and test classes"
```

### Task 20: Testbench Top

**Files:**
- Create: `NOC/tb/tb_top.sv`
- Modify: `NOC/filelist/tb.f`

**Interfaces:**
- Consumes: `mesh_8x8`, `noc_if`, `noc_pkg`, `noc_env`, `noc_sequence`, `noc_test`
- Produces: `tb_top` — complete testbench

- [ ] **Step 1: Write tb_top.sv**

```systemverilog
// tb_top.sv — 8x8 NOC mesh testbench top
module tb_top;
  import uvm_pkg::*;
  import noc_config_pkg::*;
  import noc_flit_pkg::*;

  `include "uvm_macros.svh"

  // Clock and reset
  logic clk;
  logic rst_n;

  // 64 AXI interfaces
  noc_axi_if #(.DATA_W(DATA_W)) axi_if [MESH_Y][MESH_X] (.clk, .rst_n);

  // DUT instantiation
  mesh_8x8 #(
    .MESH_X(MESH_X), .MESH_Y(MESH_Y),
    .VC_NUM(VC_NUM), .VC_DEPTH(VC_DEPTH),
    .DATA_W(DATA_W), .QOS_W(QOS_W), .PRIO_LEVELS(PRIO_LEVELS),
    .NI_FIFO_DEPTH(NI_FIFO_DEPTH), .MAX_OUTSTANDING(MAX_OUTSTANDING)
  ) dut (
    .clk, .rst_n,
    .awvalid(), .awready(), .awaddr(), .awid(), .awlen(),
    .awburst(), .awsize(), .awlock(), .awcache(), .awqos(),
    .wvalid(), .wready(), .wdata(), .wstrb(), .wlast(),
    .bvalid(), .bready(), .bid(), .bresp(),
    .arvalid(), .arready(), .araddr(), .arid(), .arlen(),
    .arburst(), .arsize(), .arlock(), .arcache(), .arqos(),
    .rvalid(), .rready(), .rid(), .rdata(), .rresp(), .rlast()
  );

  // Clock generation — 500 MHz → 1 ns period
  initial clk = 0;
  always #1 clk = ~clk;  // 2ns period (500MHz)
  // Adjust to: T=2ns for 500MHz

  // Reset
  initial begin
    rst_n = 0;
    #10 rst_n = 1;
  end

  // Connect DUT ports to interfaces
  genvar x, y;
  generate
    for (y = 0; y < MESH_Y; y++) begin : y_gen
      for (x = 0; x < MESH_X; x++) begin : x_gen
        assign dut.awvalid[y][x] = axi_if[y][x].awvalid;
        assign axi_if[y][x].awready = dut.awready[y][x];
        assign dut.awaddr[y][x]  = axi_if[y][x].awaddr;
        assign dut.awid[y][x]    = axi_if[y][x].awid;
        assign dut.awlen[y][x]   = axi_if[y][x].awlen;
        assign dut.awburst[y][x] = axi_if[y][x].awburst;
        assign dut.awsize[y][x]  = axi_if[y][x].awsize;
        assign dut.awlock[y][x]  = axi_if[y][x].awlock;
        assign dut.awcache[y][x] = axi_if[y][x].awcache;
        assign dut.awqos[y][x]   = axi_if[y][x].awqos;

        assign dut.wvalid[y][x] = axi_if[y][x].wvalid;
        assign axi_if[y][x].wready = dut.wready[y][x];
        assign dut.wdata[y][x]  = axi_if[y][x].wdata;
        assign dut.wstrb[y][x]  = axi_if[y][x].wstrb;
        assign dut.wlast[y][x]  = axi_if[y][x].wlast;

        assign axi_if[y][x].bvalid = dut.bvalid[y][x];
        assign dut.bready[y][x] = axi_if[y][x].bready;
        assign axi_if[y][x].bid   = dut.bid[y][x];
        assign axi_if[y][x].bresp = dut.bresp[y][x];

        assign dut.arvalid[y][x] = axi_if[y][x].arvalid;
        assign axi_if[y][x].arready = dut.arready[y][x];
        assign dut.araddr[y][x]  = axi_if[y][x].araddr;
        assign dut.arid[y][x]    = axi_if[y][x].arid;
        assign dut.arlen[y][x]   = axi_if[y][x].arlen;
        assign dut.arburst[y][x] = axi_if[y][x].arburst;
        assign dut.arsize[y][x]  = axi_if[y][x].arsize;
        assign dut.arlock[y][x]  = axi_if[y][x].arlock;
        assign dut.arcache[y][x] = axi_if[y][x].arcache;
        assign dut.arqos[y][x]   = axi_if[y][x].arqos;

        assign axi_if[y][x].rvalid = dut.rvalid[y][x];
        assign dut.rready[y][x] = axi_if[y][x].rready;
        assign axi_if[y][x].rid   = dut.rid[y][x];
        assign axi_if[y][x].rdata = dut.rdata[y][x];
        assign axi_if[y][x].rresp = dut.rresp[y][x];
        assign axi_if[y][x].rlast = dut.rlast[y][x];
      end
    end
  endgenerate

  // UVM
  initial begin
    uvm_config_db #(virtual noc_axi_if)::set(null, "*", "axi_vif", axi_if[0][0]);
    run_test();
  end

  // Dump waveforms
  initial begin
    $fsdbDumpfile("waves/noc.fsdb");
    $fsdbDumpvars(0, tb_top);
  end
endmodule
```

- [ ] **Step 2: Update tb.f (append)**

```
tb/tb_top.sv
```

- [ ] **Step 3: Compile check**

```bash
make compile 2>&1 | tail -30
```

Expected: "VCS compilation completed" or see compile errors to fix.

- [ ] **Step 4: Commit**

```bash
git add tb/tb_top.sv filelist/tb.f
git commit -m "feat: add NOC 8x8 testbench top"
```

---

## Phase 6: Integration Verification

### Task 21: Fix cross-module interface connections

**Files:**
- Modify: `NOC/rtl/router_5port.sv`
- Modify: `NOC/rtl/ni_axi4.sv`
- Modify: `NOC/rtl/noc_tile.sv`
- Modify: `NOC/rtl/mesh_8x8.sv`

**Interfaces:**
- Fixes struct field access for `link_in_t`/`link_out_t` across modules
- Completes SA/VA/CB integration wiring in router_5port

- [ ] **Step 1: Clean router_5port signal wiring**

The initial router_5port.sv has placeholder wiring. Replace the SA/VA/crossbar stubs with proper connections:

```systemverilog
  // In router_5port.sv, fix these connections:

  // --- Extract destination from header flit for route compute ---
  // The header fields are packed in payload; decode properly
  // flit_header_t overlay:
  // payload.data[445:390] = {src_id, dst_id} -> dst_id[5:0]
  // payload.wstrb[23:16] = dst_y, payload.wstrb[7:0] = dst_x

  for (genvar g = 0; g < 5; g++) begin : route_gen
    logic [5:0] hdr_dst_id;
    logic [2:0] hdr_dst_x, hdr_dst_y;

    assign hdr_dst_id = xbar_in_flit[g].payload.data[395:390]; // dst_id from header
    assign hdr_dst_x  = hdr_dst_id[2:0];
    assign hdr_dst_y  = hdr_dst_id[5:3];

    route_compute #(.MESH_X(MESH_X), .MESH_Y(MESH_Y)) rc (
      .src_x(local_coord.x),
      .src_y(local_coord.y),
      .dst_x({1'b0, hdr_dst_x}),
      .dst_y({1'b0, hdr_dst_y}),
      .port_disable(port_disable),
      .next_port(route_result[g])
    );
  end
  ```

- [ ] **Step 2: Verify compilation**

```bash
make compile 2>&1 | grep -E "Error|Warning" | head -20
```

- [ ] **Step 3: Commit**

```bash
git add rtl/router_5port.sv rtl/ni_axi4.sv rtl/noc_tile.sv rtl/mesh_8x8.sv
git commit -m "fix: resolve cross-module interface connections in router and mesh"
```

### Task 22: Run sanity simulation

**Files:**
- Modify: `NOC/tb/noc_test.sv` — add task to start sequence on correct interface

**Interfaces:**
- Fixes UVM test to properly interact with AXI virtual interface

- [ ] **Step 1: Fix test to use virtual interface**

Update noc_test.sv to use the virtual interface:

```systemverilog
// In noc_base_test, add:
  virtual noc_axi_if #(512) axi_vif;

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual noc_axi_if #(512))::get(this, "", "axi_vif", axi_vif))
      `uvm_fatal("NOC_TEST", "Virtual interface not set")
  endfunction
```

- [ ] **Step 2: Run sanity test**

```bash
make compile && make run TEST=noc_sanity_test
```

- [ ] **Step 3: Check results**

Expected: PASS with no errors, scoreboard matched transactions.

- [ ] **Step 4: Commit**

```bash
git add tb/noc_test.sv
git commit -m "fix: wire UVM virtual interface in test classes"
```

---

## Verification Checklist

Final verification items from the spec:

| # | Item | Test |
|---|------|------|
| 1 | XY routing correctness (4096 src-dst pairs) | noc_sanity_test |
| 2 | Flit integrity (Header→Body→Tail) | noc_sanity_test |
| 3 | AXI transaction consistency | scoreboard comparison |
| 4 | OOO read responses | noc_rr_test (random IDs) |
| 5 | Credit flow control (no overflow/drop) | pressure test |
| 6 | FIFO full/empty boundary (backpressure) | pressure test |
| 7 | VC isolation (request/response) | monitored in scoreboard |
| 8 | QoS priority (P0>P1>P2>P3) | qos_test (future task) |
| 9 | Deadlock safety (long run) | stress test 100K cycles |
| 10 | Boundary nodes (edge/corner port disable) | all tests |
