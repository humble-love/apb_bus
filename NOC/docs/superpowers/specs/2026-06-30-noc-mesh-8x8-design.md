# NOC Mesh 8x8 总线设计规格书

**版本**: 1.0
**日期**: 2026-06-30
**作者**: openclaw
**目标**: 64 NPU Core 互联 — 8×8 2D Mesh Network-on-Chip

---

## 1. 系统架构总览

### 1.1 整体拓扑

```
┌─────────────────────────────────────────────────────────────────┐
│                        NOC Mesh Top Layer                        │
│  ┌──────┐  ┌──────┐  ┌──────┐       ┌──────┐                   │
│  │Tile  │──│Tile  │──│Tile  │─ ... ─│Tile  │                   │
│  │(0,7) │  │(1,7) │  │(2,7) │       │(7,7) │                   │
│  └──┬───┘  └──┬───┘  └──┬───┘       └──┬───┘                   │
│     │         │         │               │                        │
│  ┌──┴───┐  ┌──┴───┐  ┌──┴───┐       ┌──┴───┐                   │
│  │Tile  │──│Tile  │──│Tile  │─ ... ─│Tile  │                   │
│  │(0,6) │  │(1,6) │  │(2,6) │       │(7,6) │                   │
│  └──┬───┘  └──┬───┘  └──┬───┘       └──┬───┘                   │
│     │    ...  │    ...  │    ...      │                          │
│  ┌──┴───┐  ┌──┴───┐  ┌──┴───┐       ┌──┴───┐                   │
│  │Tile  │──│Tile  │──│Tile  │─ ... ─│Tile  │                   │
│  │(0,0) │  │(1,0) │  │(2,0) │       │(7,0) │                   │
│  └──────┘  └──────┘  └──────┘       └──────┘                   │
│                    8x8 Mesh, 64 Tiles                            │
│       per-link: 512-bit + ctrl, 500MHz, credit-based             │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 单 Tile 内部结构

```
    ┌──────────┐      ┌──────────────┐      ┌───────────────┐
    │  NPU     │AXI4  │  Network     │flit  │   Router      │
    │  Core    │◄────►│  Interface   │◄────►│   (5-port)    │
    │          │      │  (NI)        │      │               │
    └──────────┘      └──────────────┘      └───┬───┬───┬───┘
                                                N   S   E   W
```

- 每个 Tile = NPU Core + Network Interface (NI) + Router
- Router 5 端口：North, South, East, West, Local
- 边界 Router 未使用的端口接地/关断
- NI 负责 AXI4 ↔ flit 协议转换

### 1.3 关键参数汇总

| 参数 | 取值 | 说明 |
|------|------|------|
| 拓扑 | 8×8 2D Mesh | 64 节点 |
| 数据位宽 | 512-bit | 链路数据宽度 |
| 频率 | 500 MHz | 全同步设计 |
| 接口协议 | AXI4 | 与 NPU Core 通信 |
| 路由算法 | XY 维序路由 | 确定性，无死锁 |
| 虚通道 VC | 2 | VC0=请求，VC1=响应 |
| 流控 | Credit-based | 每 VC 独立 credit |
| 报文格式 | Flit 级封装 | Header/Body/Tail |
| QoS | 4 级优先级 | P0-P3 + 老化晋升 |

---

## 2. 拓扑与路由设计

### 2.1 坐标系统与寻址

- 64 个 Tile 坐标：`(X, Y)`，`X, Y ∈ [0, 7]`
- 全局 Node ID：6-bit `{Y[2:0], X[2:0]}`（高 3-bit Y，低 3-bit X）
- 对角线最远距离：14 hops（(0,0) → (7,7)）

### 2.2 XY 维序路由

```
路由规则 (Router 内部决策):
  if (ΔX > 0) → 向东 (E)
  elif (ΔX < 0) → 向西 (W)
  elif (ΔY > 0) → 向北 (N)
  elif (ΔY < 0) → 向南 (S)
  else → 本地 (L)           // ΔX=0, ΔY=0, 到达目标

  ΔX = dst_x - src_x, ΔY = dst_y - src_y
```

关键性质：

- **确定性**: 同一 src-dst 对始终走相同路径
- **无死锁**: 禁止 180° 转向，依赖图无环（Dally & Seitz 定理）
- **无活锁**: 最短路径，每步严格减少曼哈顿距离
- **实现代价**: 2 个减法器 + 比较器，O(1) 路由决策

### 2.3 路由 Pipeline

```
Cycle      Stage                    说明
──────────────────────────────────────────────────
T0     RC  (Route Compute)         计算 ΔX/ΔY，选择输出端口
T1     VA  (VC Allocation)         为目标 VC 分配时隙
T2     SA  (Switch Allocation)     仲裁输出端口（多请求者竞争）
T3     ST  (Switch Traversal)      穿过 crossbar 到输出链路
T4     LT  (Link Traversal)        下一跳接收
```

4 级流水线 Router + 1 级链路传输 = 5 cycles per hop。

---

## 3. Flit 格式与封装

### 3.1 Flit 类型

| Type[1:0] | 名称 | 含义 |
|-----------|------|------|
| 2'b01 | Header Flit | 包含路由与事务信息 |
| 2'b10 | Body Flit | 数据载荷 |
| 2'b11 | Tail Flit | 最后一拍数据 + 结束标记 |
| 2'b00 | Idle Flit | 空闲 / 无有效负载 |

### 3.2 Header Flit 格式 (512-bit)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [511:504]  [503:496]  [495:488]  [487:486]  [485:482]  [481:480]     │
│  src_y     src_x      dst_y      dst_x      QoS       Type=01        │
├──────────────────────────────────────────────────────────────────────┤
│ [479:474]  [473:468]  [467:460]  [459:452]  [451:420]  [419:388]     │
│  src_id    dst_id     axlen[7:0] axid[7:0]  axaddr[31:0] axburst[1:0]│
├──────────────────────────────────────────────────────────────────────┤
│ [387:384]  [383:380] [379:378] [377:128]                    [127:0]  │
│  axsize    axlock    axcache    reserved                     axprot   │
├──────────────────────────────────────────────────────────────────────┤
│ [511:0]                                                              │
│  Header CRC / ECC (可选，高位预留)                                     │
└──────────────────────────────────────────────────────────────────────┘
```

关键字段：

- `src_y[7:0]` / `src_x[7:0]`：源坐标（高 2 位保留扩展）
- `dst_y[7:0]` / `dst_x[7:0]`：目标坐标
- `dst_x[5:0]` / `dst_y[5:0]` 组合 → 6-bit dst_id，`src_x[5:0]` / `src_y[5:0]` → 6-bit src_id
- `QoS[3:0]`：优先级标记
- AXI 地址/ID/burst/length 从 AXI 通道直接提取

### 3.3 Body/Tail Flit 格式 (512-bit)

```
Body Flit:
┌──────────────────────────────────────────────────────────────────────┐
│ [511:448]         [447:2]                        [1:0]                │
│  byte enable      data payload (446-bit)          Type=10             │
│  (wstrb, 64-bit)                                                    │
└──────────────────────────────────────────────────────────────────────┘

Tail Flit:
┌──────────────────────────────────────────────────────────────────────┐
│ [511:448]         [447:2]                        [1:0]                │
│  byte enable      data payload (446-bit)          Type=11             │
│  (wstrb, 64-bit)                                                    │
└──────────────────────────────────────────────────────────────────────┘
```

注：512-bit flit 中 446-bit 为有效载荷，含 64-bit byte enable。写事务中 byte enable 有效，读事务中忽略。

### 3.4 AXI ↔ Flit 映射

```
AXI 事务             Flit 序列                  VC   QoS(来自AxQoS)
────────────────────────────────────────────────────────────────
AW 通道             Header(写地址)  →            VC0   AxQoS
W 通道              Body(写数据)+Tail(写数据)     VC0   AxQoS
B 通道 ←            Header(写响应) ←             VC1   AxQoS(请求端携带)
AR 通道             Header(读地址)  →            VC0   AxQoS
R 通道 ←            Body(读数据)+Tail(读数据) ←  VC1   AxQoS(请求端携带)
```

AXI burst length 直接映射为 Body/Tail flit 数量：1 个 Header + (N-1) 个 Body + 1 个 Tail。写响应 B 通道封装为单 Header flit（无 Body/Tail），通过 src_id 匹配路由回源端。

---

## 4. Router 微架构

### 4.1 Router 结构 (5-Port Wormhole Router)

```
                    ┌─────────────────────────────────────┐
                    │               Router                │
                    │                                     │
   North Input ◄──► │  ┌─────────┐       ┌─────────┐     │
                    │  │  Input   │       │  Output  │     │
   South Input ◄──► │  │  Ports   │       │  Ports   │     │
                    │  │  (5x)    │       │  (5x)    │     │
   East Input  ◄──► │  │          │       │          │     │
                    │  │  ┌─────┐ │       │ ┌─────┐  │     │
   West Input  ◄──► │  │  │FIFO │ │       │ │FIFO │  │     │
                    │  │  │(2VC)│─┤       ├─│(2VC)│  │     │
   Local Input ◄──► │  │  └─────┘ │       │ └─────┘  │     │
                    │  │          │       │          │     │
                    │  └─────────┘       └─────────┘     │
                    │         │               ▲           │
                    │         │    ┌──────┐   │           │
                    │         └───►│5×5   │───┘           │
                    │              │X-bar │               │
                    │              └──────┘               │
                    └─────────────────────────────────────┘
```

### 4.2 Input Port 结构

```
Input Port (每个方向 1 个):
┌─────────────────────────────────────────────┐
│  Link In ──► ┌──────────┐                   │
│  (512b+ctrl) │Input     │  ┌──────┐ ┌────┐ │
│              │Register   │──│ VC0  │ │RC  │ │
│              └──────────┘  │FIFO  │ │    │─┼──► VA Stage
│                            │(8深) │ │    │ │
│                            └──┬───┘ └────┘ │
│                            ┌──┴───┐ ┌────┐ │
│                            │ VC1  │ │RC  │ │
│                            │FIFO  │ │    │─┼──► VA Stage
│                            │(8深) │ │    │ │
│                            └──────┘ └────┘ │
│  Credit Ctrl ◄── credit_out to upstream    │
└─────────────────────────────────────────────┘
```

- 每输入端口 2 个 VC FIFO，深度 8 个 flit（覆盖 4-cycle RTT + 余量）
- RC 在 header flit 到达 VC FIFO 头部时计算路由方向
- Credit 计数器：FIFO 每弹出一个 flit，向上一跳返还 1 个 credit

### 4.3 Output Port 结构

```
Output Port (每个方向 1 个):
┌────────────────────────────────────┐
│  Switch  ──►┌──────────┐          │
│  Output     │Output     │──► Link Out (512b+ctrl)
│             │Register   │          │
│             └──────────┘          │
│  Credit In ◄── credit_in from downstream
└────────────────────────────────────┘
```

- downstream FIFO 的 credit 信号直连到本级 Output Port 的 SA 仲裁器
- credit ≤ 0 时该 VC 不可分配，阻止发送

### 4.4 Pipeline 时序

每 hop 5 cycles：RC → VA → SA → ST → LT

| Stage | 名称 | 功能 |
|-------|------|------|
| RC | Route Compute | header flit 到达 VC FIFO 头部，计算 ΔX/ΔY |
| VA | VC Allocation | 为输出的 VC 分配下游 FIFO 槽位 |
| SA | Switch Allocation | 多输入竞争同一输出端口时仲裁 |
| ST | Switch Traversal | crossbar 导通，flit 穿行 |
| LT | Link Traversal | 下一跳接收 |

Body/Tail flit 不执行 RC 和 VA，直接跟随所属 packet 的 header 使用已建立的路由路径（wormhole 切换）。

---

## 5. 流量控制与 VC 管理

### 5.1 Credit-Based 流控

```
┌──────────────────────────────────────────────────────────────┐
│  Upstream Router              │      Downstream Router       │
│                               │                              │
│  Output         Credit_in ◄───┼──── Input FIFO (per VC)      │
│  Port           Flit_out  ───►│                              │
│                               │  FIFO弹出flit → 返还credit    │
│  Credit 计数器:               │  FIFO满 → 停止发credit        │
│   credit-- (每发1 flit)      │                              │
│   credit++ (每收1 credit)    │                              │
│   credit > 0 → 可发送         │                              │
└──────────────────────────────────────────────────────────────┘
```

参数设计：

- FIFO 深度 = 8 flits → 初始 credit = 8
- 链路 RTT ≈ 2 cycles（1 cycle 发送 + 1 cycle credit 返回）
- credit 穿越 RTT 余量 ≈ 3-4 cycles 安全余量
- 阈值：credit ≤ 1 时标记 VC 不可用（避免溢出）

### 5.2 VC 管理策略

```
VC 分配:
┌──────────────────────────────────────────┐
│ VC0 — 请求通道                           │
│   • AW flit (写地址)                      │
│   • W body/tail flits (写数据)            │
│   • AR flit (读地址)                      │
│                                          │
│ VC1 — 响应通道                           │
│   • B flit (写响应)                       │
│   • R body/tail flits (读数据)            │
└──────────────────────────────────────────┘
```

死锁避免原理：请求和响应分属不同 VC，形成独立虚网络。请求 VC → 响应 VC 单向依赖，依赖图无环 → 协议级无死锁。

### 5.3 反压传播

```
场景: 下游 FIFO 满 → credit = 0

  Src ──► R0 ──► R1 ──► R2 ──► Dst
               ▲
               └── R1 输出端口 VC0 credit = 0
                    → SA 不再选择此输出端口的 VC0
                    → R0 发往 VC0 的 flit 阻塞在 FIFO
                    → R0 VC0 FIFO 趋于满
                    → 反压逐跳传播至源端 NI
                    → NI 反压 AXI AW/AR/W 通道 (拉低 ready)
```

反压从拥塞点逐跳反向传播，不丢包，不依赖端到端信用。

---

## 6. QoS 与仲裁策略

### 6.1 优先级定义与映射

| 优先级 | QoS[3:0] | 流量类型 | AXI 信号映射 |
|--------|----------|---------|-------------|
| P0 | 4'b1000 | 实时控制/中断/同步信号 | AxQoS[3:0] |
| P1 | 4'b0100 | 低延迟推理请求/coherence | AxQoS[3:0] |
| P2 | 4'b0010 | 常规数据读写（默认） | AxQoS[3:0] |
| P3 | 4'b0001 | 后台 DMA/预取/非关键传输 | AxQoS[3:0] |

AXI AxQoS 原生为 4-bit，直接映射到 NOC 内部 QoS 字段。非标准 AxQoS 值映射规则：`bit[3] ? P0 : bit[2] ? P1 : bit[1] ? P2 : P3`。

### 6.2 两阶段仲裁

**Stage 1 — SA (Switch Allocation)，per-output-port**：

```
5 个 Input Port 请求同一 Output Port

仲裁策略: 可抢占优先级仲裁

1. 分组: P0 > P1 > P2 > P3
2. 组内: Round-Robin（公平）
3. 组间: 严格优先级（高优先级全胜）
4. 抢占: P0/P1 可打断 P3 正在传输的行
         （仅限 packet 边界）
```

**Stage 2 — VA (VC Allocation)，per-input-port**：

```
同一输入端口内 VC0/VC1 竞争发送

策略: VC0 优先于 VC1
（请求优先发送，避免响应占据链路导致新请求无法发出 → 防止链路层饥饿）
```

### 6.3 饥饿避免

```
问题: P0/P1 持续高优先级流量可能导致 P3 永久阻塞

解决:
  • 每个 P3 flit 记录等待计时器 (8-bit)
  • 等待超过阈值 64 cycles → 临时提升为 P2 (age-based 晋升)
  • 晋升后参与正常 P2 仲裁，传输完成后复位为 P3
  • 保证 P3 在最坏情况下每 64 cycles 至少获得一次发送机会
```

---

## 7. AXI4 网络接口 (NI)

### 7.1 NI 结构总览

```
┌─────────────────────────────────────────────────────────────────┐
│                    Network Interface (NI)                        │
│                                                                 │
│  ┌──────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐         │
│  │      │   │  Write    │   │  Flit     │   │          │         │
│  │ AXI  │──►│  Packer   │──►│  Sender   │──►│ Router   │         │
│  │      │   │ (AW+W→flit)│  │ (VC0)     │   │ Local    │         │
│  │ Mastr│   └──────────┘   └──────────┘   │ Input    │         │
│  │ (NPU)│                                 │          │         │
│  │      │   ┌──────────┐   ┌──────────┐   │          │         │
│  │      │   │  Read     │   │  Flit     │   │          │         │
│  │      │──►│  Packer   │──►│  Sender   │──►│          │         │
│  │      │   │ (AR→flit) │   │ (VC0)     │   │          │         │
│  │      │   └──────────┘   └──────────┘   │          │         │
│  │      │                                 │          │         │
│  │      │   ┌──────────┐   ┌──────────┐   │ Router   │         │
│  │      │◄──│  Write    │◄──│  Flit     │◄──│ Local    │         │
│  │      │   │  Unpacker │   │  Recer    │   │ Output   │         │
│  │      │   │ (flit→B) │   │ (VC1)     │   │          │         │
│  │      │   └──────────┘   └──────────┘   │          │         │
│  │      │                                 │          │         │
│  │      │   ┌──────────┐   ┌──────────┐   │          │         │
│  │      │◄──│  Read     │◄──│  Flit     │◄──│          │         │
│  │      │   │  Unpacker │   │  Recer    │   │          │         │
│  │      │   │ (flit→R) │   │ (VC1)     │   │          │         │
│  └──────┘   └──────────┘   └──────────┘   └──────────┘         │
│                                                                 │
│   NPU侧: AXI4 Master Interface           Router侧: 5-port Local │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Write Packer (AW + W → flit 序列)

```
状态机:
  IDLE ──► AW_REQ ──► W_DATA ──► WAIT_B ◄──
              │                     │       │
              │ AW handshake        │ last  │ B flit
              │捕获addr/id/len      │ W beat│ 回返
              ▼                     ▼       │
           构建Header flit       Send Body   │
           发送到VC0 FIFO       /Tail flit  │
                                    │       │
                                    ▼       │
                                  WAIT_B ───┘

Write Unpacker:
  VC1 接收 B flit ──► 提取 B 通道信号 (bid, bresp)
                     在 AXI Slave B 通道上应答 NPU
```

### 7.3 Read Packer (AR → flit 序列)

```
状态机:
  IDLE ──► AR_REQ ──► WAIT_R ◄──
              │          │        │
              │ AR       │ 收到    │ R last
              │ handshake│ Body/   │
              ▼          │ Tail    │
           构建Header   │ flit    │
           flit发送到   ▼        │
           VC0 FIFO    R通道组装 ──┘
                       返回AXI R

Read Unpacker:
  VC1 接收 R Body/Tail flits ──► 重组为 AXI R 通道
       RID匹配: src_id + axid 唯一标识响应
       支持 OOO (Out-of-Order): RID 独立返回
```

### 7.4 反压与 Credit 对接

```
NI 发送端反压:
  VC0 Flit Sender FIFO (深度 16)
  FIFO 满 → AXI AW/AR/W ready 拉低 → NPU 暂停发送

NI 接收端反压:
  VC1 Flit Receiver FIFO (深度 16)
  FIFO 空 (等待 R flit) → AXI R valid 拉低
  B flit 未到达 → AXI B valid 拉低
```

### 7.5 OOO 读响应管理

```
Read Tracker:
┌──────────────────────────────────────────┐
│  outstanding 读事务跟踪表 (深度 64 entry)  │
│                                          │
│  AR 发出时分配 entry:                     │
│    entry = {arid[7:0], seq[5:0]}         │
│    记录: arid, addr, len                 │
│                                          │
│  R flit 到达时匹配:                       │
│    按 src_id + axid 查找对应 entry        │
│    组装 R 通道返回 NPU                    │
│    R last 时释放 entry                   │
│                                          │
│  满 64 个 outstanding → AW/AR ready 拉低  │
└──────────────────────────────────────────┘
```

---

## 8. 死锁与活锁分析

### 8.1 死锁来源分析

| 类型 | 产生原因 | 本设计中的应对 |
|------|---------|---------------|
| 路由死锁 | 环状路径上的 flit 循环等待，依赖图成环 | XY 维序路由禁止 180° 转向，依赖图为 DAG → 无环 |
| 协议死锁 | 请求/响应在同一资源上相互等待 | VC0 请求 + VC1 响应独立虚网络，请求→响应单向依赖 |
| 缓冲死锁 | 下游 FIFO 满，上游持续发送 → 缓冲区溢出 | 逐跳 credit 反压，发送前检查 credit > 0 |

### 8.2 XY 路由无死锁证明

XY 路由禁止"回头"转向，packets 的转向为单调序列：

```
允许的转向:                禁止的转向:
  E→N  ✓ (先X后Y)          E→W  ✗ (回头)
  N→W  ✗ (不会出现)         N→S  ✗ (回头)

所有 packet 轨迹: X方向移动 → Y方向移动 → 到达
转向仅发生在 ΔX=0 时从 X 方向转入 Y 方向
转向图中不存在环 → 无路由死锁 (Dally & Seitz 定理)
```

### 8.3 VC 协议死锁避免

```
无VC场景: Agent A 向 Agent B 发写请求
  A: 等待 W data → B        B: 等待 B response → A
  若两者共用一个物理通道 → 相互等待 → 协议死锁

本设计 (2 VC):
  VC0 虚网络:    只承载请求 (AW/AR/W)
  VC1 虚网络:    只承载响应 (B/R)

  请求只在 VC0 中传输，响应只在 VC1 中传输
  VC0 传输不依赖 VC1 传输 (请求不需要响应完成即可发出)
  VC1 传输依赖请求到达 (响应由请求触发 → 单向依赖)
  → 依赖图无环 → 无协议死锁
```

### 8.4 活锁避免

XY 路由保证：

- 每一步严格减少 `|ΔX| + |ΔY|`
- 无可能绕路或停留在相同距离的节点
- 最大 hop 数 = 14（对角最远）
- 有限步内必然到达 → 无活锁

SA 仲裁饥饿防护：

- P3 超过 64 cycle 阈值 → 临时提升 P2
- 保证所有优先级都能在有限时间内获得服务

---

## 9. 带宽与时延分析

### 9.1 链路带宽

```
单链路带宽:
  BW_link = 512 bit × 500 MHz = 256 Gbps

有效带宽 (考虑Header开销):
  场景1: 单 beat 写 (1 body)
    发送: Hdr(512b) + Body(512b) = 1024b → 有效数据 = 512b
    效率 = 512/1024 = 50%

  场景2: 16-beat burst 写 (typical AXI burst)
    发送: Hdr(512b) + 16×Body(512b) = 8704b → 有效数据 = 8192b
    效率 = 8192/8704 ≈ 94.1%

  场景3: 256-beat burst (max AXI burst)
    发送: Hdr(512b) + 256×Body(512b) = 131584b → 有效数据 = 131072b
    效率 ≈ 99.6%
```

### 9.2 对分带宽

```
Bisection bandwidth = 8 条垂直 cut 的链路带宽总和
                     = 8 × 256 Gbps = 2.048 Tbps

最大注入率 (最远端对角交互):
  1 对对角线节点 (如 (0,0)→(7,7)): 14 hops
  若 32 对对角线同时传输，每 hop 承载多条流

热点分析:
  中心节点 (3~4, 3~4) 承载最多过境流量
  最坏情况: (3,4) 节点需承载 8×8 均匀随机流量的 ~25% 过境
```

### 9.3 零负载时延

```
Zero-load latency (无竞争):
  L_zl = L_ni_tx + hops × L_router + L_ni_rx

  其中:
    L_router  = 5 cycles (RC+VA+SA+ST+LT)
    L_ni_tx   = 2 cycles (打包)
    L_ni_rx   = 2 cycles (解包)
    hops      = 最短路径曼哈顿距离

  最近邻 (1 hop):  L_zl = 2 + 1×5 + 2 = 9 cycles = 18 ns
  对角线 (14 hops): L_zl = 2 + 14×5 + 2 = 74 cycles = 148 ns

  读事务: 地址路径 (→) + 数据路径 (←)
  最近邻读: 9 + 9 = 18 cycles = 36 ns
  对角线读: 74 + 74 = 148 cycles = 296 ns
```

### 9.4 饱和吞吐

```
饱和吞吐 (per node), injection rate:
  假设 random uniform traffic:

  每个节点 5 端口，4 个方向端口 + 1 个 local

  单节点最大注入率 (理论):
    λ_max = 链路带宽 / (吞吐因子 × 平均跳数)

  平均跳数 (8×8 mesh, uniform): ≈ 5.33 hops
  吞吐因子 (XY routing): ≈ 1.2 (考虑竞争损失)

  λ_max ≈ 256 Gbps / (1.2 × 5.33) ≈ 40 Gbps per node

  64 节点聚合带宽: 64 × 40 Gbps ≈ 2.56 Tbps (注入侧)
```

---

## 10. 实现与验证策略

### 10.1 技术栈与工具

| 类别 | 工具/标准 |
|------|----------|
| HDL | SystemVerilog (IEEE 1800) |
| 仿真 | Synopsys VCS 2018.09 |
| 波形 | Synopsys Verdi 2018.09 |
| 验证 | UVM 1.2 |
| 综合 (可选) | Design Compiler |

### 10.2 RTL 模块层次

```
noc_top
├── mesh_8x8 （generate 生成 64 tile）
│   └── noc_tile (×64)
│       ├── ni_axi4              // AXI4 网络接口
│       │   ├── ni_write_packer   // AW+W → flit
│       │   ├── ni_read_packer    // AR → flit
│       │   ├── ni_write_unpacker // flit → B
│       │   └── ni_read_unpacker  // flit → R
│       ├── router_5port         // 5端口路由器
│       │   ├── input_port (×5)  // 含 VC0/VC1 FIFO
│       │   ├── output_port (×5) // 含 credit 控制
│       │   ├── route_compute    // XY 路由计算
│       │   ├── vc_allocator     // VC 分配
│       │   ├── switch_allocator // 优先级仲裁+QoS
│       │   └── crossbar_5x5     // 5×5 交叉开关
│       └── link_ctrl            // 链路层 credit 收发
└── noc_config_pkg               // 参数化配置包
```

### 10.3 参数化配置

```systemverilog
// noc_config_pkg.sv
package noc_config_pkg;
  // Mesh 维度
  parameter int MESH_X    = 8;
  parameter int MESH_Y    = 8;

  // 链路参数
  parameter int DATA_W    = 512;
  parameter int NODE_ID_W = 6;   // $clog2(MESH_X*MESH_Y)

  // VC 参数
  parameter int VC_NUM    = 2;
  parameter int VC_DEPTH  = 8;

  // QoS 参数
  parameter int QOS_W     = 4;
  parameter int PRIO_LEVELS = 4;

  // Router pipeline
  parameter int PIPELINE_STAGES = 5;

  // NI 参数
  parameter int NI_FIFO_DEPTH   = 16;
  parameter int MAX_OUTSTANDING = 64;
endpackage
```

### 10.4 验证计划

#### 验证层次

**1. 单元级 (Unit Test)**

| 模块 | 验证内容 |
|------|---------|
| route_compute | 全坐标空间 XY 正确性 |
| switch_allocator | QoS 仲裁 + 饥饿避免 |
| ni_write_packer | AXI write → flit 转换 |
| ni_read_unpacker | flit → AXI read 重组 + OOO |
| credit_ctrl | 流控计数器正确性 |

**2. 模块级 (Module Test)**

| 模块 | 验证内容 |
|------|---------|
| router_5port | 5 方向定向测试、全方向负载测试 |
| ni_axi4 | AXI master BFM ↔ NI 闭环测试 |
| link_ctrl | credit 回传正确性 |

**3. Tile 级 (Tile Test)**

| 模块 | 验证内容 |
|------|---------|
| noc_tile | NPU BFM + NI + Router 集成测试 |

**4. 系统级 (System Test)**

| 场景 | 描述 |
|------|------|
| 均匀随机流量 | 64 NPU BFM 同时随机读写 |
| 热点流量 | 32 节点集中访问 1 个目标 |
| 对角线流量 | 32 对最远距离并发通信 |
| QoS 验证 | P0-P3 优先级 + 老化机制 |
| 压力测试 | 满注入率持续运行 100K cycles |

**5. UVM 测试框架**

```
├── noc_env              // NOC 验证环境
├── noc_scoreboard       // 注入/接收 flit 比对
├── noc_virtual_seq      // 多 NPU 并发序列
└── noc_coverage         // 功能覆盖率收集
```

### 10.5 验证 Checklist

```
┌────────────────────────────────────────────────────────┐
│  ✓ XY 路由正确性: 所有 64×64=4096 src-dst 对路径验证   │
│  ✓ Flit 完整性: Header→Body→Tail 序列无损传输          │
│  ✓ AXI 事务一致性: 注入 AXI ↔ 接收 flit ↔ 重组 AXI     │
│  ✓ OOO 读响应: 多 ID 交错返回正确匹配                  │
│  ✓ Credit 流控: 无溢出/无丢 flit                       │
│  ✓ FIFO 满/空 边界: 背压逐跳传播正确                   │
│  ✓ VC 隔离: 请求/响应不通VC互不干扰                    │
│  ✓ QoS 优先级: P0>P1>P2>P3 + 老化晋升                 │
│  ✓ 死锁安全: 长时间压力测试无死锁                       │
│  ✓ 边界节点: 边/角 router 端口关断正确                  │
└────────────────────────────────────────────────────────┘
```

### 10.6 综合门数估算

```
单 Router (粗略估算):
  • 5 个 Input Port (含 2 VC × 8 深 × 512b FIFO)
    = 5 × 2 × 8 × 512 = 40,960 bits FF ≈ 4K FF
  • 5×5 Crossbar ≈ 5×5×512 MUX ≈ 1.5K logic cells
  • RC + VA + SA 控制逻辑 ≈ 3K logic cells
  • 单 Router ≈ 4K FF + 5K comb ≈ ~50K gates

64 Router + 64 NI:
  ≈ 64 × (50K + 30K) ≈ 5.12M gates (粗略估计)

(具体值取决于综合工艺库和约束)
```

---

## 附录 A. Flit 总览

```
┌──────────┬──────────────────────────────────────────────────────┐
│ 类型      │ 格式 (512-bit total)                                 │
├──────────┼──────────────────────────────────────────────────────┤
│ Header   │ [coord:64][qos:4][srcdst_id:12][axinfo:192][resv:240]│
│ Body     │ [wstrb:64][data:446]                                  │
│ Tail     │ [wstrb:64][data:446]                                  │
│ Idle     │ all zeros                                             │
└──────────┴──────────────────────────────────────────────────────┘
```

## 附录 B. 术语表

| 术语 | 全称 | 说明 |
|------|------|------|
| NOC | Network-on-Chip | 片上网络 |
| NPU | Neural Processing Unit | 神经网络处理器 |
| NI | Network Interface | 网络接口，AXI4 ↔ flit 转换 |
| VC | Virtual Channel | 虚通道，逻辑上独立的缓冲区 |
| RC | Route Compute | 路由计算阶段 |
| VA | VC Allocation | 虚通道分配阶段 |
| SA | Switch Allocation | 交换分配/仲裁阶段 |
| ST | Switch Traversal | 交叉开关导通阶段 |
| LT | Link Traversal | 链路传输阶段 |
| OOO | Out-of-Order | 乱序（读响应） |
| XY | XY Dimension-Order Routing | XY 维序路由 |
| QoS | Quality of Service | 服务质量 |
