class_name Projectile
extends Node2D
## A simple energy bolt. Moves in a straight line, dies on solid tiles or after
## its lifetime, and damages the first valid target it passes near. Uses cheap
## distance checks against groups instead of physics areas.

const RADIUS := 7.0
const LIFETIME := 1.6

var _dir := Vector2.RIGHT
var _speed := 360.0
var _damage := 10.0
var _from_player := true
var _life := LIFETIME
var _style := "bolt"           # "bolt" = energy bolt, "bullet" = ballistic tracer

func setup(pos: Vector2, dir: Vector2, damage: float, speed: float, from_player: bool, style := "bolt") -> void:
	global_position = pos
	_dir = dir.normalized()
	_damage = damage
	_speed = speed
	_from_player = from_player
	_style = style
	rotation = _dir.angle()

func _ready() -> void:
	# enemy bolts join a group so a melee weapon can deflect them
	add_to_group("enemy_projectiles" if not _from_player else "player_projectiles")
	var s := Sprite2D.new()
	s.texture = Art.sprite(_style)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)
	var l := PointLight2D.new()
	l.texture = Art.light_texture()
	if _style == "bullet":
		l.color = Color("ffd86a")
		l.scale = Vector2(0.18, 0.18)
	else:
		l.color = Color("ff2bd6") if _from_player else Color("ff5a5a")
		l.scale = Vector2(0.3, 0.3)
	l.energy = 1.1
	add_child(l)

func _physics_process(dt: float) -> void:
	global_position += _dir * _speed * dt
	_life -= dt
	if _life <= 0.0 or (Game.world and Game.world.is_solid_at(global_position)):
		queue_free()
		return
	if _from_player:
		_hit_group("creatures")
	else:
		_hit_player()

func _hit_group(group: String) -> void:
	for e in get_tree().get_nodes_in_group(group):
		if is_instance_valid(e) and global_position.distance_to(e.global_position) <= RADIUS + 8.0:
			if e.has_method("take_damage"):
				e.take_damage(_damage)
			queue_free()
			return

func _hit_player() -> void:
	var p = Game.player
	if p and global_position.distance_to(p.global_position) <= RADIUS + 8.0:
		p.take_damage(_damage)
		queue_free()
