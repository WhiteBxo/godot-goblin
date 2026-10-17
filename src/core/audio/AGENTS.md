# AudioManager 与音频动作

本模块是跟随宿主生命周期的场景级音频服务，公开契约见 [AudioManager](../../../docs/systems/audio_manager.md)。

- 通过宿主 getter 或依赖注入使用已有 AudioManager；没有跨宿主需求时不增加 autoload，不在正式入口自动注册 Demo 音色或播放测试音乐。
- 保留 Music、SFX、UI 到 Master 的现有 Bus 路由；淡入淡出修改对应播放器音量，不改变整个 Bus 的音量。
- 声音通过 `sounds`、`register_sound` 或现有集中资源表绑定逻辑 ID；先核对宿主是否实际注册，不能用任意临时音调替代指定关键素材。
- 保持 AudioAction 的完成、取消与宿主退出清理语义。剧情有限 SFX、循环 SFX、BGM 的等待边界见 [剧情工作流](../../../docs/guides/story_authoring_workflow.md)，不能把循环音乐结束作为阻塞条件。
- 修改音频文件、来源或许可证读 [素材规范](../../../assets/AGENTS.md)；修改资源映射与动态加载读 [资源规范](../../resources/AGENTS.md)，核对导出包含范围。

候选验证：`verify_audio_manager.gd`、`verify_bgm_loop.gd`、`verify_sound_library.gd`，按 [验证分级](../../../tests/AGENTS.md) 只选本次涉及项；听感检查报告实际执行结果。
