# 小镇周报

一款系统驱动的叙事模拟游戏。你是一座程序生成小镇上唯一一份报纸的主编，世界在后台自己运转，你登出来的每一个字都会反过来改变这座镇子。

- 引擎：Godot 4.7.2（可执行文件在 `E:\Godot\`），全部 GDScript
- 原生分辨率 640×360，整数倍放大，16 色调色板
- 策划案：[design/策划案-v0.2.html](design/策划案-v0.2.html)（第二稿，决策已定）；第一稿保留在 v0.1
- 阶段记录：[M1 原型](design/notes/M1-原型记录.md) · [M2 模拟核心](design/notes/M2-模拟核心记录.md) · [M3 文本引擎](design/notes/M3-文本引擎记录.md)

## 目录

| 目录 | 放什么 |
|---|---|
| `design/` | 策划案、氛围图、设计记录。导出时排除，不进游戏包 |
| `scenes/` | 场景文件 |
| `scripts/sim/` | 模拟核心：随机源、人名、数据表、事件、生成、关系、需求、人口、选举、存档、世界、自动玩家。纯数据，可无头运行 |
| `scripts/text/` | 文本引擎：语法层、中英润色层、引擎本体 |
| `data/text/zh/`、`data/text/en/` | 报道、信、来访、界面短句的中英文模板 |
| `scripts/tools/` | 命令行入口、测试、文本抽检、盲测工具 |
| `data/events/` | 事件模板（JSON），一文件一事件 |
| `assets/` | 像素图、字体、音频 |

## 跑原型

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --auto cautious --seed 1 --weeks 12 --verbose
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --batch 10 --weeks 52
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --play --seed 3
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --auto random --seed 9 --weeks 104 --save out.json
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --load out.json
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/proto_cli.gd -- --auto cautious --seed 1 --weeks 12 --verbose --lang en
```

## 文本抽检与盲测

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/text_sample.gd -- --lang zh --seeds 6 --weeks 52 --out sample.md
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/blind_test.gd -- --brief --from 20    （--from：从哪个种子起找镇子，每轮换一个）
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/blind_test.gd -- --packet
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/blind_test.gd -- --score 3,7,12
```

## 跑测试

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/tools/run_tests.gd
```

测试内容：同种子两次运行逐字相同；存档重放后状态一致；20 种子 × 4 策略 × 52 周不崩、无 NaN；每个事件模板都能触发；事实文本没有未填槽位；104 周无人跑能生出需求驱动事件、后续事件和选举；中文局和英文局模拟结果逐字相同；中英文实际印出的文字 lint 零问题。

## 里程碑

M1 纸上原型（完成）→ M2 模拟核心（完成）→ M3 文本引擎（完成）→ M3.5 文本补课（完成，第十、十一轮盲测通过，保留意见见记录）→ M4 垂直切片 → M5 内容填充 → M6 Demo → M7 发售。排期见策划案十二版。
