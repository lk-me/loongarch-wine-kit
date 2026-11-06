# 本次工作的资源消耗说明

> **Abstract (EN)** — Platform billing data is not accessible from the workspace, so
> this document separates *verifiable effort* (commits, build cycles, test runs,
> document size) from a *token-level estimate* (3–5 M input, 0.2–0.3 M output,
> ±50 %). Convert to credits with your own plan rates.

## 0. 先说清楚计量口径

工程内无法读取平台的计费数据（积分/账单在 Trae 客户端「用量」里），
所以这里给的是**可核验的工作量记录** + **按 token 量级的估算**，
两者分开列，估算部分请按自己的套餐费率换算，误差约 ±50%。

## 1. 可核验的工作量

| 类别 | 数量 | 证据 |
| --- | --- | --- |
| LLVM 提交 | 13 | `patches/llvm/` |
| Wine 提交 | 10 | `patches/wine/` |
| Wine 改动规模 | 66 文件 / +4268 −54 | `git diff --stat 8448e6d..HEAD` |
| mingw CRT | 1 个汇编入口（`crt0.S`，578 B 目标文件） | `mingw64-loongarch64/crt/` |
| 目标机整链构建轮次 | ~10 轮（`build3`、`build3b`–`build3i`） | `/data/opt/winebuild/build3*.log` |
| 基准测试 | 3 组 × 3 次 × 2 套（进程内计时 / 整链采样） | 文档 4.9 节 |
| 卡死探针 | ~20 次最小用例 | 文档 4.8 节 |
| 文档产出 | 1900+ 行问题记录 + 本工程 | `wine-loongarch编译问题记录.md` |

## 2. Token 量级估算

本次会话信息密度高（大量构建日志、反汇编、源码片段），且**触发过 3 次自动
上下文压缩**，说明单次上下文多次接近上限。按此推算：

| 项 | 估算值 | 说明 |
| --- | --- | --- |
| 累计输入 token | 3–5 M | 含重复读取的大日志与源码；压缩后仍会重复读取 |
| 累计输出 token | 0.2–0.3 M | 补丁、脚本、文档为主 |
| 单轮平均上下文 | 60–120 K | 压缩触发点附近更高 |

换算公式（自行代入费率）：

```text
积分 ≈ 输入token/1e6 × 输入单价 + 输出token/1e6 × 输出单价
```

按常见档位（输入约为输出的 1/5 单价）粗算，本次总消耗的**输入侧占 70–85%**，
其中相当一部分来自早期探索阶段的反复构建失败与日志回读。

## 3. 机器资源消耗

| 机器 | 用途 | 消耗特征 |
| --- | --- | --- |
| x86_64 构建机 | LLVM Release 全量构建（仅 LoongArch 目标） | 一次性长构建，占本次本地 CPU 时间的大头 |
| Loongson-3A5000-HV（4 核 / 16 GB） | Wine 全量构建 ~10 轮 | 每轮数分钟到十几分钟，含多次因链接错误重跑 |
| 同上 | 运行验证与采样 | bench、整链采样、GUI 验证，累计数小时 |

## 4. 如何降低下一次的消耗

1. **补丁化**：本次已把 23 个提交导出为 `patches/`，新机器 `git am` 即可，
   不必再逐条试错——这是最大的一块可节省项。
2. **先跑 `05-verify.sh`**：两类卡死（`$ra` 自指、`-D_UCRT`）能在几分钟内被发现，
   避免再次长时间误判为 unwind 问题。
3. **构建脚本内联已知坑修正**：`04-build-wine.sh` 会自动检查
   `COMPILER_RT_PE_LIBS`，省去一轮全量构建。
4. **保留 `build-llvm` 增量构建**：LLVM 侧改动少，后续只重编 lld/clang 即可。
