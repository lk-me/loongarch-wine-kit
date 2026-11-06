#!/usr/bin/env bash
# 步骤 2：准备最小 mingw sysroot，并安装 CRT 入口对象
#
# 背景（见 MODIFICATIONS.md 第 3 节）：LLVM 的 loongarch64-windows 目标没有可用的
# mingw CRT 启动代码，早期用 "bl main; ret" 兜底，导致 $ra 自指、进程退出即自旋。
# 这里编译修正后的 crt0.S，并补齐 sysroot 里的占位导入库。

source "$(dirname "$0")/../env.sh"

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CRT_DIR="$WORK/mingw64-loongarch64/crt"
[ -f "$CRT_DIR/crt0.S" ] || CRT_DIR="$KIT_DIR/crt"
[ -f "$CRT_DIR/crt0.S" ] || { echo "缺少 crt0.S（$WORK/mingw64-loongarch64/crt 或 $KIT_DIR/crt）"; exit 1; }

mkdir -p "$SYSROOT/include" "$SYSROOT/lib"

# 1) CRT 入口与 crtbegin/crtend 占位
"$CC_PE" -c "$CRT_DIR/crt0.S"  -o "$SYSROOT/lib/crt2.o"
"$CC_PE" -c "$CRT_DIR/empty.S" -o "$SYSROOT/lib/crtbegin.o"
"$CC_PE" -c "$CRT_DIR/empty.S" -o "$SYSROOT/lib/crtend.o"

# 2) 8 字节空壳导入库：只用于让 -lkernel32 之类的参数能找到文件，
#    真正的符号解析走 Wine 构建产物 build/dlls/*/lib*.a
for lib in advapi32 gcc gcc_eh kernel32 mingw32 mingwex moldname msvcrt shell32 user32; do
  rm -f "$SYSROOT/lib/lib$lib.a"
  "$TOOLCHAIN/bin/llvm-ar" rcs "$SYSROOT/lib/lib$lib.a"
done

echo "== sysroot 就绪：$SYSROOT"
ls -l "$SYSROOT/lib" | awk '{print $5, $9}'
"$TOOLCHAIN/bin/llvm-objdump" -d "$SYSROOT/lib/crt2.o" | head -12
