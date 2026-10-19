# 携杯、交付与采集的世界反馈（2026-10-20）

前两天循环里最重复的三个动作——做出一杯、走回柜台递出去、在夜里采一份材料——之前只有库存数字在变。本轮把"东西真的换手了"做成了可见的动效，没有新增物品、价格、任务或存档字段。

## 原来的问题

| 动作 | 改动前 |
| --- | --- |
| 制作完成 | 成品只进库存。`HeldItemVisual` 虽然挂在 `shop_player.tscn` 上，但只有潜入服务驱动它，所以走到柜台时手里是空的 |
| 交付 | 只有音效、底部提示条和钱包浮字；顾客没有反应，杯子凭空消失 |
| 收银台批量结算 | 一条"N 张订单"提示，没有钱的落点 |
| 采集 | 物件 `visible = false` 直接消失，只有一声 `gather_success`；采集弹窗里只有一行字 |

## 本轮改动

### 携杯（表现层，库存仍是唯一真相）

- `main.gd` 在三种制作入口成功提交后调用 `_carry_cup()`：已知配方用 `result.product_id`，自由实验/确认配方用 `result.id`；交付后由 `_settle_carried_cup()` 按该杯在库数量决定是否清空，绝不留下一杯已经不存在的奶茶。
- `HeldItemVisual` 新增 `set_item_texture()`：有产品图就画产品图，自由配方杯用 `custom_drink.svg` 的中性杯，潜入用的火把/硬币仍走原来的绘制。
- 手持物随移动做 1.5px 起伏（`_process` 按速度判断），停下归位。只改 `position`，手部锚点与 `z_index` 不变。

### 交付

- `_present_handover()` 在真实提交成功之后触发：杯从当前朝向的手部位置抛出一道弧线落到对方胸口高度，落点浮出 `+3G`，随后对方头顶弹一个 `♪`。
- 收银台批量结算改走 `_present_counter_payout()`：按结算杯数在世界里弹出杯子，金额浮字落同样位置。
- 全部表现都在提交完成之后，不参与扣料、结算或任务进度；扣的是本单的 `money_delta`，没有额外计算。

### 采集

- 采集成功后 `ShopUI.show_harvest_result()` 把材料图标与数量从弹窗空白区升起，采集文案用 `settle()` 落定，而不是整行文字瞬间替换。图标放在正文下方，不遮住玩家正在读的那句话。

### UIFlourish 的世界层

`src/UI/components/ui_flourish.gd` 新增三个世界坐标动效，全部只动 `position/scale/rotation/modulate`：

- `world_toss()`：手部到目标的弧线（含轻微翻转），落点金额浮字。
- `world_pop()`：原地弹出 1–3 个图标 + 数量浮字。
- `world_message()`：角色头顶的一次性反应（弹一下、上浮、淡出）。**刻意不走 `ActorDirector`**——避免一次交付就占用角色的演出控制，导致紧接着的剧情 `actor_move` 被拒绝。

三者都挂在一个短暂存在的 `WorldFlourish` 节点上（`z_index = 120`，`PROCESS_MODE_ALWAYS`，1.2 秒自毁）。浮层是关卡子节点而不是 Control，所以任何布局重排都挪不动它；采集弹窗打开、树被暂停时仍能播完。

## 验证

| 检查 | 结果 |
| --- | --- |
| `verify_gathering.gd` | 107 项通过 |
| `verify_business_session.gd` | 48 项通过 |
| `verify_order_board.gd` | 116 项通过 |
| `verify_order_ui.gd` | 45 项，2 项失败（`Settlement feedback keeps gameplay available`、`Keyboard Esc closes the board and restores movement`） |

`verify_order_ui` 的两项在**把本轮改动临时禁用后同样失败**，属于同一工作区另一路剧情/关卡改动的既有失败，不是本轮引入。逐帧截图用 `--path . --script` 的真实宿主脚本拍摄，未提交到仓库。

## 试玩步骤

1. 进店，在制作台做一杯（任一模式）：人物手里出现对应的杯子，走路时有轻微起伏。
2. 走到指定顾客前按 E 交付：杯子飞过去，对方头顶弹 `♪`，落点浮出 `+3G`；手里那杯若已经没了会消失，还有剩余则继续拿着。
3. 收银台累积多张可交付订单后按 E：一次结算，柜台处弹出杯子与总额。
4. 夜里到三处材料点任一按 E：弹窗里材料从正文下方升起，文案落定。
