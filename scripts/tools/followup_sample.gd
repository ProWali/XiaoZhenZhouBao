## 续报抽检：自动玩家跑若干局，把登出来的续报（这件事早先登过）原样打出来，看续报体读起来像不像跟进报道。
## 用法：godot --headless -s res://scripts/tools/followup_sample.gd -- --lang zh --seeds 6 --weeks 30 [--strategy sensational]
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const T = preload("res://scripts/sim/tables.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var lang := "zh"
	var seeds := 6
	var weeks := 30
	var strategy := "sensational"
	for i in args.size():
		match args[i]:
			"--lang": lang = args[i + 1]
			"--seeds": seeds = int(args[i + 1])
			"--weeks": weeks = int(args[i + 1])
			"--strategy": strategy = args[i + 1]
	var total := 0
	var fu := 0
	for s in range(1, seeds + 1):
		var world = World.new(s, {"total_weeks": weeks, "lang": lang})
		var ap = Auto.new(strategy, s)
		while world.game_over == "" and world.week <= weeks:
			ap.play_week(world)
			if world.issues.is_empty():
				continue
			var iss: Dictionary = world.issues[-1]
			for a in iss.articles:
				total += 1
				var e: Dictionary = world.event_by_id(a.event)
				if int(e.get("first_printed_week", iss.week)) < int(iss.week):
					fu += 1
					print("—— 种子 %d · 第 %d 期 · %s · 首报第 %d 期 · %s %s" % [s, iss.week, T.SLOT_NAME[a.slot], int(e.first_printed_week), a.tone, a.naming])
					print("【%s】" % a.headline)
					for b in a.body:
						print("  " + b)
	print("共 %d 篇，续报 %d 篇" % [total, fu])
	quit(0)
