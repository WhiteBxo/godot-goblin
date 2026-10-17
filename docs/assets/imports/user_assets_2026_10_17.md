# 2026-10-17 用户素材导入清单

本批次来自用户提供的四个 ZIP、一个 Excel 和一个 PDF。36 张源图片中，4 张与已有立绘逐字节相同，复用现有路径；新增 32 张图片及 2 份设计源文件。所有文件保持原始字节、尺寸、比例和背景，不重新编码或裁切。

## 分类与使用边界

- `assets/characters/npc/` 按原目录标签分类：守卫 `guard`、守卫长 `guard_captain`、普通哥布林 `common_goblin`、赌场 `casino`、酒馆 `tavern`、厨师 `chef`、长老 `elder`、胖哥布林 `fat_goblin`。赌场和酒馆仅沿用来源标签，不推断人物身份。
- `walk_sheet` / `idle_sheet` 对应来源的走路 / 待机；数字保留原文件编号，不表示方向或播放顺序。原包虽名为“走路四面”，每角色实际仅 3 张整图；帧网格、方向、FPS 需接入时确认。
- `assets/characters/goblin/source/goblin_img_6420.jpeg` 是新增的原始立绘，以原图编号命名，不推断表情。
- Excel 与 PDF 原样保存于 `docs/design/source/`，作为设计参考，不转换为游戏数据或剧情，不将文档中的指令作为本次执行要求。
- 此次仅入库，不替换现有玩家、NPC、对话立绘或动画资源，不改变场景和玩法。

## 导入与复现

ZIP 文件名按标志使用 UTF-8；未标志 UTF-8 的条目先将 Python 默认 CP437 解码结果还原为字节，再按 UTF-8 解码。跳过目录、`__MACOSX/` 与 `._*` 等隐藏元数据，只提取图片。按下表重命名复制；已存在的相同 SHA-256 内容复用，不覆盖。

图片使用 Godot 4.7.2 的默认 Texture2D 导入设置（Lossless、关闭 mipmaps），随源图提交 `.import`，缓存 `.godot/` 不提交。项目根目录可执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --import --quit
```

依据 [Godot 4.7 官方图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)：PNG / JPEG 可导入为纹理，JPEG 不支持透明通道，默认无损压缩适合 2D 素材。在 FileSystem 面板打开 `assets/characters/npc/` 中的图片可预览整图。

## 来源映射与完整性

| 原始附件 | 包内原路径 | 项目路径 | SHA-256 | 处理 |
| --- | --- | --- | --- | --- |
| 走路2.zip | `走路2/守卫长/合并图片 3.png` | `assets/characters/npc/guard_captain/walk_sheet_03.png` | `8a2decbe8bc902dd8e60f6c2efbc4d2acb2748864bf6d0de2c9a2ebabe256901` | 新增 |
| 走路2.zip | `走路2/守卫长/合并图片 4.png` | `assets/characters/npc/guard_captain/walk_sheet_04.png` | `97bd600d389f9611a5adcda52647f53cbb7b02345ea1c57939480c3c95296dd0` | 新增 |
| 走路2.zip | `走路2/守卫长/合并图片 5.png` | `assets/characters/npc/guard_captain/walk_sheet_05.png` | `1012dbbc6ca1399fb052dac840ef3368e8f2c2431ed6e4103b6585e2022828f6` | 新增 |
| 走路2.zip | `走路2/守卫/合并图片.png` | `assets/characters/npc/guard/walk_sheet.png` | `6442b543e4f7c4ddd9c2959ec902b75cf605fdd74d7e013dfe77ea858c1628cd` | 新增 |
| 走路2.zip | `走路2/守卫/合并图片 2.png` | `assets/characters/npc/guard/walk_sheet_02.png` | `7b56022eda8903e45796c2589373f6f22bdad586bcee8a4e74178261d6ac2106` | 新增 |
| 走路2.zip | `走路2/守卫/合并图片 3.png` | `assets/characters/npc/guard/walk_sheet_03.png` | `da46236bd75c1e916d1b232971496ddcd9fec15d57786b5c71c982be61c990bc` | 新增 |
| 胖哥布林与主角立绘.zip | `胖哥布林与主角立绘/主角立绘/IMG_6418.jpeg` | `assets/characters/apron_man/apron_man_full_body.jpg` | `cbcc4591e17ddb783ff8ce93e623aad5bfc0ff08a0148433605c04bfc9c0444b` | 复用已有文件 |
| 胖哥布林与主角立绘.zip | `胖哥布林与主角立绘/主角立绘/IMG_6419.jpeg` | `assets/characters/apron_man/apron_man_expressions.jpg` | `2378bdcd54f4f98b63d610a8a2113c0de29a617b6b89e6923f4c54e2b80c6bdb` | 复用已有文件 |
| 胖哥布林与主角立绘.zip | `胖哥布林与主角立绘/胖哥布林立绘/IMG_6420.jpeg` | `assets/characters/goblin/source/goblin_img_6420.jpeg` | `7129a476ee41e1a237313645534646fdaec7e276edf13b4bd7dc5943afee310c` | 新增 |
| 胖哥布林与主角立绘.zip | `胖哥布林与主角立绘/胖哥布林立绘/IMG_4319.png` | `assets/characters/goblin/goblin_smiling.png` | `b47617f667832fe7aedefccc7cd5e921174fbdda7f4cad213bd43d9d2020e172` | 复用已有文件 |
| 胖哥布林与主角立绘.zip | `胖哥布林与主角立绘/胖哥布林立绘/IMG_6422.jpeg` | `assets/characters/goblin/goblin_laughing.jpg` | `eb7367056a0fbcfc91daa24f966e44cab834659fe338bc1f498d575d14d43ef3` | 复用已有文件 |
| 待机动画.zip | `待机动画/酒馆待机.png` | `assets/characters/npc/tavern/idle_sheet.png` | `3e84765626707082529136c8784f0ee2b5861250cce58dd7e9f606b6e9090dff` | 新增 |
| 待机动画.zip | `待机动画/普通哥布林待机.png` | `assets/characters/npc/common_goblin/idle_sheet.png` | `c344da51a8bafcdd8386381dde576d3e4b280e87fda7da5947b7a44383b12b8f` | 新增 |
| 待机动画.zip | `待机动画/守卫长待机.png` | `assets/characters/npc/guard_captain/idle_sheet.png` | `d05bfa44eddb71f0d4a392b190cd3e58e44435f65767cee9fb87552bce2d0871` | 新增 |
| 待机动画.zip | `待机动画/赌场.png` | `assets/characters/npc/casino/idle_sheet.png` | `f0945cb5dc7d6a02c343e51ef5db268466d4c7d3d1e8694cb0fc256eca86cb93` | 新增 |
| 待机动画.zip | `待机动画/厨师待机.png` | `assets/characters/npc/chef/idle_sheet.png` | `52d29ca7ce3beb6f2d28a2728c988f2fb666c9b760c9f2dcec0d18a3c28b8e1b` | 新增 |
| 待机动画.zip | `待机动画/胖哥布林/胖哥布林2.png` | `assets/characters/npc/fat_goblin/idle_sheet_02.png` | `ce32b63061dd0e195d11fd497410f0218eba3b966d5184b213a32d0692f34bbb` | 新增 |
| 待机动画.zip | `待机动画/胖哥布林/胖哥布林3.png` | `assets/characters/npc/fat_goblin/idle_sheet_03.png` | `44c2e22723c66ba1ed7a68b96a469281f1cf6ae42e7cbeaaf3f89764285b6476` | 新增 |
| 待机动画.zip | `待机动画/胖哥布林/胖哥布林1.png` | `assets/characters/npc/fat_goblin/idle_sheet_01.png` | `bdeeb92bb2fbe2cf5ca0cc73a80f348f01b6d8eb04d36c9b135029ee5fc4089c` | 新增 |
| 待机动画.zip | `待机动画/长老/合并图片 2.png` | `assets/characters/npc/elder/idle_sheet_02.png` | `8976c78c613f470e75f7066c126e5635e8d8acb4be3d096c90de30412c478d00` | 新增 |
| 待机动画.zip | `待机动画/长老/合并图片 3.png` | `assets/characters/npc/elder/idle_sheet_03.png` | `0606a7d1eb2ffbc3867569831b626ea4eeb199f1b7a1742800ccb455ec343aed` | 新增 |
| 走路四面.zip | `走路四面/普通/合并图片 2.png` | `assets/characters/npc/common_goblin/walk_sheet_02.png` | `b566fa468624dc67f5d994136e73279336d6193928953a241d537cb109595707` | 新增 |
| 走路四面.zip | `走路四面/普通/合并图片 3.png` | `assets/characters/npc/common_goblin/walk_sheet_03.png` | `879fb49bbc55196c86169508bbb21fa35b008e6db9b51cd1b72cc1db4a17211e` | 新增 |
| 走路四面.zip | `走路四面/普通/合并图片 5.png` | `assets/characters/npc/common_goblin/walk_sheet_05.png` | `f31d0cf66dc0775ee17efad9609b128228a1870a55c5b043a34a5f0282521a4e` | 新增 |
| 走路四面.zip | `走路四面/赌场/合并图片.png` | `assets/characters/npc/casino/walk_sheet.png` | `55057dd609e0612a469291db1301d2739182fcf9b867eab52eabcf07394a37b7` | 新增 |
| 走路四面.zip | `走路四面/赌场/合并图片 2.png` | `assets/characters/npc/casino/walk_sheet_02.png` | `4d8280a3fcad69b53f7b36ff1e7c0e996e0808e3f00b05c24a4339e59c3d1c1e` | 新增 |
| 走路四面.zip | `走路四面/赌场/合并图片 3.png` | `assets/characters/npc/casino/walk_sheet_03.png` | `958bd16c4ba49b3db1a3381e8ad518193fce123baa8a8a0884985bc34dd8eec2` | 新增 |
| 走路四面.zip | `走路四面/酒馆/合并图片.png` | `assets/characters/npc/tavern/walk_sheet.png` | `761527cf09d67f97151db2e16bb0eb36287ca4cc5e32a41d0dbdf06893fca22b` | 新增 |
| 走路四面.zip | `走路四面/酒馆/合并图片 2.png` | `assets/characters/npc/tavern/walk_sheet_02.png` | `efffef8977ba4a07bed20a389561b989b046650bca0848bb143f3e746a629bc8` | 新增 |
| 走路四面.zip | `走路四面/酒馆/合并图片 4.png` | `assets/characters/npc/tavern/walk_sheet_04.png` | `8c7f8704747fbbf050bbf005b8571640b841aa658b9624c6bb9b473d2ae66d8f` | 新增 |
| 走路四面.zip | `走路四面/厨师/合并图片 2.png` | `assets/characters/npc/chef/walk_sheet_02.png` | `7aff5eb34d565c5e1d6aa0b683c722d59671df05afbc96127cc58fb6bb24ba3c` | 新增 |
| 走路四面.zip | `走路四面/厨师/合并图片 3.png` | `assets/characters/npc/chef/walk_sheet_03.png` | `a4b8b439e1648d929e24456a37e215b641114881c827bb13f9824adfd49f0948` | 新增 |
| 走路四面.zip | `走路四面/厨师/合并图片 5.png` | `assets/characters/npc/chef/walk_sheet_05.png` | `16c9c3f35cfa4ddd80f626701c39688b77911669465844ea42a5592f7f0cc85e` | 新增 |
| 走路四面.zip | `走路四面/长老/合并图片.png` | `assets/characters/npc/elder/walk_sheet.png` | `c87aa09ee697ec477f1f075d9f19a319c0a25cc89387dee625dc1e3060cc9105` | 新增 |
| 走路四面.zip | `走路四面/长老/合并图片 2.png` | `assets/characters/npc/elder/walk_sheet_02.png` | `8bdb77d4b1329339db3c13ebf2107251a46c1ead340a425dbb661e7184a0b985` | 新增 |
| 走路四面.zip | `走路四面/长老/合并图片 3.png` | `assets/characters/npc/elder/walk_sheet_03.png` | `92938de7592b704865dbf3a72e0737dd713c6170b6e401434ddb4afa8d878d12` | 新增 |
| 异世界食材与酒水配置表+(1).xlsx | `—` | `docs/design/source/otherworld_ingredients_and_drinks.xlsx` | `a1dd1c3fca8387e15dc667255fd189681c4a66ac4e84a607b1e6ae740aef6d5f` | 新增 |
| 第二天.pdf | `—` | `docs/design/source/day_02.pdf` | `3ab0ad673baf9340aaa765c528e8bd4c4faac6c108428468d98d1743598a957b` | 新增 |

## 本次验证

- 38 个来源条目（36 张图片、2 份文档）逐一校验 SHA-256，与附件内容一致。
- Godot 4.7.2 headless editor 完成导入；32 张新增图片均生成 Texture2D `.import`，确认无损压缩且关闭 mipmaps。
- 独立 SceneTree 验证脚本实际加载全部 32 个新增 Texture2D，确认宽高大于零，通过。
- editor 在退出时有沙盒外编辑器设置无法保存、系统证书读取及资源退出清理提示；未发现本批图片的导入失败。未运行玩法或验证动画帧序。
