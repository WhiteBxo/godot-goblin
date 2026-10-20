# 安卓手机试玩与打包

游戏按 640×360 设计、横屏运行。手机端不改变玩法数据，只增加触摸操作与移动端显示配置；桌面键鼠行为保持不变。

## 手机上的操作

| 操作 | 位置 | 说明 |
| --- | --- | --- |
| 移动 | 左下摇杆 | 拖动方向，松手停下；对话与演出期间自动收起 |
| 交互 / 推进对白 | 右下「交互」 | 对白期间该按钮上移到文本框上方，长按可快进 |
| 跑 / 蹲 | 右下「跑」「蹲」 | 点一下锁定，再点取消，两者互斥 |
| 投掷 | 右下「投掷」 | 只在 Day 1 潜行段出现 |
| 暂停 | 顶部中间「暂停」 | 与键盘 P 等价 |
| 地图 / 菜单 | 右上门形按钮 | 直接点按，与原 HUD 按钮同一入口 |
| 关闭弹窗 | 系统返回键 | 等同 Esc，不会直接杀进程 |

列表、仓库、手册等长页面可以直接拖动滚动；弹窗打开时触摸层整体隐藏，不会抢弹窗的点击。

## 打包前置

1. 安装 Godot 4.7 对应的**导出模板**（编辑器 → 管理导出模板 → 下载并安装）。
2. 安装 Android SDK：需要 `platform-tools`、`build-tools` 与至少一个 `platform`（本仓库按 API 34 以上可用），并安装 JDK 17。
3. 在编辑器设置 → 导出 → Android 里填入 SDK 路径；同一页确认调试密钥库可用。
4. 首次导出若提示生成 Gradle 构建模板，按提示安装即可；仓库默认使用预编译 APK 模板，不依赖 Gradle。

## 导出

`export_presets.cfg` 已包含 `Android` 预设（arm64-v8a，横屏，自动横屏方向，发行名 `com.godotgoblin.game`）：

```bash
godot --headless --path . --export-debug "Android" dist/android/goblin_milk_tea.apk
```

- 调试包用编辑器自动生成的调试签名，可直接 `adb install -r dist/android/goblin_milk_tea.apk` 侧载。
- 正式包在预设里填自己的 keystore 后改用 `--export-release`。
- 本次双平台 Demo 已使用独立本地密钥导出 Release APK，实际文件、图标与验收见 [最终发包记录](../development/final_demo_release_2026_10_20.md)。
- `dist/` 与 `/android/` 都在忽略列表内，产物不进版本库。

## 移动端配置

配置都在 `project.godot`，改动前先确认桌面端不受影响：

| 设置 | 值 | 原因 |
| --- | --- | --- |
| `display/window/handheld/orientation` | `4`（传感器横屏） | 支持左右横握，不出现竖屏 |
| `display/window/stretch/aspect` | `expand` | 超宽屏用扩展视口代替黑边，HUD 贴住物理边 |
| `display/window/stretch/scale_mode` | `integer`（沿用） | 像素图保持整数倍缩放；超宽屏只扩展宽度，仍能填满 |
| `rendering/renderer/rendering_method.mobile` | `gl_compatibility` | 纯 2D + canvas shader，避开 Vulkan 覆盖不全的机型；桌面仍是 Forward+ |
| `input_devices/pointing/android/enable_long_press_as_right_click` | `false` | 长按摇杆不应弹出右键菜单 |
| `application/config/quit_on_go_back` | `false` | 返回键交给游戏当取消键 |

## 触摸层的接入点

- 触摸层由 `MainGame._create_touch_support()` 创建，只在 `MobileSupport.should_show_touch_controls()` 为真时加载（`mobile` 特性或触屏设备）。
- 桌面调试可在启动参数末尾加 `-- --touch-controls` 强制显示触摸 HUD。
- 按钮不是新玩法入口：它们回放 `project.godot` 里对应 action 的原始按键事件，玩法代码只认 InputMap。
- 细节与布局约束见 [触摸操作层规范](../../src/UI/touch/AGENTS.md)。

## 已知边界

- 本机已使用 Godot 4.7.2 模板、Android SDK 与本地 Demo release 密钥完成 APK 导出，并在 Android 15 模拟器通过安装、标题与新游戏开场触摸冒烟；实体手机完整通关与性能验收尚未执行。
- 触摸层只覆盖单人本地玩法，未加虚拟手柄、手柄映射或云端存档相关适配。
- 覆盖 HUD 的场景（潜行卡片、交互提示）在触摸下会让位，新增常驻 HUD 时同样要避开左下与右下两块拇指区。
