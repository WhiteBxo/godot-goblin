# 重新导出 macOS 与 Windows 安装包（2026-10-21）

源码从上次出包的 `24a4622` 前进到 `fe6d956`，中间隔了 31 个提交（136 个文件、4319 行新增），涵盖赌场与地图遮挡修复、蘑菇回程、立绘替换、整数缩放铺满、任务日志与委托文案等。本次按当前 HEAD 重做两个桌面平台的对外包，不改任何玩法代码。

## 交付物

根目录 `dist/installer_20261021_fe6d956/`，已被忽略，不提交二进制。

| 平台 | 文件 | 大小 | SHA-256 |
| --- | --- | --- | --- |
| macOS | `macos/我的奶茶店连通异世界-v0.1.0-demo-macos-universal.dmg` | 183644689 字节（175.1 MiB） | `4fe566649072d794a0970af5274e175bf2fa7d95c5c5f0b70780306a6df2c070` |
| Windows | `windows/我的奶茶店连通异世界-v0.1.0-demo-win64.zip` | 150307638 字节（143.3 MiB） | `3473c7f6646f12c4c3f3cb0030d154654cc161dba54ea4233c0eeac0070ba826` |

dmg 内含 `.app`、指向 `/Applications` 的「应用程序」快捷方式与 `试玩说明.txt`；zip 内含同名 exe、pck 与 `试玩说明.txt`，UTF-8 条目标志已校验。根目录 `build_manifest.json` 汇总两个包、校验值与验收结果，各包旁附 `.sha256`。

安卓未导出：本机没有 Android SDK，也没有 demo release keystore（`~/Library/Application Support/Godot/keystores` 不存在），只有模板缺少 SDK 也打不出 APK。

## 构建来源

- `macOS` 预设：universal（arm64 + x86_64），ad-hoc 签名，未公证；pck 118164084 字节，`icon.icns` 2871060 字节（已被「图标保留透明边」修复更新）。
- `Windows Desktop` 预设：x86_64，exe 109322752 字节，未做代码签名。
- 两个平台的 pck 都是 2577 条目；与 `24a4622` 那版同条目数，但体积与内容随剧情和立绘改动更新。
- 本机导出模板目录此前只有 `macos.zip`，这次补入 `windows_release_x86_64.exe`（同一模板包，`4.7.2.stable`）。

## 本次实际验收

| 检查 | 结果 |
| --- | --- |
| 资源导入 `--import` | 退出 0，仅退出期资源未释放诊断 |
| macOS `--export-release` | 退出 0；退出时仍有既有插件对象 / 资源未释放诊断 |
| Windows `--export-release` | 退出 0，同上 |
| macOS `codesign --verify --deep --strict` | 应用包与挂载后的 dmg 内均通过 |
| macOS `lipo -info` | `x86_64 arm64` |
| Windows PE | `PE32+ executable (GUI) x86-64`，产品名 UTF-16 资源存在 |
| `pck_preflight.py` | macOS 包内 pck 全部通过（关键场景、`main.gdc`、文本资源、四种风味串、无开发目录） |
| macOS 启动 | 应用包与挂载 dmg 各跑 `--quit-after 300`，均退出 0，`Metal 4.0 - Forward+`，0 条 ERROR |
| `package_demo.py` | zip CRC 通过，中文条目带 UTF-8 标志 |

## 测试结果与归因

`tests/verify_two_day_flow.gd` 跑出 **388 项，1 项失败**：`Accepted commission shows the real material shortfall`。

失败点在 `src/core/story/chapter_gameplay.gd:604` 的 `get_gathering_notice()`。该函数在 `24a4622` 里只要接受七日祭委托就直接列出食材清单；当前版本在 `day3.festival.available` 未置位时提前返回「七日祭委托 · 明天向酒馆老板确认食材清单。」，而该标志只在第三天置位，于是第二天接受委托时提示里没有「苔痕青 0/2 · 缺2」这类明细，与断言的预期不符。

这属于新剧情流程（第六阶段改为回店对质、食材清单次日到酒馆确认）带来的行为变化，断言没有同步，不是打包造成的。**但它同时影响第二天夜间采集的指引可读性**：玩家在当晚看不到还缺哪些材料。是否恢复明细、或在第二天用别的说法补上，需要作者判断，本次未改动代码，也未修改测试。

## 未做

- Windows 包未在实机运行（本机为 macOS），只做了 PE 头、资源名与 zip 结构检查。
- macOS 未公证、未用 Developer ID 签名；Intel 实机仍未验证。
- 未跑完整回归（`tests/run_all.py` 需要批量清理 `.godot/test_logs`，本次环境拦下了删除请求，只单独跑了上述两天流程脚本）。
- 未导出安卓 APK。

打包步骤见 [macOS 安装包与打包](../guides/macos_build.md) 与 [安卓手机试玩与打包](../guides/android_build.md)。
