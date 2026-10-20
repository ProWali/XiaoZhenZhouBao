## 事件模板：从 data/events/*.json 读入，按角色条件在镇子里选人，实例化成一组事实碎片。
## 实例结构：
##   {id, tid, name, severity, soft, positive, target(role), roles{role: [resident ids]},
##    week_start, week_end, facts: [fact_id], witness: {loc: fact_id}, printed: bool, ...}
extends RefCounted

const T = preload("res://scripts/sim/tables.gd")

var templates: Array = []


func load_all(dir_path: String = "res://data/events") -> void:
	templates.clear()
	var dir := DirAccess.open(dir_path)
	assert(dir != null, "打不开事件目录 " + dir_path)
	var names: Array = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()  # 读入顺序必须稳定，否则同种子不同结果
	for n in names:
		var text := FileAccess.get_file_as_string(dir_path + "/" + n)
		var data = JSON.parse_string(text)
		assert(data is Dictionary, "事件模板不是合法 JSON：" + n)
		templates.append(data)


func template_by_id(tid: String) -> Dictionary:
	for t in templates:
		if t.id == tid:
			return t
	return {}


## 判断居民是否满足角色条件。
static func _fits(res: Dictionary, spec: Dictionary, world) -> bool:
	if not res.in_town or not res.alive:
		return false
	if spec.has("occupation") and not (res.occ in spec.occupation):
		return false
	if spec.has("wealth_max") and res.wealth > spec.wealth_max:
		return false
	if spec.has("power_min") and res.power < spec.power_min:
		return false
	if spec.has("female") and res.female != spec.female:
		return false
	if spec.get("single", false) and (res.spouse != "" or int(res.get("widowed_week", -99)) > world.week - 30):
		return false
	if spec.get("married", false) and res.spouse == "":
		return false
	if res.get("busy_until", 0) > world.week:
		return false
	return true


## 为模板选角。失败返回空字典。preset 指定某些角色必须是谁（{role: [rid]}），用于需求驱动和后续事件。
func cast_roles(tpl: Dictionary, world, preset: Dictionary = {}) -> Dictionary:
	var roles := {}
	var taken := {}
	for role in preset:
		for rid in preset[role]:
			taken[rid] = true
	var order: Array = tpl.roles.keys()
	# spouse_of 依赖别的角色，放到最后
	order.sort_custom(func(a, b): return int(tpl.roles[a].has("spouse_of")) < int(tpl.roles[b].has("spouse_of")))
	for role in order:
		var spec: Dictionary = tpl.roles[role]
		var count: int = spec.get("count", 1)
		var picked: Array = []
		if preset.has(role):
			picked = preset[role].duplicate()
			for rid in picked:
				if not world.residents.has(rid) or not world.residents[rid].alive or not world.residents[rid].in_town:
					return {}
				# 预设的人也得符合角色条件（后续事件的角色条件是空的，天然通过）
				if not spec.is_empty() and (not _fits(world.residents[rid], spec, world) or world.residents[rid].done.has(tpl.id)):
					return {}
		elif spec.has("spouse_of"):
			var base: Array = roles.get(spec.spouse_of, [])
			if base.is_empty():
				return {}
			var sp: String = world.residents[base[0]].spouse
			if sp == "" or taken.has(sp) or not world.residents[sp].alive or not world.residents[sp].in_town:
				return {}
			picked.append(sp)
		else:
			var pool: Array = []
			for rid in world.residents:
				if taken.has(rid) or world.residents[rid].done.has(tpl.id):
					continue
				if _fits(world.residents[rid], spec, world):
					pool.append(rid)
			if pool.size() < count:
				return {}
			picked = world.rng.sample(pool, count)
		for rid in picked:
			taken[rid] = true
		roles[role] = picked
	return roles


## 实例化：生成事实碎片并分发「谁知道」。extras 是模板里 {x_键} 槽位的填充文本。
func instantiate(tpl: Dictionary, roles: Dictionary, world, extras: Dictionary = {}) -> Dictionary:
	var inst := {
		"id": "e%d" % world.next_event_id, "tid": tpl.id, "name": tpl.name, "extras": extras,
		"severity": int(tpl.severity), "soft": tpl.get("soft", false), "positive": tpl.get("positive", false),
		"target": tpl.target, "roles": roles, "detail": tpl.get("detail", ""),
		"week_start": world.week, "week_end": world.week + int(tpl.weeks),
		"facts": [], "rumor_facts": [], "witness": {}, "printed": false, "printed_week": 0,
		"plea": "", "suppressed": false, "bribed_by": "", "occ_at": {},
	}
	for role in roles:
		for rid in roles[role]:
			inst.occ_at[rid] = world.residents[rid].occ
	world.next_event_id += 1
	for frag in tpl.fragments:
		var fid := _make_fact(inst, frag, roles, world, 1.0)
		inst.facts.append(fid)
		if frag.has("witness"):
			inst.witness[frag.witness] = fid
	for rum in tpl.get("rumors", []):
		var fid := _make_fact(inst, rum, roles, world, float(rum.truth))
		inst.rumor_facts.append(fid)
	# 当事人把自己牵扯进去的时间标记，避免同一个人同时是三件事的主角
	for role in roles:
		for rid in roles[role]:
			world.residents[rid].busy_until = inst.week_end
			if tpl.get("once", false):
				world.residents[rid].done[tpl.id] = true
	if tpl.get("marry", false):
		var ids: Array = []
		for role in roles:
			ids.append(roles[role][0])
		if ids.size() == 2:
			var a: Dictionary = world.residents[ids[0]]
			var b: Dictionary = world.residents[ids[1]]
			a.spouse = b.id
			b.spouse = a.id
			a.family.append(b.id)
			b.family.append(a.id)
	return inst


func _make_fact(inst: Dictionary, frag: Dictionary, roles: Dictionary, world, truth: float) -> String:
	var subj: String = roles[frag.subject][0]
	var fid := "f%d" % world.next_fact_id
	world.next_fact_id += 1
	var fact := {
		"id": fid, "event": inst.id, "key": frag.get("key", "rumor"),
		"subject": subj, "text_tpl": frag.text, "truth": truth,
		"secrecy": frag.get("secrecy", "secret"),
		"archive": frag.get("archive", ""), "witness": frag.get("witness", ""),
		"week": world.week, "is_rumor": truth < 0.5,
	}
	fact["text"] = fill_text(frag.text, roles, world, "named", "", "named", inst.extras)
	world.facts[fid] = fact
	# 分发知情者
	for spec in frag.get("known_by", []):
		for rid in _resolve_known(spec, roles, world):
			world.residents[rid].knows[fid] = true
	return fid


## known_by 语法：role | friends:role | family:role | enemies:role | work:role:n | random:n | gossip:n | all
func _resolve_known(spec: String, roles: Dictionary, world) -> Array:
	var parts := spec.split(":")
	var out: Array = []
	match parts[0]:
		"all":
			for rid in world.residents:
				out.append(rid)
		"random":
			out = world.rng.sample(world.living_ids(), int(parts[1]))
		"gossip":
			var pool: Array = []
			for rid in world.living_ids():
				if "gossip" in world.residents[rid].traits:
					pool.append(rid)
			out = world.rng.sample(pool, int(parts[1]))
		"friends", "family", "enemies", "work":
			for rid in roles.get(parts[1], []):
				var r: Dictionary = world.residents[rid]
				match parts[0]:
					"friends": out.append_array(r.friends)
					"family": out.append_array(r.family)
					"enemies": out.append_array(r.enemies)
					"work":
						var pool: Array = []
						for oid in world.living_ids():
							if oid != rid and world.residents[oid].work == r.work:
								pool.append(oid)
						out.append_array(world.rng.sample(pool, int(parts[2])))
		_:
			out.append_array(roles.get(parts[0], []))
	return out


## 把 {role} 槽位填成名字。naming 只作用于 target 角色；其余角色按 other_mode（"named" 真名 / "occ" 职业）。
static func fill_text(tpl: String, roles: Dictionary, world, naming: String, target_role: String, other_mode: String = "named", extras: Dictionary = {}, occ_at: Dictionary = {}) -> String:
	var s := tpl
	for k in extras:
		s = s.replace("{x_" + k + "}", str(extras[k]))
	for role in roles:
		var rid: String = roles[role][0]
		var r: Dictionary = world.residents[rid]
		var occ_id: String = occ_at.get(rid, "")
		var occ: String = r.occ_name
		if occ_id != "":
			var o := T.occupation_by_id(occ_id)
			occ = o.name if not o.is_empty() else {"homemaker": "家眷", "retired": "赋闲的人"}.get(occ_id, r.occ_name)
		var shown: String
		if role == target_role:
			shown = display_name(r, naming, occ)
		elif other_mode == "occ":
			shown = "某" + occ
		else:
			shown = r.name
		s = s.replace("{" + role + "}", shown)
	return s


static func display_name(r: Dictionary, naming: String, occ: String = "") -> String:
	match naming:
		"named": return r.name
		"alias": return "某" + (occ if occ != "" else r.occ_name)
		_: return "镇上某人"


## 候选标题：模板里该语气的全部变体，已填槽。
func headlines(inst: Dictionary, tone: String, naming: String, world) -> Array:
	var tpl := template_by_id(inst.tid)
	var out: Array = []
	for h in tpl.headlines.get(tone, tpl.headlines.get("neutral", [])):
		out.append(fill_text(h, inst.roles, world, naming, inst.target, "occ" if naming != "named" else "named", inst.get("extras", {}), inst.get("occ_at", {})))
	return out
