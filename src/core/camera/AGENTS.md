# CameraDirector 与镜头动作

接口和通道语义见 [CameraDirector](../../../docs/systems/camera_director.md)。

- 复用玩家现有的唯一 BoundedFollowCamera，通过宿主注入；不创建第二个 Camera2D，也不接管玩家输入、碰撞或对话 UI。洞穴旧相机不具备此能力时保留明确的不可用状态。
- 位置使用全局世界坐标，duration 使用秒，震动强度使用逻辑视口像素，不能随窗口放大改变逻辑强度；实际视口参数以项目配置为准。
- 跟随、聚焦、缩放、震动保持当前通道替换与并行语义；取消、目标释放和退出时正确结束 CameraAction 并恢复受影响的相机状态。
- 房间遮挡不通过镜头实现；房间模块边界见 [rooms/AGENTS.md](../../gameplay/rooms/AGENTS.md)。涉及地图边界或出生点时同时读 [关卡规范](../../levels/AGENTS.md)。

候选验证：`tests/verify_camera_director.gd`、地图直接相关的相机检查及宿主 F6；按 [验证分级](../../../tests/AGENTS.md) 选范围。
