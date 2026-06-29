# APB3 快速操作手册

## 一、快速跑用例

### 编译（只需一次，改完代码后重新编译）

```bash
make compile
```

### 运行

```bash
make run TEST=apb_sanity_test
```

不指定 TEST 默认跑 `apb_sanity_test`。可用用例：

| 命令 | 内容 |
|------|------|
| `make run TEST=apb_sanity_test` | 基础读写 + GPIO W1C 验证 |
| `make run TEST=apb_random_test` | 20 次随机事务 |
| `make run TEST=apb_burst_test` | 连续 10 次背靠背读写 |
| `make run TEST=apb_error_test` | 访问未映射地址，触发错误响应 |

### 查看结果

仿真结束后直接看 log：
```bash
grep -E "PASS|ERROR|FATAL" sim.log
```

---

## 二、如何更改/新增用例

### 改现有 sequence

编辑 `tb/sequence_lib.sv`，找到对应的 sequence 类，改 `body()` task 里的内容。

例如 `apb_sanity_seq` 的 body()：
```systemverilog
task body();
    bit [31:0] rd;
    write(32'h0000_0000, 32'hDEAD_BEEF);   // 写地址 数据
    read (32'h0000_0000, rd);               // 读回验证
endtask
```

基类 `apb_base_sequence` 提供了 `write(addr, data)` 和 `read(addr, data)` 两个 helper task，直接调用即可。

### 新增 sequence

在 `tb/sequence_lib.sv` 中新增一个类，继承 `apb_base_sequence`：

```systemverilog
class my_custom_seq extends apb_base_sequence;
    `uvm_object_utils(my_custom_seq)

    function new(string name = "my_custom_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] rd;
        `uvm_info("SEQ", "My custom sequence started", UVM_LOW)
        write(32'h0000_0000, 32'h1234_5678);
        read (32'h0000_0000, rd);
        `uvm_info("SEQ", "My custom sequence done", UVM_LOW)
    endtask
endclass
```

### 新增 test（注册到 UVM）

在 `tb/apb_test.sv` 中新增一个 test 类：

```systemverilog
class my_custom_test extends apb_base_test;
    `uvm_component_utils(my_custom_test)

    function new(string name = "my_custom_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        my_custom_seq seq;
        phase.raise_objection(this);
        seq = my_custom_seq::type_id::create("seq");
        seq.start(env.agent_m0.sequencer);
        #100;
        phase.drop_objection(this);
    endtask
endclass
```

改完后重新编译再运行：
```bash
make compile && make run TEST=my_custom_test
```

### 地址空间

| 地址范围 | Slave |
|----------|-------|
| `0x0000_0000 - 0x0000_0FFF` | Memory (256×32) |
| `0x0000_1000 - 0x0000_1FFF` | GPIO 寄存器 |

GPIO 寄存器偏移：`0x00` DATA, `0x04` DIR, `0x08` INT_EN, `0x0C` INT_STATUS

### 随机约束

随机测试的约束在 `tb/apb_pkg.sv` 的 `apb_transaction` 类中，修改约束条件即可控制随机范围。

---

## 三、查看波形

```bash
make verdi
```

Verdi 打开后自动加载 `waves/apb.fsdb` 和全部源码。

### 关键信号

在 Verdi 中按 `Ctrl+W` 添加信号到波形窗口：

| 信号 | 含义 |
|------|------|
| `pclk`, `presetn` | 时钟和复位 |
| `req_0`, `gnt_0` | Master 请求/授予 |
| `paddr`, `pwdata`, `prdata` | 地址、写数据、读数据 |
| `pwrite` | 1=写, 0=读 |
| `psel`, `penable` | 传输阶段: IDLE→SETUP(psel)→ACCESS(penable)→IDLE |
| `pready` | Slave 就绪（低=stall） |
| `psel_slv[1:0]` | 各 slave 片选 |

### 常用操作

- `Ctrl+W` — 添加信号
- 鼠标滚轮 — 缩放时间轴
- 中键拖拽 — 平移
- 双击信号 — 跳到源码

---

## 四、清理

```bash
make clean
```

删除所有生成文件（simv、log、波形等），保留源码和脚本。
