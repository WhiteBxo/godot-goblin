# Fusion Pixel 中文字体

- 上游：[TakWolf/fusion-pixel-font](https://github.com/TakWolf/fusion-pixel-font)，版本 `2026.09.01`。
- 原始包：[12px monospaced OTF WOFF2](https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.09.01/fusion-pixel-font-12px-monospaced-otf.woff2-v2026.09.01.zip)。
- 保留原包中的简体中文字体 `fusion-pixel-12px-monospaced-zh_hans.otf.woff2`、`OFL.txt` 和 `LICENSES/`，字体未修改，未裁剪字符集。
- 主许可证为 SIL Open Font License 1.1，衍生字体许可证随 `LICENSES/` 一起保留。
- 可复现步骤：下载上述固定版本 zip，仅提取上述字体、`OFL.txt`、`LICENSES/`。Godot 4.7 直接导入 WOFF2；`.import` 随仓库保存，`.godot` 缓存不提交。
- 使用 12px 字号及其整数倍，关闭抗锯齿与系统 fallback，保证像素外观和中文可读性。这里只供通用对话 UI 与独立试玩场景使用。
