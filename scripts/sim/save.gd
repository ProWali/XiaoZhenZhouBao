## 存档 = 种子 + 配置 + 玩家操作日志。读档就是重放。
## world.actions 由 world 在每个玩家操作里记录；重放时 world.recording 关掉，避免重复记录。
extends RefCounted

const World = preload("res://scripts/sim/world.gd")
const VERSION := 1


static func to_dict(world) -> Dictionary:
	return {
		"version": VERSION, "seed": world.seed_value, "config": world.config,
		"paper_name": world.paper_name, "player_name": world.player_name,
		"actions": world.actions,
	}


static func save(world, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(world)))
	f.close()
	return true


static func load_path(path: String):
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return null
	return from_dict(data)


## 重放。返回新的 world；若操作序列在新规则下走不通，world.replay_error 记录第几步失败。
static func from_dict(data: Dictionary):
	var cfg: Dictionary = {}
	for k in data.get("config", {}):
		var v = data.config[k]
		cfg[k] = int(v) if (v is float and k == "total_weeks") else v
	var world = World.new(int(data.seed), cfg)
	world.paper_name = data.get("paper_name", world.paper_name)
	world.player_name = data.get("player_name", world.player_name)
	# 重放时照常记录，这样 actions 永远是规范形式（JSON 读回来的整数会变浮点）
	world.actions = []
	world.recording = true
	var i := 0
	for act in data.get("actions", []):
		if world.game_over != "":
			break
		if not world.apply_action(act):
			world.replay_error = "第 %d 步操作失败：%s" % [i, JSON.stringify(act)]
			break
		i += 1
	return world
