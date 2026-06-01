class_name Player
extends CharacterBody2D
## The player: platforming movement plus mine / build / shoot interactions that
## all key off the currently selected hotbar item.

const SPEED := 120.0
const ACCEL := 1400.0
const FRICTION := 1600.0
const JUMP_VELOCITY := -270.0
const GRAVITY := 760.0
const MAX_FALL := 520.0
const REACH := 5.5                 # tiles
const MINE_BASE := 0.12            # seconds per mine, scaled by tile hardness
const PLACE_COOLDOWN := 0.12
const INVULN := 0.6

var inv: Inventory
var sprite: Sprite2D
var facing := 1
var _mine_target := Vector2i(2147483647, 0)
var _mine_progress := 0.0
var _place_cd := 0.0
var _fire_cd := 0.0
var _invuln := 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2          # player on its own layer...
	collision_mask = 1           # ...colliding only with the world tiles
	inv = Inventory.new()
	_starting_kit()
	Game.inventory = inv
	Game.player = self

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 20)
	shape.shape = rect
	add_child(shape)

	sprite = Sprite2D.new()
	sprite.texture = Art.sprite("player")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)

	var cam := Camera2D.new()
	cam.zoom = Vector2(3, 3)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()

	# shadow-casting headlamp so caves and night are explorable
	var lamp := PointLight2D.new()
	lamp.texture = Art.light_texture()
	lamp.color = Color(1.0, 0.96, 0.86)
	lamp.energy = 1.05
	lamp.scale = Vector2(1.25, 1.25)
	lamp.shadow_enabled = true
	lamp.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	lamp.position = Vector2(0, -6)
	add_child(lamp)
	# soft personal glow that ignores walls, so the player is always visible
	var aura := PointLight2D.new()
	aura.texture = Art.light_texture()
	aura.color = Color(0.6, 0.8, 1.0)
	aura.energy = 0.5
	aura.scale = Vector2(0.45, 0.45)
	add_child(aura)

	Game.player_died.connect(_on_died)

func _starting_kit() -> void:
	inv.add("pickaxe", 1)
	inv.add("blaster", 1)
	inv.add("plating", 30)
	inv.add("neon_glass", 10)
	inv.add("med_cell", 3)
	inv.select(0)

# ---------------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	_place_cd = maxf(0.0, _place_cd - dt)
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_invuln = maxf(0.0, _invuln - dt)

	# horizontal movement
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * SPEED, ACCEL * dt)
		facing = signi(int(dir))
		sprite.flip_h = facing < 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * dt)

	# gravity + jump
	if not is_on_floor():
		velocity.y = minf(velocity.y + GRAVITY * dt, MAX_FALL)
	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	move_and_slide()

	if not Game.ui_blocking:
		_handle_interaction(dt)
	queue_redraw()

func _handle_interaction(dt: float) -> void:
	# Right mouse always mines (handy even with a weapon selected).
	var primary := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mining := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	var sel := inv.selected_id()
	var t := ItemDB.type_of(sel) if sel != "" else -1

	if primary:
		match t:
			ItemDB.TOOL: mining = true
			ItemDB.BLOCK: _try_place(sel)
			ItemDB.WEAPON: _try_fire(sel)
			ItemDB.CONSUMABLE: _try_consume(sel)

	if mining:
		_try_mine(dt)
	else:
		_mine_target = Vector2i(2147483647, 0)
		_mine_progress = 0.0

func _target_tile() -> Vector2i:
	return Game.world.world_to_tile(get_global_mouse_position())

func _in_reach(t: Vector2i) -> bool:
	var c: Vector2 = Game.world.tile_to_world_center(t)
	return global_position.distance_to(c) <= REACH * World.TILE

func _try_mine(dt: float) -> void:
	var t := _target_tile()
	if not _in_reach(t):
		return
	var id: int = Game.world.get_tile(t)
	if not Tiles.is_solid(id):
		return
	# only mine blocks exposed to open space, so you can't dig more than one
	# block deep into solid terrain at a time
	if not _is_exposed(t):
		return
	if t != _mine_target:
		_mine_target = t
		_mine_progress = 0.0
	_mine_progress += dt
	if _mine_progress >= MINE_BASE * Tiles.hardness(id):
		_mine_progress = 0.0
		Game.world.set_tile(t, Tiles.AIR)
		_spawn_drop(t, Tiles.drop_item(id))

func _spawn_drop(t: Vector2i, item_id: String) -> void:
	if item_id == "":
		return
	var p := ItemPickup.new()
	p.setup(item_id, 1, Game.world.tile_to_world_center(t))
	Game.world.add_child(p)

func _try_place(item_id: String) -> void:
	if _place_cd > 0.0:
		return
	var t := _target_tile()
	if not _in_reach(t):
		return
	if Tiles.is_solid(Game.world.get_tile(t)):
		return
	# don't entomb ourselves
	var tile_rect := Rect2(t.x * World.TILE, t.y * World.TILE, World.TILE, World.TILE)
	var body := Rect2(global_position - Vector2(6, 11), Vector2(12, 22))
	if tile_rect.intersects(body):
		return
	# require an adjacent solid tile for support
	if not _has_support(t):
		return
	var tile := ItemDB.place_tile(item_id)
	if tile == Tiles.AIR:
		return
	Game.world.set_tile(t, tile)
	inv.consume_selected(1)
	_place_cd = PLACE_COOLDOWN

func _has_support(t: Vector2i) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Tiles.is_solid(Game.world.get_tile(t + o)):
			return true
	return false

func _is_exposed(t: Vector2i) -> bool:
	# true if any orthogonal neighbour is open (air), i.e. the block has a face
	# the drill can actually reach
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not Tiles.is_solid(Game.world.get_tile(t + o)):
			return true
	return false

func _try_fire(item_id: String) -> void:
	if _fire_cd > 0.0:
		return
	var d = ItemDB.get_item(item_id)
	var dir := (get_global_mouse_position() - global_position)
	if dir.length() < 1.0:
		dir = Vector2(facing, 0)
	dir = dir.normalized()
	var p := Projectile.new()
	p.setup(global_position + dir * 10.0, dir, d.damage, d.speed, true)
	Game.world.add_child(p)
	_fire_cd = d.cooldown

func _try_consume(item_id: String) -> void:
	if _place_cd > 0.0:
		return
	var d = ItemDB.get_item(item_id)
	if Game.health >= Game.max_health:
		return
	Game.heal_player(d.heal)
	inv.consume_selected(1)
	_place_cd = 0.4

# ---------------------------------------------------------------------------
func take_damage(amount: float) -> void:
	if _invuln > 0.0:
		return
	_invuln = INVULN
	Game.damage_player(amount)
	# knockback flash
	modulate = Color(1, 0.5, 0.5)
	create_tween().tween_property(self, "modulate", Color.WHITE, INVULN)

func _on_died() -> void:
	Game.reset_health()
	global_position = Vector2(0, (Game.world.surface_tile_y(0) - 4) * World.TILE)
	velocity = Vector2.ZERO

func _draw() -> void:
	# Highlight the tile under the cursor when it is within reach.
	var t := _target_tile()
	if not _in_reach(t):
		return
	var top_left := Vector2(t.x * World.TILE, t.y * World.TILE) - global_position
	var col := Color(0.18, 1.0, 0.85, 0.5)
	if Tiles.is_solid(Game.world.get_tile(t)) and not _is_exposed(t):
		col = Color(0.5, 0.5, 0.55, 0.3)   # buried: too deep to mine
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		col = Color(1.0, 0.2, 0.6, 0.6)
	draw_rect(Rect2(top_left, Vector2(World.TILE, World.TILE)), col, false, 1.0)
