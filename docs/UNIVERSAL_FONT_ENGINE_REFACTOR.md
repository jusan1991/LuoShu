# 洛书通用字体引擎重构总路线

> 本文档是洛书“全系统通用换字体”重构的唯一权威路线图。后续实现、PR、测试和兼容补丁必须以本文档为准；如果设计发生变化，先更新本文档，再改代码，避免边做边偏。

长期追踪 Issue：#254。Phase 2 实现 PR：#255。

## 最终目标

把洛书从“按 ROM / 文件名堆规则的字体替换模块”重构为：

**Android Universal Font Compiler**
= 设备字体拓扑识别 + 字体角色分类 + 字体兼容编译 + 最小路由补丁 + Systemless 挂载 + 自动验收。

目标系统包括但不限于 HyperOS、ColorOS/OxygenOS、OriginOS、One UI、MagicOS、Flyme、Pixel/AOSP，以及未来未见过的新 ROM。

## 不可偏离的原则

1. **不使用 Zygisk / LSPosed / App Hook。**
   系统字体链能覆盖的范围全部通过 ROM 原生字体配置、systemless overlay 和可验证的动态字体机制完成。

2. **ROM 名称不是主逻辑。**
   HyperOS / ColorOS 等识别仅允许作为兼容提示和回退，不允许继续成为核心替换规则的 source of truth。

3. **设备真实拓扑是唯一输入。**
   任何替换计划必须来自本机扫描得到的字体 family、XML 路由、物理槽位、运行时 FontManager 和 /data/fonts 状态。

4. **先识别角色，再决定替换。**
   不允许因为一个文件“看起来像系统字体”就直接替换。

5. **未知默认保护。**
   未能高置信度分类的字体一律先保留，不允许为了“覆盖更多”而盲换。

6. **Emoji / Icon / Symbol 永久禁止通用替换。**
   只有独立专用功能可以显式处理这些角色。

7. **Serif / Code Monospace 默认保留。**
   用户只选择“系统字体”时，不改变 serif 与代码等宽字体。

8. **Clock / Numeric 是专用角色。**
   它们可以替换，但必须经过独立数字覆盖与度量契约，禁止直接套普通 UI 字体逻辑。

9. **OEM 原始 XML 结构必须保留。**
   洛书只能最小化 patch 当前设备自己的 XML；不允许拿一份通用 AOSP XML 覆盖 OEM 配置。

10. **/data/fonts 是独立层。**
    允许识别、验证和有条件处理，但禁止粗暴清空、盲写或把它当普通 /system/fonts 目录。

11. **所有新引擎先 Shadow Mode。**
    新算法必须先只生成计划，与当前实现比较；未通过真实设备和回归测试前不得接管实际替换。

12. **切换路径必须可回滚、可验证、无后台死循环。**
    失败必须 fail-safe；不得靠永久 watcher、无限重试或重启循环掩盖问题。

## 阶段路线

### Phase 1 — Device Font Topology
状态：**已完成 / PR #253**

产物：

- `config/device_font_topology.json`
- 合并原厂 inventory、fonts XML、FontManager runtime evidence、mountinfo、`/data/fonts`
- OTA / 安装 / 首次开机补扫 / App 手动重扫后可重建

完成标准：

- 不修改任何实际字体
- 能表达 family → slot → partition → XML → runtime 的关系
- 未知 OEM 分区可以进入拓扑

### Phase 2 — Role Classifier + Shadow Replacement Plan
状态：**进行中**

目标：

对每个拓扑槽位分类，并生成“如果新引擎接管会怎么处理”的只读计划。

标准角色：

- `ui-sans`
- `cjk`
- `latin`
- `numeric`
- `clock`
- `monospace`
- `serif`
- `emoji`
- `symbol-icon`
- `special-fallback`
- `unknown-protected`

Shadow 动作：

- `replace`：普通系统 UI 候选
- `conditional`：依赖源字体覆盖能力
- `specialized`：数字/时钟等需要专用编译
- `preserve`：必须保留
- `review`：证据不足，禁止自动替换

产物：

- `config/device_font_roles.json`
- `config/device_font_shadow_plan.json`

额外要求：

- 同时记录当前旧引擎 `replaceable` 结论
- 输出 `agree / current-gap / current-overreach / not-comparable`
- 第二阶段不允许实际写入字体或 XML

### Phase 3 — Imported Font Analyzer / Compiler Input
状态：**进行中 / source-font-profile-v1**

目标：

统一解析 TTF / OTF / TTC / OTC / Variable Font；导入 WOFF/WOFF2 时先转换。

必须读取：

- cmap
- name
- OS/2
- head
- hhea
- maxp
- GSUB / GPOS
- fvar / avar / STAT
- HVAR / VVAR / MVAR
- TTC face index

输出：

- 字形覆盖
- language/script 能力
- 可变轴
- 字重
- 度量
- 字体角色适配能力

标准产物：

- `config/source-font-profiles/*.json`
- Schema：`source-font-profile-v1`
- WOFF/WOFF2 必须先通过 `font_web_convert.py` 解包为真实 SFNT，禁止仅改扩展名
- Phase 4 只能消费 Source Profile，不得重新散读多个旧探测器

### Phase 4 — Universal Replacement Planner
状态：**进行中 / universal-font-plan-v1**

输入：Phase 1 拓扑 + Phase 2 角色 + Phase 3 源字体能力。

输出一份确定性 `FontPlan`，不得直接修改系统。

标准产物：

- `config/universal-font-plans/*.json`
- Schema：`universal-font-plan-v1`
- `planId` 必须由设备 buildKey、Source Profile 与确定性 targets 计算，重复输入必须得到同一 ID
- Phase 4 可以选择具体 source face、目标字重、目标槽位与后续 compiler requirement
- Phase 4 不允许生成字体文件、不允许 patch XML、不允许 mount、不允许声明 `executableNow=true`
- Phase 5/6/7 只能消费 FontPlan，不能重新绕过它自行挑目标槽位


计划必须说明：

- 哪些槽替换
- 哪些槽保留
- 哪些 family 改路由
- 哪些角色需要独立编译
- 为什么这么决定
- 风险与回退方案

### Phase 5 — Minimal XML Router
状态：未开始

目标：

从设备自己的：

- `fonts.xml`
- `font_fallback.xml`
- `fonts_customization.xml`
- OEM 自定义字体 XML

生成最小 patch。

禁止：

- 用通用模板覆盖整个 ROM XML
- 删除未知 OEM family
- 打乱 fallback 顺序
- 丢失 lang / variant / fallbackFor / axis 等属性

### Phase 6 — Metrics / Variable Font Compiler
状态：未开始

目标：

针对目标槽位生成兼容字体。

重点解决：

- HyperOS baseline 偏移
- 状态栏 / QQ 标签 / 秒表数字偏移
- static ↔ variable font 不兼容
- 多字重
- UPEM / ascent / descent / lineGap / capHeight / xHeight
- 数字宽度和 clock exact-width

### Phase 7 — Unified Mount Backends
状态：未开始

上层只接受同一份 `FontPlan`。

后端分别处理：

- Magisk
- KernelSU
- APatch

禁止三套字体判断逻辑。

### Phase 8 — Runtime Verification
状态：未开始

重启后自动验证：

- family 是否加载
- 物理槽是否挂载
- CJK / Latin / digits 是否覆盖
- 多字重 / variable axis
- /data/fonts 是否反向覆盖
- 目标 FontManager 是否真实命中新字体
- 是否发生 baseline / bounding box 高风险

最终给用户 PASS / WARN / FAIL，而不是让用户盲测。

## 当前迁移策略

旧的 HyperOS / ColorOS / Generic 路由暂时保留，只作为“当前生产实现”。

新引擎按以下顺序迁移：

1. Shadow 分类
2. Shadow 替换计划
3. 与旧实现比较
4. 真机验证
5. 按角色逐类接管
6. 删除被证明多余的 ROM 专用硬编码

绝不一次性删除所有旧规则。

## 第二阶段验收门槛

Phase 2 只有满足以下条件才允许进入 Phase 3：

- Emoji、Symbol/Icon 不出现 `replace`
- 未知槽位默认 `review` 或 `preserve`
- Clock/Numeric 不出现普通 `replace`
- Serif/Monospace 默认不被系统字体替换
- CJK fallback 只有明确 CJK 证据才成为候选
- Latin fallback 只有明确 Latin 证据才成为候选
- HyperOS / ColorOS 合成测试可重复
- Shadow 计划本身不修改任何系统文件
- CI 能报告旧引擎过度替换与漏替换差异

## 变更纪律

以后每个通用字体引擎 PR 都必须：

1. 写明属于哪个 Phase。
2. 写明修改了哪条 invariant。
3. 如果改变本文设计，先改本文档。
4. 新增至少一个回归测试。
5. 不允许用“某手机临时能用”替代通用逻辑。
6. ROM 特例必须有真实拓扑无法表达的证据，否则不得新增。

