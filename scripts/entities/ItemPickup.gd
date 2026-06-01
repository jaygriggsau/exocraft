class_name ItemPickup
extends Node2D
## A dropped item that falls to the ground, then is magnetically pulled toward
## the player and collected on contact.

const GRAVITY := 420.0
const MAX_FALL := 300.0
const MAGNET_RANGE := 48.0
const MAGNET_SPEED := 220.0
const PICKUP_DIST := 9.0

var item_id := ""
var count := 1
var _vy := 0.0
var _delay := 0.35   ## brief grace so freshly-mined drops don't vanish instantly
var _bob := 0.0

func setup(id: String, n: int, pos: Vector2) -> void:
	item_id = id
	count = n
	global_position = pos

func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = Art.item_icon(item_id)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(0.6, 0.6)
	add_child(s)

func _physics_process(dt: float) -> void:
	_delay = maxf(0.0, _delay - dt)
	_bob += dt * 4.0
	var p = Game.player

	if _delay <= 0.0 and p and global_position.distance_to(p.global_position) <= MAGNET_RANGE:
		# pull toward player
		var to: Vector2 = (p.global_position - global_position).normalized()
		global_position += to * MAGNET_SPEED * dt
		if global_position.distance_to(p.global_position) <= PICKUP_DIST:
			_collect()
		return

	# otherwise fall under gravity until resting on a solid tile
	if Game.world == null:
		return
	if not Game.world.is_solid_at(global_position + Vector2(0, 5)):
		_vy = minf(_vy + GRAVITY * dt, MAX_FALL)
	else:
		_vy = 0.0
	global_position.y += _vy * dt
	position.y += sin(_bob) * 0.15

func _collect() -> void:
	if _delay > 0.0 or Game.inventory == null:
		return
	var leftover := Game.inventory.add(item_id, count)
	if leftover <= 0:
		queue_free()
	else:
		count = leftover
