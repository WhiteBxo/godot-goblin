# 应用图标

原图由项目作者于 2026-10-20 在对话中提供并更新，最新版本为白底圆形徽章，指定作为《我的奶茶店连通异世界》的应用图标，随本项目及其构建物使用。原文件保存在 `source/app_icon.png`，不随包导出。

在仓库根运行 `python tools/build/prepare_app_icons.py`（需要 Pillow）可重建全部格式：

- `app_icon.png`：512×512，项目与安卓传统图标。
- `app_icon.ico`：16、32、48、64、128、256 像素，Windows 文件与任务栏图标。
- `adaptive_foreground.png`：432×432，原画等比缩至中心 264×264 安全区。
- `adaptive_background.png`：432×432 白色底图，与原画背景一致。

只做格式转换和等比缩放，不重绘、裁切或修改原画文字。
