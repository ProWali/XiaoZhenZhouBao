## 审稿用：把几局里真实印出来的硬新闻全部导出，给人从头读到尾。
##   godot --headless -s res://scripts/tools/hard_dump.gd -- 40 43 out.md    （种子 40 到 42，谨慎策略）
## 审稿请用种子 40 以上，别碰盲测出卷用的镇子。
extends SceneTree
const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const TE = preload("res://scripts/text/text_engine.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := ""
	for s in range(int(args[0]), int(args[1])):
		var world = World.new(s, {"total_weeks": 104, "lang": "zh"})
		var auto = Auto.new("cautious", s)
		while world.game_over == "":
			var issue: Dictionary = auto.play_week(world)
			if issue.is_empty():
				break
			for a in issue.articles:
				var e: Dictionary = world.event_by_id(a.event)
				if e.soft or a.slot == "small":
					continue
				out += "## %s（种子%d 第%d周 %s %s %s）\n\n%s\n\n---\n\n" % [a.headline, s, world.week - 1, e.tid, a.tone, a.naming, "\n\n".join(a.body)]
	var f := FileAccess.open(args[2], FileAccess.WRITE)
	f.store_string(out)
	f.close()
	quit()
