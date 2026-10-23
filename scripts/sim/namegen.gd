## 人名生成器。目标是「听起来像哪里都有」的音译味：莫兰、哈维、托尔森、艾达。
## 每个音节同时有中文和英文写法，一个人的中英文名由同一组音节拼成，读起来是同一个名字。
## 中文写法「名·姓」（音译名的习惯写法，一家人共用后半截），英文写法「Given Surname」。词表顺序不要改，改了同种子的人名就变了。
## 一局里名不重复、不同的家不同姓（老板试玩：「卡维·瑞恩」「卡维·卢比」是一家人，读着像两个叫卡维的人）。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")

const SURNAME_HEAD := [["莫", "Mor"], ["哈", "Har"], ["托", "Tor"], ["韦", "Wey"], ["格", "Gren"], ["兰", "Lan"], ["艾", "Ash"], ["凯", "Kel"], ["罗", "Ros"], ["斯", "Stan"], ["马", "Mar"], ["贝", "Bel"], ["德", "Dal"], ["法", "Fal"], ["霍", "Hol"], ["卡", "Car"], ["拉", "Rad"], ["诺", "Nor"], ["帕", "Pal"], ["萨", "Sal"], ["塔", "Tal"], ["瓦", "Wal"], ["雷", "Ray"], ["吉", "Gil"]]
const SURNAME_TAIL := [["兰", "land"], ["维", "ville"], ["尔森", "son"], ["伯", "by"], ["林", "ling"], ["特", "ter"], ["德", "den"], ["斯", "ley"], ["曼", "man"], ["顿", "ton"], ["克", "wick"], ["尔", "well"], ["宁", "ning"], ["森", "sen"], ["利", "ly"], ["沃", "worth"], ["彻", "chett"], ["比", "bury"]]
const MALE_HEAD := [["艾", "Al"], ["安", "An"], ["本", "Ben"], ["达", "Dan"], ["恩", "En"], ["弗", "Fre"], ["汉", "Han"], ["吉", "Gil"], ["卡", "Cal"], ["拉", "Ral"], ["卢", "Lu"], ["马", "Mal"], ["米", "Mil"], ["诺", "Nor"], ["帕", "Pat"], ["瑞", "Ren"], ["索", "Sol"], ["托", "Tom"], ["维", "Vin"], ["约", "Jo"]]
const MALE_TAIL := [["德", "den"], ["尔", "vin"], ["克", "ric"], ["森", "son"], ["斯", "las"], ["特", "bert"], ["姆", "mond"], ["恩", "ney"], ["比", "by"], ["顿", "ton"]]
const FEMALE_HEAD := [["艾", "A"], ["安", "An"], ["贝", "Be"], ["黛", "Dai"], ["艾", "E"], ["菲", "Fi"], ["格", "Gre"], ["海", "He"], ["伊", "I"], ["珂", "Co"], ["莉", "Li"], ["露", "Lu"], ["玛", "Ma"], ["米", "Mi"], ["妮", "Ni"], ["诺", "No"], ["佩", "Pe"], ["萨", "Sa"], ["泰", "Te"], ["薇", "Vi"]]
const FEMALE_TAIL := [["娜", "na"], ["拉", "ra"], ["丝", "ssa"], ["雅", "ya"], ["莉", "lia"], ["蒂", "tty"], ["塔", "ta"], ["德", "da"], ["琳", "lyn"], ["妲", "dra"]]

var _rng: Rng
var _used := {}
var _given_used := {}   # 用过的名（中文），一局不重复
var last_en := ""   # 上一次 full() 生成的英文名


func _init(rng: Rng) -> void:
	_rng = rng


## 返回 [中文, 英文]
func surname_pair() -> Array:
	var h: Array = _rng.pick(SURNAME_HEAD)
	var t: Array = _rng.pick(SURNAME_TAIL)
	# 「德德」「兰兰」这种叠字姓不像名字，换一个尾音
	while t[0] == h[0]:
		t = _rng.pick(SURNAME_TAIL)
	return [h[0] + t[0], h[1] + t[1]]


func given_pair(is_female: bool) -> Array:
	var h: Array
	var t: Array
	if is_female:
		h = _rng.pick(FEMALE_HEAD)
		t = _rng.pick(FEMALE_TAIL)
	else:
		h = _rng.pick(MALE_HEAD)
		t = _rng.pick(MALE_TAIL)
	return [h[0] + t[0], h[1] + t[1]]


## 中文全名，名和姓都不跟镇上别的人撞。family 非空时沿用家族姓（传中文姓，英文姓从登记表里查）。
## 英文名放在 last_en。
func full(is_female: bool, family: String = "") -> String:
	for _attempt in 60:
		var s: Array = [family, _family_en.get(family, "")] if family != "" else surname_pair()
		# 新起的一家不跟已有的家同姓
		if family == "" and (_family_en.has(s[0]) or _given_used.has(s[0])):
			continue
		var g: Array = given_pair(is_female)
		# 名不跟别人的名、别家的姓撞，也不跟自己的姓同头同尾（「维德·韦德」「拉森·拉斯」念起来像一个词）
		if _given_used.has(g[0]) or _family_en.has(g[0]) or g[0].right(1) == s[0].right(1) or g[0].left(1) == s[0].left(1):
			continue
		var name: String = g[0] + "·" + s[0]
		if not _used.has(name):
			_used[name] = true
			_given_used[g[0]] = true
			_family_en[s[0]] = s[1]
			last_en = g[1] + " " + s[1]
			return name
	var fallback := "无名·%d" % _used.size()
	_used[fallback] = true
	last_en = "Nobody %d" % _used.size()
	return fallback


## 中文名里的姓（「名·姓」的后半截）
static func zh_surname(name: String) -> String:
	var parts := name.split("·")
	return parts[parts.size() - 1]


var _family_en := {}
