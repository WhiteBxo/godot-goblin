# RPG Maker 移植地图

- 现行地图以 `map_001.tscn`、`map_004.tscn`、`map_005.tscn`、`map_006.tscn` 内的 TileMapLayer 为准；源快照和 catalog 仅供显式离线转换，运行时不得重铺格子。
- 原点为地图左上，原生图块 48 世界像素。`Ground0..3` 保存普通图块，`Upper0..3` 保存各原始层的星号图块；阴影、桌沿独立保存。手绘时把星号图块放对应 Upper 层，并按需要同步相邻桌沿。
- TileSet 的 `rpg_tile_id`、`passage`、`star` 是通行契约；passage 的 1/2/4/8 分别表示下/左/右/上阻挡。空格及星号不决定通行，从高到低的首个非星号格决定方向。共享 TileSet 修改会影响所有引用地图。
- `rebuild_passability()` 只从已保存格子派生世界层碰撞，不改格子；部分方向阻挡使用边界碰撞，不能简单替换成整格实心。坐标转换和通行查询集中在地图公开方法。
- 家具前后遮挡在原始地图根节点的 `depth_sorted_regions` 配置图层、格子矩形与共同脚线 `sort_y`（地图本地像素）。同一物件跨格 / 跨层共用脚线；默认最终 `z_index = 0` 与人物排序，贴地兽皮、污渍可指定 `-1`。宿主调用 `configure_depth_sort()`；运行时仅覆盖 TileData 的绘制属性，不搬动保存格子、不改共享 TileSet。实体家具另配 `solid_regions` 或保存的 passage，贴地装饰不加实心碰撞。
- `Spawn` 是可编辑试玩出生点；源项目没有有效起点或地图事件，当前出生点由最大可达区域确定，不代表剧情锚点或传送连接。
- 试玩和截图使用 [独立宿主](../../debug/rpg_maker/rpg_maker_preview.tscn)。使用 `rpg_player.tscn` 半尺寸玩家与 2 倍跟随镜头，z_index 为 0，与已配置家具按脚底排序，未配置的 Upper 保持前景；正式 RPG 宿主使用同一玩家的 1 倍镜头。RPG NPC 使用 `rpg_*.tscn` 派生场景，不能通过缩小共享基础角色影响独立奶茶店。
- 人物能力距离按半尺寸角色配置：RPG 交互使用 `rpg_interaction_point.tscn`，守卫视听距、投掷射程及效果空间倍率在章节场景中配置；时间、角度和地图锚点不跟随缩放，不能回改共享基础参数影响奶茶店。
- 正式接线在 `chapter_*.tscn` 继承场景内维护，原始 `map_*.tscn` 不承载剧情。`RpgChapterMap` 只查询门、锚点、交互和外景数据；`RpgWorldMapData` 的命名入口与场景位置同步。地图与业务规则见[两天对接约定](../../../docs/design/two_day_flow_integration_plan.md)。
- 重导入必须明确输出路径；覆盖已手工编辑场景需要工具的显式 `--replace`。完整流程、校验与许可限制见 [移植说明](../../../docs/levels/rpg_maker/README.md)。
