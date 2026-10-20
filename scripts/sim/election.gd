## 年度节点：每年秋天的镇议会预算；最后一年秋天的镇长选举。
## 报纸对候选人的报道会改变选票：曝光度 × 公信力。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const Relations = preload("res://scripts/sim/relations.gd")
const TownGen = preload("res://scripts/sim/town_gen.gd")

const BUDGET_WEEK_IN_YEAR := 39   # 秋天第一周
const ELECTION_OFFSET := 9        # 选举在任期结束前 9 周
const CAMPAIGN_LENGTH := 10


static func election_week(world) -> int:
	return int(world.config.total_weeks) - ELECTION_OFFSET


static func tick_week(world) -> void:
	var w: int = world.week
	# 镇长空缺（死亡或辞职）：书记员或最有地位的人代理
	if world.flags.get("mayor_vacant", false):
		world.flags.mayor_vacant = false
		var pick := _best_candidate(world, "")
		if pick != "":
			TownGen.change_job(world, pick, "mayor")
			world.log.append("第 %d 周：%s代理镇长。" % [w, world.residents[pick].name])
			_soft(world, "succession", {"mayor": [pick]}, {})
	# 预算
	if (w - 1) % 52 + 1 == BUDGET_WEEK_IN_YEAR:
		_budget(world)
	# 选举
	var ew := election_week(world)
	if w == ew - CAMPAIGN_LENGTH:
		_announce(world)
	elif w == ew:
		_vote(world)


static func _mayor(world) -> String:
	for rid in world.living_ids():
		if world.residents[rid].occ == "mayor":
			return rid
	return ""


static func _best_candidate(world, exclude: String) -> String:
	var best := ""
	var best_score := -1.0
	for rid in world.living_ids():
		var r: Dictionary = world.residents[rid]
		if rid == exclude or r.occ == "mayor" or r.age < 25:
			continue
		var score: float = r.power * 1.0 + r.wealth * 0.5 + (1.0 if "ambitious" in r.traits else 0.0) + r.friends.size() * 0.1
		if r.occ in ["owner", "grocer", "priest", "sheriff", "clerk", "doctor"]:
			score += 0.5
		if score > best_score:
			best_score = score
			best = rid
	return best


static func _budget(world) -> void:
	var mayor := _mayor(world)
	if mayor == "":
		return
	var options := {"bridge": "修桥", "road": "修路", "school": "修学校", "mill": "补贴锯木厂"}
	var options_en := {"bridge": "repairing the bridge", "road": "mending the road", "school": "a new schoolroom", "mill": "a grant to the sawmill"}
	var weights := {"bridge": 1.0, "road": 1.0, "school": 0.8, "mill": 0.8}
	# 报纸影响：登过春汛就修桥；登过受贿就不敢补贴厂子
	for iss in world.issues:
		if iss.week < world.week - 26:
			continue
		for a in iss.articles:
			var e: Dictionary = world.event_by_id(a.event)
			if e.is_empty():
				continue
			match e.tid:
				"flood": weights.bridge += 1.5
				"bribery": weights.mill -= 0.6
				"pollution": weights.mill -= 0.5
	var mr: Dictionary = world.residents[mayor]
	if "greedy" in mr.traits:
		weights.mill += 0.8
	var keys: Array = options.keys()
	var ws: Array = []
	for k in keys:
		ws.append(maxf(0.05, float(weights[k])))
	var choice: String = keys[world.rng.weighted(ws)]
	world.flags["budget_" + str(world.week)] = choice
	world.log.append("第 %d 周：镇议会把今年的钱花在「%s」上。" % [world.week, options[choice]])
	_soft(world, "budget", {"mayor": [mayor]}, {"decision": options[choice], "decision_en": options_en[choice]})
	if choice == "mill":
		for rid in world.living_ids():
			if world.residents[rid].occ == "owner":
				world.residents[rid].wealth = mini(2, world.residents[rid].wealth + 1)


static func _announce(world) -> void:
	var mayor := _mayor(world)
	var challenger := _best_candidate(world, mayor)
	if mayor == "" or challenger == "":
		return
	world.campaign = {"active": true, "mayor": mayor, "challenger": challenger, "hits": {mayor: 0.0, challenger: 0.0}}
	world.log.append("第 %d 周：%s宣布竞选镇长，对手是现任%s。" % [world.week, world.residents[challenger].name, world.residents[mayor].name])
	_soft(world, "candidacy", {"challenger": [challenger], "mayor": [mayor]}, {})


## 报道影响：s 为负面严重度（正数），positive 为真表示夸。
static func on_article(world, subj: String, s: float, positive: bool) -> void:
	if not world.campaign.get("active", false):
		return
	if not world.campaign.hits.has(subj):
		return
	var weight: float = (0.3 + float(world.stats.credibility) / 100.0)
	world.campaign.hits[subj] += (-0.6 if positive else s) * weight


static func _vote(world) -> void:
	var c: Dictionary = world.campaign
	if not c.get("active", false):
		return
	var mayor: String = c.mayor
	var challenger: String = c.challenger
	var votes := {mayor: 0, challenger: 0}
	for rid in world.living_ids():
		var r: Dictionary = world.residents[rid]
		if r.age < 21 or rid == mayor or rid == challenger:
			continue
		var best := ""
		var best_score := -99.0
		for cand in [mayor, challenger]:
			if not world.residents[cand].alive or not world.residents[cand].in_town:
				continue
			var cr: Dictionary = world.residents[cand]
			var score: float = Relations.get_dim(world, rid, cand, "like")
			score += 0.1 if (rid in cr.friends or rid in cr.family or r.work == cr.work) else 0.0
			score += 0.08 if cand == mayor else 0.0  # 现任优势
			score -= float(c.hits[cand]) * 0.12
			score += world.rng.randf_range(-0.08, 0.08)
			if score > best_score:
				best_score = score
				best = cand
		if best != "":
			votes[best] += 1
	var winner: String = mayor if votes[mayor] >= votes[challenger] else challenger
	var loser: String = challenger if winner == mayor else mayor
	c.active = false
	c["result"] = {"winner": winner, "votes": votes}
	world.log.append("第 %d 周：镇长选举，%s %d 票，%s %d 票。%s当选。" % [world.week, world.residents[mayor].name, votes[mayor], world.residents[challenger].name, votes[challenger], world.residents[winner].name])
	if winner == challenger:
		TownGen.change_job(world, mayor, "retired")
		TownGen.change_job(world, challenger, "mayor")
	_soft(world, "election", {"winner": [winner]}, {"loser": world.residents[loser].name, "loser_en": world.residents[loser].name_en, "v1": str(votes[winner]), "v2": str(votes[loser])})


static func _soft(world, tid: String, preset: Dictionary, extras: Dictionary) -> void:
	var tpl: Dictionary = world.events_db.template_by_id(tid)
	if tpl.is_empty():
		return
	var roles: Dictionary = world.events_db.cast_roles(tpl, world, preset)
	if roles.is_empty():
		return
	world.spawn_instance(tpl, roles, extras)
