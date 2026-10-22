extends Node
## 游戏入口。带 --walkthrough 参数启动时交给自动走查脚本（截图审界面用）；
## 带 --check-scripts 时只编译一遍画面层脚本就退出（运行时才加载的脚本，语法错误别处暴露不出来）。否则进主菜单。


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--check-scripts" in args:
		_check_scripts()
		return
	if "--walkthrough" in args:
		Game.save_path = "user://saves/walkthrough.json"
		Game.log_enabled = false
	Game.boot()
	if "--walkthrough" in args:
		var w: Node = load("res://scripts/debug/walkthrough.gd").new()
		add_child(w)


func _check_scripts() -> void:
	var bad := 0
	var n := 0
	for dir in ["res://scripts/ui", "res://scripts/ui/screens", "res://scripts/debug"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			n += 1
			var sc = ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_IGNORE)
			if sc == null or not (sc is GDScript) or not sc.can_instantiate():
				print("编译不过：" + dir + "/" + f)
				bad += 1
	print("画面层脚本 %d 个，编译不过 %d 个" % [n, bad])
	get_tree().quit(1 if bad > 0 else 0)
