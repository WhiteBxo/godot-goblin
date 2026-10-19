# 普通哥布林正面与背面待机

2026-10-19 按用户要求，通过内置 imagegen 编辑模式，以仓库现有角色走路图集为参考生成缺失的待机图集。新增的是独立美术帧，动作是原地呼吸；无背包正面包含一次眨眼。背包版已有的正面 16 帧待机继续使用原素材。

| 图集 | 参考原图 | 接入动画 | 帧数 |
| --- | --- | --- | --- |
| `backpack_idle_up.png` | `../walk_sheet_03.png` | 背包版 `idle_up` | 8 |
| `unpacked_idle_down.png` | `../../../goblin_actions/goblin_walk_down.png` | 无背包版 `idle_down` | 8 |
| `unpacked_idle_up.png` | `../../../goblin_actions/goblin_walk_up.png` | 无背包版 `idle_up` | 8 |

生成原图保存在 [source/](source/)，完整提示词见 [prompts.json](source/prompts.json)，按用户反馈进行的颜色修正提示词见 [color_correction_prompts.json](source/color_correction_prompts.json)。共同要求：保留原角色身份、服装、比例、橄榄绿和棕色像素配色；严格保持正面或背面视角；双脚着地，仅做轻微呼吸；4 列 × 2 行、按行排列的 8 帧循环；透明背景，无武器、阴影、文字和格线。背包版保留大背包，无背包版不添加背包。生成结果可能存在细微造型差异，以已提交图集为准。

`source/.gdignore` 避免高分辨率生成原图被作为运行时纹理导入。原图保持生成字节，派生流程在 [build_common_goblin_idle.gd](../../../../../tools/characters/build_common_goblin_idle.gd)：分离 8 个格子，清理低于 0.5 的微弱 alpha，按各自参考原图的第一帧高度使用统一等比 nearest 缩采样，逐帧对齐原始脚底与水平中心，打包为 256×128 的 RGBA PNG。每帧仍为原生 64×64，不拉伸整张图集；播放为 6 FPS 循环。纹理无损导入，关闭 mipmaps。

颜色锁定同样由派生工具完成：按肤色、裤子、皮革、轮廓与中性色分组，对齐原图的主要色调，再把每个可见像素映射到对应原始走路图集实际存在的 RGB。新动画不引入原调色板之外的颜色。专项测试逐像素核对这个约束，避免生成式配色在待机与行走切换时漂移。

无背包正面额外保留眼白高光：生成图中的中性白与原走路图中的暖米色眼白单独匹配，避免中性白被映射到仅含暗色的中性色组。该处理只作用于无背包正面，不改变肤色、衣服或背面动画。第 5 帧保留闭眼，其余 7 帧在原生 64×64 格内均保留左右眼白与深色细节。

运行时由 [common_goblin.gd](../../../../../src/gameplay/characters/common_goblin.gd) 使用独立 SpriteFrames 覆盖缺失的待机方向。原始资源不被改写；走路与侧面待机沿用现有资源。普通场景与 RPG 缩小版场景共用这套接入。

在项目根目录执行（`godot` 指向 Godot 4.7）：

```powershell
godot --headless --path . --script tools/characters/build_common_goblin_idle.gd
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/verify_common_goblin_idle.gd
godot --headless --path . --script tests/verify_characters.gd
```

打开 [common_goblin_idle_preview.tscn](../../../../../src/debug/characters/common_goblin_idle_preview.tscn) 后按 F6，从左到右观察背包正面、背包背面、无背包正面、无背包背面。点击“走两步，再回到待机”，可观察两个方向的行走到待机切换，随后角色回到原位。专项测试覆盖两种场景、两种外观、前后方向、真实帧变化、循环、脚底锚点、停止移动后的播放和原始资源隔离。

API 核对：[Godot 4.7 SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html) 的帧速率与 `LOOP_LINEAR`；[AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html) 的 `region` 与 `filter_clip`。每个新图集的 8 个 64×64 区域独立切帧，避免相邻格串色。

首轮验证：专项测试 272 项通过；重建三张 PNG 和 SpriteFrames 的 SHA-256 完全一致；Godot Compatibility 渲染预览成功。`verify_characters.gd` 共 12859 项检查，8 项聚落 NPC 注册失败；在独立进程内使用提交前的角色脚本与原测试复现相同 8 项失败（12845 项检查），不属于本次动画改动。编辑器导入成功退出，但仍报告退出时的 495 个 ObjectDB 实例与 10 个资源未释放诊断；专项运行与渲染预览没有这些诊断。本次未运行全项目回归，改动不涉及公共玩法状态或剧情。

眼白修复验证：专项测试新增 16 项双眼对比度和眨眼检查，共 288 项通过；Compatibility 实际渲染中可见浅米色眼白。与提交前图集逐像素比较，变化仅限眼白与牙齿高光区域，身体配色未变；旧图集的 14 只睁眼均无法通过新的眼白检查，修复后全部通过。编辑器导入仍有上述既有退出诊断，本次局部修复未重复运行角色模块或全项目回归。
