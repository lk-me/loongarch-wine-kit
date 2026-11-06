#!/usr/bin/env bash
# 步骤 1：构建 LLVM（LoongArch + clang + lld），并安装到 $TOOLCHAIN。
# 产物用于生成 loongarch64 PE，必须应用 patches/llvm 下全部补丁。

source "$(dirname "$0")/../env.sh"

echo "== LLVM 源码: $LLVM_SRC"
echo "== 构建目录:  $LLVM_BUILD"
echo "== 安装到:    $TOOLCHAIN"

"$CMAKE" -S "$LLVM_SRC/llvm" -B "$LLVM_BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CMAKE_C_COMPILER:-/usr/bin/cc}" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="LoongArch" \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DCMAKE_INSTALL_PREFIX="$TOOLCHAIN"

"$CMAKE" --build "$LLVM_BUILD" -j "$JOBS"
"$CMAKE" --install "$LLVM_BUILD"

# llvm-mingw 风格的驱动包装：把 -target/--sysroot 固化进去，
# Wine 的 configure 会直接调用 loongarch64-w64-mingw32-clang。
mkdir -p "$TOOLCHAIN/bin"
cat > "$TOOLCHAIN/bin/$TARGET-clang" <<EOF
#!/bin/sh
exec "$TOOLCHAIN/bin/clang" --target=$TARGET_TRIPLE --sysroot="$SYSROOT" "\$@"
EOF
chmod +x "$TOOLCHAIN/bin/$TARGET-clang"

for tool in ar ranlib nm strip objcopy; do
  ln -sf "$TOOLCHAIN/bin/llvm-$tool" "$TOOLCHAIN/bin/$TARGET-$tool"
done
ln -sf "$TOOLCHAIN/bin/llvm-dlltool" "$TOOLCHAIN/bin/$TARGET-dlltool"

echo "== 完成，检查："
"$CC_PE" --version | head -1
ls "$TOOLCHAIN/bin/ld.lld" "$TOOLCHAIN/bin/lld-link"
