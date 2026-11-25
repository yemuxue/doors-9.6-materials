# IBM DOORS 9.6 使用过程资料

一套基于本机 **IBM Rational DOORS 9.6.1.11** 实测整理的需求管理资料：数据模型、DXL 自动化、原生基线、追溯矩阵，以及一份可直接汇报的 13 页 PPT。

> 非 IBM 官方文档；不含安装包、License、破解文件或客户数据。示例库为虚构的“智慧园区”演示数据。

## 内容

| 目录 | 内容 |
|---|---|
| `docs/` | 核心功能操作手册、全链路使用文档、需求工程全流程实践指南、原生基线操作指南 |
| `dxl/` | 导入、建链、快照、影响分析、变更演示、导出等 DXL 脚本 |
| `tools/` | `doors-run.ps1`（COM 跑 DXL 并自动关错误弹窗）、基线发布、影响分析、建链报告等 PowerShell |
| `slides/` | 《DOORS 功能介绍》13 页汇报版 PPTX / PDF |
| `screenshots/` | 模块编辑、数据库树、矩阵、CR 链接、原生基线比较等实拍截图 |
| `samples/` | 演示库导出的链接清单 CSV |

## 实测环境

- 客户端：`doors.exe` 64 位，DOORS 9.6.1.11
- 服务端：`doorsd.exe` 32 位 Windows 服务，TCP 36677
- 数据库：自研对象库 `data\v6data`，不依赖外部 RDBMS
- 演示库：11 个模块、995 个对象、662 条追溯链接、15 张 CR

## 快速开始

1. 先读 `docs/核心功能操作手册.md`，按任务走一遍模块、属性、链接、基线；
2. 需要批量导入/建链时看 `docs/使用文档.md` 和 `dxl/`；
3. 跑 DXL 用 `tools/doors-run.ps1`，避免编译错误弹窗卡住 COM：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\doors-run.ps1 -DxlFile .\dxl\snapshot.dxl
```

4. 直接看汇报材料：`slides/DOORS功能介绍.pptx`。

## 原生基线（重点）

DOORS 的基线不是“点一下就有”，需要三层：

```text
文件夹属性 → 基线集定义 → 基线集（1.0 / 1.1） → 模块基线
```

完整步骤、菜单路径和踩坑见 [`docs/DOORS-基线操作指南.md`](docs/DOORS-基线操作指南.md)。

要点：

- 基线集定义建在**文件夹属性 → 基线集定义**，不在数据库窗口的“文件 → 新建”；
- 定义建好后要“编辑”把模块加进去；
- 再在“基线集”标签里新建版本（如 `1.0`）；
- 模块窗口 **文件 → 基线 → 新建** 才能看到可选基线集；
- 比较用 **文件 → 基线 → 比较**，两边选不同版本；
- DXL 的 `baseline(Module)` 在本环境返回 `false`，原生基线请走 GUI。

## 说明

- 文档中的账号、主机名、绝对路径已脱敏；脚本里的 `C:\doors-demo` 是示例路径，运行前请改成你的环境。
- `dxl/import-*.dxl` 含演示数据文本，导入前先在空库/测试库验证。
- 未收录：IBM 安装介质、License、破解文件、ZenTao 同步脚本中的账号密码、二进制逆向分析产物。
- IBM、Rational、DOORS 是 IBM 的商标；本仓库与 IBM 无隶属关系。
