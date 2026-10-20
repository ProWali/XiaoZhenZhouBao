## 带种子的随机数封装。模拟层所有随机都从这里走，同一个种子永远跑出同一座镇。
## 不要在模拟层直接用 randi()/randf()，那会破坏确定性。
extends RefCounted

var _rng := RandomNumberGenerator.new()
var seed_value: int = 0


func _init(seed_in: int) -> void:
	seed_value = seed_in
	_rng.seed = seed_in


func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)


func randf() -> float:
	return _rng.randf()


func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)


func chance(p: float) -> bool:
	return _rng.randf() < p


## 从非空数组里随机取一个。
func pick(arr: Array) -> Variant:
	assert(arr.size() > 0, "pick 不能作用于空数组")
	return arr[_rng.randi_range(0, arr.size() - 1)]


## 按权重取下标。weights 全为 0 时退化为均匀。
func weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, float(w))
	if total <= 0.0:
		return _rng.randi_range(0, weights.size() - 1)
	var r := _rng.randf() * total
	for i in weights.size():
		r -= maxf(0.0, float(weights[i]))
		if r <= 0.0:
			return i
	return weights.size() - 1


## 原地洗牌（Fisher-Yates），不用 Array.shuffle()，那个走全局随机。
func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## 取 n 个不重复元素。
func sample(arr: Array, n: int) -> Array:
	var copy := arr.duplicate()
	shuffle(copy)
	return copy.slice(0, mini(n, copy.size()))
