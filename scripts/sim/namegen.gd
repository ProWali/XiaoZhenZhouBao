## 人名生成器。目标是「听起来像哪里都有」的音译味：莫兰、哈维、托尔森、艾达。
## 不含真实公众人物的姓名组合，词表故意短，发售前再扩。
extends RefCounted

const SURNAME_HEAD := ["莫", "哈", "托", "韦", "格", "兰", "艾", "凯", "罗", "斯", "马", "贝", "德", "法", "霍", "卡", "拉", "诺", "帕", "萨", "塔", "瓦", "雷", "吉"]
const SURNAME_TAIL := ["兰", "维", "尔森", "伯", "林", "特", "德", "斯", "曼", "顿", "克", "尔", "宁", "森", "利", "沃", "彻", "比"]
const MALE_HEAD := ["艾", "安", "本", "达", "恩", "弗", "汉", "吉", "卡", "拉", "卢", "马", "米", "诺", "帕", "瑞", "索", "托", "维", "约"]
const MALE_TAIL := ["德", "尔", "克", "森", "斯", "特", "姆", "恩", "比", "顿"]
const FEMALE_HEAD := ["艾", "安", "贝", "黛", "艾", "菲", "格", "海", "伊", "珂", "莉", "露", "玛", "米", "妮", "诺", "佩", "萨", "泰", "薇"]
const FEMALE_TAIL := ["娜", "拉", "丝", "雅", "莉", "蒂", "塔", "德", "琳", "妲"]

const Rng = preload("res://scripts/sim/rng.gd")

var _rng: Rng
var _used := {}


func _init(rng: Rng) -> void:
	_rng = rng


func surname() -> String:
	return _rng.pick(SURNAME_HEAD) + _rng.pick(SURNAME_TAIL)


func given(is_female: bool) -> String:
	if is_female:
		return _rng.pick(FEMALE_HEAD) + _rng.pick(FEMALE_TAIL)
	return _rng.pick(MALE_HEAD) + _rng.pick(MALE_TAIL)


## 全名，保证一局内不重复。family 非空时沿用家族姓。
func full(is_female: bool, family: String = "") -> String:
	for _attempt in 40:
		var s := family if family != "" else surname()
		var name := s + "·" + given(is_female)
		if not _used.has(name):
			_used[name] = true
			return name
	# 词表耗尽的兜底，几乎不会发生
	var fallback := "无名·%d" % _used.size()
	_used[fallback] = true
	return fallback
