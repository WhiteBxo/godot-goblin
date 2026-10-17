# 主角对话立绘：平静 / 说话

来源：用户于 2026-10-17 在本次任务中提供的两张图片。保留原图，未重新绘制或改变人物比例；素材权属仍按提供方授权管理。

| 用户附件 | 保留原图 | 游戏使用 |
| --- | --- | --- |
| `189a3b9acc3c14317cfeb3a5a98d525b.jpg` | `assets/characters/apron_man/source/player_neutral.jpg` | `assets/characters/apron_man/player_neutral_portrait.png` |
| `15ec2905059b20e0fb87c7b33f242f89.png` | `assets/characters/apron_man/source/player_talking.png` | `assets/characters/apron_man/player_talking_portrait.png` |

原图均为 1084×992。生成图片共用原图裁切框 `(331, 30, 721, 925)`，得到 390×895 RGBA PNG，未重采样、拉伸、镜像或修改表情。两个表情的空间对齐保持不变，旧 `player_portrait.png` 未覆盖。

## 可复现处理

运行 `python tools/art/prepare_player_portraits.py`（依赖 Pillow、numpy）：

1. 从画布外缘移除连通的近白背景；不全局删除白色，保留眼白与衣服高光。
2. 在源图 `(463, 465)` 与 `(553, 765)` 处分别清除手臂和腿间的封闭白底。
3. 对源图前 305 行的头发区域采用更严格的灰色背景判定，从外部连通区域移除发梢和发丝缝隙的灰白残边；保留被头发包围的原画高光。
4. 使用脚部轮廓蒙版移除鞋子外侧的地面阴影和残纸，并沿脚背、鞋尖收紧轮廓；源图第 760 行起，从外部连通区域继续去除较暗的中性灰地面残边，保留被黑色鞋子轮廓包围的鞋面和鞋底高光。轮廓点记录在脚本内，以原图坐标转换后执行。
5. 对外缘一像素去白色预混，降低暗背景下的白边；最后固定使用已接入的共同裁切框，至少留出 16 像素边距，避免清理残边后自动收窄画布造成位置变化。原图与重建脚本一并保留。

Godot 使用无损纹理导入、透明边缘修正、无 mipmap，保留生成的 `.import` 文件。对话 UI 使用原有 TextureRect 等比缩放，图片切换不改变排版。

## 验证入口

Godot F6：`src/debug/dialogue/dialogue_demo.tscn`。右上方“平静 / 说话 / 隐藏”通过 Manager 的公开方法即时换图；逐句 JSON 示例也位于 `demo.player_expressions`。观察头发白边、手臂和腿间透明、两张表情对齐、文字进度不重置、结束清理。

`tests/verify_dialogue.gd` 包含透明角、发梢灰白残边、内部空隙、脚部地面、鞋尖/脚背/脚跟/鞋底残边、同画布、逐字显示期间即时切换、默认图更新、JSON 优先级、下一句重置、选项焦点保持、完成与中止清理，以及试玩按钮的真实鼠标点击回归。

验证记录（Godot 4.7.2）：对话模块与独立试玩专项共 141 项通过；完整 `verify_dialogue.gd` 还有一项既存的 MainGame 状态断言失败：打开订单板除了设置 `shop.orders_viewed`，还会由已存在的任务系统设置 `task.shop.first_order.active`，旧断言仅预期前者。本次已用原测试逻辑复现该差异，未更改任务行为或该断言。实际渲染截图与暗底放大检查覆盖两个表情、头发、手臂/腿间和结束隐藏。
