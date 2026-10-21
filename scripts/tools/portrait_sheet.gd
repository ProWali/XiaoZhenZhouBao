## 把一座镇子所有居民的头像和小人拼成一张图，自己审美术用。
## 用法：godot --headless -s res://scripts/tools/portrait_sheet.gd -- --seed 3 --out sheet.png
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")


func _init() -> void:
	var seed_v := 3
	var out := "user://portrait_sheet.png"
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed": seed_v = int(args[i + 1])
		if args[i] == "--out": out = args[i + 1]
	var world = World.new(seed_v, {})
	var ids: Array = world.living_ids()
	var cols := 12
	var rows := int(ceil(ids.size() / float(cols)))
	var sheet := Image.create(cols * 52, rows * 36, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("e6dcc3"))
	for i in ids.size():
		var x := (i % cols) * 52
		var y := (i / cols) * 36
		sheet.blit_rect(Portrait.face(world, ids[i]).get_image(), Rect2i(0, 0, 32, 32), Vector2i(x + 2, y + 2))
		sheet.blit_rect(Portrait.figure(world, ids[i]).get_image(), Rect2i(0, 0, 14, 30), Vector2i(x + 36, y + 3))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out)
	print("写到 ", out, "，", ids.size(), " 人")
	quit()
