# loongarch-wine-kit

把一台 loongarch64 Linux 机器变成“能编译、能运行 **LoongArch64 原生 Wine**”的可复现工程。

产出：`loongarch64-windows` 的 PE（`clang --target=loongarch64-windows` + `lld-link`），
由原生 Wine 直接加载，**不经过任何 x86 指令翻译**。

已验证版本：Wine 10.14、Wine 11.16（`notepad`、`winecfg` 均能映射真实窗口）。

---

## 1. 前置条件

| 项 | 要求 |
| --- | --- |
| 机器 | **loongarch64 Linux**（Wine 的 unix 侧需本机链接，x86 上编不出来） |
| 实测环境 | Loongson-3A5000，4 核 / 16 GB / 35 GB 可用空间，Debian 10（kernel 4.19、16K 页） |
| 依赖 | `gcc g++ make ninja-build flex bison pkg-config python3 git`，X11 开发库（`libx11-dev libxext-dev libxrender-dev`） |
| CMake | ≥ 3.20（系统若只有 3.13，见 1.1 源码引导） |
| 磁盘 | LLVM 源码 + 构建约 25–30 GB，Wine 构建约 6 GB |
| 运行期 | Xorg（`DISPLAY=:0`）用于验证窗口 |

### 1.1 系统 CMake 太老时

LLVM 主线的 `cmake_minimum_required` 要求 ≥ 3.20，而 Debian 10 自带 3.13.4：

```bash
BASE=$HOME/cmake-boot && mkdir -p $BASE && cd $BASE
curl -sLO https://cmake.org/files/v3.28/cmake-3.28.6.tar.gz   # GitHub Release 在国内常不可达
tar xf cmake-3.28.6.tar.gz && cd cmake-3.28.6
./bootstrap --parallel=4 --prefix=$BASE/install > bootstrap.log 2>&1
make -j4 >> bootstrap.log 2>&1 && make install >> bootstrap.log 2>&1
$BASE/install/bin/cmake --version
```

4 核约 15–30 分钟。之后把 `$BASE/install/bin` 放进 `PATH`，或直接改 `env.sh` 的 `CMAKE`。

---

## 2. 目录结构

```text
loongarch-wine-kit/
├── env.sh                  # 所有路径/参数集中在这里（换机器只改这里）
├── README.md
├── MODIFICATIONS.md        # LLVM 13 个提交 + Wine 10.14/11.16 补丁逐项说明
├── CREDITS.md              # 本次工作的资源/积分消耗口径
├── crt/
│   ├── crt0.S              # PE 入口 mainCRTStartup（保存/恢复 $ra + .seh_*）
│   └── empty.S             # crtbegin/crtend 占位对象
├── patches/
│   ├── llvm/               # 13 个，git am 可直接应用
│   ├── wine/               # wine-10.14 基线（11 个）
│   └── wine-11.16/         # wine-11.16 基线（20 个，已验证）
└── scripts/
    ├── 01-build-llvm.sh    # 构建 LLVM/clang/lld，生成 cross 驱动包装
    ├── 02-install-crt.sh   # 生成最小 sysroot（CRT + 空壳导入库）
    ├── 03-deploy-toolchain.sh  # 多机时才需要，单机自动跳过
    ├── 04-build-wine.sh    # configure + make
    └── 05-verify.sh        # 冒烟验证（退出码 / printf / 窗口）
```

源码与构建目录默认在 `$WORK=$HOME/loongarch-wine`：

```text
$WORK/
├── llvm-project/
├── wine-11.16/            # 或 wine-10.14
├── build-llvm/
├── toolchain/             # clang/lld + sysroot/loongarch64-w64-mingw32
└── build-wine/
```

---

## 3. 快速开始（单机，5 步）

```bash
KIT=<本仓库路径>
export WORK=$HOME/loongarch-wine
mkdir -p $WORK

# 0) 准备源码
git clone --depth 1 https://github.com/llvm/llvm-project.git $WORK/llvm-project
git clone https://github.com/wine-mirror/wine.git $WORK/wine-11.16
git -C $WORK/wine-11.16 checkout wine-11.16

# 1) 应用补丁
git -C $WORK/llvm-project am $KIT/patches/llvm/*.patch
git -C $WORK/wine-11.16   am $KIT/patches/wine-11.16/*.patch

# 2) 依次执行脚本
$KIT/scripts/01-build-llvm.sh        # 数小时，务必后台跑
$KIT/scripts/02-install-crt.sh       # 秒级
$KIT/scripts/03-deploy-toolchain.sh  # TARGET_HOST 为空 -> 自动跳过
$KIT/scripts/04-build-wine.sh        # 1~2 小时
DISPLAY=:0 $KIT/scripts/05-verify.sh
```

Wine 10.14 同理，把第 0/1 步换成 `wine-10.14` 与 `patches/wine/`。

### 3.1 各步骤在做什么

| 步骤 | 内容 | 关键点 |
| --- | --- | --- |
| 01 | `cmake` 配置 + `ninja` 构建 `clang;lld`，只开 LoongArch 目标 | 生成 `$TOOLCHAIN/bin/loongarch64-w64-mingw32-clang` 包装，把 `--target` 与 `--sysroot` 固化进去 |
| 02 | 编译 `crt/crt0.S` → `crt2.o`；`empty.S` → `crtbegin.o`/`crtend.o`；生成 8 字节空壳 `lib*.a` | 空壳库只解决“文件找不到”，符号解析要用 Wine 构建产物 |
| 03 | `rsync` 工具链到目标机 | 仅当构建机 ≠ 运行机；两者同架构时单机即可 |
| 04 | `configure` + `make` | `configure` 靠名字找交叉编译器，必须把 `$TOOLCHAIN/bin` 放进 `PATH` |
| 05 | 跑 `t_exit`/`t_printf`，起 `winecfg`/`notepad` 并查窗口 | 任一项超时即判定失败（历史上对应两类卡死） |

---

## 4. 验证基线

| 用例 | 通过标准 |
| --- | --- |
| `t_exit` | 5 秒内退出，`rc=0` |
| `t_printf` | 5 秒内输出 `A B S C`，`rc=0` |
| `wineboot --init` | 正常结束，前缀目录生成 |
| `wine cmd /c ver` | 输出 `Microsoft Windows 10.0.x` |
| `winecfg` | 8 秒内出现 X 顶层窗口（标题含 `Wine`） |
| `notepad` | 同上 |

实测结果（Loongson-3A5000，Wine 11.16）：`wineboot` 返回 0，
`wine cfg` 输出 `Microsoft Windows 10.0.19045`，`notepad` 窗口 721x512，
`winecfg` 窗口 `Wine 设置` 477x608。

故障对照：`t_exit` 超时且 CPU 100% → CRT 的 `$ra` 没保存；
`t_printf` 超时 → 编译时漏了 `-D_UCRT`；
`wineboot` 报 `double free or corruption` → `loader.c` 路径缓冲区长度不足（已修）。

---

## 5. 新机器上最容易踩的 6 个坑

1. **sysroot 的 `lib*.a` 是 8 字节空壳**：真实导入库在 `$WINE_BUILD/dlls/*/lib*.a`，
   手工链接外部程序必须显式给全路径，否则一堆 `undefined symbol: __imp_xxx`。
2. **`COMPILER_RT_PE_LIBS` 为空** → `programs/xcopy` 报 `-lcompiler-rt`。
   源码层已修（`configure.ac`/`configure` 的 `*-mingw32` 分支），若仍为空说明
   `configure` 不是补丁后的版本；手工赋值**结尾不能有空格**，否则 makedep 匹配失败。
3. **CRT 入口必须保存/恢复 `$ra` 并带 `.seh_*`**，否则退出自旋、异常展开死循环。
4. **用 ucrtbase 的程序必须加 `-D_UCRT`**，否则 `FILE` 布局不匹配 →
   `STATUS_INVALID_HANDLE (c0000008)`。
5. **`.pdata` 必须按 RVA 排序**（lld 已补），否则异常分发查表失败。
6. **Wine 必须在 loongarch64 上构建**；x86 只能产出编译器工具链，产不出可运行的 Wine。

---

## 6. 版本与补丁矩阵

| Wine 基线 | 补丁目录 | 提交数 | 状态 |
| --- | --- | --- | --- |
| `wine-10.14` | `patches/wine/` | 11 | 已验证（winecfg/notepad、性能基准） |
| `wine-11.16` | `patches/wine-11.16/` | 20 | 已验证（构建、安装、winecfg/notepad） |

11.16 相比 10.14 需要额外处理：`get_thread_ldt_entry` 原型变更、
`NtSetLdtEntries` 迁到 `virtual.c`、新增 `libs/symcrypt`、C++ 模块（`vcruntime140`/
`msvcp140`/`concrt140`）在 loongarch64 下禁用、`sqlite3` 的 `__int128` 判断、
128 位 `long double` 内建函数、`loader.c` 路径缓冲区长度。
详见 `MODIFICATIONS.md` 第 8 节。

---

## 7. 已知限制（未完成）

- 后台服务忙等：`services`/`winedevice`/`rpcss`/`plugplay` 空闲时各占满一个核；
- `dlls/rsaenh` 链接 `libtomcrypt.a` 报重定位错误；
- C++ 异常（`-fexceptions`）与 MSVC C++ ABI 不可用（相关模块已禁用）；
- 32 位 / WoW64 链路未开始。

---

## 8. 参考

- 完整问题记录：`../wine-loongarch编译问题记录.md`
- 改动明细：`MODIFICATIONS.md`
- 资源消耗口径：`CREDITS.md`
