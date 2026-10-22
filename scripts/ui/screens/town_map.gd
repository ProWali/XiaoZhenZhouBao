## 镇子地图：一屏走完主街。白天点地点进去找人；晚上只开酒馆和几处能蹲守的地方。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const T = preload("res://scripts/sim/tables.gd")

## 地点在 town_map.png 上的位置
const SPOTS := {
	"woods": Rect2(0, 0, 120, 70),
	"station": Rect2(285, 4, 120, 38),
	"church": Rect2(25, 55, 62, 95),
	"tavern": Rect2(100, 85, 66, 65),
	"store": Rect2(185, 95, 62, 62),
	"post": Rect2(268, 100, 56, 52),
	"hall": Rect2(355, 75, 68, 80),
	"clinic": Rect2(438, 100, 50, 52),
	"school": Rect2(498, 88, 60, 64),
	"office": Rect2(572, 92, 46, 64),
	"mill": Rect2(425, 168, 190, 92),
	"bridge": Rect2(280, 172, 42, 98),
	"river": Rect2(0, 196, 270, 62),
	"farm_b": Rect2(60, 262, 90, 62),
	"farm_a": Rect2(495, 272, 80, 62),
}
const NIGHT_SPOTS := ["tavern", "river", "bridge", "woods", "mill"]

var params := {}
var _note: Label


func _ready() -> void:
	var w = Game.world
	var night: bool = w.slot >= 2
	add_child(K.image("res://assets/sprites/bg/town_map.png"))
	if night:
		add_child(K.rect(Color(P.SLATE_DARK, 0.72), Vector2.ZERO, Vector2(640, 360)))
		# 酒馆和报社的窗户还亮着
		for p in [Vector2(122, 128), Vector2(140, 128), Vector2(590, 132)]:
			add_child(K.rect(P.LAMP, p, Vector2(3, 4)))
	elif w.slot == 1:
		add_child(K.rect(Color(P.OCHRE, 0.13), Vector2.ZERO, Vector2(640, 360)))
	Game.ambience("night_ambience" if night else "day_ambience")
	for loc in SPOTS:
		var name: String = Game.place_title(loc)
		var cb: Callable
		var tip := name
		var enabled := true
		var badge := ""
		if loc == "office":
			tip = Game.t("town_map.office_tip")
			cb = func(): Game.sfx("door_open"); Game.route()
		elif night:
			enabled = loc in NIGHT_SPOTS and w.can_act_night()
			tip = Game.t("town_map.night_tip", {"place": name}) if enabled else Game.t("town_map.night_closed", {"place": name})
			cb = _night_action.bind(loc)
		else:
			var n: int = w.people_at(loc).size()
			tip = Game.t("town_map.day_tip", {"place": name, "n": n}) if n > 0 else Game.t("town_map.day_tip_empty", {"place": name})
			badge = ""
			enabled = n > 0 or T.location_by_id(loc).get("archive", false)
			cb = func(): Game.fade_to("location", {"loc": loc}, 0.2)
		var h := K.hotspot(SPOTS[loc], tip, cb)
		h.enabled = enabled
		h.badge = badge
		if loc == "office":
			h.plate = Game.t("town_map.office_plate")
		elif night:
			h.plate = name if enabled else ""
		else:
			var cnt: int = w.people_at(loc).size()
			h.plate = "%s %d" % [name, cnt] if cnt > 0 else name
			for rid in w.people_at(loc):
				if Game.lead_from(rid) != "":
					h.plate += " ★"
					h.tip += Game.t("town_map.lead_here")
					break
		add_child(h)
	var hud := Hud.new()
	hud.end_day_requested.connect(Game.request_end_day)
	add_child(hud)
	_note = K.note_bar(self, 342, 18, 0.85)
	if night:
		if w.can_act_night():
			_note.text = Game.t("town_map.night_note")
		else:
			_note.text = Game.t("town_map.night_done")
	elif not w.can_act_day():
		_note.text = Game.t("location.no_actions")
	else:
		_note.text = Game.t("town_map.day_note")


func _night_action(loc: String) -> void:
	var w = Game.world
	var warn := ""
	if w.nights_used >= w.MAX_NIGHTS:
		warn = Game.t("town_map.warn_nights") + "\n"
	if loc == "tavern":
		Game.open_overlay("pick", {"title": Game.t("town_map.tavern_title"), "note": warn + Game.t("town_map.tavern_note"), "items": [
			{"text": Game.t("town_map.tavern_listen"), "cb": func(): _do_night("eavesdrop", loc)},
			{"text": Game.t("town_map.tavern_watch"), "cb": func(): _do_night("stakeout", loc)},
		]})
	else:
		Game.open_overlay("confirm", {"text": warn + Game.t("town_map.watch_confirm", {"place": Game.place(loc)}), "yes": Game.t("town_map.watch_yes"), "no": Game.t("location.archive_no"), "on_yes": func(): _do_night("stakeout", loc)})


func _do_night(kind: String, loc: String) -> void:
	var w = Game.world
	var res: Dictionary = w.act_eavesdrop() if kind == "eavesdrop" else w.act_stakeout(loc)
	Game.sfx("footsteps_wood")
	var title := Game.t("town_map.tavern_result") if kind == "eavesdrop" else Game.t("town_map.watch_result", {"place": Game.place(loc)})
	Game.show_result(title, res, "", func(): Game.route())
