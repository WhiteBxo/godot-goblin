# macOS 两日试玩版（2026-10-20）

按作者要求补出 macOS 安装包。内容、版本与素材与同日 Windows / 安卓包一致：版本 `0.1.0`，内容截止第二天结尾，应用名《我的奶茶店连通异世界》，图标沿用作者提供的插画。本次没有改动任何游戏逻辑、场景或资源，只新增了一个 dmg 产物和打包文档。

## 交付物

根目录为 `dist/mac_demo_20261020_24a4622/`，已在忽略列表内，不提交二进制构建物。

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `我的奶茶店连通异世界-v0.1.0-demo-macos-universal.dmg` | 184604335 字节（176.0 MiB） | `e5e1c2aff8dfc841cc1b154db0b460728648f048801edf4ceb27b94c451ac462` |

dmg 内含 `我的奶茶店连通异世界.app`、指向 `/Applications` 的「应用程序」快捷方式和 `试玩说明.txt`。同目录 `build_manifest.json` 记录构建来源、体积、校验值与验收结果，包旁附 `.sha256`。

## 构建来源

- 源码 `24a4622`，Godot `4.7.2.stable.official.ed1daf0bf`，`macOS` 预设，release 模板。
- 应用包：可执行文件 170963648 字节（universal），`Contents/Resources/我的奶茶店连通异世界.pck` 119183068 字节。
- `Info.plist`：`CFBundleIdentifier=com.godotgoblin.game`，`CFBundleShortVersionString=0.1.0`，`LSMinimumSystemVersion` arm64 为 13.0、x86_64 为 11.0。
- 签名方式为 ad-hoc（`Signature=adhoc`，带 hardened runtime 标志），**没有** Apple Developer ID，也没有公证。
- 本次首次安装导出模板：`~/Library/Application Support/Godot/export_templates/4.7.2.stable/` 原先为空，补入模板包中的 `macos.zip` 与 `version.txt`（`4.7.2.stable`）后才可导出。

## 本次实际验收

| 检查 | 结果 |
| --- | --- |
| `--export-release "macOS"` | 退出 0；编辑器退出时仍有插件对象 / 资源未释放诊断 |
| `codesign --verify --deep --strict` | 无输出，退出 0；`valid on disk`，满足 Designated Requirement |
| `codesign -dv` | `Format=app bundle with Mach-O universal (x86_64 arm64)`，`Signature=adhoc` |
| `lipo -info` | `x86_64 arm64` |
| `pck_preflight.py` | 2577 条目，113.66 MB；标题场景、`main.gdc`、`basic_menu.tres` 均在，文本资源未被转码，四种风味串完整，开发目录未泄漏 |
| 应用包直接启动 | `--quit-after 240`，退出 0；`Metal 4.0 - Forward+ - Apple M1`，日志 0 条 ERROR |
| 挂载 dmg 后启动 | 退出 0，日志 0 条 ERROR |
| dmg 内签名 | 挂载卷内 `codesign --verify --deep --strict` 通过，签名未因打包失效 |

## 未做与限制

- 未在 Intel 实机运行过；包里已含 x86_64 slice，但没有实机验收。
- 未公证、未签名分发证书，玩家首次打开需要右键「打开」或清除隔离属性，已写入 `试玩说明.txt`。
- 未做 App Store 上架配置（sandbox entitlements、商店元数据均未准备）。
- 未执行完整回归与两天流程验证：本次没有代码与资源改动，只做包体与启动验收。
- 组装 dmg 时 `hdiutil` 提示 `-volname/-format` 语法已废弃，改为 `diskutil image create` 的建议尚未跟进；当前命令仍可用。

流程、命令与验收清单见 [macOS 安装包与打包](../guides/macos_build.md)。
