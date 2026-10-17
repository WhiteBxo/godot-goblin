# 第三方插件边界

本目录保存随项目提交的第三方插件。日常任务只检查直接相关依赖，不全面审查或批量改写插件。

- 优先通过项目配置或项目代码封装接入，保留插件源码、许可证、版本信息和 UID；既有插件 autoload 不迁入 MainGame 的 Systems。
- 插件源码修改或升级必须单独提交，记录原因、版本变化及实际验证结果，不夹带在玩法或文档整理提交中。
- 开发插件的运行时边界优先由项目侧管理。MainGame 在 Release 停止 MCPRuntimeProbe 的处理，避免无 debugger 时逐帧轮询；不要为此改插件源码。项目接入见 [入口规范](../src/core/AGENTS.md) 和 [Debug 规范](../src/debug/AGENTS.md)。
- 修改插件配置前核对 `project.godot` 的 autoload 与启用插件依赖；验证范围按 [tests/AGENTS.md](../tests/AGENTS.md) 选择。
