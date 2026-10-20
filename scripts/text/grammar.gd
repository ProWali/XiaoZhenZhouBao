## 语法层：类 Tracery 的模板展开器。只处理文字结构，不认识居民和事件。
##
##   #符号#          从规则表抽一条并递归展开。先找带后缀的特化版本：#close# 在秋天、煽动语气下
##                   依次尝试 close@hot、close@autumn，都没有才用 close。
##   #符号.cap#      英文：首字母大写
##   #符号.a#        英文：前面加 a / an
##   [甲|乙|丙]      就地多选一，可以嵌套
##   [?文字]         一半概率出现
##   {槽位}          原样保留，交给 text_engine 填
##
## 所有随机都走传进来的 rng，同一个 rng 状态展开同一个模板，结果逐字相同。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")
const MAX_DEPTH := 10

var rules: Dictionary
var rng: Rng
var suffixes: Array = []   # 例如 ["@hot", "@autumn"]，越靠前越优先
## 用过的句子：模板原文 -> 上次用的周。设了它，抽取时避开最近 FRESH_WEEKS 周用过的。
## 只影响措辞，不影响模拟；存在 world.text_memory 里，重放时按同样顺序重建。
var memory = null
var week := 0
const FRESH_WEEKS := 26

static var _re_sym: RegEx
static var _re_bracket: RegEx


func _init(rules_in: Dictionary, rng_in: Rng, suffixes_in: Array = []) -> void:
	rules = rules_in
	rng = rng_in
	suffixes = suffixes_in
	if _re_sym == null:
		_re_sym = RegEx.new()
		_re_sym.compile("#([A-Za-z0-9_]+)(\\.[a-z]+)?#")
		_re_bracket = RegEx.new()
		_re_bracket.compile("\\[([^\\[\\]]*)\\]")


func has_rule(name: String) -> bool:
	if rules.has(name):
		return true
	for suf in suffixes:
		if rules.has(name + suf):
			return true
	return false


## 从一组候选里抽一条再展开。候选可以是字符串或字符串数组。
func pick_expand(options) -> String:
	if options is String:
		return expand(options)
	if options is Array and not options.is_empty():
		return expand(pick_fresh(options))
	return ""


## 抽一条：有记忆时避开最近用过的，全用过了就挑最久没用的。抽中的记下来。
func pick_fresh(options: Array) -> String:
	if options.is_empty():
		return ""
	if memory == null:
		return str(rng.pick(options))
	var min_n := 1 << 30
	for o in options:
		min_n = mini(min_n, int(memory.get("n:" + str(o), 0)))
	var least: Array = []
	var fresh: Array = []
	for o in options:
		var k := str(o)
		if int(memory.get("n:" + k, 0)) != min_n:
			continue
		least.append(k)
		if int(memory.get(k, -999)) <= week - FRESH_WEEKS:
			fresh.append(k)
	var chosen: String = str(rng.pick(fresh)) if not fresh.is_empty() else str(rng.pick(least))
	memory[chosen] = week
	memory["n:" + chosen] = int(memory.get("n:" + chosen, 0)) + 1
	return chosen


func expand(text: String, depth: int = 0) -> String:
	if depth > MAX_DEPTH:
		return text
	var s := _expand_brackets(text)
	var out := ""
	var pos := 0
	for m in _re_sym.search_all(s):
		out += s.substr(pos, m.get_start() - pos)
		out += _apply_mod(_expand_symbol(m.get_string(1), depth), m.get_string(2))
		pos = m.get_end()
	out += s.substr(pos)
	# 展开出来的文字里可能又有方括号或符号
	if out.find("#") >= 0 or out.find("[") >= 0:
		if out != text:
			return expand(out, depth + 1)
	return out


func _expand_symbol(name: String, depth: int) -> String:
	var options = null
	for suf in suffixes:
		if rules.has(name + suf):
			options = rules[name + suf]
			break
	if options == null:
		options = rules.get(name, null)
	if options == null:
		return "〔%s〕" % name  # 缺规则时留下显眼标记，lint 会抓
	var chosen: String = options if options is String else (pick_fresh(options) if options.size() >= 3 else str(rng.pick(options)))
	return expand(chosen, depth + 1)


## 从最内层开始处理方括号，保证嵌套也能正确展开。
func _expand_brackets(text: String) -> String:
	var s := text
	for _guard in 64:
		var m := _re_bracket.search(s)
		if m == null:
			break
		var inner := m.get_string(1)
		var rep: String
		if inner.begins_with("?"):
			rep = inner.substr(1) if rng.chance(0.5) else ""
		else:
			rep = str(rng.pick(Array(inner.split("|"))))
		s = s.substr(0, m.get_start()) + rep + s.substr(m.get_end())
	return s


static func _apply_mod(s: String, mod: String) -> String:
	match mod:
		".cap":
			return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s
		".a":
			if s == "":
				return s
			var first := s.substr(0, 1).to_lower()
			return ("an " if first in ["a", "e", "i", "o", "u"] else "a ") + s
	return s
