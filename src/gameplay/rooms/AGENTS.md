# 房间遮挡与门框前景

表现与场景配置见 [开放房间与遮挡渐隐](../../../docs/levels/milk_tea_map.md)。

- RoomReveal 只控制本房间的 Occlusion，DoorframeForeground 只处理相应前景显示；不创建或修改 Camera2D，不锁玩家移动，不管理剧情状态。
- 保持原背景和家具素材的显示 / 碰撞职责，局部遮挡使用裁片或对应前景节点，不改变整张背景透明度或比例。
- `_ready` 时物理 overlap 尚未同步，且宿主可能随后设置玩家出生点；初始显隐须考虑首次物理同步，避免室内出生时屋顶闪现。
- 范围、遮挡层级和可见性属于所属关卡配置；改店铺布局读 [店铺规范](../../levels/milkTea/AGENTS.md)，Shader 改动读 [着色器规范](../../shaders/AGENTS.md)。

候选验证：`tests/verify_room_reveal.gd` 与目标房间 F6，观察室内出生、进出边缘、局部渐隐及遮挡前后通行行为。
