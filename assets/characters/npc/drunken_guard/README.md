# 醉酒守卫小人

2026-10-24 按现有 [守卫立绘](../../dialogue/guard_portrait.png) 使用内置 imagegen 生成；原始输出、生成说明和处理参数分别保存在 `source/generated_sheet.png`、[提示词](source/prompt.txt)、[处理清单](source/processing.json)。铁桶盔、大眼睛、棕色破衣和酒桶与立绘一致。

四行依次为正面待机、正面行走、朝右行走、背面行走，各 4 帧。脚本以统一包围框、统一等比倍率和最近邻取样导出 128px 帧，脚底锚点为 y=126。左右共用朝右图，由角色控制器镜像；侧面和背面待机使用相应行走首帧，没有伪造额外动作。

步频为行走 5 FPS、正面待机 4 FPS。行走四帧循环为 0.8 秒，比初版 8 FPS 更舒缓；角色位移速度与剧情移动时序不变。

重建：`python tools/characters/build_drunken_guard.py`。原始输出保持不变；运行时只引用四张派生图和 `drunken_guard_frames.tres`。`rpg_drunken_guard.tscn` 继承原 RPG 守卫的输入、碰撞和半尺寸配置，地图内仍使用 `drunken_guard` Actor ID。酒馆外的醉鬼与普通守卫使用各自原有资源。
