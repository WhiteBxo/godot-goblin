# 对话加载与运行

接口、数据与 UI 协议见 [对话系统](../../../docs/systems/dialogue_system.md)；内容编排另读 [剧情源稿规范](../../../docs/design/AGENTS.md)。

- DialogueLibrary 负责 JSON 加载与校验；失败保留上一份有效目录，对外返回独立数据副本，不把解析规则散落到 UI。
- DialogueManager 管理当前对白、推进、选择和结束，不读写 GameState，不管理玩家、店铺或剧情步骤。剧情状态由调用它的调度层处理。
- DialogueUI 负责姓名、可选立绘、纯文本逐字显示、选项按钮与输入请求，不解释 `next` 或业务选项 ID；UI 的层与模态规则见 [UI 规范](../../UI/AGENTS.md)。
- 分支依据稳定的 `next` / `choices` ID，不按显示文本匹配；逐字保留源稿中的台词与标点，内容变动同步其来源和 Beat 清单。
- 立绘先核对当前说话人的真实资源绑定及导出引用；素材来源与派生处理见 [素材规范](../../../assets/AGENTS.md)。

候选验证：解析或运行逻辑用 `tests/verify_dialogue.gd` 加直接调用方；单句、立绘引用用对应清单和宿主 F6，遵守 [验证分级](../../../tests/AGENTS.md)。
