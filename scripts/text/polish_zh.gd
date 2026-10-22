## 中文润色层：规则集，处理模板拼接后留下的机械痕迹。只做确定性的规则，不用随机。
extends RefCounted

## 后面跟动词时应该写「地」的副词
const ADVERBS := ["悄悄", "偷偷", "慢慢", "默默", "渐渐", "匆匆", "狠狠", "静静", "远远", "早早", "好好", "急急", "轻轻", "重重", "死死", "直直", "一声不吭", "不声不响", "不紧不慢"]
## 「一个 X」里该换成「一位」的人（体面职业），其余人用「一名」
const RESPECT := ["镇长", "牧师", "医生", "教师", "店主", "站长", "警长", "书记员", "厂主", "护士", "老人", "太太", "先生", "小姐", "寡妇"]
const PEOPLE := ["工人", "工头", "农户", "渔夫", "女佣", "学徒", "裁缝", "铁匠", "流浪汉", "退伍兵", "邮差", "酒馆老板", "新来的"]
## 正常中文里的叠字，lint 不算错
const ALLOWED_DUPS := ["算是了了", "总算了了", "就此了了", "是是非非"]
## 写作禁用的通用句：出现即视为模板写得偷懒
const BANNED := ["某某", "某事", "做了一件事", "发生了一些事", "一些事情", "非常非常", "很多很多", "总而言之", "众所周知", "不得不说", "值得一提的是", "令人震惊的是"]

static var _compiled := false
static var _re_space: RegEx
static var _re_adv: RegEx
static var _re_measure_resp: RegEx
static var _re_measure_ppl: RegEx
static var _re_sentence: RegEx


static func _compile() -> void:
	if _compiled:
		return
	_compiled = true
	_re_space = RegEx.new()
	_re_space.compile("(?<=[\\x{4e00}-\\x{9fff}，。！？、；：「」『』（）])\\s+|\\s+(?=[\\x{4e00}-\\x{9fff}，。！？、；：「」『』（）])")
	_re_adv = RegEx.new()
	_re_adv.compile("(" + "|".join(ADVERBS) + ")的(?=[\\x{4e00}-\\x{9fff}])")
	_re_measure_resp = RegEx.new()
	_re_measure_resp.compile("一个(?=(" + "|".join(RESPECT) + "))")
	_re_measure_ppl = RegEx.new()
	_re_measure_ppl.compile("一个(?=(" + "|".join(PEOPLE) + "))")
	_re_sentence = RegEx.new()
	_re_sentence.compile("[^。！？]+[。！？]+」?|[^。！？]+$")


static func polish(text: String) -> String:
	_compile()
	var s := text.strip_edges()
	if s == "":
		return s
	s = _re_space.sub(s, "", true)
	# 半角标点 → 全角（只在中文语境下，数字之间的小数点不动）
	s = s.replace(",", "，").replace("?", "？").replace("!", "！").replace(";", "；")
	s = s.replace(":", "：")
	# 重复和冲突的标点
	for _i in 3:
		s = s.replace("，，", "，").replace("。。", "。").replace("，。", "。").replace("。，", "。")
		s = s.replace("、，", "，").replace("，、", "，").replace("！。", "！").replace("？。", "？")
		s = s.replace("：。", "。").replace("：，", "：")
	s = s.replace("。」。", "。」").replace("」。」", "」」")
	while s.begins_with("，") or s.begins_with("。"):
		s = s.substr(1)
	# 匿名时的「此人本人」
	s = s.replace("此人本人", "此人")
	# 一句里两个冒号（引号外）：前一个改成逗号
	s = _one_colon(s)
	# 职业名以「的」结尾（新来的）再接「的」
	s = s.replace("新来的的", "新来的人的")
	# 引号里的引号用『』
	s = _nest_quotes(s)
	# 的地得
	s = _re_adv.sub(s, "$1地", true)
	# 量词
	s = _re_measure_resp.sub(s, "一位", true)
	s = _re_measure_ppl.sub(s, "一名", true)
	# 句子层：去相邻重复；连续三句都极短（四个字以内）读起来像电报，把后两句并成一句。
	# 作者有意写的「写得好。就这一句。」只有两句，不动。
	var sentences := split_sentences(s)
	var out: Array = []
	for sen in sentences:
		if not out.is_empty() and out[-1] == sen:
			continue
		if out.size() >= 2 and _plain_len(out[-2]) <= 4 and _plain_len(out[-1]) <= 4 and _plain_len(sen) <= 4 and out[-1].ends_with("。"):
			out[-1] = out[-1].substr(0, out[-1].length() - 1) + "，" + sen
			continue
		out.append(sen)
	s = "".join(out)
	# 结尾补标点
	var last := s.substr(s.length() - 1)
	# 整句在括号里、括号里已有句号的不再补（试玩：「（对方是真不知道这件事。）。」）
	var boxed := last == "）" and s.length() >= 2 and s.substr(s.length() - 2, 1) in ["。", "！", "？"]
	if not (last in ["。", "！", "？", "」", "…", "—"]) and not boxed:
		s += "。"
	return s


static func _one_colon(s: String) -> String:
	var out := ""
	for sen_v in split_sentences(s):
		var sen: String = sen_v
		var depth := 0
		var colons: Array = []
		for i in sen.length():
			var c := sen.substr(i, 1)
			if c == "「" or c == "『":
				depth += 1
			elif c == "」" or c == "』":
				depth = maxi(0, depth - 1)
			elif c == "：" and depth == 0:
				colons.append(i)
		if colons.size() >= 2:
			var k: int = colons[0]
			sen = sen.substr(0, k) + "，" + sen.substr(k + 1)
		out += sen
	return out


static func _nest_quotes(s: String) -> String:
	var out := ""
	var depth := 0
	for i in s.length():
		var c := s.substr(i, 1)
		if c == "「" or c == "『":
			out += "「" if depth % 2 == 0 else "『"
			depth += 1
		elif c == "」" or c == "』":
			depth = maxi(0, depth - 1)
			out += "」" if depth % 2 == 0 else "』"
		else:
			out += c
	return out


static func split_sentences(s: String) -> Array:
	_compile()
	var out: Array = []
	for m in _re_sentence.search_all(s):
		var t := m.get_string().strip_edges()
		if t != "":
			out.append(t)
	return out


static func _plain_len(s: String) -> int:
	var n := 0
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x4e00 and c <= 0x9fff:
			n += 1
	return n


## 检查一段文字，返回问题列表（空表示通过）。
static func lint(text: String, names: Array = []) -> Array:
	_compile()
	var issues: Array = []
	if text.strip_edges() == "":
		issues.append("空文本")
		return issues
	for bad in ["{", "}", "#", "〔", "["]:
		if text.find(bad) >= 0:
			issues.append("未填槽位：" + bad)
	var scrubbed := text
	for ok in ALLOWED_DUPS:
		scrubbed = scrubbed.replace(ok, "")
	for dup in ["的的", "了了", "，，", "。。", "地地", "是是", "在在"]:
		if scrubbed.find(dup) >= 0:
			issues.append("重复字：" + dup)
	for b in BANNED:
		if text.find(b) >= 0:
			issues.append("通用句：" + b)
	var re_latin := RegEx.new()
	re_latin.compile("[A-Za-z]{2,}")
	if re_latin.search(text) != null:
		issues.append("中文里混了英文")
	for sen in split_sentences(text):
		if _plain_len(sen) > 70:
			issues.append("句子过长（%d 字）" % _plain_len(sen))
		for n in names:
			if n != "" and sen.count(n) >= 3:
				issues.append("一句里名字出现三次：" + n)
	return issues
