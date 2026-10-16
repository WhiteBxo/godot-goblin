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
