## 居民之间的有向关系边：好感 like、信任 trust、恐惧 fear、亏欠 debt。
## 边是稀疏的，没存的边按默认值算。r.friends / r.enemies 是每周从边里刷出来的缓存，给旧代码和事件模板用。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const FRIEND_LIKE := 0.6
const ENEMY_LIKE := 0.2


static func default_edge() -> Dictionary:
	return {"like": 0.5, "trust": 0.5, "fear": 0.0, "debt": 0.0}


## 取 a 对 b 的边，不存在就建默认边。
static func edge(world, a: String, b: String) -> Dictionary:
	var r: Dictionary = world.residents[a]
	if not r.rel.has(b):
		r.rel[b] = default_edge()
	return r.rel[b]


static func get_dim(world, a: String, b: String, dim: String) -> float:
	var r: Dictionary = world.residents[a]
	if not r.rel.has(b):
		return 0.0 if dim in ["fear", "debt"] else 0.5
	return float(r.rel[b][dim])


static func adjust(world, a: String, b: String, dim: String, delta: float) -> void:
	if a == b or not world.residents.has(a) or not world.residents.has(b):
		return
	var e := edge(world, a, b)
	if dim == "debt":
		e[dim] = maxf(0.0, float(e[dim]) + delta)
	else:
		e[dim] = clampf(float(e[dim]) + delta, 0.0, 1.0)


## 双向同时调（朋友关系大多是对称的）。
static func adjust_both(world, a: String, b: String, dim: String, delta: float) -> void:
	adjust(world, a, b, dim, delta)
	adjust(world, b, a, dim, delta)


static func friends_of(world, rid: String) -> Array:
	var out: Array = []
	var r: Dictionary = world.residents[rid]
	for oid in r.rel:
		if float(r.rel[oid].like) >= FRIEND_LIKE and world.residents.has(oid) and world.residents[oid].alive and world.residents[oid].in_town and not (oid in r.family):
			out.append(oid)
	return out


static func enemies_of(world, rid: String) -> Array:
	var out: Array = []
	var r: Dictionary = world.residents[rid]
	for oid in r.rel:
		if float(r.rel[oid].like) <= ENEMY_LIKE and world.residents.has(oid) and world.residents[oid].alive and world.residents[oid].in_town:
			out.append(oid)
	return out


## 刷新所有人的朋友/仇人缓存。每周一次。
static func refresh_lists(world) -> void:
	for rid in world.residents:
		var r: Dictionary = world.residents[rid]
		r.friends = friends_of(world, rid)
		r.enemies = enemies_of(world, rid)


## 开局建边：家人、同事、朋友、仇人、债务。
static func init_edges(world) -> void:
	var rng: Rng = world.rng
	var ids: Array = world.residents.keys()
	for rid in ids:
		var r: Dictionary = world.residents[rid]
		for fid in r.family:
			var e := edge(world, rid, fid)
			e.like = rng.randf_range(0.65, 0.95)
			e.trust = rng.randf_range(0.6, 0.9)
		# 同事
		var mates: Array = []
		for oid in ids:
			if oid != rid and world.residents[oid].work == r.work and not (oid in r.family):
				mates.append(oid)
		for oid in rng.sample(mates, 4):
			var e := edge(world, rid, oid)
			e.like = rng.randf_range(0.45, 0.65)
			e.trust = rng.randf_range(0.4, 0.6)
		# 朋友
		var want := rng.randi_range(2, 4)
		var tries := 0
		while friends_of(world, rid).size() < want and tries < 30:
			tries += 1
			var other: String = rng.pick(mates) if (not mates.is_empty() and rng.chance(0.6)) else rng.pick(ids)
			if other == rid or other in r.family:
				continue
			var v := rng.randf_range(0.62, 0.85)
			edge(world, rid, other).like = v
			edge(world, rid, other).trust = v - 0.1
			edge(world, other, rid).like = clampf(v + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
			edge(world, other, rid).trust = v - 0.15
		# 仇人
		var hate := rng.weighted([0.45, 0.4, 0.15])
		tries = 0
		var count := 0
		while count < hate and tries < 20:
			tries += 1
			var other: String = rng.pick(ids)
			if other == rid or other in r.family or float(edge(world, rid, other).like) >= FRIEND_LIKE:
				continue
			edge(world, rid, other).like = rng.randf_range(0.05, 0.18)
			edge(world, rid, other).trust = 0.1
			edge(world, other, rid).like = rng.randf_range(0.08, 0.25)
			count += 1
	# 债务：穷人欠店主，普通人偶尔欠厂主
	var grocer := ""
	var owner := ""
	for rid in ids:
		if world.residents[rid].occ == "grocer":
			grocer = rid
		if world.residents[rid].occ == "owner":
			owner = rid
	for rid in ids:
		var r: Dictionary = world.residents[rid]
		if rid == grocer or rid == owner:
			continue
		if r.wealth == 0 and grocer != "" and rng.chance(0.4):
			edge(world, rid, grocer).debt = float(rng.randi_range(4, 18))
		elif r.wealth == 1 and owner != "" and rng.chance(0.12):
			edge(world, rid, owner).debt = float(rng.randi_range(10, 30))
	refresh_lists(world)


## 报道的社会扩散：subj 被曝光后，各方对玩家和对 subj 的看法变化。s 是严重度。
static func on_exposed(world, subj: String, s: float, e: Dictionary) -> void:
	var r: Dictionary = world.residents[subj]
	for fid_ in r.family:
		_bump_player(world, fid_, -0.15 * s)
	for fr in r.friends:
		_bump_player(world, fr, -0.1 * s)
		for ff in world.residents[fr].friends:
			if ff != subj:
				_bump_player(world, ff, -0.03 * s)
	for en in r.enemies:
		_bump_player(world, en, 0.15)
		world.residents[en].player_rel.trust = minf(1.0, world.residents[en].player_rel.trust + 0.1)
	# 受害者角色感激玩家，并且更恨当事人
	for role in e.roles:
		if role != e.target:
			for vid in e.roles[role]:
				if vid != subj and not (vid in r.family):
					_bump_player(world, vid, 0.1)
					adjust(world, vid, subj, "like", -0.2 * s)
					adjust(world, vid, subj, "trust", -0.2 * s)
	# 镇上其他人：看到报道后对当事人的好感下降，信任下降
	for oid in world.living_ids():
		if oid == subj or oid in r.family:
			continue
		if world.residents[oid].rel.has(subj) or world.rng.chance(0.3):
			adjust(world, oid, subj, "like", -0.08 * s)
			adjust(world, oid, subj, "trust", -0.1 * s)


static func _bump_player(world, rid: String, delta: float) -> void:
	var pr: Dictionary = world.residents[rid].player_rel
	pr.like = clampf(float(pr.like) + delta, 0.0, 1.0)
