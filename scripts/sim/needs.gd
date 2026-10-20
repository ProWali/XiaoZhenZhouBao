## 五项需求：钱 money、安全 safety、名声 reputation、归属 belonging、欲望 desire。0 到 1，低了会铤而走险。
## 每周一次 tick，返回「需求长期不满的人」列表，供事件生成挑当事人。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const Relations = preload("res://scripts/sim/relations.gd")
const LOW := 0.3
const NEEDS := ["money", "safety", "reputation", "belonging", "desire"]
const NEED_NAME := {"money": "钱", "safety": "安全", "reputation": "名声", "belonging": "归属", "desire": "欲望"}


## 返回 [{rid, need, weeks}]，按不满时长降序。
static func tick_week(world) -> Array:
	var rng: Rng = world.rng
	var needy: Array = []
	for rid in world.living_ids():
		var r: Dictionary = world.residents[rid]
		var target := _targets(world, r)
		for n in NEEDS:
			var cur: float = float(r.needs[n])
			var nxt: float = 0.7 * cur + 0.3 * float(target[n]) + rng.randf_range(-0.05, 0.05)
			r.needs[n] = clampf(nxt, 0.0, 1.0)
			if r.needs[n] < LOW:
				r.low_weeks[n] = int(r.low_weeks.get(n, 0)) + 1
				if int(r.low_weeks[n]) >= 2:
					needy.append({"rid": rid, "need": n, "weeks": r.low_weeks[n]})
			else:
				r.low_weeks[n] = 0
	needy.sort_custom(func(a, b): return int(a.weeks) > int(b.weeks))
	return needy


static func _targets(world, r: Dictionary) -> Dictionary:
	var money: float = [0.42, 0.58, 0.8][clampi(int(r.wealth), 0, 2)]
	var debt_total := 0.0
	for oid in r.rel:
		debt_total += float(r.rel[oid].debt)
	money -= minf(0.2, debt_total * 0.01)
	if r.occ == "drifter" or r.occ == "retired":
		money -= 0.2
	if "greedy" in r.traits or "vain" in r.traits:
		money -= 0.08
	if r.sick_until > world.week:
		money -= 0.1
	var safety := 0.75
	if world.week - int(r.exposed_week) < 8:
		safety -= 0.3
	if r.enemies.size() >= 2:
		safety -= 0.15
	if float(r.player_rel.fear) > 0.4:
		safety -= 0.1
	var reputation := 0.6 + 0.1 * float(r.power)
	if world.week - int(r.exposed_week) < 12:
		reputation -= 0.4
	if world.week - int(r.praised_week) < 8:
		reputation += 0.2
	var belonging: float = 0.25 + 0.12 * r.friends.size() + (0.25 if r.spouse != "" else 0.0)
	if world.week - int(r.arrived_week) < 10:
		belonging -= 0.15
	var desire := 0.55
	if r.spouse == "" and r.age < 45:
		desire -= 0.15
	if r.spouse != "" and Relations.get_dim(world, r.id, r.spouse, "like") < 0.4:
		desire -= 0.25
	if "vain" in r.traits or "ambitious" in r.traits:
		desire -= 0.1
	return {"money": money, "safety": safety, "reputation": reputation, "belonging": clampf(belonging, 0.0, 1.0), "desire": desire}


static func describe(world, rid: String) -> String:
	var r: Dictionary = world.residents[rid]
	var parts: Array = []
	for n in NEEDS:
		parts.append("%s %.0f" % [NEED_NAME[n], float(r.needs[n]) * 100])
	return "，".join(parts)
