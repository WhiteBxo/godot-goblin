# 奶茶店地图

本目录保留现有 `milkTea` 大小写。布局与遮挡依据见 [开放房间说明](../../../docs/levels/milk_tea_map.md)，业务体验另见 [奶茶店 MVP](../../../docs/levels/milk_tea_mvp.md)。历史尺寸记录不能覆盖当前场景实际配置。

- `milk_tea_shop.tscn` 是地图组件，独立游戏宿主为 `src/core/main.tscn`；地图不负责制作、订单、库存或玩家输入。
- 家具、交互点、出生点和出口跟随地图配置；业务服务由宿主取得并注入。改对象 ID 或 Marker 时检查真实剧情路由与导航入口的直接引用。
- 开放房间沿用现有通路与局部遮挡；修改房间或门框前景先读 [rooms/AGENTS.md](../../gameplay/rooms/AGENTS.md)，不要为显示效果添加移动锁、镜头控制或额外门碰撞。
- 原图、地面与遮挡裁片遵守 [地图素材规范](../../../assets/map/AGENTS.md)；不通过拉伸整张背景、改整图透明度或重画家具修正局部问题。
- 制作台、订单板与仓库交互读 [交互规范](../../gameplay/interaction/AGENTS.md)；店铺业务读 [制作与库存规范](../../gameplay/milk_tea/AGENTS.md)，出入口读 [导航规范](../../core/navigation/AGENTS.md)。

候选验证：`verify_milk_tea_shop.gd`、`verify_shop_camera.gd`、`verify_shop_equipment.gd` 和相关房间检查；选择受影响项，并 F6 目标宿主观察局部通行 / 遮挡。
