# 屏幕转场视觉

API 与接入见 [ScreenTransition](../../../docs/systems/screen_transition.md)。

- 本模块的根为 ScreenTransition（Control），只显示转场视觉；场景切换、输入锁、暂停和剧情数据由宿主或导航协调，不在视觉脚本中处理。
- 挂到宿主的 TransitionLayer，沿用 layer 40、Always、关闭 follow viewport 的约定；使用时由宿主显式显示，待机与完成后隐藏对应层。
- 保持现有动作的完成、取消、重入与释放语义；取消或失败不能让视觉永久遮住游戏，也不能自行重置业务状态。
- 真正的进出场景流程另读 [导航规范](../../core/navigation/AGENTS.md)，视觉结束不等于场景切换成功。

候选验证：`tests/verify_screen_transition.gd` 与目标宿主 F6；仅视觉参数改动按局部验证处理。
