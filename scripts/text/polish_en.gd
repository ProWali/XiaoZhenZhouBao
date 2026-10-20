## English polish layer: deterministic clean-up rules for assembled template text.
extends RefCounted

const SMALL_WORDS := ["a", "an", "the", "and", "but", "or", "nor", "for", "of", "on", "in", "at", "to", "by", "as", "with", "from", "into", "over"]
const BANNED := ["something happened", "some things", "very very", "needless to say", "it goes without saying", "shocking news", "at the end of the day", "in conclusion"]

static var _compiled := false
static var _re_a: RegEx
static var _re_space_punct: RegEx
static var _re_multi_space: RegEx
static var _re_sentence_start: RegEx
static var _re_sentence: RegEx
static var _re_an_exc: RegEx
static var _re_a_exc: RegEx


static func _compile() -> void:
	if _compiled:
		return
	_compiled = true
	_re_a = RegEx.new()
	_re_a.compile("\\b([Aa]) (?=[AEIOUaeiou])")
	_re_space_punct = RegEx.new()
	_re_space_punct.compile("\\s+([,.;:!?])")
	_re_multi_space = RegEx.new()
	_re_multi_space.compile("[ \\t]{2,}")
	_re_sentence_start = RegEx.new()
	_re_sentence_start.compile("([.!?][\"”’]?\\s+)([a-z])")
	_re_sentence = RegEx.new()
	_re_sentence.compile("[^.!?]+[.!?]+[\"”]?|[^.!?]+$")
	# 元音开头却读辅音的词用 a；h 不发音的词用 an
	_re_an_exc = RegEx.new()
	_re_an_exc.compile("\\b([Aa])n (one|once|union|unique|usual|useful|uniform|universal|European|eulogy)\\b")
	_re_a_exc = RegEx.new()
	_re_a_exc.compile("\\b([Aa]) (hour|honest|heir|honour|honor)\\b")


static func polish(text: String) -> String:
	_compile()
	var s := text.strip_edges()
	if s == "":
		return s
	# Words like "hour", "honest", "one", "uniform" break the simple vowel rule.
	s = _re_a.sub(s, "$1n ", true)
	s = _re_an_exc.sub(s, "$1 $2", true)
	s = _re_a_exc.sub(s, "$1n $2", true)
	s = _re_space_punct.sub(s, "$1", true)
	s = _re_multi_space.sub(s, " ", true)
	for _i in 3:
		s = s.replace(",,", ",").replace("..", ".").replace(",.", ".").replace(".,", ".").replace("!.", "!").replace("?.", "?")
	while s.begins_with(",") or s.begins_with("."):
		s = s.substr(1).strip_edges()
	s = s.substr(0, 1).to_upper() + s.substr(1)
	s = _capitalize_starts(s)
	var sentences := split_sentences(s)
	var out: Array = []
	for sen in sentences:
		if not out.is_empty() and out[-1] == sen:
			continue
		out.append(sen)
	s = " ".join(out)
	var last := s.substr(s.length() - 1)
	if not (last in [".", "!", "?", "\"", "”", "…"]):
		s += "."
	return s


static func _capitalize_starts(s: String) -> String:
	var out := ""
	var pos := 0
	for m in _re_sentence_start.search_all(s):
		out += s.substr(pos, m.get_start(2) - pos) + m.get_string(2).to_upper()
		pos = m.get_end(2)
	out += s.substr(pos)
	return out


static func split_sentences(s: String) -> Array:
	_compile()
	var out: Array = []
	for m in _re_sentence.search_all(s):
		var t := m.get_string().strip_edges()
		if t != "":
			out.append(t)
	return out


## Headline style: capitalise every word except short function words (not the first).
static func title_case(s: String) -> String:
	var words := s.strip_edges().split(" ", false)
	var out: Array = []
	for i in words.size():
		var w: String = words[i]
		var bare := w.to_lower().rstrip(",.;:!?")
		var after_break: bool = i > 0 and str(words[i - 1]).right(1) in ["!", "?", ":", "."]
		if i > 0 and i < words.size() - 1 and not after_break and bare in SMALL_WORDS:
			out.append(w.to_lower() if w == w.to_lower() or w.capitalize() == w else w)
		else:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	var t := " ".join(out)
	if t.ends_with("."):
		t = t.substr(0, t.length() - 1)
	return t


static func lint(text: String, names: Array = []) -> Array:
	_compile()
	var issues: Array = []
	if text.strip_edges() == "":
		issues.append("empty text")
		return issues
	for bad in ["{", "}", "#", "〔", "["]:
		if text.find(bad) >= 0:
			issues.append("unfilled slot: " + bad)
	var re_cjk := RegEx.new()
	re_cjk.compile("[\\x{4e00}-\\x{9fff}]")
	if re_cjk.search(text) != null:
		issues.append("Chinese characters in English text")
	var re_dup := RegEx.new()
	re_dup.compile("\\b(\\w+) \\1\\b")
	var m := re_dup.search(text.to_lower())
	if m != null and m.get_string(1) not in ["that", "had"]:
		issues.append("doubled word: " + m.get_string(1))
	for b in BANNED:
		if text.to_lower().find(b) >= 0:
			issues.append("generic phrase: " + b)
	for sen in split_sentences(text):
		var wc: int = sen.split(" ", false).size()
		if wc > 45:
			issues.append("sentence too long (%d words)" % wc)
		var first: String = sen.substr(0, 1)
		if first != first.to_upper() and not first.is_valid_int():
			issues.append("lowercase sentence start")
		for n in names:
			if n != "" and sen.count(n) >= 3:
				issues.append("name three times in one sentence: " + n)
	return issues
