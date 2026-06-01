class_name Crawler
extends CharacterBody2D
## Ground-bound alien bug. Walks toward the player, hops over obstacles, and
## deals contact damage. Collides only with the world (not the player or other
## crawlers) so it never shoves things around.

const SPEED := 56.0
const GRAVITY := 760.0
const MAX_FALL := 520.0
const JUMP := -250.0
const TOUCH_DAMAGE := 8.0
const TOUCH_RANGE := 14.0
const MAX_HP := 30.0

var hp := MAX_HP
var _sprite: Sprite2D
var _hit_cd := 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(16, 11)
	shape.shape = r
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = Art.sprite("crawler")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)

func _physics_process(dt: float) -> void:
	_hit_cd = maxf(0.0, _hit_cd - dt)
	var p = Game.player
	if p == null:
		return

	var dx: float = p.global_position.x - global_position.x
	var dirx := signf(dx)
	velocity.x = dirx * SPEED
	_sprite.flip_h = dirx < 0

	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * dt, MAX_FALL)
	elif is_on_wall() and absf(dx) > 4.0:
		velocity.y = JUMP

	move_and_slide()

	# contact damage
	if _hit_cd <= 0.0 and global_position.distance_to(p.global_position) <= TOUCH_RANGE:
		p.take_damage(TOUCH_DAMAGE)
		_hit_cd = 0.5

	# despawn if the player wanders very far away
	if global_position.distance_to(p.global_position) > 900.0:
		queue_free()

func take_damage(amount: float) -> void:
	hp -= amount
	modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.2)
	if hp <= 0.0:
		_die()

func _die() -> void:
	var drop := ItemPickup.new()
	drop.setup("scrap", 1 + (randi() % 2), global_position)
	Game.world.add_child(drop)
	queue_free()
