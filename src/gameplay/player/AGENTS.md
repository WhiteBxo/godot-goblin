# 玩家移动与控制

适用于 PlayerController、玩家场景、视觉与跟随相机的玩家侧接入。

- 输入只读取既有 InputMap actions；NPC 复用控制器时关闭 `accepts_player_input`，不能读取真人玩家输入。
- 移动、朝向、速度与演出控制使用现有公开接口；演出接管保持 owner 的领取 / 释放契约，不让普通输入与 ActorDirector 同时驱动角色。
- 物理层和隐藏 NPC 规则见 [玩法通用规范](../AGENTS.md)；移动查询由宿主注入，坐标换算由地图集中提供，不能复制格子尺寸或查地图内部节点。
- 速度使用世界像素 / 秒，加减速度使用世界像素 / 秒平方；修改手感参数同时核对正常移动、停止、碰撞与演出移动。
- 角色素材保持原始比例，校准以约 110 世界像素高的主角为基准；视觉与切帧来源见 [角色素材说明](../../../assets/characters/player/README.md) 和 [素材规范](../../../assets/AGENTS.md)。
- 玩家保留既有唯一跟随相机；镜头调度读 [CameraDirector 规范](../../core/camera/AGENTS.md)，房间遮挡不反向接管玩家或镜头。
- `BoundedFollowCamera.follow_look_ahead` 默认 0，当前只有 RPG 玩家开启 8 世界像素前瞻；前瞻仍受地图边界钳制，停步时归零。

候选验证：`tests/verify_player.gd`、`tests/verify_player_visuals.gd`；按风险选择实际运行项，并给出移动、碰撞或视觉的试玩结果。
