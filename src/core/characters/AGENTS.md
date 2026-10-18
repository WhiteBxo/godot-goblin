# 人物记录

接口与试玩见 [人物记录模块](../../../docs/gameplay/character_records.md)。

- CharacterJournal 管理人物解锁、追加情报与已读状态，唯一进度保存在已有 GameState 的 `characters.entries`；不借用见闻录、不新增 autoload。
- 稳定人物 ID 和全局唯一记录 ID 保持重试幂等；查询返回副本。整局 reset / restore 与场景重建保留既有通知、订阅和状态边界。
- CharacterRecordsPanel 嵌入统一手册，遵守 [UI 规范](../../UI/AGENTS.md) 和 [手册规范](../../UI/handbook/AGENTS.md)，只展示主角已获得的信息，不推断身份、关系或招募能力。
- 剧情使用 `character_unlock` / `character_append`，宿主注入服务。内容与顺序仍由剧情数据维护，另读 [剧情规范](../story/AGENTS.md)。

验证按 [分级规范](../../../tests/AGENTS.md) 选择 `verify_character_records.gd` 和直接受影响的手册、剧情或存档检查。
