# MySFE · 余烬行动

单人离线 3D 搜打撤游戏原型，支持第一、第三人称。当前包含自由瞄准、跳跑蹲、枪械命中与 AI、逐件搜索、格子背包、仓库、任务、双撤离、存档恢复，以及人物/枪械骨骼表现和敌人物资搜索。

目前提供 Windows 试玩工程，iPad 是后续适配目标，尚未提供已签名的 iPad 安装包。全部美术为项目原创程序化样板，详细来源见[资产清单](ember-3d/docs/ASSET_MANIFEST.md)。

## 运行

使用 **Godot 4.7.2 标准版**，在项目管理器中导入 [ember-3d/project.godot](ember-3d/project.godot)，打开后运行主场景。

也可使用命令行：

```powershell
godot --path ember-3d
```

根目录的各个 `试玩*.bat` 使用开发机的 `F:\Godot-4.7.2\` 引擎路径；其他电脑需修改启动器中的路径，或直接通过 Godot 运行项目。

- 普通行动：`godot --path ember-3d`
- 靶场：`godot --path ember-3d -- --training`
- 双守卫演练：`godot --path ember-3d -- --combat-drill`
- 敌人搜索练习：`godot --path ember-3d --script res://scripts/demo/corpse_demo.gd`，使用临时进度，不保存个人存档。

WASD 移动、Shift 快跑、空格跳跃、C 蹲下、V 切换视角、右键/X 瞄准、R 换弹、E 搜索/撤离、B 背包、M 地图任务、Q 治疗。完整说明见[使用说明](ember-3d/使用说明.md)。

## 目录

| 目录 | 内容 |
| --- | --- |
| `ember-3d/` | 当前 Godot 工程、数据、测试、模型预览与开发记录 |
| `planning/` | 游戏设计规划及各阶段源码基线备份 |
| `offline-extraction/` | 早期网页搜打撤原型 |
| `reaction-lab/` | 当前工作目录保留的网页反应练习及测试脚本 |

## 开发文档与验证

- [技术设计](ember-3d/docs/TECHNICAL_DESIGN.md)
- [第五阶段人物与枪械报告](ember-3d/docs/PHASE5_REPORT.md)
- [敌人物资搜索更新](ember-3d/docs/CORPSE_LOOT_REPORT.md)

敌人物资搜索版本的完整回归结果为 **27/27 套件通过**。执行：

```powershell
godot --headless --path ember-3d --script res://tests/run_all.gd
```

个人存档、Godot 下载文件、引擎缓存、日志及临时测试存档不纳入仓库。源码试玩的个人进度在 `ember-3d/user_data/saves/`；导出版本使用 Godot 的 `user://saves`。
