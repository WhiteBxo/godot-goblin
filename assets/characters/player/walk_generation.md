# 角色素材生成记录

2026-10-16 使用内置 `image_gen.imagegen`，输出真实透明背景。用户原图 `player_sheet.png` 作为角色身份、衣着与像素画风参考。源图保留，生成图与派生图分开保存。

首轮将原图扩展为八列四行的行走图，再针对缺少收腿的侧面姿势迭代。最终行走图保存为 `player_walk_sheet.png`；以它为参考补充中立站姿，保存为 `player_idle_source.png`。下面记录最终两次调用的提示词。模型生成的实际格子位置与尺寸由处理工具检测并规范化，不将提示词中的尺寸要求视为已经验证的结果。

## 行走修整提示词

参考：首轮生成的八列四行草稿，草稿来自用户原图，要求保留黑发、蓝色卷袖衬衫、棕围裙、深色裤子与靴子。

```text
Refine this exact sprite sheet into a correct 8-frame walk cycle. Preserve the same 1536x1024 transparent PNG, 8 columns x 4 rows, same character identity, clothes, pixel art, direction per row. Critical fix: currently left/right rows repeat almost the same spread-leg pose, which must be replaced by SEQUENTIAL PHASES. For EACH row implement these exact eight columns in order: 1 left heel contact (left leg forward right back); 2 left planted with knees bent low, right heel lifts; 3 RIGHT KNEE SWINGS THROUGH, legs close together beneath pelvis; 4 right knee forward, trailing left heel lifts, body rises slightly; 5 RIGHT heel contact (opposite legs to column 1); 6 right planted knees bent low, left heel lifts; 7 LEFT KNEE SWINGS THROUGH with legs close together; 8 left knee forward, trailing right heel lifts. This is WALKING, not running. Alternate opposing arm swing too. Left/right views must visibly have four narrow/passing stances, not all spread leg poses. All heads remain the same size, torso vertical and centered, subtle 1-2px up/down bob only. Preserve tidy opaque contours with no translucent afterimages and no motion blur. Frame centers must be x=96+192*column, feet baseline y=240+256*row. Keep 32 sprites distinct separated by transparent gutters. No checkerboard painted into image, no ground shadows, no lighting glow, no extra marks. True alpha transparency outside each figure.
```

## 中立站姿提示词

参考：`player_walk_sheet.png`。

```text
Create the companion IDLE STANDING sprite sheet for the EXACT character in this reference. Match the reference pixel art character identity, head/body proportions, black short hair, light blue rolled sleeve shirt, brown apron, dark trousers and boots, crossed apron straps on back. Deliver a true transparent PNG exactly 1024x256 with FOUR equal 256x256 cells in ONE row. Cell 1 faces DOWN front, cell 2 faces LEFT strict profile, cell 3 faces RIGHT strict profile, cell 4 faces UP back. Each character stands naturally still with BOTH boots flat on the same baseline, feet side by side under hips, knees straight but relaxed, weight equally distributed. Arms hang relaxed at sides. NO walking, NO crossed legs, NO raised foot, NO knee bent up, NO wide stance. Preserve same size as reference figures: hair top about y=32, soles on y=240, height about 208px, torso centered on x=128 in each 256px cell. Keep ample transparent padding around each figure. Single crisp opaque outline, no motion blur, no ghosting, no glows, no translucent fringe, no floor shadows, no scenery, no text, no labels, no gridlines. These are static neutral rest poses.
```

待机源图实际为 2172 × 724；工具按四列检测不透明区域，以 nearest 缩至 208 像素高，并按躯干中心与脚底对齐到四个 200 × 300 格子。行走源图不改像素，使用 AtlasTexture 的 region 和 margin 对齐。渲染材质统一清理半透明杂色。

## 并脚过渡修正

用户指出旧循环仍缺少真正并脚的瞬间。此次使用内置 imagegen，以 `player_walk_sheet.png` 和 `player_idle_atlas.png` 为参考，单独生成四向并脚姿势，保存为 `player_passing_source.png`（实际 1254 × 1254，2 × 2 排列）。工具以相同 nearest 规范生成 `player_passing_atlas.png`，直接替换每个方向第 3、7 帧，并将这两帧相对时长设为 1.25。

```text
Make ONLY FOUR feet-together PASSING POSES to insert between left and right steps of the walking cycle in Image 1. Image 2 is the required legs and boots reference. VERY IMPORTANT: both knees nearly straight, both boots together immediately beneath the pelvis, soles side by side on the SAME horizontal floor level. The outer silhouettes of the two legs are parallel and touching or very close. No raised knee, no foot kicked behind, NO bent lifted leg, no straddling, no crossing legs, no forward/back spread. This is the instant when the feet come together during a simple RPG walking cycle. Follow the narrow closed-leg stance of Image 2 exactly. Arms are near the middle of the swing, hanging naturally near the hips. Preserve Image 1's character identity, EXACT head size/body proportions, blue shirt, brown apron, black hair and dark trousers/boots, same crisp pixel-art style. Four isolated full-body figures on TRUE TRANSPARENT background, no shadows or scenery. Arrange a clean 2x2 grid on a 1024x1024 PNG: top-left DOWN front; top-right LEFT profile; bottom-left RIGHT profile; bottom-right UP back. Use one character per 512x512 quadrant, centered on the torso, identical scale around 400px tall, ground baseline 475 within each quadrant. Down/up must visibly have TWO level boots touching side-by-side, left/right must visibly form a narrow vertical pair of legs, with both soles aligned. No text, no guides, no motion blur, no translucent fringes. The whole purpose of these four images is visibly FEET TOGETHER, unlike the spread and lifted walking frames.
```

逐帧确认：第 3、7 帧已实际引用并脚图集，脚底仍在 y=294；独立预览场景提供慢放和手动单步，供检查迈步与并脚的先后关系。
