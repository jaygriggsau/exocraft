class_name StoragePod
extends Node2D
## A deployed storage container. Holds items; nearby stations draw ingredients
## from it when crafting, and the player can open it to deposit / withdraw.

const SIZE := 24

var slots: Array = []   # each entry null or {id, count}

func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = null

func _ready() -> void:
	var tex := Art.sprite("storage_pod")
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = false
	s.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	s.z_index = 1
	add_child(s)
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
