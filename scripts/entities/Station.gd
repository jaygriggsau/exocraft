class_name Station
extends Node2D
## A deployed crafting station (workbench / fabricator / synthesizer). Standing
## within range of one unlocks its recipes. Registers with the World so recipes
## can check proximity.

var station_id := "workbench"

func _ready() -> void:
	var tex := Art.sprite(station_id)
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	s.z_index = 1
	add_child(s)
	DeployFX.play(self, s)
	if station_id != "workbench":
		var l := PointLight2D.new()
		l.texture = Art.light_texture()
		l.color = Color("2dffff") if station_id == "fabricator" else Color("b06aff")
		l.energy = 0.7
		l.scale = Vector2(0.55, 0.55)
		l.position = Vector2(0, -tex.get_height() / 2.0)
		add_child(l)
	if Game.world:
		Game.world.register_station(self)

func _exit_tree() -> void:
	if Game.world:
		Game.world.unregister_station(self)
