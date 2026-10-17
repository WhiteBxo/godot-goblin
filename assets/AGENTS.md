# 素材来源、派生与导入

本目录按用途保存图片、音频、字体等素材；可复用数据定义属于 `src/resources/`，处理脚本属于 `tools/`。

- 保留源素材与派生素材的区别，记录来源、授权和必要处理步骤，沿用现有分类并保留可复现的处理方式；用户要求保留的原图不被派生结果覆盖。
- 素材与必要的 `.import` 设置一起提交，`.godot/` 派生缓存不提交、不作为运行时源文件；修改导入设置只覆盖任务所需项。
- 不通过拉伸整张角色或场景素材修正尺寸 / 布局。地图与角色以约 110 世界像素高的主角校准比例；不合适时按相关模块规范重新生成。
- 角色原图、透明派生立绘与动画分别核对，不能用对话立绘替换行走动画。来源与处理见 [角色 README](characters/README.md)、[玩家 README](characters/player/README.md) 和 [人物接入](../docs/assets/characters.md)；角色消费者读 [NPC 规范](../src/gameplay/characters/AGENTS.md) 或 [玩家规范](../src/gameplay/player/AGENTS.md)。
- 地图美术、建筑比例与遮挡裁片另读 [map/AGENTS.md](map/AGENTS.md)，改显示时同时核对对应 [关卡规范](../src/levels/AGENTS.md)。
- 音频保留 [许可证](audio/LICENSE.md)，逻辑 ID 与绑定见 [音效库](../docs/assets/sound_library.md) 和 [音频规范](../src/core/audio/AGENTS.md)；生成映射与处理脚本读 [工具规范](../tools/AGENTS.md)。
- 字体保留随素材的来源、版本与许可证；接入共享 Theme 时读 [UI 规范](../src/UI/AGENTS.md)，不为单个界面替换全项目字体。
- 运行时资源引用与动态加载必须可导出，见 [资源规范](../src/resources/AGENTS.md)。仅更换立绘或音效引用时采用局部解析和目标宿主观察，不默认完整回归。
