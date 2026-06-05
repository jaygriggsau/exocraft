class_name Creature
extends CharacterBody2D
## Generic alien animal / faction unit. Behaviours:
##   PASSIVE     - wanders aimlessly, never attacks, flees when hurt
##   TERRITORIAL - wanders until the player enters detect_range, then attacks
##                 (contact, or ranged); calms down out of range. Corp robots and
##                 drones use this with a home anchor so they patrol/defend a base.
##   NEUTRAL     - the cave Kin: roams and mines, never attacks first. Befriends
##                 you over time while peaceful; turns hostile for a while if hit.
## Configure the public fields before add_child(); _ready() applies them.
## Ground creatures collide with the world; flying ones phase through it.

enum { PASSIVE, TERRITORIAL, NEUTRAL }

const GRAVITY := 760.0
const MAX_FALL := 520.0
const JUMP := -250.0

# --- config (set on spawn) ---
var species := "creature"
var sprite_name := "grazer"
var behavior := PASSIVE
var flying := false
var max_hp := 20.0
var move_speed := 45.0
var body_size := Vector2(16, 12)
var detect_range := 150.0
var touch_damage := 8.0
var touch_range := 14.0
var ranged := false
var shoot_range := 170.0
var shoot_cooldown := 1.6
var projectile_damage := 8.0
var projectile_speed := 150.0
var drops: Array = []          # [[item_id, count, chance], ...]
var tint := Color.WHITE
# --- faction extras (Corp patrol / Kin reputation + mining) ---
var faction := ""              # "corp", "kin", or "" (wild fauna)
var has_home := false          # anchor patrols to home (Corp around their base)
var home := Vector2.ZERO
var patrol_radius := 120.0     # how far from home a unit roams / leashes its chase
var can_mine := false          # the Kin slowly dig the rock around them
var rep_gain := 0.0            # alien rep/sec earned while peaceful & near you

# --- runtime ---
var hp := 0.0
var aggro_t := 0.0             # NEUTRAL: seconds of provoked hostility left
var _mine_cd := 0.0
var _sprite: AnimatedSprite2D
var _anim := ""
var _state := 0                # 0 wander, 1 chase, 2 flee
var _wander := 0.0             # ground: direction; flying: heading angle
var _wander_t := 0.0
var _flee_t := 0.0
var _hit_cd := 0.0
var _shoot_t := 0.0
var _bob := 0.0

func _ready() -> void:
	add_to_group("creatures")
	if behavior == TERRITORIAL:
		add_to_group("hostile")
	if faction != "":
		add_to_group(faction)
	hp = max_hp
	collision_layer = 4
	collision_mask = 0 if flying else 1
	if flying:
		motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = body_size
	shape.shape = r
	add_child(shape)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = Art.creature_frames(sprite_name)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.modulate = tint
	_sprite.play("move")
	_anim = "move"
	add_child(_sprite)
	if flying:
		var l := PointLight2D.new()
		l.texture = Art.light_texture()
		l.color = Color("ff5a5a") if behavior == TERRITORIAL else Color("8fe0ff")
		l.energy = 0.5
		l.scale = Vector2(0.3, 0.3)
		add_child(l)
	_wander = randf() * TAU if flying else (1.0 if randf() < 0.5 else -1.0)
	_wander_t = randf_range(0.6, 1.8)

func _physics_process(dt: float) -> void:
	_hit_cd = maxf(0.0, _hit_cd - dt)
	_shoot_t = maxf(0.0, _shoot_t - dt)
	_flee_t = maxf(0.0, _flee_t - dt)
	aggro_t = maxf(0.0, aggro_t - dt)
	_mine_cd = maxf(0.0, _mine_cd - dt)
	_bob += dt
	var p = Game.player
	if p == null:
		return
	var to_player: Vector2 = p.global_position - global_position
	var dist := to_player.length()

	if _flee_t > 0.0:
		_state = 2
	elif _is_hostile(dist):
		_state = 1
	else:
		_state = 0

	# the cave Kin earn your trust by peaceful proximity
	if behavior == NEUTRAL and _state != 1 and rep_gain > 0.0 and dist < 200.0:
		Game.add_alien_rep(rep_gain * dt)

	if flying:
		_move_fly(dt, to_player)
	else:
		_move_walk(dt, to_player)
		if can_mine and _state == 0 and _mine_cd <= 0.0 and is_on_floor():
			_try_mine_rock()
	_update_anim()

	# attacks (while engaged)
	if _state == 1:
		if ranged:
			if dist <= shoot_range and _shoot_t <= 0.0:
				_shoot(to_player.normalized())
				_shoot_t = shoot_cooldown
		elif _hit_cd <= 0.0 and dist <= touch_range:
			p.take_damage(touch_damage)
			_hit_cd = 0.6

	if dist > 1400.0:
		queue_free()

## Should this unit be actively chasing/attacking the player right now?
func _is_hostile(dist: float) -> bool:
	match behavior:
		TERRITORIAL:
			if dist > detect_range:
				return false
			# Corp patrol & defend: only give chase while the fight stays near
			# base; chase too far and the unit breaks off to return home.
			if has_home and global_position.distance_to(home) > patrol_radius * 2.2:
				return false
			return true
		NEUTRAL:
			# never strikes first — only while provoked, and not once truly allied
			return aggro_t > 0.0 and not Game.aliens_friendly()
		_:
			return false

func _try_mine_rock() -> void:
	var w = Game.world
	if w == null:
		return
	var t: Vector2i = w.world_to_tile(global_position)
	var fx := -1 if _sprite.flip_h else 1
	var ptile: Vector2i = w.world_to_tile(Game.player.global_position)
	for cand in [Vector2i(t.x + fx, t.y), Vector2i(t.x + fx, t.y + 1), Vector2i(t.x, t.y + 1)]:
		if cand == ptile:
			continue
		if _diggable(w.get_tile(cand)):
			w.set_tile(cand, Tiles.AIR)
			_mine_cd = randf_range(1.8, 3.6)
			return

func _diggable(id: int) -> bool:
	# the Kin only chew plain rock/soil — never ore veins or built blocks
	return id == Tiles.STONE or id == Tiles.DARKROCK or id == Tiles.DIRT

func _move_walk(dt: float, to_player: Vector2) -> void:
	var dir := 0.0
	match _state:
		1: dir = signf(to_player.x)
		2: dir = -signf(to_player.x)
		_:
			_wander_t -= dt
			if _wander_t <= 0.0:
				_wander_t = randf_range(0.8, 2.4)
				_wander = [-1.0, 0.0, 0.0, 1.0][randi() % 4]
			dir = _wander
			# patrollers drift back toward their base when they stray too far
			if has_home and global_position.distance_to(home) > patrol_radius:
				dir = signf(home.x - global_position.x)
	# curious Kin sidle up to you (and hang around once close) so trust can grow
	if behavior == NEUTRAL and _state == 0:
		var pd := to_player.length()
		if pd <= 28.0:
			dir = 0.0
		elif pd < detect_range:
			dir = signf(to_player.x)
	var spd := move_speed * (1.5 if _state == 2 else 1.0)
	velocity.x = dir * spd
	if dir != 0.0:
		_sprite.flip_h = dir < 0
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * dt, MAX_FALL)
	elif is_on_wall() and dir != 0.0:
		velocity.y = JUMP
	move_and_slide()

func _move_fly(dt: float, to_player: Vector2) -> void:
	var target := Vector2.ZERO
	match _state:
		1: target = to_player.normalized() * move_speed
		2: target = -to_player.normalized() * move_speed * 1.4
		_:
			_wander_t -= dt
			if _wander_t <= 0.0:
				_wander_t = randf_range(1.0, 2.6)
				_wander = randf() * TAU
			target = Vector2(cos(_wander), sin(_wander)) * move_speed * 0.6
			# drone patrols circle back to base when they wander off
			if has_home and global_position.distance_to(home) > patrol_radius:
				target = (home - global_position).normalized() * move_speed
	velocity = velocity.lerp(target, 0.05)
	velocity.y += sin(_bob * 3.0) * 5.0
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0
	move_and_slide()

func _update_anim() -> void:
	# fliers always hover; walkers idle when standing still
	var want := "move" if (flying or absf(velocity.x) > 6.0) else "idle"
	if want != _anim:
		_anim = want
		_sprite.play(want)

func _shoot(dir: Vector2) -> void:
	var b := Projectile.new()
	b.setup(global_position + dir * 10.0, dir, projectile_damage, projectile_speed, false)
	Game.world.add_child(b)

func take_damage(amount: float) -> void:
	hp -= amount
	modulate = Color(1, 0.4, 0.4)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.2)
	if behavior == PASSIVE:
		_flee_t = 4.0          # bolt away when hurt
	elif behavior == NEUTRAL:
		# the Kin remember a betrayal: they fight back and lose trust in you
		aggro_t = 9.0
		Game.add_alien_rep(-25.0)
	if hp <= 0.0:
		_die()

func _die() -> void:
	for d in drops:
		if randf() <= d[2]:
			var pk := ItemPickup.new()
			pk.setup(d[0], d[1], global_position)
			Game.world.add_child(pk)
	queue_free()
