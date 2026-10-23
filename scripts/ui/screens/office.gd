## 编辑室：一张固定画面加可变层（策划案九版决策 5）。白天是枢纽，周一早上先读门缝下的信。
## mode: morning（周一读信）、day（白天和晚上的枢纽）
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Layers = preload("res://scripts/ui/office_layers.gd")
const TE = preload("res://scripts/text/text_engine.gd")

var params := {}
var _hud: Control
var _layers: Control
var _note: Label


func _ready() -> void:
	var w = Game.world
	var mode: String = params.get("mode", "day")
	var night: bool = mode == "day" and w.slot >= 2
	add_child(K.image("res://assets/sprites/bg/office.png" if (night or mode == "morning") else "res://assets/sprites/bg/office_day.png"))
	_layers = Layers.new()
	_layers.letters = w.letters.size() if mode == "morning" else 0
	add_child(_layers)
	_hud = Hud.new()
	_hud.show_end_day = mode == "day"
	_hud.end_day_requested.connect(Game.request_end_day)
	add_child(_hud)
	# 底下一行：现在该干什么
	_note = K.note_bar(self, 342, 18, 0.85)
	if mode == "morning":
		_morning()
	else:
		_day()


func _morning() -> void:
	var w = Game.world
	Game.ambience("night_ambience")
	Game.music("piano_2" if w.week > 1 else "piano_1")
	await get_tree().create_timer(0.6).timeout
	Game.sfx("mail_slot")
	var n: int = w.letters.size()
	if w.week == 1:
		_note.text = Game.t("office.morning_first")
	elif n > 0:
		_note.text = Game.t("office.morning_letters", {"n": n})
	else:
		_note.text = Game.t("office.morning_none")
	add_child(K.hotspot(Rect2(500, 300, 110, 40), Game.t("office.tip_letters") if n > 0 else Game.t("office.tip_ledger"), _read))
	var b := K.button(Game.t("office.read_letters") if n > 0 else Game.t("office.read_ledger"), _read, 80)
	b.position = Vector2(552, 320)
	add_child(b)
	b.grab_focus()


func _read() -> void:
	Game.open_overlay("letters", {"on_done": func():
		Game.ui.letters_week = Game.world.week
		Game.track("letters_done", {"n": Game.world.letters.size()})
		Game.route()})


func _day() -> void:
	var w = Game.world
	var evening: bool = w.slot >= 2
	Game.ambience("night_ambience" if evening else "day_ambience")
	if evening:
		Game.stop_music()
	# 热区：门、选题簿、抽屉（线人）、日历（收工）、印刷机、广告板
	add_child(K.hotspot(Rect2(560, 20, 60, 300), Game.t("office.tip_door_night") if evening else Game.t("office.tip_door_day"), func(): Game.sfx("door_open"); Game.fade_to("town_map")))
	add_child(K.hotspot(Rect2(322, 192, 74, 22), Game.t("hud.notebook"), func(): Game.open_overlay("notebook")))
	add_child(K.hotspot(Rect2(166, 222, 60, 82), Game.t("office.tip_drawer"), _informer))
	add_child(K.hotspot(Rect2(388, 40, 54, 72), Game.t("office.tip_calendar", {"what": Game.t("hud.go_to_bed") if evening else Game.t("hud.end_day")}), Game.request_end_day))
	add_child(K.hotspot(Rect2(430, 92, 110, 176), Game.t("office.tip_press"), func(): _say(Game.t("office.press_wait"))))
	add_child(K.hotspot(Rect2(228, 38, 144, 88), Game.t("office.tip_ads"), _ads_info))
	if w.slept_in == w.week * 10 + w.day:
		_note.text = Game.t("office.slept_in")
	elif w.day == 1 and w.slot == 0 and w.week == 1:
		_note.text = Game.t("office.first_week")
	elif w.day == 2 and w.slot == 0 and w.week == 1:
		_note.text = Game.t("office.first_tuesday")
	elif w.day == 3 and w.slot == 0 and w.week == 1:
		# 第 6 轮：新手不知道「章」是什么、怎样算坐实
		_note.text = Game.t("office.first_wednesday")
	elif evening:
		_note.text = Game.t("office.evening")
	elif w.day == 6:
		_note.text = Game.t("office.saturday")
	elif w.slot == 0:
		_note.text = Game.t("office.day_slot", {"day": Game.day_name(w.day), "slot": Game.slot_name(0)}) + _hint()
	else:
		_note.text = Game.t("office.day_slot", {"day": Game.day_name(w.day), "slot": Game.slot_name(1)}) + _hint()


func _hint() -> String:
	var w = Game.world
	for l in w.leads:
		var where: String = w.where_is(l.who)
		if where != "" and not where.begins_with("home:"):
			var key := "office.hint_lead_self" if str(l.from) == str(l.who) else "office.hint_lead"
			if l.has("fact"):
				key = "office.hint_lead_vouch"
			return Game.t(key, {"from": Game.name_of(l.from), "who": Game.name_of(l.who), "where": Game.place(where)})
	var groups: Array = w.notebook()
	if groups.is_empty():
		return Game.t("office.hint_empty")
	var unverified := 0
	for g in groups:
		for fid in g.facts:
			if not w.is_verified(fid):
				unverified += 1
	if unverified > 0:
		return Game.t("office.hint_unverified", {"n": groups.size(), "u": unverified})
	return Game.t("office.hint_n", {"n": groups.size()})


func _say(text: String) -> void:
	_note.text = text


func _informer() -> void:
	var w = Game.world
	if not w.can_act_day():
		_say(Game.t("office.informer_day_only"))
		return
	if w.stats.cash < 3:
		_say(Game.t("office.informer_broke"))
		return
	var items: Array = []
	var known_people := _people_of_interest()
	for rid in known_people:
		var r: Dictionary = w.residents[rid]
		items.append({"text": Game.t("office.person_occ", {"name": Game.name_of(rid), "occ": Game.occ(rid)}), "who": rid, "cb": func():
			var res: Dictionary = w.act_informer(rid)
			Game.sfx("coins")
			Game.show_result(Game.t("office.informer_title", {"name": Game.name_of(rid)}), res, "", func(): Game.route(false))})
	Game.open_overlay("pick", {"title": Game.t("office.informer_pick"), "note": Game.t("office.informer_note"), "items": items})


## 玩家见过或听说过的人：选题簿里出现过的、告诉过你事情的、采访过的
func _people_of_interest() -> Array:
	var w = Game.world
	var seen := {}
	for fid in w.known:
		seen[w.facts[fid].subject] = true
		for s in w.known[fid].sources:
			if s.who != "":
				seen[s.who] = true
	for a in w.actions:
		if a.get("kind", "") == "interview":
			seen[str(a.rid)] = true
	var out: Array = []
	for rid in w.living_ids():
		if seen.has(rid):
			out.append(rid)
	if out.is_empty():
		out = w.living_ids()
	return out


func _ads_info() -> void:
	var w = Game.world
	var lines: Array = []
	for rid in w.ads:
		var r: Dictionary = w.residents[rid]
		var on: bool = w.ads[rid].paused_until <= w.week and r.in_town and r.player_rel.like >= 0.3
		lines.append(Game.t("office.ad_line", {"name": Game.name_of(rid), "where": Game.place(r.work), "state": Game.t("office.ad_on") if on else Game.t("office.ad_off")}))
	_say(Game.t("office.ads") + Game.t("common.list_sep").join(lines))
