class_name Station
extends Node2D
## A deployed crafting station (workbench / fabricator / synthesizer). Standing
## within range of one unlocks its recipes. Can be dismantled with the gun to
## recover the item.

var station_id := "workbench"
var _sprite: Sprite2D
var _w := 0.0
var _h := 0.0

func _ready() -> void:
	var tex := Art.sprite(station_id)
	_w = tex.get_width()
	_h = tex.get_height()
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.offset = Vector2(-_w / 2.0, -_h)
	_sprite.z_index = 1
	add_child(_sprite)
	DeployFX.play(self, _sprite)
	if station_id != "workbench":
		var l := PointLight2D.new()
		l.texture = Art.light_texture()
		l.color = Color("2dffff") if station_id == "fabricator" else Color("b06aff")
		l.energy = 0.7
		l.scale = Vector2(0.55, 0.55)
		l.position = Vector2(0, -_h / 2.0)
		add_child(l)
	if Game.world:
		Game.world.register_station(self)

func _exit_tree() -> void:
	if Game.world:
		Game.world.unregister_station(self)

func contains_point(p: Vector2) -> bool:
	var dx := p.x - global_position.x
	var dy := p.y - global_position.y           # base at bottom; sprite extends up
	return absf(dx) <= _w / 2.0 + 2.0 and dy <= 4.0 and dy >= -_h - 4.0

func set_dismantle(frac: float) -> void:
	_sprite.modulate = Color(1, 1, 1).lerp(Color(1.8, 1.9, 2.2), frac)
	_sprite.position.x = sin(Time.get_ticks_msec() * 0.05) * 1.5 * frac

func collapse_and_free() -> void:
	DeployFX.dismantle(self, _sprite)
