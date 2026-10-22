## 取料探针：模拟一个不懂门道的新玩家玩前四周，量每个行动问出多少东西、每周有几件能登的事。
## 新玩家：有线头就去找线头上的人；没有就去人多的地方随便找一个人，六成随便聊、四成拿选题簿里的事当话头；
## 每周熬一夜（酒馆偷听或随便蹲一处），不查档案、不找线人。周日把能登的全登上，克制、化名。
## 用法：godot --headless -s res://scripts/tools/yield_probe.gd -- [--seeds 30] [--weeks 4]
extends SceneTree

const World = preload("res://scripts/sim/world.gd")


func _init() -> void:
	var seeds := 30
	var weeks := 4
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seeds": seeds = int(args[i + 1])
		if args[i] == "--weeks": weeks = int(args[i + 1])
	var tot := {"talks": 0, "talk_gain": 0, "talk_empty": 0, "nights": 0, "night_gain": 0, "leads": 0, "lead_talks": 0, "lead_gain": 0}
	var stories_per_week: Array = []
	var empty_weeks := 0
	var first_week_secret := 0
	for s in range(1, seeds + 1):
		var w = World.new(1000 + s, {"total_weeks": 104})
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		while w.week <= weeks and w.game_over == "":
			var night_done := false
			while w.day <= 6:
				if w.can_act_day():
					var rid := _pick_person(w, rng)
					if rid == "":
						w.end_day()
						continue
					var via_lead := _has_lead(w, rid)
					var topic := ""
					var groups: Array = w.notebook()
					if not via_lead and not groups.is_empty() and rng.randf() < 0.4:
						var g: Dictionary = groups[rng.randi() % groups.size()]
						topic = g.facts[rng.randi() % g.facts.size()]
					var leads_before: int = w.leads.size() if "leads" in w else 0
					var res: Dictionary = w.act_interview(rid, topic)
					tot.talks += 1
					tot.talk_gain += res.gained.size()
					if res.gained.is_empty() and not res.has("lead"):
						tot.talk_empty += 1
					if via_lead:
						tot.lead_talks += 1
						tot.lead_gain += res.gained.size()
					if "leads" in w and w.leads.size() > leads_before:
						tot.leads += 1
				elif w.slot >= 2 and not night_done and w.day >= 2 and w.can_act_night():
					night_done = true
					var spots := ["tavern", "tavern", "river", "bridge", "woods", "mill"]
					var loc: String = spots[rng.randi() % spots.size()]
					var res: Dictionary = w.act_eavesdrop() if loc == "tavern" else w.act_stakeout(loc)
					tot.nights += 1
					tot.night_gain += res.gained.size()
				else:
					w.end_day()
			w.saturday_visitors()
			var arts: Array = []
			var slots := ["head", "second", "third", "small"]
			var secret_known := false
			for g in w.notebook():
				var fresh: Array = []
				for fid in g.facts:
					if not (fid in g.event.get("printed_facts", [])) and (not g.event.printed or g.event.has("printed_facts")):
						fresh.append(fid)
				if fresh.is_empty() or arts.size() >= 4:
					continue
				if not g.event.soft:
					secret_known = true
				arts.append({"slot": slots[arts.size()], "facts": fresh.slice(0, 4), "tone": "calm", "naming": "alias", "evidence": false})
			if w.week == 1 and secret_known:
				first_week_secret += 1
			stories_per_week.append(arts.size())
			if arts.is_empty():
				empty_weeks += 1
			w.print_issue(arts)
	var n_weeks := stories_per_week.size()
	var sum := 0
	for x in stories_per_week:
		sum += x
	print("种子 %d × 前 %d 周" % [seeds, weeks])
	print("交谈 %d 次，每次平均问出 %.2f 条，既没料也没线头 %.0f%%" % [tot.talks, float(tot.talk_gain) / max(1, tot.talks), 100.0 * tot.talk_empty / max(1, tot.talks)])
	print("得到线头 %d 次；按线头找人 %d 次，每次平均 %.2f 条" % [tot.leads, tot.lead_talks, float(tot.lead_gain) / max(1, tot.lead_talks)])
	print("熬夜 %d 次，每次平均 %.2f 条" % [tot.nights, float(tot.night_gain) / max(1, tot.nights)])
	print("每周能登的事 %.2f 件；一件都没有的周 %d / %d" % [float(sum) / max(1, n_weeks), empty_weeks, n_weeks])
	print("第一周就摸到秘密事件的局 %d / %d" % [first_week_secret, seeds])
	quit()


func _has_lead(w, rid: String) -> bool:
	if not ("leads" in w):
		return false
	for l in w.leads:
		if l.who == rid:
			return true
	return false


func _pick_person(w, rng: RandomNumberGenerator) -> String:
	if "leads" in w:
		for l in w.leads:
			var loc: String = w.where_is(l.who)
			if loc != "" and not loc.begins_with("home:"):
				return l.who
	var best := ""
	var best_n := 0
	for loc in w.public_locations():
		var n: int = w.people_at(loc).size()
		if n > best_n or (n == best_n and rng.randf() < 0.3) or (n > 0 and rng.randf() < 0.25):
			best_n = n
			best = loc
	if best == "":
		return ""
	var people: Array = w.people_at(best)
	return people[rng.randi() % people.size()]
