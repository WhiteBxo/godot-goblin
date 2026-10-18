# 两工作树整合记录（2026-10-19）

本次按[两天流程对接约定](../design/two_day_flow_integration_plan.md)和[经济实现方案](../design/milk_tea_economy_implementation_plan.md)整合地图／剧情线与经济线。正式入口为 F5 标题 → 新游戏；当前已接通两天与第三天既有任务交接。图形自动化已通过，完整人工步行与听感尚未验收。

## 两树来源与取舍

| 来源 | 整合前状态 | 处理 |
| --- | --- | --- |
| 主工作树 main | HEAD `29ea1fe`；自共同祖先依次有 `98f2425` 地图、`eff193c` 宿主业务、`5fcd7e1` 价格账本、`29ea1fe` 守卫／跨室内重试；另有未提交的两天接线 | 作为唯一实现基础，补完并验证正式两天数据与业务 |
| codex/milk-tea-economy | HEAD `7da2bb1`，另有未提交的经济修正 | 移植独有能力与边界校验；不复制它的 MilkTeaEconomy 第二套规则类 |

共同祖先是 `33bfc7409be9e092c6e9e0839bb2ece95d117b11`。两树确实重复实现了经济阶段 1–3：原料等级、定价、库存、制作／奖励和快照。整合保留 `WalletTransactions + FormulaPricing + EconomyRules`，调用方共用同一库存及账本。

从另一实现吸收：互斥 `delivery.uses`、按次任务展示／交付、钱包商品与酒馆报价一致性、折扣资格实时读取、旧报价／奖励布局迁移和失败边界。原始脏改动及散列已在本机 `/tmp/goblin_integration_20261019/` 备份。`project.godot`、building_atlas 素材及其生成工具属于既有无关改动，不纳入本次提交；另一个工作树未改写或删除。

## RPG Maker 地图确认

| 正式宿主 | 继承场景 | 原始地图 |
| --- | --- | --- |
| `src/core/settlement.tscn` | `src/levels/rpg_maker/chapter_cave.tscn` | `map_001.tscn` |
| `src/core/tavern.tscn` | `src/levels/rpg_maker/chapter_tavern.tscn` | `map_004.tscn` |
| `src/core/casino.tscn` | `src/levels/rpg_maker/chapter_casino.tscn` | `map_005.tscn` |
| `src/core/elder_house.tscn` | `src/levels/rpg_maker/chapter_elder_house.tscn` | `map_006.tscn` |

四个 `map_*.tscn` 相对共同祖先无改动；门、锚点、路障、守卫、采集和调查保存在继承场景中。商业路线与潜入支路分开，灰色道路封闭，祭坛右侧保留唯一潜入通道。奶茶店继续使用既有 `milk_tea_shop.tscn`。正式交互隐藏开发标签，使用项目内置中文字库，地图不显示原料内部 ID。

## 业务与经济结果

- Day 1 五单及 S04 第六单均为 H01／3G；三处实际调查、回店、手动接制交、实际开关地图与选项汇合均接通。F04／F05 各赠两次，潜入经费 50G 有独立防重回执。
- 首夜实际投币 10G／次；醉卫 10G、双卫共 10G，双卫本次往返持续放行。被发现可重试；整次尝试跨室内恢复完整库存、钱包、付款和调查事实，中途不写文件存档。
- 文书展示后关窗才自动收入且只收入一次；血液取得三次用量。顺序自由，真实撤离返店后才进入 S06。C01＋血各用一次，余血两次，特调总收入 40G；异常与休息按源稿叙述，自动进入 Day 2。
- Day 2 四组剧情客按序五杯 H01；三名普通客可选接单或雇一人，已接单须交后关店，不要求必须雇佣。
- 代购 35G 专款与普通钱包隔离：实购 30G、跑腿费 5G、余款退委托方；Day 2 雇佣于 Day 3 早回来，Day 3 雇佣于当晚回来，Day 4 未交付则超时。
- 酒馆一份标价 60G／折后 48G，五次用量、限一份；定价成本仍读标准市场价 100G。赌场两次真实按钮开始，先生成十杯债、再发三份原料并真实取消债务。
- 守卫招待 C01＋酒＋幻金菇各一次，不使用血液，酒／菇各余四次；三句问候后才允许交付，收入 0G，随后试饮与人物记录。实际返店才播章末。第三天只开放既有交接和等夜，不扩写主线。
- 七日祭三种材料各两份，夜间真实采集，第三天交付奖励 60G；普通采集历史与醒神菇代购分别保存。

最低必经预算：六杯 18G＋潜入经费 50G－潜入 50G＋血特调 40G＋次日五杯 15G＝购酒前 **73G**，支付 48G 后 **25G**。专款、随机售价及爆品奖励不参与该预算。

C01–C10 初始各五份、每份五次，0G 整份补给。自由配方最多三槽，合法基底并至少一种经营哥布林原料；预览只读，明确确认才记录永久报价，换序／加冰共价。实际制作一次提交用量、杯、图鉴、回执及首发奖励；150G 奖励机制已验证，正式爆品表仍为空。F09 限任务使用，禁止普通销售、自由配方和市场采购。

## 快照与安全边界

统一版本为 **GameState 8／库存 6／经济 3**。两分支曾使用相同旧版本号表达不同布局，故递增版本并按字段迁移，兼容已有完整 v2–v7。旧币按 10G 折入钱包后清零，旧商品升级，既有报价及领奖记录保留；未定价旧杯保留 `legacy_unpriced`，迁移不抽价、不补发奖。小数／负数／溢出／未发现实体币、非法账本、坏专款及双方库存不一致均拒绝整包恢复。

场景到达事实要求真实旅行，读档入口不伪造到达。顾客出入场期间不保存，防止重建改变业务状态。20 个真实自动存档包括首夜准备、Day 2 各经营／购买／赌场／守卫等待、Day 3 交接与 Day 4 超时；分别在新进程恢复，核对整包状态、输入释放、无重复发物／付款及存档文件不被无故改写。

## 实际验证

引擎：Godot `4.7.2.stable.official.ed1daf0bf`。下表为本次会话实际执行的相关检查，不表示仓库所有历史 Demo 回归全部通过。

| 检查 | 结果 |
| --- | --- |
| 两天真实流程，无可选订单，含 20 个真实自动存档 | 214 项，0 失败 |
| 图形两天流程，含接可选订单后关店分支 | 272 项，0 失败；保存 65 张截图 |
| 两天自动存档冷恢复 | 20 个独立读进程，全部 0 失败 |
| 原有前段存档回归 | writer 48 项及八个独立 reader，通过 |
| RPG 地图／长老室内真实交互／通用交互 | 105／45／46 项，通过 |
| Day 1 首夜／章节系统 | 100／99 项，通过 |
| 代购专款／Day 2 交易 | 53／62 项，通过 |
| 定价迁移／钱包／库存／自由配方 | 131／146／189／238 项，通过 |
| 任务系统／交付／任务面板 | 196／69／92 项，通过 |
| 订单板／订单 UI／旧教学池隔离 | 57／33／33 项，通过 |
| 顾客营业调度／经营会话／持久营业 | 188／48／94 项，通过 |
| GameState／实际场景旅行／入口 | 126／163／66 项，通过 |
| StoryDirector／Gameplay Bridge／正式后段编排 | 165／249／148 项，通过 |
| SaveStore／SaveGame／保存边界 | 25／45／18 项，通过 |
| 配方资源／固定制作／配方制作 | 292 项／PASS／PASS |

图形截图核对了洞窟、长老室内、酒馆、赌场、店内顾客和交接界面；中文与交互提示可读，没有开发 Marker／内部原料名覆盖地图。图形测试使用真实宿主、SceneTravel、投币动画和业务事务；靠近目标用自动定位、台词自动推进，不算人工完整步行或听音验收。室内专项额外覆盖 MainGame 文书展示／关窗路由、实际反馈、两种取得顺序及重复操作拒绝。

可复现的核心检查（从仓库根运行）：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_economy_pricing.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_day1_world_flow.gd
python3 tests/verify_two_day_persistence.py
/Applications/Godot.app/Contents/MacOS/Godot --path . --rendering-method gl_compatibility --script res://tests/verify_two_day_flow.gd -- --captures=/tmp/goblin_two_day_captures --ordinary-order
```

### 未通过与未执行

- `verify_day1_stages_01_02.gd` 在旧 E 键焦点断言中止；该问题在既有 `05429c3` 基线已有记录，脚本后续仍含旧 10G／四枚实体币预期。未声称该 UI 脚本通过；现行正式销售与完整两天由新流程覆盖，但自动定位无法证明人工交互手感。
- `verify_story_authoring.py` 的前四个负例通过，随后被旧 Cinematic 顾客向 `(1470, 560)` 移动受阻中止，后续未执行。相同历史失败见[10-18 记录](development_status_2026_10_18.md)与[存档基线](../systems/save_system.md#验证)。本轮未修改该演出路线。
- 原 `verify_day1_world_flow.gd` 依赖旧 16 区节点结构，已迁移为当前 RPG 长老室内真实交互专项；跨场景、撤离、重试与 S06 由 `verify_two_day_flow.gd` 覆盖。旧 `day1_world_flow_demo` 保留为历史调试夹具。
- 部分 headless 模块退出仍有既有资源存活诊断，macOS 沙箱有 CA 证书诊断；均与脚本业务失败分别记录。最新图形完整流程无脚本错误。
- 本轮未执行完整人工步行、人工听感或 Release 重新导出；其他无关历史 Demo 不重复扩大验证。未发布放火、专用异常动画、自由赌博、长期雇佣、队伍或独立战斗商品。

## 试玩步骤与可观察结果

1. F5 → 新游戏，按提示接单、制作与指定顾客交付；前五杯钱包 15G。出店到洞窟完成三处调查，回店完成第六单，实际打开并关闭地图；接受委托后钱包 68G、进入夜晚。
2. 沿祭坛右侧潜入支路前进，投币与两笔付款均扣真实钱包；被发现可从潜入前完整重试。进入长老室内，阅读关窗取得文书、拾取三次血液，原路撤离再回店。
3. 制作并交付 C01＋一血特调，观察余血两次及 40G 收入；剧情安排休息后自动进入第二天早晨。
4. 完成四组剧情客；可接普通单、雇一名普通客，或直接关店。观察专款独立，购酒前必经钱包 73G、折后购酒减 48G。
5. 夜间接七日祭、酒馆买酒、赌场分别点击两局。制作三料守卫饮品并回原位置，问候结束后交付，酒／菇余四次、无收入。真实回店后章末，第三天可交接或等待傍晚。
6. 安全操作阶段退出至标题并继续游戏，检查钱包、剩余次数、订单、报价和专款不变；潜入中断回到整次尝试前。

## Godot 4.7 API 依据

- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：真实切换后等待 `scene_changed` 再绑定目的宿主，避免继续使用旧场景。
- [Node 生命周期](https://docs.godotengine.org/en/4.7/classes/class_node.html)：地图子交互点 ready 后，宿主经公开方法隐藏开发显示并组装服务。
- [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：嵌套事务草稿／快照深拷贝，失败不污染当前状态。
