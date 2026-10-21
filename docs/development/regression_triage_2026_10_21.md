# 回归红区分类（2026-10-21，上线后首次收敛）

> 数据来源：`python tests/run_all.py --jobs 4`，126 项，354.0s。
> 结果：**PASS 105 / FAIL 13 / CRASH 0 / SKIP 6 / HANG 0 / KNOWN 2**。
> 收敛前基线（同日 03:58）：PASS 100 / FAIL 17 / CRASH 1 / HANG 2 / SKIP 6。

本文只做一件事：把 14 项红按「谁该动手」分开，避免下一次又从头猜。
每项标明**已确证**（有日志或数据佐证）还是**待定性**（还没查到根因）。

## 一、已修复（本轮）

| 测试 | 根因 | 修法 |
| --- | --- | --- |
| `verify_disappeared_street.gd` | 断言把「不许拉伸」写成 `scale == Vector2.ONE`，而 7 个道具是合法的等比缩放（0.65–0.9）；另有一条停位期望 616–631 是旧硬编码，实际应贴 tile 边界 640 | 改成判等比 `x == y`；停位期望由 `tile_size * 5` 推出 |
| `verify_scene_travel.gd` | 「落地后能走开」只给 10 物理帧（0.167s），加速度 1800、移速 122 下满打满算约 16px，断言要求 >15px，余量不足复现不稳 | 给 20 帧，失败信息带实测位移与速度 |
| `verify_audio_manager.gd` | 4 条断言假设「事件开始前音频为空」，但店铺场景自带 `assets/audio/ambience/shop.wav` 常驻音景 | 引入 `ambient` 基线，全部改为相对计数 |
| `verify_cinematic_integration.gd` | 同上，`Cancel stops owned audio` 7 条都卡在环境音占位 | 同上，13 条 → 6 条 |
| `verify_otherworld_catalog.gd`（61 条） | 提交 `c52233fd`（信息只写"加酒馆地图 tile"）在重存 `.tres` 时静默删掉了 4 类手工字段：`flavor_tags` 31、`source_ids` 31（数组被截断成只剩首个）、`processing_methods` 15、`acquisition_sources` 13，共 90 处；图鉴因此显示「加工：」空白、风味整行消失 | 从 `c52233fd^` 逐字段恢复，`source_ids` 仅在"当前值是旧值子集"时覆盖；另有一条 `== 6` 的过期断言改为「教学只暴露 human 侧材料」 |

**结论：`stop_owned` / `StoryAudioAdapter` 归属逻辑本身没有 bug**，先前「两个不同 owner」的怀疑是环境音与 story voice 混在一起看导致的误判。

## 二、产品缺陷（玩家能感知，优先修）

| 测试 | 现象 | 证据 |
| --- | --- | --- |
| `verify_cinematic_integration.gd`（6 条） | 开场演出的 `customer` 走 `aisle`(1470,560) 被挡，顾客到不了柜台；另有时长断言要求 20–30s 而实际 10.15s | 已确证走位被挡；**时长需产品裁定**：是内容被压缩了，还是断言过期 |
| `verify_milk_tea_shop.gd`（1 条） | 设施与交付 NPC 从出生点不可达 | 待定性：需确认是布局改了还是寻路口径变了 |
| `verify_tea_recipes.gd`（5 条） | 教学「提交」按钮在小视口被挤出面板可视区；解锁原料未进入可选列表 | 布局溢出已定性；解锁列表待确认 |
| `verify_signature_interaction.gd`（5 条） | S08 线索无法物理重叠触发，文档打不开 | 待定性：疑与 S08 互动点位移有关 |
| `verify_chapter_stealth_route.gd`（1 条） | 潜行地面路线到 (216,440) 不通 | 待定性 |
| `verify_supplement_content.gd`（2 条） | 六种补充素材的 patch 与采集状态不符 | 与 `verify_gathering` 同源 |
| `verify_gathering.gd`（4 条） | 同上，外加佣金短差显示 | 待定性 |
| `verify_warehouse_inventory.gd`（1 条） | 制作台未默认为引导式接单生产 | 待定性 |
| `verify_flow_playtest.gd`（2 条） | 正式菜单里出现 fixture 产品 | 待定性：疑为测试夹具写入共享 Resource |

## 三、基线落后于实现（改测试期望即可）

| 测试 | 现象 |
| --- | --- |
| `verify_rpg_maker_map.gd`（4 条） | 4/5/6 号图的 tile 与星号切分和源图不一致——地图在编辑器里改过，期望表未跟 |
| `verify_day1_stages_01_02.gd`（16 条） | 编年史未解锁可见性、任务目标与制作进度快照、每次成功制作只播一次倒茶声等时序/计数断言 |
| `verify_day1_chapter_systems.gd`（3 条） | `Held pose stays after the event`、busy host 拒绝再启动等演出时序 |
| `verify_interaction_audio.gd`（2 条） | 采集音效确认与结果 |

> 这三项共同特征：测试假设的是旧的事件顺序或旧的资源结构。**注意 `verify_day1_stages_01_02` 对 `sound` 调用次数极敏感**，任何新增音效都会假阳性，改它前先确认不是产品侧多播了一次。

## 四、已登记台账（`tests/known_red.json`）

| 测试 | 类别 | 理由 |
| --- | --- | --- |
| `verify_characters.gd` | environment | `await` 缺 deadline，打完 appearances 后死等被强杀 |
| `verify_rpg_chapter_maps.gd` | test-drift | MansionPayment 距离倍率随地图重导漂移，README 已登记 |

> `verify_day1_return_feedback.gd` 曾因 4 路并发下 `0xC0000005` 登记在册；同日复跑两次均通过，
> 已按台账规则移出。若再复现，先串行 `--jobs 1` 确认，再考虑是引擎侧并发问题。

## 五、建议顺序

1. `verify_cinematic_integration` 的顾客走位（开场演出是玩家第一印象），并裁定开场时长该是 20–30s 还是 10s。
2. 三项「基线落后」批量改期望，成本低、收益是让红区只剩真问题。
3. `verify_tea_recipes` / `verify_warehouse_inventory` 的 UI 溢出与制作台默认模式——同属玩家可见的界面问题。
4. 其余按模块归属逐个确认。

发布验收命令：`python tests/run_all.py --strict-known`。

## 六、这次最值得记住的教训

`c52233fd` 的提交信息只提到"加酒馆地图 tile"，实际顺带重存了两个菜单资源，静默删掉 90 处手工维护的字段。四个测试项、61 条断言为它红了很久，而没人知道该去哪个提交里找。

两点防护已经落地：`src/resources/AGENTS.md` 写明批量重存的风险与逐字段恢复的方法；`tools/git/check_regression.py` 保证这类破坏不会再悄悄进来——它一出现就会挡住推送。

另有一项独立发现，未修：`python tools/milk_tea/import_recipe_ingredients.py --check` 报
`STALE basic_menu.tres, day1_menu.tres (22 rows)`。对 `HEAD` 版本跑同样报 22 行，说明这是既有
同步债而非本次恢复引入；它不影响当前任何一个验证项，但意味着这两份菜单已落后于
`recipe_ingredients_revised_2026_10_19.xlsx`，下次重导前要先确认这 22 行的差异是设计变更还是漏导。
