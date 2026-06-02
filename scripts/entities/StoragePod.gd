class_name StoragePod
extends Node2D
## A deployed storage container. Holds items; nearby stations draw ingredients
## from it when crafting, and the player can open it to deposit / withdraw.

const SIZE := 24

var slots: Array = []   # each entry null or {id, count}
var _sprite: Sprite2D
var _w := 0.0
var _h := 0.0

func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = null

func _ready() -> void:
	var tex := Art.sprite("storage_pod")
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
	var l := PointLight2D.new()
	l.texture = Art.light_texture()
	l.color = Color("6fd0e0")
	l.energy = 0.4
	l.scale = Vector2(0.35, 0.35)
	l.position = Vector2(0, -tex.get_height() / 2.0)
	add_child(l)
	if Game.world:
		Game.world.register_pod(self)

func _exit_tree() -> void:
	if Game.world:
		Game.world.unregister_pod(self)

func contains_point(p: Vector2) -> bool:
	var dx := p.x - global_position.x
	var dy := p.y - global_position.y
	return absf(dx) <= _w / 2.0 + 2.0 and dy <= 4.0 and dy >= -_h - 4.0

func set_dismantle(frac: float) -> void:
	_sprite.modulate = Color(1, 1, 1).lerp(Color(1.8, 1.9, 2.2), frac)
	_sprite.position.x = sin(Time.get_ticks_msec() * 0.05) * 1.5 * frac

func collapse_and_free() -> void:
	DeployFX.dismantle(self, _sprite)

func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == id:
			n += s.count
	return n

## Add up to count; returns leftover that didn't fit.
func add(id: String, count: int) -> int:
	var ms := ItemDB.max_stack(id)
	for i in SIZE:
		if count <= 0:
			break
		var s = slots[i]
		if s != null and s.id == id and s.count < ms:
			var moved: int = min(ms - s.count, count)
			s.count += moved
			count -= moved
	for i in SIZE:
		if count <= 0:
			break
		if slots[i] == null:
			var moved: int = min(ms, count)
			slots[i] = {"id": id, "count": moved}
			count -= moved
	return count

## Remove up to count; returns true if the full amount was removed.
func remove(id: String, count: int) -> bool:
	if self.count(id) < count:
		return false
	for i in SIZE:
		if count <= 0:
			break
		var s = slots[i]
		if s != null and s.id == id:
			var taken: int = min(s.count, count)
			s.count -= taken
			count -= taken
			if s.count <= 0:
				slots[i] = null
	return true
