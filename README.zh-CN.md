# loongarch-wine-kit

[English](README.md) | **简体中文**

在 **LoongArch64 Linux** 上原生运行 Wine 的可复现工具链与构建流程，不依赖 x86 模拟或二进制翻译。

本工程把一台普通的 loongarch64 机器变成可编译 `loongarch64-windows` PE 程序、
并由原生 LoongArch 版 Wine 直接加载的环境。

| 项目 | 内容 |
| --- | --- |
| 目标三元组 | `loongarch64-windows`（`IMAGE_FILE_MACHINE_LOONGARCH64`，`0x6264`） |
| 工具链 | LLVM/Clang + LLD，面向 LoongArch PE |
| Wine 版本 | 10.14、11.16 |
| 验证环境 | Loongson-3A5000，4 核 / 16 GB，Debian 10，kernel 4.19（16 KB 页） |
| 验证项 | `wineboot`、`wine cmd /c ver`、`winecfg`、`notepad` |

---

## 1. 为什么需要这套工具链

上游 LLVM 不支持为 LoongArch 生成 Windows PE，上游 Wine 也没有 LoongArch 后端。
本工程补齐了三个层次：

| 层次 | 内容 |
| --- | --- |
| LLVM（13 个提交） | MC 层 COFF 写出、LLD COFF 链接、导入 thunk、`.pdata` 排序、PE unwind 编码、Windows 目标信息 |
| mingw CRT | 最小 `mainCRTStartup`，保存/恢复 `$ra` 并携带 `.seh_*` 展开信息 |
| Wine（11 / 20 个提交） | 构建系统、信号与上下文、栈展开与 `__C_specific_handler`、PE 运行期修复 |

逐提交说明见 [MODIFICATIONS.md](MODIFICATIONS.md)。

---

## 2. 环境要求

| 项目 | 要求 |
| --- | --- |
| 构建机 | **loongarch64 Linux**（Wine 需链接本机 unix 侧目标文件，x86 上无法交叉构建） |
| 依赖包 | `gcc g++ make ninja-build flex bison pkg-config python3 git`，X11 开发库（`libx11-dev libxext-dev libxrender-dev`） |
| CMake | ≥ 3.20（发行版过旧时见 §2.1） |
| 磁盘 | LLVM 源码与构建 25–30 GB，Wine 构建约 6 GB |
| 显示 | 验证图形步骤需要 Xorg，`DISPLAY=:0` |

### 2.1 引导新版 CMake

Debian 10 自带 CMake 3.13.4，低于 LLVM 要求：

```bash
BASE=$HOME/cmake-boot && mkdir -p "$BASE" && cd "$BASE"
curl -sLO https://cmake.org/files/v3.28/cmake-3.28.6.tar.gz
tar xf cmake-3.28.6.tar.gz && cd cmake-3.28.6
./bootstrap --parallel=4 --prefix="$BASE/install" > bootstrap.log 2>&1
make -j4 >> bootstrap.log 2>&1
make install >> bootstrap.log 2>&1
export PATH="$BASE/install/bin:$PATH"
```

4 核约 15–30 分钟。

---

## 3. 目录结构

```text
loongarch-wine-kit/
├── env.sh                     # 所有路径与参数集中在此
├── README.md                  # 英文版
├── README.zh-CN.md            # 本文件
├── MODIFICATIONS.md           # 每项改动的逐提交说明
├── CREDITS.md                 # 工作量与资源口径
├── crt/
│   ├── crt0.S                 # PE 入口：保存 $ra，携带 .seh_* 展开信息
│   └── empty.S                # crtbegin.o / crtend.o 占位
├── patches/
│   ├── llvm/                  # llvm-project 补丁 13 个
│   ├── wine/                  # wine-10.14 补丁 11 个
│   └── wine-11.16/            # wine-11.16 补丁 20 个
└── scripts/
    ├── 01-build-llvm.sh
    ├── 02-install-crt.sh
    ├── 03-deploy-toolchain.sh
    ├── 04-build-wine.sh
    └── 05-verify.sh
```

工作目录默认 `$WORK=$HOME/loongarch-wine`：

```text
$WORK/
├── llvm-project/
├── wine-11.16/            # 或 wine-10.14
├── build-llvm/
├── toolchain/             # clang、lld、sysroot/loongarch64-w64-mingw32
└── build-wine/
```

---

## 4. 快速开始（单机）

```bash
KIT=/path/to/loongarch-wine-kit
export WORK=$HOME/loongarch-wine && mkdir -p "$WORK"

# 1. 获取源码
git clone --depth 1 https://github.com/llvm/llvm-project.git "$WORK/llvm-project"
git clone https://github.com/wine-mirror/wine.git "$WORK/wine-11.16"
git -C "$WORK/wine-11.16" checkout wine-11.16

# 2. 应用补丁
git -C "$WORK/llvm-project" am "$KIT"/patches/llvm/*.patch
git -C "$WORK/wine-11.16"   am "$KIT"/patches/wine-11.16/*.patch

# 3. 构建（步骤 01 耗时数小时，请在 nohup/screen 中执行）
"$KIT"/scripts/01-build-llvm.sh
"$KIT"/scripts/02-install-crt.sh
"$KIT"/scripts/03-deploy-toolchain.sh    # TARGET_HOST 为空时自动跳过
"$KIT"/scripts/04-build-wine.sh
DISPLAY=:0 "$KIT"/scripts/05-verify.sh
```

使用 Wine 10.14 时改用 `patches/wine/`，并设置 `WINE_SRC=$WORK/wine-10.14`。

### 4.1 各步骤说明

| 步骤 | 内容 | 要点 |
| --- | --- | --- |
| 01 | 仅启用 LoongArch 目标，构建 `clang;lld` | 安装 `loongarch64-w64-mingw32-clang` 包装脚本，内置 `--target` 与 `--sysroot` |
| 02 | `crt0.S` → `crt2.o`，`empty.S` → `crtbegin.o`/`crtend.o`，生成空壳导入库 | 空壳库为 8 字节归档，仅用于满足 `-lxxx`，真实符号来自 Wine 构建产物 |
| 03 | 将工具链同步到目标机 | 仅构建机与运行机分离时需要 |
| 04 | `configure` + `make` | 必须把 `$TOOLCHAIN/bin` 加入 `PATH`，`configure` 通过名字识别交叉编译器 |
| 05 | 退出码与标准输出用例，再检查 `winecfg`/`notepad` 窗口 | 任一项超时即失败，对应历史上两类卡死 |

---

## 5. 验证基线

| 用例 | 通过标准 |
| --- | --- |
| `t_exit` | 5 秒内退出，`rc=0` |
| `t_printf` | 5 秒内输出 `A B S C`，`rc=0` |
| `wineboot --init` | 正常结束并生成前缀目录 |
| `wine cmd /c ver` | 输出 `Microsoft Windows 10.0.x` |
| `winecfg` | 8 秒内出现 X 顶层窗口 |
| `notepad` | 同上 |

实测（Loongson-3A5000，Wine 11.16）：`wineboot` 返回 0，
`wine cmd /c ver` 输出 `Microsoft Windows 10.0.19045`，
`notepad` 窗口 721×512，`winecfg` 窗口 `Wine 设置` 477×608。

### 5.1 现象与原因对照

| 现象 | 可能原因 |
| --- | --- |
| `t_exit` 卡死且 CPU 100% | `mainCRTStartup` 未保存 `$ra`，返回地址自指 |
| `t_printf` 卡死 | 编译时缺少 `-D_UCRT`，`FILE` 布局不匹配 |
| `wineboot` 报 `double free or corruption` | `ntdll/unix/loader.c` 路径缓冲区按 `/aarch64-windows` 估算长度 |
| 链接报 `undefined symbol: __imp_*` | 使用了空壳 `lib*.a`，应链接 `$WINE_BUILD/dlls/*/lib*.a` |
| 链接报 `unable to find library -lcompiler-rt` | `COMPILER_RT_PE_LIBS` 为空，`configure` 不是补丁后的版本 |

---

## 6. 支持的版本

| Wine 基线 | 补丁目录 | 提交数 | 状态 |
| --- | --- | --- | --- |
| `wine-10.14` | `patches/wine/` | 11 | 已验证：窗口、控制台用例、性能基准 |
| `wine-11.16` | `patches/wine-11.16/` | 20 | 已验证：构建、安装、`winecfg`/`notepad` |

11.16 的额外改动：LDT 原型更新、删除重复的 `NtSetLdtEntries`、SymCrypt 通用路径、
loongarch64 下禁用 C++ ABI 模块（`vcruntime140`、`msvcp140`、`concrt140`）、
`sqlite3` 的 `__int128` 分支、128 位 `long double` 内建函数、`loader.c` 缓冲区长度。
详见 [MODIFICATIONS.md](MODIFICATIONS.md) 第 8 节。

---

## 7. 当前限制

- 后台服务忙等：`services`、`winedevice`、`rpcss`、`plugplay` 空闲时各占满一个核；
- `dlls/rsaenh` 链接 `libtomcrypt.a` 报重定位错误；
- 不支持 C++ 异常与 MSVC C++ ABI，相关模块在 loongarch64 下已禁用；
- 32 位 / WoW64 链路尚未开始。

---

## 8. 参考

- 完整问题记录（中文）：`../wine-loongarch编译问题记录.md`
- 改动明细：[MODIFICATIONS.md](MODIFICATIONS.md)
- 资源消耗口径：[CREDITS.md](CREDITS.md)

## 9. 许可

本仓库的脚本与文档采用 MIT 许可。`patches/` 下的补丁分别派生自 Wine
（LGPL-2.1-or-later）与 LLVM（Apache-2.0 WITH LLVM-exception），保持上游许可。
