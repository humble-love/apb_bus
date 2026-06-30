# VCS + UVM 环境搭建问题与解决

## 环境信息

| 组件 | 版本 |
|------|------|
| VCS | O-2018.09-SP2 |
| Verdi | O-2018.09-SP2 |
| OS | Ubuntu 24.04 (WSL2) |
| glibc | 2.34+ |
| 默认 Shell | /bin/sh → dash |

---

## 问题 1：VCS 2018 与 dash 不兼容

### 现象

```
/bin/sh: 0: Illegal option -f
```

VCS 2018 内部脚本调用 `/bin/sh -f`，但 WSL2 下 `/bin/sh` 链接到 `dash`，dash 不支持 `-f` 选项。

### 解决

在 `compile.sh` 中使用 `bwrap` 将 `/bin/bash` 映射到 `/usr/bin/dash`，让 VCS 内部使用 bash：

```bash
if [ "$(readlink -f /bin/sh)" = "/usr/bin/dash" ]; then
    bwrap --bind / / --dev /dev --bind /bin/bash /usr/bin/dash bash -c "
        export VCS_HOME=\"$VCS_HOME\"
        export PATH=\"$VCS_HOME/bin:\$PATH\"
        vcs ...
    "
else
    vcs ...
fi
```

注意：`bwrap` 内的环境变量需要重新 export，因为 bubblewrap 创建了新的执行环境。

---

## 问题 2：glibc 2.34+ 移除 pthread_yield

### 现象

```
simv: symbol lookup error: undefined symbol: pthread_yield
```

### 原因

glibc >= 2.34 移除了 `pthread_yield` 符号。VCS 2018 编译生成的可执行文件运行时依赖此符号。

### 解决

创建 `pthread_yield_compat.c` shim：

```c
#include <sched.h>

int pthread_yield(void) {
    return sched_yield();
}
```

编译为 `.o` 并在 VCS 链接阶段加入：

```bash
gcc -c pthread_yield_compat.c -o pthread_yield_compat.o
# VCS 命令中加入 pthread_yield_compat.o 作为链接对象
```

---

## 问题 3：Verdi 2018 缺少 libpng12

### 现象

```
verdi: error while loading shared libraries: libpng12.so.0:
  cannot open shared object file: No such file or directory
```

### 原因

Ubuntu 24.04 已升级到 libpng16，不再提供 libpng12 共享库。

### 解决

1. 从旧版 Ubuntu 或 Synopsys 安装包中获取 `libpng12.so.0`
2. 放置到固定路径（如 `/home/openclaw/hardware/Synopsys/libpng12.so.0`）
3. 在 `verdi.sh` 中设置 `LD_LIBRARY_PATH`：

```bash
export LD_LIBRARY_PATH="\
  $VERDI_HOME/share/PLI/VCS/linux64:\
  /path/to/libpng12/compat:\
  $LD_LIBRARY_PATH"
```

---

## 问题 4：UVM 文件缺少 import/include

### 现象

```
Error: Unknown base class 'uvm_env'
Error: Unknown base class 'uvm_agent'
Error: Unknown base class 'uvm_driver'
...
```

### 原因

VCS 按 `filelist.f` 中的文件列表逐个编译。每个文件作为独立的编译单元，如果没有显式 import，则找不到 UVM 基类定义。这与在 package 文件中统一 include 的用法不同。

### 解决

在每个 `.sv` 文件头部显式添加：

```systemverilog
import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_pkg::*;
```

### 涉及文件

- `tb/apb_env.sv`
- `tb/apb_master_agent.sv`
- `tb/apb_master_driver.sv`
- `tb/apb_master_monitor.sv`
- `tb/apb_scoreboard.sv`
- `tb/apb_test.sv`
- `tb/sequence_lib.sv`

---

## 问题 5：VCS 2018 依赖 dc（desk calculator）

### 现象

VCS 内部脚本在分析阶段静默失败或行为异常。

### 原因

VCS 2018 某些内部流程依赖 `dc` 工具做数值计算，而 Ubuntu 默认不安装 `dc`。

### 解决

在 `compile.sh` 中确保 `dc` 在 PATH 中：

```bash
if [ -x "$HOME/.local/bin/dc" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
```

也可以通过 `apt install dc` 安装。

---

## 问题 6：许可证变量未设置

### 现象

```
Failed to obtain license...
```

### 原因

Synopsys 工具需要 `LM_LICENSE_FILE` 和 `SNPSLMD_LICENSE_FILE` 环境变量指向许可证服务器。

### 解决

在 `compile.sh`、`run.sh`、`verdi.sh` 中统一设置：

```bash
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@<license-host>}
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-27000@<license-host>}
```

用户可通过环境变量覆盖默认值。

---

## 问题 7：FSDB 波形 dumper 库路径

### 现象

运行 `simv` 时 `$fsdbDumpfile` 调用失败，无波形文件生成。

### 原因

Verdi PLI 库不在 `LD_LIBRARY_PATH` 中，导致 FSDB dumper 无法加载。

### 解决

在 `run.sh` 中设置：

```bash
export LD_LIBRARY_PATH="$VERDI_HOME/share/PLI/VCS/linux64:$LD_LIBRARY_PATH"
```

---

## 脚本修改速查

| 文件 | 修改内容 |
|------|---------|
| `scripts/compile.sh` | `dc` PATH、bwrap dash 绕行、license 变量、VCS/VERDI HOME 默认值、pthread_yield_compat.o 链接 |
| `scripts/run.sh` | FSDB `LD_LIBRARY_PATH`、license 变量 |
| `scripts/verdi.sh` | `VERDI_HOME` PATH、license、libpng12 `LD_LIBRARY_PATH` |
| `pthread_yield_compat.c` | 新建 glibc 兼容 shim |
| `tb/*.sv` | 每个文件 head 添加 UVM import/include |
