# 哥布林洞窟大地图生成记录

- 日期：2026-10-19
- 工具：内置 image_gen
- 参考：用户提供的集市、公共区、西商业区、东居民区分区草图。
- 运行时图片：`../goblin_cavern_overview.png`（相对本目录的上一级）。
- 图片不包含动态标记；地点名称、玩家与目标由 Godot 叠加。
- 未改动实际 TileMap、通行与建筑布局。

## 最终提示词

Use case: sketch-to-render. Asset type: illustrated in-game overview map for a Chinese pixel-art goblin milk-tea RPG.
Transform the attached hand-drawn map into a finished top-down cavern settlement cartography painting. Preserve its topology: WEST commercial district with warehouse near upper-left and riverside workshop below, casino lower-left; CENTRAL civic district with ritual altar at top, a broad residential public square surrounding a communal hearth in the middle, and market at bottom with a small milk-tea shop on the market's lower-right edge; EAST residential district with elder's grand house at upper-right, barracks beneath, ordinary homes farther down, tavern between civic square and eastern homes. A main north-south road runs altar -> communal hearth -> market; east and west district roads and connecting small lanes follow the reference.
Composition: portrait 4:5 map, one continuous flat cave floor enclosed by a rocky perimeter. No separate floating islands, no independent caves for each district. Clean nearly-black pixel-like outlines, stepped edges, restrained flat shading, readable brown stone and timber buildings, warm parchment earth palette, muted moss accents, small warm lights. Map ornament is minimal, usable as a game interface illustration. No characters or guards. Landmark artwork should be arranged at approximately normalized map coordinates: altar (0.49,0.16), elder house (0.85,0.19), barracks (0.79,0.37), warehouse (0.21,0.23), workshop (0.13,0.54), central hearth square (0.49,0.56), casino (0.25,0.79), tavern (0.63,0.70), market (0.49,0.91), milk-tea shop (0.67,0.95), eastern homes (0.86,0.70). Leave calm negative space beside each landmark for runtime UI labels. Output the map art only, full image edge to edge, no frame, no panel, no buttons.
Text: absolutely no text, numbers, lettering or labels; game code overlays all names, player position, arrows and objectives. Do not copy the reference's handwritten words or colored marker lines. Render roads as believable pale stone/dirt paths, not neon strokes.
