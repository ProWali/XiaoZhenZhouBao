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
	add_child(K.rect(Color(P.INK, 0.85), Vector2(0, 342), Vector2(640, 18)))
	_note = K.label("", "pixel", 12, P.PAPER)
	_note.position = Vector2(6, 344)
	add_child(_note)
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
		_note.text = "周一早上。门缝下有前任主编留下的一封信。"
	elif n > 0:
		_note.text = "周一早上。报纸发出去了，门缝下塞进来 %d 封信。" % n
	else:
		_note.text = "周一早上。门缝下什么也没有。桌上是上周的账本。"
	add_child(K.hotspot(Rect2(500, 300, 110, 40), "门缝下的信" if n > 0 else "账本", _read))
	var b := K.button("读信" if n > 0 else "看账本", _read, 80)
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
	add_child(K.hotspot(Rect2(560, 20, 60, 300), "出门 · 晚上去哪蹲着" if evening else "出门 · 去镇上", func(): Game.sfx("door_open"); Game.fade_to("town_map")))
	add_child(K.hotspot(Rect2(322, 192, 74, 22), "选题簿", func(): Game.open_overlay("notebook")))
	add_child(K.hotspot(Rect2(166, 222, 60, 82), "抽屉 · 线人的地址", _informer))
	add_child(K.hotspot(Rect2(388, 40, 54, 72), "日历 · %s" % ("回去睡觉" if evening else "收工"), Game.request_end_day))
	add_child(K.hotspot(Rect2(430, 92, 110, 176), "印刷机 · 周日才开", func(): _say("印刷机要等到周日。这一周的料先攒在选题簿里。")))
	add_child(K.hotspot(Rect2(228, 38, 144, 88), "广告板", _ads_info))
	if w.day == 1 and w.slot == 0 and w.week == 1:
		_note.text = "第一周。推开右边的门去镇上找人聊聊；问到的事会记进桌上的选题簿。"
	elif w.day == 2 and w.slot == 0 and w.week == 1:
		_note.text = "桌子左边的抽屉里有线人的地址：花三块钱，可以托他打听某个人。"
	elif evening:
		_note.text = "天黑了。可以出门去酒馆听听、找个地方蹲守（熬夜），或者回去睡觉。"
	elif w.day == 6:
		_note.text = "周六。今晚可能有人上门，明天周日排版付印。"
	elif w.slot == 0:
		_note.text = "%s上午。" % w.DAY_NAMES[w.day] + _hint()
	else:
		_note.text = "%s下午。" % w.DAY_NAMES[w.day] + _hint()


func _hint() -> String:
	var w = Game.world
	var groups: Array = w.notebook()
	if groups.is_empty():
		return "选题簿还是空的。"
	var unverified := 0
	for g in groups:
		for fid in g.facts:
			if not w.is_verified(fid):
				unverified += 1
	if unverified > 0:
		return "选题簿里有 %d 件事，%d 条还没坐实。" % [groups.size(), unverified]
	return "选题簿里有 %d 件事。" % groups.size()


func _say(text: String) -> void:
	_note.text = text


func _informer() -> void:
	var w = Game.world
	if not w.can_act_day():
		_say("线人只在白天见。")
		return
	if w.stats.cash < 3:
		_say("线人要三块钱，抽屉里不够。")
		return
	var items: Array = []
	var known_people := _people_of_interest()
	for rid in known_people:
		var r: Dictionary = w.residents[rid]
		items.append({"text": "%s（%s）" % [r.name, TE.occ_label(w, rid, "zh")], "who": rid, "cb": func():
			var res: Dictionary = w.act_informer(rid)
			Game.sfx("coins")
			Game.show_result("托线人打听%s" % r.name, res, "", func(): Game.route(false))})
	Game.open_overlay("pick", {"title": "托线人打听谁？", "note": "花 3 块钱和一个行动点。线人消息准，但有时会被人收买。只列你见过或听说过的人。", "items": items})


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
		lines.append("%s（%s）：%s" % [r.name, TE.loc_label(w, r.work, "zh"), "登着" if on else "撤了"])
	_say("广告：" + "；".join(lines))
