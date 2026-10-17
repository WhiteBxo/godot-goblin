# 哥布林动作资源

本目录保存动作 SpriteFrames，角色场景与行为仍由 [characters](../characters/AGENTS.md) 和 [ActorDirector](../../core/actors/AGENTS.md) 管理。

- 复用既有角色的动作命名、朝向、帧顺序、速度与循环约定，先核对实际消费者，不只按源图排布猜测动作。
- 原图保存在 `assets/characters/goblin_actions/`；派生过程沿用 `tools/art/import_goblin_actions.py` 等现有工具。修改生成过程读 [工具规范](../../../tools/AGENTS.md)，保留可复现步骤与素材来源。
- 不通过拉伸整张素材修正尺寸；核对帧裁切、脚底锚点和角色原始比例。角色身份、碰撞和剧情顺序不写入 SpriteFrames 资源。

候选验证：`tests/verify_goblin_actions.gd` 与 `src/debug/goblin_action_preview/` 的相关预览；素材引用调整按局部验证处理。
