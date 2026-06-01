class_name Drone
extends Node2D
## Flying sentry drone. Drifts toward the player through the air (phases through
## terrain like a hovering machine) and deals contact damage. Tougher to reach
## than crawlers but easy to shoot.

const SPEED := 70.0
const TOUCH_DAMAGE := 10.0
const TOUCH_RANGE := 13.0
const MAX_HP := 22.0

var hp := MAX_HP
var _vel := Vector2.ZERO
var _hit_cd := 0.0
var _bob := 0.0

func setup(pos: Vector2) -> void:
	global_position = pos

func _ready() -> void:
	add_to_group("enemies")
	var s := Sprite2D.new()
	s.texture = Art.sprite("drone")
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)
	var l := PointLight2D.new()
	l.texture = Art.light_texture()
	l.color = Color("ff5a5a")
	l.energy = 0.7
	l.scale = Vector2(0.28, 0.28)
	add_child(l)

func _physics_process(dt: float) -> void:
	_hit_cd = maxf(0.0, _hit_cd - dt)
	_bob += dt * 3.0
	var p = Game.player
	if p == null:
		return

	var to: Vector2 = (p.global_position - global_position)
	_vel = _vel.lerp(to.normalized() * SPEED, 0.05)
	global_position += _vel * dt
	position.y += sin(_bob) * 0.2

	if _hit_cd <= 0.0 and global_position.distance_to(p.global_position) <= TOUCH_RANGE:
		p.take_damage(TOUCH_DAMAGE)
		_hit_cd = 0.6

	if global_position.distance_to(p.global_position) > 1100.0:
		queue_free()

func take_damage(amount: float) -> void:
	hp -= amount
	modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.2)
	if hp <= 0.0:
		_die()

func _die() -> void:
	var drop := ItemPickup.new()
	drop.setup("energy_core" if randf() < 0.4 else "scrap", 1, global_position)
	Game.world.add_child(drop)
	queue_free()
