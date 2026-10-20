# 最终 Demo：Windows 与安卓（2026-10-20）

本次按作者要求，将游戏更名为《我的奶茶店连通异世界》，使用作者提供的插画作为应用图标，重新导出 Windows 与安卓两日试玩版。版本仍为 `0.1.0`，内容截止第二天结尾。此前旧名称的 Windows 包由本次双平台包取代。

## 交付物

根目录为 `dist/final_demo_20261020_a23c7962/`，全部产物已忽略，不提交二进制构建物。

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `我的奶茶店连通异世界-v0.1.0-demo-win64.zip` | 151179742 字节（144.2 MiB） | `205d87bcf5c4ed0645f75035e4a5d1c1042f5ddd7d60d0adcefa3728f54e48d3` |
| `android/我的奶茶店连通异世界-v0.1.0-demo-arm64.apk` | 141928919 字节（135.4 MiB） | `39a869bd54069f5d664e403fe80d91cda6fe260aff2260241e40b1c542b84b41` |

Windows zip 内含同名 exe、pck 和 `试玩说明.txt`，必须整包解压再运行。安卓为可直接侧载的签名 Release APK，Android 7.0 以上、ARM64、OpenGL ES 3；安装与操作说明在同目录 `试玩说明.txt`。各包旁附 `.sha256`，根目录 `build_manifest.json` 记录构建来源、大小、校验值及验收结果。

## 名称、图标与签名

- 基于源码 `a23c7962` 加本次更名、图标及打包说明改动；Godot `4.7.2.stable.official.ed1daf0bf`，两个平台均使用 release 模板。
- 更新 `project.godot` 应用名、项目图标与 Windows 原生图标，Windows 产品名及文件说明、安卓显示名、标题菜单、结尾卡及分发包命名。
- 店内招牌「小小奶茶店」是剧情中的店名，继续保留。安卓应用 ID 仍为 `com.godotgoblin.game`。
- 图标原图与来源说明见 [图标目录](../../assets/ui/app_icon/README.md)。只转换格式和等比缩放；Windows ICO 含六种标准尺寸，安卓自适应前景保留中央安全边距。
- 安卓使用本机新建的独立 Demo release 密钥。密钥与复现导出所需的凭据分别保存在 `%APPDATA%/Godot/keystores/godot_goblin_demo.keystore` 和 `godot_goblin_demo_signing.json`，均在仓库外；不随包分发。Windows 未做代码签名。
- 更名后的 Windows 默认存档目录为 `%APPDATA%/Godot/app_userdata/我的奶茶店连通异世界/`。旧名称目录仍在，未改写；要继续旧进度，可将旧目录中的 `saves` 复制到新目录。

实现核对了 Godot 4.7 官方 [Windows 图标格式与六种尺寸](https://docs.godotengine.org/en/4.7/tutorials/export/changing_application_icon_for_windows.html) 和 [安卓图标安全区、签名及环境变量](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html)。

图标透明修正（2026-10-20 晚）：本轮包内图标仍是把 RGBA 原画压成 RGB 白底的版本，Windows 任务栏、桌面快捷方式与安卓自适应前景会显示白方块。`prepare_app_icons.py` 已改为保留原画 alpha（PNG 与 ICO 各尺寸逐层透明，自适应前景安全区外透明），图标文件已按新逻辑重新生成；上面两个包要重新导出才会带上修正后的图标。

## 本次实际验收

| 检查 | 结果 |
| --- | --- |
| 资源导入与两平台 `--export-release` | 均退出 0；编辑器退出时仍有插件对象 / 资源未释放诊断 |
| 标题与结尾卡窗口截图 | 新名称完整显示，无裁切 |
| Windows PE 资源核对 | 产品名正确；16 / 32 / 48 / 64 / 128 / 256 像素图标与 ICO 原始数据逐项一致 |
| `pck_preflight.py` | 2577 条目；关键场景、脚本存在；原料目录仍为文本，四种风味串完整；开发目录未泄漏 |
| `package_demo.py` | UTF-8 中文条目、zip CRC 通过 |
| zip 解压后运行 exe | `--quit-after 180 --verbose`，退出 0，无运行时 ERROR；有两条既有 RGB8 转换警告 |
| 用编辑器引擎挂载导出的 PCK 执行 `verify_two_day_flow.gd` | 384 项，0 失败，退出 0；只有对象释放警告 |
| 源项目两天流程 | 417 项，0 失败 |
| `verify_two_day_persistence.py` | 33 个检查点，0 失败进程；日志仍有既有地图资源加载及退出清理诊断，不能解释为完全无错误日志 |
| 安卓包内抽检 | APK CRC、ARM64 库、标题、关键资源、原料风味字段及 source / 开发目录排除均通过 |
| 安卓签名及清单 | `apksigner verify` 通过 v2 / v3；显示名正确，非 debuggable，最低 API 24、目标 API 36 |
| 安卓安装与交互 | Android 15 平板模拟器，host GPU、ARM64 转译：安装成功，进入标题、点击新游戏进入开场对白，触摸交互推进正常，进程日志无 Godot ERROR |
| 完整回归 | 117 项：82 PASS、27 FAIL、2 HANG、6 SKIP；改动前 `a23c7962` 复跑全部 29 个失败 / 超时项，仍为 27 FAIL、2 HANG |

完整回归实际命令为 `python tests/run_all.py --report dist/build_logs/final_regression.json`。117 项执行与 JSON 写入已完成；运行器最后打印相对报告路径时抛出既有 `Path.relative_to` 异常。基线复跑改用绝对 `--report` 路径，正常输出汇总，退出 124 对应两项超时。

所有失败 / 超时测试名称与状态都在改动前复现；部分动画时序断言的失败条数有波动。失败涉及旧洞穴宿主、角色动画、界面解锁、配方和钱包等已有检查，本次未改这些模块。完整结果与对照在 `dist/build_logs/final_regression.json`、`final_baseline.json`、`final_baseline_comparison.json`，不能将本包描述为全量测试通过。

模拟器的 SwiftShader 软件渲染曾报画布 shader uniform 上限错误并黑屏；切换 host GPU 后同一 APK 正常显示，未为此修改项目渲染参数。尚未执行实体安卓手机完整通关与性能 / 发热验收，也未进行商店上架或 Windows 代码签名。

## 试玩入口

Windows 解压后双击 exe，安卓安装 APK 后点新图标。标题应显示《我的奶茶店连通异世界》；点「新游戏」进入店内开场，安卓对白右上方可点「交互」推进。主线到第二天结束后显示回顾页，点「结束本版」进入同名结尾卡，再返回标题。

可复现命令在 [先前 Windows 打包说明](demo_release_v0_1_0_2026_10_20.md#复现发包) 与 [安卓打包指南](../guides/android_build.md)；改用本页的新名称和本次构建目录。导出密钥通过 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` 传入，勿写进预设或提交凭据。
