# macOS 安装包与打包

macOS 版与桌面键鼠玩法一致，不引入新操作；打包只决定应用身份、架构和签名方式。预设 `macOS` 与 Windows 共用同一套导出筛选，仓库里没有单独的 macOS 素材分支。

## 打包前置

1. 安装与编辑器严格同版本的**导出模板**。编辑器 → 编辑器 → 管理导出模板 → 下载并安装，或手动放置：

   ```text
   ~/Library/Application Support/Godot/export_templates/4.7.2.stable/
     macos.zip          # 模板包里的 templates/macos.zip，不要解压
     version.txt        # 内容为 4.7.2.stable
   ```

   目录名必须是 `version.txt` 里的版本串（本仓库当前 `4.7.2.stable`）；只放 `macos.zip` 时导出会报找不到模板。

2. 本机需要 `codesign`、`hdiutil`、`lipo`，随 Xcode 命令行工具提供，macOS 自带即可。
3. 服务器上导出时先用 `--export-pack` 或一次性导入（`--headless --import`）准备好 `.godot`，避免首轮导出卡在素材导入。

## 预设

`export_presets.cfg` 里的 `macOS` 预设：

| 设置 | 值 | 说明 |
| --- | --- | --- |
| `application/bundle_identifier` | `com.godotgoblin.game` | 与安卓应用 ID 一致 |
| `binary_format/architecture` | `universal` | 同一份包含 arm64 与 x86_64 |
| `codesign/codesign` | `1`（Built-in，ad-hoc） | 本机可运行，未使用 Developer ID |
| `notarization/notarization` | `0` | 不做公证，首次打开需手动放行 |
| `application/icon` | 空 | 回落到 `project.godot` 的项目图标，导出时自动转 `icon.icns` |

模板自带的 `LSMinimumSystemVersion` 按架构分列：arm64 需 macOS 13，x86_64 需 macOS 11。

## 导出

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --export-release "macOS" "dist/mac_demo/我的奶茶店连通异世界.app"
```

- 产物是 `.app` 目录，不是单文件；`Contents/Resources/我的奶茶店连通异世界.pck` 才是游戏数据。
- 预设里没有写死导出路径，命令里的目标路径即产物位置；换名字时 `CFBundleName` 会跟着 `project.godot` 的应用名走，目录名只影响方便程度。
- 退出时会有 `ObjectDB instances were leaked` / `resources still in use` 诊断，属既有编辑器退出噪音，不影响包体。

## 打成 dmg

dmg 里放应用和一个指向 `/Applications` 的快捷方式，玩家拖进去就是安装：

```bash
STAGE=/tmp/mac_stage
mkdir -p "$STAGE"
cp -R "dist/mac_demo/我的奶茶店连通异世界.app" "$STAGE/"
ln -sfn /Applications "$STAGE/应用程序"
hdiutil create -volname "我的奶茶店连通异世界" -srcfolder "$STAGE" \
  -fs HFS+ -format UDZO -ov "dist/mac_demo/我的奶茶店连通异世界-v0.1.0-demo-macos-universal.dmg"
```

- `-fs HFS+` 保留可执行位与 `_CodeSignature`；换 APFS 也能用，但体积与兼容性没有收益。
- 分发包命名沿用 `游戏名-v版本-demo-macos-架构.dmg`，旁附 `.sha256` 和 `试玩说明.txt`。
- 对外的 dmg 必须重做，不要在已挂载的镜像里改文件，否则签名与资源封条会失效。

## 分发注意

ad-hoc 签名不等于可分发签名。经浏览器下载的包会带隔离属性，双击会提示「无法打开，因为 Apple 无法检查其是否包含恶意软件」。两种放行方式都要写进试玩说明：

- 右键应用 →「打开」→ 再点一次「打开」；
- `xattr -dr com.apple.quarantine "/Applications/我的奶茶店连通异世界.app"`。

要让玩家双击就能开，需要 Apple Developer ID 证书签名并公证（`codesign/codesign=2` 或 Xcode codesign 加 `notarization/notarization=2`，密钥通过环境变量传入），仓库当前不持有证书。

## 验收

| 检查 | 命令 | 通过标准 |
| --- | --- | --- |
| 签名 | `codesign --verify --deep --strict <app>` | 无输出，退出 0 |
| 签名类型 | `codesign -dv --verbose=2 <app>` | `Signature=adhoc`，`Mach-O universal (x86_64 arm64)` |
| 架构 | `lipo -info <app>/Contents/MacOS/<名>` | `x86_64 arm64` |
| 包内容 | `python tools/build/pck_preflight.py <app>/Contents/Resources/<名>.pck` | 关键场景与脚本存在，无开发目录泄漏 |
| 启动 | `<app>/Contents/MacOS/<名> --quit-after 240` | 退出 0，日志无 `ERROR` |
| 镜像 | `hdiutil attach -nobrowse -readonly <dmg>` 后重复上面三项 | 挂载卷内文件与签名一致 |

启动检查会真开一个窗口，Metal 设备初始化失败时会直接退出非 0，所以这条同时验证了渲染器。

## 存档位置

`~/Library/Application Support/Godot/app_userdata/我的奶茶店连通异世界/saves`。与 Windows 版的 `%APPDATA%/Godot/app_userdata/我的奶茶店连通异世界/saves` 目录结构一致，可以互相搬运。

## 已知边界

- 未在 Intel 实机验证过运行；架构已包含 x86_64，但没有实机验收记录。
- 未做公证，也没有 App Store 上架配置（缺 sandbox entitlements 与商店元数据）。
- `dist/` 在忽略列表内，产物不进版本库。
