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
		var name: String = w.loc_name(loc)
		var cb: Callable
		var tip := name
		var enabled := true
		var badge := ""
		if loc == "office":
			tip = "报社 · 回去"
			cb = func(): Game.sfx("door_open"); Game.route()
		elif night:
			enabled = loc in NIGHT_SPOTS and w.can_act_night()
			tip = name + (" · 熬夜" if enabled else " · 晚上没人")
			cb = _night_action.bind(loc)
		else:
			var n: int = w.people_at(loc).size()
			tip = "%s · %s" % [name, ("%d 人" % n) if n > 0 else "没人"]
			badge = ""
			enabled = n > 0 or T.location_by_id(loc).get("archive", false)
			cb = func(): Game.fade_to("location", {"loc": loc}, 0.2)
		var h := K.hotspot(SPOTS[loc], tip, cb)
		h.enabled = enabled
		h.badge = badge
		if loc == "office":
			h.plate = "报社"
		elif night:
			h.plate = name if enabled else ""
		else:
			var cnt: int = w.people_at(loc).size()
			h.plate = "%s %d" % [name, cnt] if cnt > 0 else name
		add_child(h)
	var hud := Hud.new()
	hud.end_day_requested.connect(Game.request_end_day)
	add_child(hud)
	add_child(K.rect(Color(P.INK, 0.85), Vector2(0, 342), Vector2(640, 18)))
	_note = K.label("", "pixel", 12, P.PAPER)
	_note.position = Vector2(6, 344)
	add_child(_note)
	if night:
		if w.can_act_night():
			_note.text = "晚上。酒馆里能听到醉话；河边、桥头、树林、锯木厂可以蹲守。熬夜一周最多两次。"
		else:
			_note.text = "今晚出不去了。回报社睡觉。"
	elif not w.can_act_day():
		_note.text = "今天的行动点用完了。"
	else:
		_note.text = "名牌上的数字是这会儿在那儿的人。进门不花行动点，找人谈、查档案才花。"


func _night_action(loc: String) -> void:
	var w = Game.world
	var warn := ""
	if w.nights_used >= w.MAX_NIGHTS:
		warn = "这周已经熬了两夜。再熬，明天上午就起不来了。\n"
	if loc == "tavern":
		Game.open_overlay("pick", {"title": "酒馆，晚上", "note": warn + "熬一夜，明天照常。", "items": [
			{"text": "坐进去听酒客说话（量大，可信度低，可能听到假的）", "cb": func(): _do_night("eavesdrop", loc)},
			{"text": "在外面守着，看谁进出", "cb": func(): _do_night("stakeout", loc)},
		]})
	else:
		Game.open_overlay("confirm", {"text": warn + "在%s蹲一夜？亲眼看见的事最可信，但不一定有事。" % w.loc_name(loc), "yes": "蹲守", "no": "算了", "on_yes": func(): _do_night("stakeout", loc)})


func _do_night(kind: String, loc: String) -> void:
	var w = Game.world
	var res: Dictionary = w.act_eavesdrop() if kind == "eavesdrop" else w.act_stakeout(loc)
	Game.sfx("footsteps_wood")
	var title := "酒馆里" if kind == "eavesdrop" else "在%s守了一夜" % w.loc_name(loc)
	Game.show_result(title, res, "", func(): Game.route())
