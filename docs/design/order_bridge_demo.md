# 真实订单 Gameplay Bridge 最小示例

编排约定：独立 Debug 宿主 `src/debug/gameplay_bridge/order_bridge_demo.tscn`，复用奶茶店 MainGame。
正式入口是 settlement.tscn，它没有 TeaProduction，不自动播放本示例或正式 Day 1。
当前稿仅验证真实店铺的订单教学，不确定的正式聚落进店/转场不在本稿中实现。

## Beat opening

- 执行模式：自动演出
- 主角：「先去看看订单板吧。」
- 末尾设置阶段 `day1.before_order`，结束 `order_demo.intro`。

## Beat check_board

- 执行模式：玩家操作
- 玩法完成条件：在 `orders` 调查订单板，按既有交互 trigger 请求 `order_demo.tutorial`。
- 此段复用交互路由，不另建 Bridge wait。事件要求 `day1.before_order`、开场已完成，且教学未完成。

## Beat tutorial

- 执行模式：自动演出
- 主角：「第一单是珍珠奶茶：红茶、奶精、珍珠，再加糖浆。去制作台做好并交付吧。」
- 末尾设置阶段 `day1.waiting_order`，结束 `order_demo.tutorial`。

## Beat deliver

- 执行模式：玩家操作
- 玩法完成条件：TeaProduction 的订单 #001 成功交付；业务 flag `shop.order_001_delivered` 为 true。
- 历史策略：允许已有结果（`allow_existing: true`）。这一唯一订单提前交付也有效，不要求玩家重做已交付订单。
- 前置事件 `order_demo.tutorial`，阶段 `day1.waiting_order`，phase ID `order_demo.deliver`。
- 输出完成 flag `order_demo.delivery_done`，后续事件 `order_demo.after_order`。
- 此时再次调查 `orders` 没有匹配剧情，fallback 到 ShopUI 显示当前真实订单。
- 制作错误/库存不足/关闭弹窗不算完成；成功后仍等 modal 关闭、暂停解除。

## Beat continuation

- 执行模式：自动演出
- `order_demo.after_order` 要求教学已完成、阶段 `day1.waiting_order`、`order_demo.delivery_done` 为 true。
- 主角：「第一杯已经交付，接下来可以继续营业了。」
- 末尾设置阶段 `day1.after_order`。

## Beat board_after

- 执行模式：自动演出
- 阶段 `day1.after_order` 再调查 `orders`，触发一次 `order_demo.board_after`。
- 要求 `order_demo.after_order` 已完成、`shop.order_001_delivered` 为 true。
- 主角：「订单板上已经记下这杯珍珠奶茶了。」
- 完成后再次调查，fallback 到原订单 UI。
