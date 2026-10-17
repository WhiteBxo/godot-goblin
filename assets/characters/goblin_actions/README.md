# 哥布林攻击与无背包走路动画

来源：用户于 2026-10-17 提供的 `攻击动画合集.zip`。15 张 PNG 按原始字节导入，未缩放、重绘或裁掉武器。附件未附许可证；授权信息以用户提供为准。`manifest.json` 记录原始中文路径、英文文件名、SHA-256、格子、步长、帧数和播放设置；忽略 `__MACOSX` 元数据。

## 动画资源

| 资源（`src/gameplay/goblin_actions/`） | 攻击：正面 / 侧面 / 背面 | 走路：正面 / 侧面 / 背面 | 原始单帧 |
| --- | --- | --- | --- |
| `goblin_frames.tres` | 9 / 12 / 8 | 9 / 15 / 15 | 64×64 |
| `guard_frames.tres` | 9 / 10 / 10 | — | 64×64 |
| `captain_frames.tres` | 10 / 13 / 9 | — | 256×256 |
| `chef_frames.tres` | 12 / 9 / 9 | — | 64×64 |

动画名使用 `attack_down/side/up`、`walk_down/side/up`。方向按原图人物朝向识别，非附件文件名声明。侧面朝右，可用 `AnimatedSprite2D.flip_h = true` 朝左；正面、背面应恢复 false。未伪造缺失方向或待机帧。

统一以 12 FPS 等帧时长作为初始播放节奏，攻击单次停止在末帧，走路循环；可在 SpriteFrames 编辑器中调整速度。源图每行 6 格，格间 24 像素透明留白；按行优先读取，只保留有内容的格。AtlasTexture 开启 `filter_clip`，PNG 使用无损导入、关闭 mipmaps，显示节点使用 nearest。保存原始格子锚点，保留动作中的身体位移。

将对应 `.tres` 赋给 `AnimatedSprite2D.sprite_frames` 即可使用。攻击结束可监听 `animation_finished` 恢复调用方的待机动画；循环动画不会发此结束信号。当前交付为独立美术动画库，不改变主角与 NPC 的现有动作或战斗规则。

## 预览与验证

打开 `src/debug/goblin_action_preview/goblin_action_preview.tscn` 按 F6。选择角色与动作，可暂停、逐帧前后检查、重播、调整速度，侧面动作可切换镜像。攻击到末帧停止，点击播放或重播从头开始；走路持续循环。预览仅以统一比例缩放显示（普通角色 3 倍、守卫长 0.75 倍），资源仍保留原始像素尺寸；背景参考线代表格子底边，不是逐帧贴地修正。

```sh
# 从源附件导入并生成资源（仅 Python 标准库）
python3 tools/art/import_goblin_actions.py /path/to/攻击动画合集.zip
# 不传附件则直接用已导入 PNG 重建 manifest 和四个 SpriteFrames
python3 tools/art/import_goblin_actions.py
godot --headless --editor --path . --import --quit
godot --headless --path . --script tests/verify_goblin_actions.gd
# 带渲染检查，截图写入 /tmp/goblin_action_preview.png
godot --path . --script tests/verify_goblin_actions.gd -- --capture
```

测试覆盖 15 段动画、159 个非空帧、全部源图可见像素覆盖、播放结束/循环行为、预览角色/动作切换及逐帧重播。

核对 Godot 4.7 官方文档：[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html) 的帧速度与循环设置；[AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html) 的 region 和 filter_clip；[AnimatedSprite2D](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html) 的暂停、重播、flip_h 与 animation_finished。
