# 改动清单（相对上游）

> **Abstract (EN)** — Every change required to run Wine natively on LoongArch64 is
> confined to three trees: `llvm-project` (13 commits: COFF/PE codegen, LLD COFF
> backend, driver and Windows target info), `wine` (11 commits on the 10.14
> baseline, 20 on the 11.16 baseline: build system, signal/context, unwinding,
> PE loading and runtime fixes), and a hand-written mingw CRT entry point.
> See §8 for the Wine 11.16 delta.

本工程把 LoongArch64 原生 Wine 所需的全部改动收敛到三个仓库：

| 仓库 | 基线 | 提交数 | 规模 | 补丁目录 |
| --- | --- | --- | --- | --- |
| `llvm-project` | `4497566c7`（libc 上游提交） | 13 | 后端 + lld + 驱动 | `patches/llvm/` |
| `wine-10.14` | `8448e6d`（Baseline: Wine 10.14 upstream source） | 11 | 66 文件，+4268/−54 | `patches/wine/` |
| `wine-11.16` | `5e99426`（Wine 11.16 upstream） | 20 | 构建 + 运行期修复 | `patches/wine-11.16/` |
| `mingw64-loongarch64` | 无上游 | — | `crt/crt0.S`、`crt/empty.S` | 源码随工程保存 |

应用方式：

```bash
git -C llvm-project   am patches/llvm/*.patch
git -C wine-10.14     am patches/wine/*.patch
```

---

## 1. LLVM：LoongArch 的 COFF/PE 能力

上游 LoongArch 后端只输出 ELF，Windows 目标完全不可用。按依赖顺序补齐：

| # | 提交 | 作用 |
| --- | --- | --- |
| 1 | `Add MC layer COFF object writer support` | `WinCOFFObjectWriter` 接受 LoongArch，输出 COFF 节/重定位 |
| 2 | `Add COFF linker (lld) support` | `IMAGE_FILE_MACHINE_LOONGARCH64` 识别、`is64Bit`、机器码映射 |
| 3 | `Add mingw/PE driver support` | clang 驱动支持 `-target loongarch64-windows`、`--sysroot`、lld 链接 |
| 4 | `Allow loongarch64 objects in llvm-lib / lld-link /lib` | 静态库工具链打通 |
| 5 | `Add COFF import thunk support` | 导入库 thunk（`__imp_` 跳转桩） |
| 6 | `Sort .pdata entries in lld COFF linker` | 异常表按 RVA 排序，否则运行期查表失败/告警 |
| 7 | `Emit .pdata/.xdata for leaf PE functions` | 叶子函数生成展开信息 |
| 8 | `Emit and encode PE unwind codes` | LoongArch unwind code 编码器 |
| 9 | `Emit PE epilogue ranges and chained unwind info` | epilogue 范围 + CHAININFO |
| 10 | `Support implicit COFF addends and CALL36 relocations` | COFF 隐式加数、`CALL36` 等重定位 |
| 11 | `Add Windows target info for loongarch64` | clang TargetInfo：数据模型、ABI、预定义宏 |
| 12 | `Fall back to close() when sigprocmask is rejected` | 兼容只支持 `pthread_sigmask` 的 glibc，避免构建/运行中断 |
| 13 | `Emit PE unwind info for all non-leaf frames` | 非叶子帧也生成 `.pdata/.xdata`（与 Wine 侧展开实现对齐） |

关键约束（踩过的坑）：

- 直接开 COFF 会因 linker relaxation 分支未处理空符号而在 `WinCOFFObjectWriter` 崩溃 → 必须先加格式判断守卫。
- `.pdata` 不排序时 lld 只告警不报错，问题会推迟到异常分发时才暴露。
- 非叶子帧的 unwind 编码若与 Wine 侧 `RtlVirtualUnwind2` 解码不一致，异常会静默展开失败。

## 2. lld / 链接层的三个必要条件

`IMAGE_FILE_MACHINE_LOONGARCH64` 需要在三处同时补：Magic 识别、`is64Bit` 判断、机器码映射；
漏一处会表现为 “unknown file type” 或链接成功但 PE 头部机器码错误。

## 3. mingw-w64 CRT 入口（`crt/crt0.S`）

上游没有 loongarch64-windows 的 CRT 启动代码，Wine 构建出的 PE 无法正确退出。

- 早期兜底写法 `bl main; ret`：`bl` 覆盖 `$ra`，`ret` 跳回自身 → 进程 100% 自旋；
  同时该帧无 `.seh_*`，异常经过时 `RtlVirtualUnwind2` 的叶子分支取 `Pc = $ra`，
  展开链不前进，表现为“退出卡死”。
- 修正后：栈上保存/恢复 `$ra`，补齐 `.seh_proc/.seh_stackalloc/.seh_savereg/.seh_endproc`。
- 退出码由 `$a0` 传递：`BaseThreadInitThunk` 即 `RtlExitUserThread(entry(arg))`。

## 4. Wine：10 个提交、66 个文件

### 4.1 构建系统与工具

`configure.ac`、`tools/winebuild/*`、`tools/winegcc/winegcc.c`、`tools/widl/typegen.c`、
`tools/tools.h`、`dlls/*/Makefile.in`：

- `HOST_ARCH=loongarch64`、`--enable-archs` 白名单、cross CC 探测（`loongarch64-w64-mingw32-clang`）；
- `arm|aarch64` 的“必须交叉编译 PE”分支扩展到 `loongarch64`；
- winebuild 生成 LoongArch PE thunk / 导入表；winegcc 传递目标三元组。

### 4.2 运行时核心

| 文件 | 改动 |
| --- | --- |
| `dlls/ntdll/unix/signal_loongarch64.c` | 1.5k 行：信号栈、上下文切换、`call_seh_handlers` |
| `dlls/ntdll/signal_loongarch64.c` | 951 行：PE 侧异常/上下文处理 |
| `dlls/ntdll/unwind.c` | `RtlVirtualUnwind2` 的 LoongArch 分支（含叶子/非叶子、epilogue、CHAININFO） |
| `dlls/ntdll/unix/dwarf.h`、`unix_private.h` | DWARF 寄存器映射、`__C_specific_handler` 声明 |
| `dlls/ntdll/sync.c`、`unix/system.c`、`unix/virtual.c`、`unix/loader.c` | 架构相关分支 |
| `dlls/win32u/syscall.c` | 系统调用桩 |
| `dlls/winecrt0/setjmp.c`、`include/msvcrt/setjmp.h` | `setjmp/longjmp` 上下文 |
| `dlls/vcomp/fork.c` | 浮点环境（FPIEEE）处理 |
| `include/winnt.h`、`include/wine/asm.h`、`include/wine/exception.h`、`include/basetsd.h`、`include/minwindef.h`、`include/msvcrt/corecrt.h` | 架构宏、CONTEXT 布局、函数修饰 |
| `dlls/rpcrt4/{ndr_stubless,ndr_typelib,thunks}.c` | 调用约定与 thunk |
| `dlls/setupapi/{devinst,dirid,fakedll}.c`、`dlls/winspool.drv/info.c`、`programs/winecfg/libraries.c`、`server/{object,registry}.c` | 目标平台差异 |
| `libs/png/Makefile.in` | 构建修正 |

### 4.3 运行期约定

- 返回码位于 `$a0`；参数按 LoongArch ABI（`$a0-$a7`、`$fa0-$fa7`）。
- 手写汇编帧必须带 `.seh_*`，否则异常穿过时自旋（与 CRT 入口同一类问题）。

## 5. 构建配置修复（`configure.ac` + 生成的 `configure`）

| 问题 | 原因 | 修法 |
| --- | --- | --- |
| `COMPILER_RT_PE_LIBS` 为空 → `xcopy` 报 `unable to find library -lcompiler-rt` | llvm-mingw 风格交叉编译器叫 `loongarch64-w64-mingw32-clang`，configure 从名字反推出 `*-mingw32` 三元组，而判断条件只认 `*-windows`，于是 `wine_compiler_rt_libs` 从未被赋值 | 在 `configure.ac` 的 `case "$target"` 里补 `*-mingw32` 分支，并同步修改已入库的生成脚本 `configure`（本地 autoconf 为 2.72、仓库内 `configure` 由 2.71 生成，重新生成会产生大量无关差异） |
| `libs/png/Makefile.in` 缺 LSX 开关 | LoongArch 后端不支持 ARM NEON 宏的假设 | `EXTRADEFS` 增加 `-DPNG_LOONGARCH_LSX_OPT=0` |

验证：重新执行 configure 后 `Makefile` 中 `COMPILER_RT_PE_LIBS = compiler-rt`，
`xcopy.exe` 链接命令行出现 `libs/compiler-rt/loongarch64-windows/libcompiler-rt.a`，重新链接成功。

**这类修改必须同时落在 `configure.ac` 和 `configure`**：只改构建目录里的 `Makefile`
会在下一次 configure 时被覆盖（本次 `build3` 就是这样丢掉了早期的手工赋值，转而报
`-lcompiler-rt`）。

## 6. 本次应用层修复（不在仓库内）

| 项 | 说明 |
| --- | --- |
| 测试程序缺 `-D_UCRT` | `FILE` 结构来自 msvcrt、格式化函数来自 ucrtbase → `STATUS_INVALID_HANDLE` → 展开自旋。所有用 ucrtbase 的程序必须带 `-D_UCRT` |
| sysroot 的 `lib*.a` 是 8 字节空壳 | 真实导入库要用 Wine 构建产物 `dlls/*/lib*.a`，链接时显式给全路径 |

## 7. 已知遗留

- 原生链路 `services.exe` / `winedevice.exe` / `rpcss.exe` / `plugplay.exe` 空闲时各占满一个核（忙等），见文档 4.9.5。
- `dlls/rsaenh` 链接 `libtomcrypt.a` 报重定位错误，尚未修。
- C++ 异常（`-fexceptions`）在 LoongArch COFF 上仍不可用。
- 32 位（`win32` / WoW64）链路未开始。

## 8. Wine 11.16 升级（2026-11-06）

基线 `wine-11.16`（上游 `5e99426`），重放 10.14 的 LoongArch 补丁并适配 11.x API，
共 20 个提交，补丁在 `patches/wine-11.16/`。构建、安装、窗口验证均在龙芯机上完成。

| 问题 | 修复 |
| --- | --- |
| `get_thread_ldt_entry` 原型变更、`NtSetLdtEntries` 迁到 `virtual.c` | 更新原型，删除旧实现避免重复定义 |
| 新增 `libs/symcrypt` 无 LoongArch 分支 | 走通用平台路径 |
| `vcruntime140/new.cpp` 的 `operator new` 类型不匹配（LP64 的 `size_t` 为 `unsigned long`） | loongarch64 下禁用 C++ 模块；正解是 clang 的 `SizeType = unsigned long long`（已提交，待重建部署） |
| `sqlite3.c` 使用 ARM64 的 `__umulh` | `SQLITE_USE_UINT128` 判断加入 `__loongarch__` |
| 链接缺 `__floatunsitf`/`__multf3`/`__addtf3` | 引入 18 个 `tf` 内建源文件与依赖头到 `libs/compiler-rt` |
| `wineboot` 报 `double free or corruption` | `loader.c` 路径缓冲区按 `sizeof("/aarch64-windows")` 估算，`loongarch64-windows` 更长导致越界，改为实际长度 |

验证：`make`/`make install` 成功；`wineboot --init` 正常；`wine cmd /c ver` 输出
`Microsoft Windows 10.0.19045`；`notepad`（721x512）与 `winecfg`（`Wine 设置` 477x608）
均映射真实窗口。
