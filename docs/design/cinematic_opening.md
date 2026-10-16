# Cinematic 开场（工作流基准稿）

本稿将已有 Cinematic Demo 转录为自然语言创作源，不是 Day 1 正式剧情定稿。此后本段剧情的内容只在本稿维护；JSON 是执行产物。首次转录不修改现有 JSON。

- 试玩宿主：`res://src/debug/cinematic/cinematic_demo.tscn`。
- Story：`res://src/resources/story/cinematic_opening.json`；事件 `cinematic.opening`，允许重播，无状态前置条件，无交互 trigger。
- Dialogue：`res://src/resources/dialogue/cinematic_opening.json`。
- 主角对应 `player`；暖色顾客对应 `customer`，场景为 `res://src/debug/cinematic/customer.tscn`（已有占位角色，不表示哥布林定稿）。
- 门口、过道、柜台分别复用宿主已注册的 `door`、`aisle`、`counter`，不改变位置。
- 房间底音、门铃、地下敲击分别复用 `cinematic.room`、`cinematic.bell`、`cinematic.rumble`，均为现有程序占位声音。
- 对白由玩家手动推进。验收时每段约阅读 4 秒，总长约 24 秒；不自动定时关闭对白。

## Beat quiet_shop

主角面向下方。房间底音以 -24 dB、0.5 秒淡入，等淡入完成。

主角·内心（对白 `cinematic.monologue`，行 `opening`）：

> 午后了，店里还是这么安静。希望今天能有几位客人……至少让我付得起下个月的房租。

对白结束后，停顿 1 秒。

## Beat arrival

播放门铃，等声音结束。主角面向右侧，镜头用 0.9 秒聚焦门口，等镜头到位。在门口生成暖色顾客。

镜头用 1.2 秒转为跟踪顾客，同时顾客以每秒 100 世界像素走到过道，超时 6 秒；到达后，以每秒 90 世界像素走到柜台，超时 7 秒。两段移动依次完成，不抄近路。

顾客到达柜台后面向左侧，头顶显示 `!`，持续 1.2 秒，等表情结束，再停顿 1 秒。

## Beat rumble

播放地下敲击声，同时镜头以强度 2 轻震 0.7 秒（沿用系统默认衰减 1.5）。等震动完成，再停顿 1.5 秒。

主角（对白 `cinematic.reaction`，行 `reaction`）：

> ……刚才的声音，是从地板下面传来的吗？别怕，先让我看看。

## Beat return_control

对白结束后停顿 1 秒。房间底音用 0.7 秒淡出并停止，等待完成。镜头立即恢复默认跟随，结束演出，恢复原来的移动和交互权限。顾客留在柜台。重播前由 Demo 清理上一位顾客并把主角放回既有出生点。
