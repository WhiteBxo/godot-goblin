# Gameplay Bridge 独立验收剧情

编排约定：宿主为 `src/debug/gameplay_bridge/gameplay_bridge_demo.tscn`。
仅 Debug 运行时自动请求一次 `bridge.intro`；不重置已有 GameState。
此稿是技术验收内容，不替代第一天正式剧情。音乐使用已有 `AudioDemoTones`
注册的 CC0 室内环境采样循环 `demo.music_a`；成功事件结束后持续，最终不主动停止。

## Beat instruction

- 执行模式：自动演出
- 开场播放场景音乐，淡入 0 秒。
- 主角：「去奶茶制作台，按红茶、牛奶、珍珠的顺序制作一杯珍珠奶茶。」
- 末尾设置阶段 `bridge.make_tea`，结束事件 `bridge.intro`。

## Beat make_tea

- 执行模式：玩家操作
- 玩法完成条件：在 `tea_station` 完成固定配方 `pearl_milk_tea` 一杯。
- 配方步骤：红茶 → 牛奶 → 珍珠；错误顺序清空本杯进度。
- 前置事件：`bridge.intro` 成功完成；目标阶段：`bridge.make_tea`。
- 目标 ID：`bridge.make_tea`；完成 flag：`bridge.tea_done`。
- 允许关窗后重新打开继续制作；提前、其他交互点、重复完成均不计数。
- 完成后仍停留在制作弹窗，玩家关闭所有弹窗、解除暂停后请求 `bridge.after_tea`。

## Beat thanks

- 执行模式：自动演出
- 准入：前置 `bridge.intro` 已完成、阶段 `bridge.make_tea`、`bridge.tea_done` 为 true。
- 主角：「珍珠奶茶做好了，继续接下来的故事吧。」
- 末尾设置阶段 `bridge.finished`，结束事件 `bridge.after_tea`。
