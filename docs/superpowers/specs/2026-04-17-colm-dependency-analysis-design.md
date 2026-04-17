# CoLM 代码工程化改造 — 依赖分析与编译链重构设计

## 1. 背景与目标

CoLM (Common Land Model 202X) 是一个大型 Fortran 数值模型程序，代码规模大、模块多、依赖关系复杂。当前存在以下问题：

- **编译配置复杂**：条件编译宏分散在 `define.h` 和 Makefile 中，配置困难
- **依赖不清晰**：模块间 `use`、`call`、`include` 关系缺乏完整图谱
- **代码质量黑盒**：潜在的传参错误、并行争用、语法不标准问题难以诊断
- **协作困难**：多人/多agent并行工作时缺乏统一的依赖数据库

本项目旨在：
1. 建立完整的依赖分析框架，产出可渐进验证的数据库
2. 基于依赖图谱重构编译链（迁移到 CMake）
3. 驱动 Bug 诊断与修复
4. 产出可视化文档（流程图、HTML 交互界面）

---

## 2. 整体架构

### 2.1 阶段划分与依赖关系

```
P0: 工具链 + Schema + 验证框架
 │
 ├───────────────────────────────┐
 │                               │
 ▼                               ▼
P1: 文件级依赖图               P5: 宏/条件编译路径分析
(share先行)                   (可独立推进)
 │
 ▼
P2: 模块级 use/call 链
 │
 ├───────────────────────────────┐
 │                               │
 ▼                               ▼
P3: 全局变量追踪             P4: 并行区域分析
(HYDRO/BGC先行)             (MPI/OpenMP争用检测)
 │                               │
 └──────────────┬────────────────┘
                │
                ▼
 ───── CMake 迁移 (基于完整依赖图) ─────
                │
                ▼
 ───── Bug 诊断/修复 (依赖分析驱动) ─────
                │
                ▼
 ───── 可视化呈现 (HTML交互界面) ─────
```

**关键原则**：
- P0 是绝对前置条件，完成后才能规模化推进
- P1/P2 可按模块分配给多个 agent 并行
- P3 依赖 P1+P2；P4 依赖 P3
- Bug 修复从 P2 完成后可开始（粗粒度图足够）

### 2.2 模块优先级排序

| 模块 | 代码量 | 依赖复杂度 | 并行特征 | 优先级 |
|------|--------|-----------|---------|--------|
| share/ | 大 | 低（被所有人依赖）| 少量 | P0 后首批 |
| main/HYDRO | 大 | 高 | 有 | P1 首批 |
| main/BGC | 中 | 高 | 有 | P1 首批 |
| main/URBAN | 小 | 中 | 少 | P2 |
| main/LULCC | 小 | 中 | 少 | P2 |
| main/DA | 中 | 中 | 有 | P3 |
| main/ParaOpt | 小 | 低 | 少 | P3 |
| extends/CaMa | 大 | 高 | 有 | 最后 |

---

## 3. 分析框架设计

### 3.1 渐进式阶段目标

| 阶段 | 内容 | 验证方式 | 通过标准 |
|------|------|---------|----------|
| **P0** | 工具链搭建 + Schema + 验证规程 | 选一个文件端到端跑通 | 手工核对 use/include 语句正确 |
| **P1** | 文件级依赖图 | 交叉验证：gfortran -M vs 脚本输出 | 95%以上一致 |
| **P2** | 模块级 use/call 链 | 抽样追踪 10 个 call 链 | 完全一致 |
| **P3** | 全局/模块变量追踪 | 追踪一个变量从入口到出口 | 路径完整不断链 |
| **P4** | 并行区域分析 | gfortran -fsanitize=thread | 检测到预期的共享变量争用 |
| **P5** | 宏定义 + 条件编译路径 | 两种配置编译对比 | 差异被正确捕获 |

**验证时机**：每个 agent 完成模块分析后立即本地验证，再提交合并。不层层积压。

### 3.2 数据库 Schema (SQLite)

```sql
-- 文件级依赖
CREATE TABLE file_deps (
    id          INTEGER PRIMARY KEY,
    src_file    TEXT NOT NULL,
    dst_file    TEXT NOT NULL,
    dep_type    TEXT,             -- 'use', 'include', 'call', 'reference'
    module_name TEXT,
    line_num    INTEGER,
    confidence  REAL DEFAULT 1.0,  -- 0-1
    source      TEXT,             -- 'script', 'manual', 'compiler'
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 模块/过程级依赖
CREATE TABLE proc_deps (
    id            INTEGER PRIMARY KEY,
    caller_file   TEXT NOT NULL,
    caller_proc   TEXT NOT NULL,
    callee_file   TEXT,
    callee_proc   TEXT,
    intent        TEXT,           -- 'in', 'out', 'inout'
    confidence    REAL DEFAULT 1.0,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 全局/模块变量
CREATE TABLE global_vars (
    id            INTEGER PRIMARY KEY,
    var_name      TEXT NOT NULL,
    module_name   TEXT NOT NULL,
    declared_in   TEXT NOT NULL,
    var_type      TEXT,
    intent        TEXT,
    accesses      TEXT,           -- JSON: [{file, proc, access_type}]
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 宏/条件编译
CREATE TABLE macro_defs (
    id            INTEGER PRIMARY KEY,
    macro_name    TEXT NOT NULL,
    defined_in    TEXT NOT NULL,
    line_num      INTEGER,
    conditions    TEXT,
    created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 分析任务追踪
CREATE TABLE analysis_tasks (
    id            INTEGER PRIMARY KEY,
    module_name   TEXT NOT NULL,
    phase         TEXT NOT NULL,  -- 'P0', 'P1', ...
    status        TEXT NOT NULL,  -- 'pending', 'in_progress', 'done', 'conflict'
    assigned_to   TEXT,
    started_at    TIMESTAMP,
    completed_at  TIMESTAMP,
    notes         TEXT
);
```

### 3.3 多 Agent 协作机制

**问题**：多个 agent 同时写同一个 SQLite 会冲突。

**方案**：生产者-消费者模式

```
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Agent 1 │  │ Agent 2 │  │ Agent 3 │  ... (生产者)
│ BGC模块 │  │ HYDRO模块│  │ URBAN模块│
└────┬────┘  └────┬────┘  └────┬────┘
     │            │            │
     ▼            ▼            ▼
┌─────────────────────────────────┐
│      中间文件 (JSON/SQLite)     │
│  每个agent写自己的结果文件       │
└───────────────┬─────────────────┘
                │
                ▼
┌─────────────────────────────────┐
│     Merge Agent (定时/按需)       │
│   合并所有中间文件 → 统一数据库    │
└───────────────┬─────────────────┘
                │
                ▼
         ──── 统一数据库 ────
```

**冲突处理**：如果两个 agent 对同一模块的依赖关系矛盾，标记为"待人工复核"，不阻塞其他工作。

**工具链**：通用开源工具（正则解析 + gfortran 前端），不做商业工具依赖。

---

## 4. 编译链重构

### 4.1 目标

- 替代当前 Makefile + define.h 的复杂配置方式
- 实现层级清晰、代码清晰、流程清晰、易读易配置、逻辑正确
- 保留增加模块的接口

### 4.2 策略

1. **渐进迁移**：选一个简单模块（share/）先迁移到 CMake，验证后推广
2. **与 Makefile 共存过渡期**：CMake 和 Makefile 同时维护，直到稳定
3. **基于依赖图谱**：CMake 的 `target_link_libraries` 直接从分析数据库生成

### 4.3 CMake 设计原则

- 每个模块一个 `CMakeLists.txt`
- 条件编译通过 CMake 的 `option()` 和 `add_compile_definitions` 管理
- 依赖关系通过数据库自动推断，减少手工维护

---

## 5. Bug 诊断与修复

### 5.1 依赖分析驱动的诊断

基于 P2/P3/P4 的依赖图谱：
- **传参错误**：检查 `intent(in/out/inout)` 与实际使用的匹配
- **未初始化变量**：追踪变量的定义-使用链
- **并行争用**：识别 MPI/OpenMP 区域内对同一全局变量的读写冲突

### 5.2 修复原则

- 高内聚低耦合：依赖分析结果指导重构边界
- 先验证再修复：每一步修改后运行对应阶段的验证

---

## 6. 可视化呈现

### 6.1 产出形式

- **程序运行流程图**：模块间的调用顺序和数据流
- **HTML 交互界面**：可缩放、可点击的依赖图思维导图
- **文档导出**：PDF/Markdown 格式的模块接口文档

### 6.2 实现方式

- 调用图用 Graphviz + D3.js 做成 Web 界面
- 静态文档从数据库 schema 直接生成

---

## 7. 工具做成 Skill

### 7.1 目标

将分析工具构建为可分发的 skill，供多个 agent 调用。

### 7.2 Skill 结构

```
colm-dependency-analyzer/
├── parser/           # Fortran 依赖解析脚本
├── merger/           # 多 agent 结果合并工具
├── validator/        # 各阶段验证工具
├── db/               # SQLite schema 和连接管理
├── viz/              # 可视化生成脚本
└── skill.md          # Skill 定义
```

---

## 8. 进度管理

### 8.1 看板设计

```
┌─────────────────────────────────────────────────┐
│              分析任务看板 (TUI/HTML)              │
├──────────────┬──────────────┬────────────────────┤
│   Pending    │  In Progress │      Done          │
├──────────────┼──────────────┼────────────────────┤
│ CaMa P2分析  │ BGC P1分析   │ share P0验证完成    │
│ LULCC P1规划 │ HYDRO P1分析 │                    │
└──────────────┴──────────────┴────────────────────┘
```

### 8.2 阻塞检测

Merge agent 发现某模块的依赖数据缺失（如 A 依赖 B 但 B 还未分析），自动标记 B 为"blocked by A"。

---

## 9. 风险与对策

| 风险 | 对策 |
|------|------|
| Fortran 隐式类型、COMMON 块导致解析不准确 | P0 阶段重点验证，必要时用编译器前端补充 |
| 多 agent 并行写入冲突 | 中间文件 + Merge agent 模式 |
| 大规模代码改动积重难返 | 每阶段验证后再推进，不把问题往后传 |
| CMake 迁移影响现有 CI/CD | 过渡期双轨制，并行维护 Makefile |

---

## 10. 下一步行动

1. **P0 启动**：搭建解析脚本、SQLite schema、验证规程
2. **试点模块**：选 share/ 模块完成 P0-P2 全流程，验证工具链
3. **并行扩展**：试点验证后，按优先级分配到多个 agent 并行
4. **定期合并**：Merge agent 每日/每阶段合并一次中间结果

---

*文档版本：2026-04-17*
*状态：待审批*
