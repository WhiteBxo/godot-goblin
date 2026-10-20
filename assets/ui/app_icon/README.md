# 应用图标

原图由项目作者于 2026-10-20 在对话中提供并更新，为四周透明的圆形徽章，指定作为《我的奶茶店连通异世界》的应用图标，随本项目及其构建物使用。原文件为 1254×1254 RGBA，保存在 `source/app_icon.png`，不随包导出。

在仓库根运行 `python tools/build/prepare_app_icons.py`（需要 Pillow）可重建全部格式：

- `app_icon.png`：512×512 RGBA，保留原画的圆形透明边，用作项目图标与安卓传统图标。
- `app_icon.ico`：16、32、48、64、128、256 像素的 32 位图标，逐层带 alpha，四角透明。
- `adaptive_foreground.png`：432×432 RGBA，原画等比缩至中心 264×264 安全区，安全区外透明。
- `adaptive_background.png`：432×432 白底。自适应图标要求背景层不透明，这一层是按格式要求补的底色，不是原画自带的背景。

只做格式转换和等比缩放，不重绘、裁切或修改原画文字。早期版本把 RGBA 原画 `convert("RGB")` 压到白底再导出，Windows 任务栏、桌面快捷方式与安卓自适应前景因此都带白方块；现在直接保留原画 alpha，补边也用全透明。前后对比见[对比图](../../docs/assets/captures/app_icon_alpha_2026_10_20.png)。
