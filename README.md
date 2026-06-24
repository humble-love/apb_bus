# APB3 Bus Practice Framework

基于 AMBA APB3 协议的 RTL 总线编程练习框架。RTL 用纯 Verilog，验证用 SystemVerilog UVM，VCS 编译，Verdi 看波形。

## 架构

```
Master 0 ──┐
            ├─ req/gnt ─→ Arbiter ─→ Decoder ─┬─→ Slave 0 (Memory, 0x0xxx)
Master 1 ──┘                                   └─→ Slave 1 (GPIO,   0x1xxx)
```

- 2 个 Master → 固定优先级仲裁器（M0 > M1）→ 地址译码器 → 2 个 Slave
- APB3 传输时序: IDLE → SETUP (PSEL=1) → ACCESS (PENABLE=1) → [等 PREADY] → IDLE
- Memory Slave 带 LFSR 随机 PREADY stall（默认 25% 概率）
- GPIO Slave 带中断输出（`gpio_int = INT_STATUS & INT_EN`）

## 目录结构

```
bus/
├── rtl/                    # 纯 Verilog RTL
│   ├── apb_master.v        # Master FSM 控制器
│   ├── apb_arbiter.v       # 固定优先级仲裁器
│   ├── apb_decoder.v       # 地址译码器
│   ├── apb_slave_mem.v     # 256×32 Memory Slave
│   ├── apb_slave_gpio.v    # GPIO 寄存器 Slave
│   └── apb_top.v           # 顶层集成
├── tb/                     # UVM 验证环境 (SystemVerilog)
│   ├── apb_if.sv           # APB Interface (clocking blocks)
│   ├── apb_pkg.sv          # Transaction + 约束
│   ├── apb_master_driver.sv
│   ├── apb_master_monitor.sv
│   ├── apb_master_agent.sv
│   ├── apb_scoreboard.sv   # Reference model
│   ├── apb_env.sv
│   ├── sequence_lib.sv     # 测试序列库
│   ├── apb_test.sv         # UVM Tests
│   └── tb_top.sv           # Testbench 顶层
├── scripts/
│   ├── filelist.f          # VCS 文件列表
│   ├── compile.sh          # VCS 编译脚本
│   ├── run.sh              # 仿真运行脚本
│   └── verdi.sh            # Verdi 波形查看
├── Makefile
├── waves/                  # FSDB 波形输出
└── docs/                   # 设计文档
```

## 环境要求

| 工具 | 用途 |
|------|------|
| VCS (Synopsys) | 编译 + 仿真 |
| Verdi (Synopsys) | 波形查看 |

Ensure `VCS_HOME` and `VERDI_HOME` are set, or edit the paths in `scripts/compile.sh`.

## 快速开始

### 1. 编译

```bash
make compile
```

等价于:

```bash
bash scripts/compile.sh
```

输出 `simv` 可执行文件。编译选项：
- `-sverilog -ntb_opts uvm-1.2` — UVM 1.2 支持
- `-debug_access+all -kdb` — Verdi debug
- `-fsdb` + Verdi PLI — FSDB 波形 dump
- `+vcs+lic+wait` — 等 license

### 2. 运行仿真

```bash
make run TEST=apb_sanity_test
```

等价于:

```bash
bash scripts/run.sh apb_sanity_test
```

可用的测试：

| Test | Sequence | 说明 |
|------|----------|------|
| `apb_sanity_test` | 每个 slave 各读写一次 | 基础连通性 |
| `apb_random_test` | 20 次随机读写 | 随机覆盖率 |
| `apb_burst_test` | 连续 10 次 back-to-back 读写 | Pipeline 行为 |
| `apb_error_test` | 访问未映射地址 0x2000 | 错误响应 |

不指定 TEST 默认跑 `apb_sanity_test`。

### 3. 查看波形

```bash
make verdi
```

等价于:

```bash
bash scripts/verdi.sh
```

Verdi 打开后自动加载 `waves/apb.fsdb` 和所有源码。

### 4. 清理

```bash
make clean
```

## 地址映射

| 地址范围 | Slave | 说明 |
|----------|-------|------|
| `0x0000_0000 - 0x0000_0FFF` | Slave 0 (Memory) | 256×32 存储 |
| `0x0000_1000 - 0x0000_1FFF` | Slave 1 (GPIO) | 寄存器文件 |

## GPIO 寄存器

| 偏移 | 寄存器 | 说明 |
|------|--------|------|
| `0x00` | DATA | GPIO 输出数据 |
| `0x04` | DIR | 方向控制 (1=output) |
| `0x08` | INT_EN | 中断使能 |
| `0x0C` | INT_STATUS | 中断状态 |

## 关键波形信号

在 Verdi 中关注以下信号来理解 APB 时序：

| 信号 | 说明 |
|------|------|
| `req_0`, `gnt_0` | Master 0 的请求/授予握手 |
| `paddr`, `pwdata`, `prdata` | 地址、写数据、读数据 |
| `pwrite` | 1=写, 0=读 |
| `psel`, `penable` | APB 传输阶段 |
| `pready` | Slave 就绪（低 = stall） |
| `psel_slv[1:0]` | 每个 slave 的片选 |
| `gpio_int` | GPIO 中断输出 |

## 修改练习

- **调整 Memory stall 概率**: 改 `rtl/apb_top.v` 中 `apb_slave_mem` 的 `STALL_PROB` 参数（0-255）
- **加第三个 master**: 在 `rtl/apb_top.v` 中例化新的 `apb_master`，修改 `apb_arbiter` 和 `apb_if` 的 `NUM_MASTERS`
- **加新 slave**: 写新的 slave 模块，在 decoder 中加地址映射，在 `apb_top.v` 的 PRDATA mux 中加对应逻辑
- **写自己的 sequence**: 参考 `tb/sequence_lib.sv` 中的 `apb_base_sequence`，继承它写新的 body()
- **同时跑两个 master**: 用 `fork...join` 在两个 agent 的 sequencer 上同时 start sequence

## 编译脚本自定义

如果 VCS/Verdi 路径不同，设置环境变量：

```bash
export VCS_HOME=/your/vcs/path
export VERDI_HOME=/your/verdi/path
make compile
```

也可以在 `scripts/compile.sh` 中直接修改默认值。
