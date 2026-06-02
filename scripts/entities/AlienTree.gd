class_name AlienTree
extends Node2D
## A harvestable alien tree. It is purely decorative collision-wise (the player
## walks through it); harvesting is driven by the particle gun via World, which
## tracks which tiles the tree occupies. Sways gently and shakes while harvested.

var biome := 0
var column := 0          # world tile-x, used to remember it was harvested
var occupied: Array = [] # tiles the gun can target to harvest it
var drops: Array = []    # [[item_id, count], ...]
var harvest_time := 6.0

var _sprite: Sprite2D
var _phase := 0.0
var _t := 0.0
var _harvest := 0.0

func setup(biome_id: int, base_world: Vector2, col: int) -> void:
	biome = biome_id
	column = col
	global_position = base_world
	_phase = randf() * TAU

func _ready() -> void:
	var tex := Art.tree_texture(biome)
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.centered = false
	_sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	add_child(_sprite)
	# glowing canopy light for luminous biomes
	if biome == World.WASTES or biome == World.JUNGLE:
		var l := PointLight2D.new()
		l.texture = Art.light_texture()
		l.color = Color("ff4df0") if biome == World.WASTES else Color("7aff3a")
		l.energy = 0.7
		l.scale = Vector2(0.5, 0.5)
		l.position = Vector2(0, -tex.get_height() + 24)
		add_child(l)

func _process(dt: float) -> void:
	_t += dt
	_harvest = maxf(0.0, _harvest - dt * 2.0)
	var sway := sin(_t * 0.9 + _phase) * 0.025
	var shake := sin(_t * 60.0) * 0.06 * _harvest
	_sprite.rotation = sway + shake

func set_harvest(frac: float) -> void:
	_harvest = clampf(frac, 0.0, 1.0)
	_sprite.modulate = Color(1, 1, 1).lerp(Color(1.5, 1.5, 1.5), _harvest)
