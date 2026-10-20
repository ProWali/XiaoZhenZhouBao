## 镇子生成：居民、配偶、雇主、关系边。从 world.gd 拆出来，全部是静态函数。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const T = preload("res://scripts/sim/tables.gd")
const Relations = preload("res://scripts/sim/relations.gd")

const HOMEMAKER := {"id": "homemaker", "name": "家眷", "work": "home", "power": 0, "wealth": 1, "literate": 0.6}


static func generate(world) -> void:
	var rng: Rng = world.rng
	var farms := ["farm_a", "farm_b"]
	for occ in T.OCCUPATIONS:
		var count: int = rng.randi_range(occ.count[0], occ.count[1])
		for i in count:
			var female: bool = rng.chance(float(occ.female))
			var r := new_resident(world, female, occ, "")
			if occ.work == "farm":
				r.work = rng.pick(farms)
			world.residents[r.id] = r
	# 配偶
	var ids: Array = world.residents.keys()
	for rid in ids:
		var r: Dictionary = world.residents[rid]
		if r.age < 24 or r.occ in ["priest", "widow", "drifter", "newcomer", "apprentice", "maid"]:
			continue
		if rng.chance(0.55):
			var occ := HOMEMAKER.duplicate()
			occ.wealth = r.wealth
			var s := new_resident(world, not r.female, occ, r.name.split("·")[0])
			s.age = clampi(r.age + rng.randi_range(-6, 6), 18, 80)
			world.residents[s.id] = s
			marry(world, rid, s.id)
	# 女佣的雇主
	var rich: Array = []
	for rid in world.residents:
		if world.residents[rid].wealth >= 2:
			rich.append(rid)
	for rid in world.residents:
		var r: Dictionary = world.residents[rid]
		if r.occ == "maid" and not rich.is_empty():
			r.work = "home:" + rng.pick(rich)
	Relations.init_edges(world)
	# 邮差是前任主编的朋友；广告主登记
	for rid in world.residents:
		var r: Dictionary = world.residents[rid]
		if r.occ == "postman":
			r.player_rel.like = 0.75
			r.player_rel.trust = 0.7
		if r.get("advertiser", false):
			world.ads[rid] = {"paused_until": 0}
	world.log.append("灰河镇生成完毕：%d 位居民，种子 %d。" % [world.residents.size(), world.seed_value])


static func marry(world, a: String, b: String) -> void:
	var ra: Dictionary = world.residents[a]
	var rb: Dictionary = world.residents[b]
	ra.spouse = b
	rb.spouse = a
	if not (b in ra.family):
		ra.family.append(b)
	if not (a in rb.family):
		rb.family.append(a)
	Relations.edge(world, a, b).like = maxf(0.7, Relations.get_dim(world, a, b, "like"))
	Relations.edge(world, b, a).like = maxf(0.7, Relations.get_dim(world, b, a, "like"))


## 新建居民。id 自动分配。
static func new_resident(world, female: bool, occ: Dictionary, family_name: String) -> Dictionary:
	var rng: Rng = world.rng
	var id := "r%d" % world.next_resident_id
	world.next_resident_id += 1
	var age: int
	match occ.id:
		"apprentice": age = rng.randi_range(15, 20)
		"widow": age = rng.randi_range(45, 72)
		"mayor", "priest", "owner", "doctor": age = rng.randi_range(40, 64)
		_: age = rng.randi_range(19, 60)
	var traits: Array = []
	var used_excl := {}
	var pool: Array = T.TRAITS.duplicate()
	rng.shuffle(pool)
	for t in pool:
		if traits.size() >= 3:
			break
		var ex: String = t.get("excl", "")
		if ex != "" and used_excl.has(ex):
			continue
		traits.append(t.id)
		if ex != "":
			used_excl[ex] = true
	var literate: bool = rng.chance(float(occ.literate))
	var zh_name: String = world.namegen.full(female, family_name)
	var r := {
		"id": id, "name": zh_name, "name_en": world.namegen.last_en, "female": female, "age": age, "age_weeks": 0,
		"occ": occ.id, "occ_name": occ.name, "occ_en": T.occ_en(occ.id), "work": occ.work,
		"power": int(occ.power), "wealth": int(occ.wealth), "literate": literate,
		"subscribed": (literate and rng.chance(0.75)) or rng.chance(0.25),
		"traits": traits, "bucket": "",
		"spouse": "", "family": [], "friends": [], "enemies": [], "rel": {},
		"player_rel": {"like": rng.randf_range(0.3, 0.6), "trust": rng.randf_range(0.3, 0.5), "fear": 0.0},
		"needs": {"money": 0.5, "safety": 0.7, "reputation": 0.6, "belonging": 0.5, "desire": 0.5},
		"low_weeks": {},
		"knows": {}, "in_town": true, "alive": true, "sick_until": 0, "children": 0,
		"exposed_week": -99, "praised_week": -99, "arrived_week": world.week,
		"avoid_until": 0, "aware": false, "busy_until": 0, "done": {},
		"advertiser": occ.get("advertiser", false), "informer": occ.get("informer", false),
		"keeper": occ.get("keeper", ""), "today": ["", "", ""],
	}
	r.bucket = bucket_of(r)
	return r


static func bucket_of(r: Dictionary) -> String:
	if int(r.power) >= 2:
		return "powerful"
	var bucket := "practical"
	for tid in r.traits:
		var tb: String = T.trait_by_id(tid).get("bucket", "")
		if tb != "":
			bucket = tb
	return bucket


## 换职业（辞退、辞职、升任）。
static func change_job(world, rid: String, occ_id: String) -> void:
	var occ := T.occupation_by_id(occ_id)
	if occ.is_empty():
		if occ_id == "retired":
			occ = {"id": "retired", "name": "赋闲", "work": "home", "power": 0, "wealth": world.residents[rid].wealth}
		else:
			return
	var r: Dictionary = world.residents[rid]
	r.occ = occ.id
	r.occ_name = occ.name
	r.occ_en = T.occ_en(occ.id)
	r.work = occ.work
	if r.work == "farm":
		r.work = world.rng.pick(["farm_a", "farm_b"])
	r.power = int(occ.power)
	r.wealth = mini(int(r.wealth), int(occ.wealth))
	r.informer = occ.get("informer", false)
	r.keeper = occ.get("keeper", "")
	r.advertiser = occ.get("advertiser", false)
	if r.advertiser and not world.ads.has(rid):
		world.ads[rid] = {"paused_until": 0}
	r.bucket = bucket_of(r)
