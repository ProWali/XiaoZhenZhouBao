## 人口流动：衰老、生病、死亡、生子、新来、离镇。每周一次。
## 生死通过「生活事件」模板落到报纸上：obituary、birth、arrival、departure。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const TownGen = preload("res://scripts/sim/town_gen.gd")
const Relations = preload("res://scripts/sim/relations.gd")
const T = preload("res://scripts/sim/tables.gd")


static func tick_week(world) -> void:
	var rng: Rng = world.rng
	for rid in world.living_ids():
		var r: Dictionary = world.residents[rid]
		r.age_weeks += 1
		if r.age_weeks >= 52:
			r.age_weeks = 0
			r.age += 1
		# 生病
		if r.sick_until <= world.week:
			var p := 0.003
			if r.age > 50:
				p += (r.age - 50) * 0.0012
			if "drinker" in r.traits:
				p += 0.003
			if rng.chance(p):
				r.sick_until = world.week + rng.randi_range(3, 10)
				if r.power >= 1:
					world.log.append("第 %d 周：%s病倒了。" % [world.week, r.name])
		else:
			# 病中可能死
			var pd := 0.01 if r.age < 60 else 0.06
			if r.age > 70:
				pd = 0.12
			if rng.chance(pd):
				_die(world, rid)
				continue
		# 生子
		if r.female and r.spouse != "" and r.age >= 19 and r.age <= 41 and world.residents[r.spouse].alive and rng.chance(0.006):
			r.children += 1
			world.residents[r.spouse].children += 1
			_life_event(world, "birth", {"mother": [rid], "father": [r.spouse]}, {})
		# 离镇：名声或钱长期不满、没有家人在镇上
		var stuck: int = maxi(int(r.low_weeks.get("reputation", 0)), int(r.low_weeks.get("money", 0)))
		if stuck >= 8 and r.power < 2 and rng.chance(0.08):
			var has_family := false
			for fid in r.family:
				if world.residents[fid].alive and world.residents[fid].in_town:
					has_family = true
			if not has_family or rng.chance(0.1):
				_leave(world, rid)
				continue
	# 新来的人
	if rng.chance(0.07) and world.living_ids().size() < 90:
		var occ: Dictionary = T.occupation_by_id(rng.pick(["newcomer", "worker", "drifter", "farmer"]))
		var nr := TownGen.new_resident(world, rng.chance(0.4), occ, "")
		nr.age = rng.randi_range(18, 40)
		if occ.work == "farm":
			nr.work = rng.pick(["farm_a", "farm_b"])
		world.residents[nr.id] = nr
		_life_event(world, "arrival", {"newcomer": [nr.id]}, {})


static func _die(world, rid: String) -> void:
	var r: Dictionary = world.residents[rid]
	r.alive = false
	r.in_town = false
	world.log.append("第 %d 周：%s去世，%d 岁。" % [world.week, r.name, r.age])
	var kin := ""
	if r.spouse != "" and world.residents[r.spouse].alive and world.residents[r.spouse].in_town:
		kin = r.spouse
		var s: Dictionary = world.residents[kin]
		s.spouse = ""
		s["widowed_week"] = world.week
		if s.female and s.occ == "homemaker":
			TownGen.change_job(world, kin, "widow")
	else:
		for fid in r.family:
			if world.residents[fid].alive and world.residents[fid].in_town:
				kin = fid
		if kin == "" and not r.friends.is_empty():
			kin = r.friends[0]
	# 职位空出来
	if r.occ == "mayor":
		world.flags["mayor_vacant"] = true
	if kin != "":
		_life_event(world, "obituary", {"kin": [kin]}, {"deceased": r.name, "deceased_en": r.name_en, "age": str(r.age)})


static func _leave(world, rid: String) -> void:
	var r: Dictionary = world.residents[rid]
	r.in_town = false
	if r.spouse != "":
		world.residents[r.spouse].spouse = ""
		world.residents[r.spouse]["widowed_week"] = world.week
		r.spouse = ""
	world.log.append("第 %d 周：%s收拾了东西，坐火车走了。" % [world.week, r.name])
	var kin := ""
	for fid in r.family:
		if world.residents[fid].alive and world.residents[fid].in_town:
			kin = fid
	if kin == "" and not r.friends.is_empty():
		kin = r.friends[0]
	if kin != "":
		_life_event(world, "departure", {"kin": [kin]}, {"leaver": r.name, "leaver_en": r.name_en})


## 用预设角色实例化一个生活事件，直接变成公开事实。
static func _life_event(world, tid: String, preset: Dictionary, extras: Dictionary) -> void:
	var tpl: Dictionary = world.events_db.template_by_id(tid)
	if tpl.is_empty():
		return
	var roles: Dictionary = world.events_db.cast_roles(tpl, world, preset)
	if roles.is_empty():
		return
	world.spawn_instance(tpl, roles, extras)
