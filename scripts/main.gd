extends Node
## 游戏入口。带 --walkthrough 参数启动时交给自动走查脚本（截图审界面用），否则进主菜单。


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	Game.boot()
	if "--walkthrough" in args:
		var w: Node = load("res://scripts/debug/walkthrough.gd").new()
		add_child(w)
