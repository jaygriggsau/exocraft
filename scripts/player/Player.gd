class_name Player
extends CharacterBody2D
## The player: platforming movement plus mine / build / shoot interactions that
## all key off the currently selected hotbar item.

const SPEED := 120.0
const SPRINT_MULT := 1.7
const REGEN_DELAY := 4.0            # seconds out of combat before health regens
const REGEN_RATE := 7.0            # health per second
const ACCEL := 1400.0
const FRICTION := 1600.0
const JUMP_VELOCITY := -270.0
const GRAVITY := 760.0
const MAX_FALL := 520.0
const REACH := 5.5                 # tiles
const MINE_BASE := 0.12            # seconds per mine, scaled by tile hardness
const PLACE_COOLDOWN := 0.12
const INVULN := 0.6
const FIRE_KICK := 3.5             # blaster recoil impulse (px)
const MINE_RECOIL := 1.3           # steady kickback while mining (px)
const RECOIL_RECOVER := 36.0       # px/s the sprite eases back

var inv: Inventory
var sprite: AnimatedSprite2D
var fx: MiningFX
var facing := 1
var _anim := ""
var _recoil := Vector2.ZERO
var _mining_now := false
var _mine_dir := Vector2.RIGHT
var _mine_target := Vector2i(2147483647, 0)
var _mine_obj = null            # station/pod currently being dismantled
var _mine_progress := 0.0
var _place_cd := 0.0
var _fire_cd := 0.0
var _invuln := 0.0
var _no_dmg := 0.0

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

	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = Art.player_frames()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play("idle")
	add_child(sprite)

	var cam := Camera2D.new()
	cam.zoom = Vector2(4.5, 4.5)
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

	# the particle-gun mining effect lives in world space
	fx = MiningFX.new()
	Game.world.add_child(fx)

	Game.player_died.connect(_on_died)

func _starting_kit() -> void:
	# starter kit: a tool, a few meds, and raws to bootstrap the crafting tree
	inv.add("pickaxe", 1)
	inv.add("med_cell", 3)
	inv.add("scrap", 10)
	inv.add("stone", 8)
	inv.add("metal_ore", 4)
	inv.add("wood", 6)
	inv.select(0)

# ---------------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	_place_cd = maxf(0.0, _place_cd - dt)
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_invuln = maxf(0.0, _invuln - dt)

	# regenerate health when out of combat
	_no_dmg += dt
	if _no_dmg >= REGEN_DELAY and Game.health < Game.max_health:
		Game.heal_player(REGEN_RATE * dt)

	# horizontal movement (Shift to sprint)
	var spd := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * spd, ACCEL * dt)
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
	_update_anim()

	if Game.ui_blocking:
		_stop_mining()
	else:
		_handle_interaction(dt)

	# recoil: a steady kickback while mining, an impulse when firing
	if _mining_now:
		_recoil = (-_mine_dir * MINE_RECOIL) + Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
	else:
		_recoil = _recoil.move_toward(Vector2.ZERO, RECOIL_RECOVER * dt)
	sprite.position = _recoil
	queue_redraw()

func _update_anim() -> void:
	var name := "idle"
	if not is_on_floor():
		name = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 8.0:
		name = "run"
	if name != _anim:
		_anim = name
		sprite.play(name)

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
			ItemDB.DEPLOYABLE: _try_deploy(sel)

	if not (mining and _try_mine(dt)):
		_stop_mining()

func _stop_mining() -> void:
	_mine_target = Vector2i(2147483647, 0)
	_mine_obj = null
	_mine_progress = 0.0
	_mining_now = false
	fx.set_state(false, Vector2i.ZERO, Vector2.ZERO, Color.WHITE, Color.WHITE, 0.0)

func _target_tile() -> Vector2i:
	return Game.world.world_to_tile(get_global_mouse_position())

func _in_reach(t: Vector2i) -> bool:
	var c: Vector2 = Game.world.tile_to_world_center(t)
	return global_position.distance_to(c) <= REACH * World.TILE

func _try_mine(dt: float) -> bool:
	# dismantling a deployed station / storage pod (aim the gun at it)
	var mpos := get_global_mouse_position()
	var struct = Game.world.structure_at(mpos)
	if struct != null and global_position.distance_to(struct.global_position) <= REACH * World.TILE:
		if struct != _mine_obj:
			_mine_obj = struct
			_mine_progress = 0.0
		_mine_progress += dt
		var ddur: float = MINE_BASE * 9.0 / _mining_power()
		var dfrac := clampf(_mine_progress / ddur, 0.0, 1.0)
		var sp: Vector2 = struct.global_position - Vector2(0, 10)
		_mine_dir = (sp - global_position).normalized()
		_mining_now = true
		var dc := Color("aef6ff")
		fx.set_state(true, Game.world.world_to_tile(sp), global_position + _mine_dir * 6.0, dc, dc, dfrac, false)
		struct.set_dismantle(dfrac)
		if _mine_progress >= ddur:
			_mine_progress = 0.0
			_mine_obj = null
			Game.world.dismantle(struct)
			Sfx.play("deploy")
		return true

	var t := _target_tile()
	if not _in_reach(t):
		return false

	# harvesting an alien tree (non-solid; no block erosion in the FX)
	var tree = Game.world.tree_at(t)
	if tree != null:
		if t != _mine_target:
			_mine_target = t
			_mine_progress = 0.0
		_mine_progress += dt
		var hdur: float = MINE_BASE * tree.harvest_time / _mining_power()
		var hfrac := clampf(_mine_progress / hdur, 0.0, 1.0)
		var hcenter: Vector2 = Game.world.tile_to_world_center(t)
		_mine_dir = (hcenter - global_position).normalized()
		_mining_now = true
		var hcol := _tree_color(tree.biome)
		fx.set_state(true, t, global_position + _mine_dir * 6.0, hcol, hcol, hfrac, false)
		tree.set_harvest(hfrac)
		if _mine_progress >= hdur:
			_mine_progress = 0.0
			Game.world.harvest_tree(tree, t)
			Sfx.play("mine")
		return true

	var id: int = Game.world.get_tile(t)
	if not Tiles.is_solid(id):
		return false
	# only mine blocks exposed to open space, so you can't dig more than one
	# block deep into solid terrain at a time
	if not _is_exposed(t):
		return false
	if t != _mine_target:
		_mine_target = t
		_mine_progress = 0.0
	_mine_progress += dt

	var dur: float = MINE_BASE * Tiles.hardness(id) / _mining_power()
	var frac := clampf(_mine_progress / dur, 0.0, 1.0)
	var d = Tiles.def(id)
	# gun muzzle just in front of the player, pointed at the block
	var center: Vector2 = Game.world.tile_to_world_center(t)
	_mine_dir = (center - global_position).normalized()
	_mining_now = true
	var muzzle := global_position + _mine_dir * 6.0
	fx.set_state(true, t, muzzle, d.base, _mine_accent(d), frac)

	if _mine_progress >= dur:
		_mine_progress = 0.0
		Game.world.set_tile(t, Tiles.AIR)
		Sfx.play("mine")
		_spawn_drop(t, Tiles.drop_item(id))
	return true

func _mine_accent(d: Dictionary) -> Color:
	# the gun/particle colour: prefer a tile's glow/ore tint, else its accent
	return d.get("light", d.get("ore", d.get("accent", d.base)))

func _tree_color(biome: int) -> Color:
	match biome:
		World.TUNDRA: return Color("8fe8ff")
		World.DUNES: return Color("a7c08a")
		World.JUNGLE: return Color("7aff3a")
		_: return Color("ff4df0")

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

func _try_deploy(item_id: String) -> void:
	# place a station / storage pod on flat ground within reach
	if _place_cd > 0.0:
		return
	var t := _target_tile()
	if not _in_reach(t):
		return
	if Tiles.is_solid(Game.world.get_tile(t)):
		return
	if not Tiles.is_solid(Game.world.get_tile(t + Vector2i(0, 1))):
		return                              # needs solid ground beneath
	var tile_rect := Rect2(t.x * World.TILE, (t.y - 1) * World.TILE, World.TILE, World.TILE * 2)
	var body := Rect2(global_position - Vector2(6, 11), Vector2(12, 22))
	if tile_rect.intersects(body):
		return                              # don't drop it on ourselves
	Game.world.spawn_structure(item_id, t)
	Sfx.play("deploy")
	inv.consume_selected(1)
	_place_cd = 0.3

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
	var it := ItemDB.get_item(item_id)
	var dmg: float = it.stats.get("damage", 10.0)
	var spd: float = it.stats.get("speed", 320.0)
	var cd: float = it.stats.get("cooldown", 0.25)
	var dir := (get_global_mouse_position() - global_position)
	if dir.length() < 1.0:
		dir = Vector2(facing, 0)
	dir = dir.normalized()
	var p := Projectile.new()
	p.setup(global_position + dir * 10.0, dir, dmg, spd, true)
	Sfx.play("shoot")
	Game.world.add_child(p)
	_fire_cd = cd
	# kickback + muzzle flash
	_recoil += -dir * FIRE_KICK
	_spawn_muzzle_flash(dir * 11.0, it.color, 0.5)

func _mining_power() -> float:
	var it := ItemDB.get_item(inv.selected_id())
	if it and it.stats.has("mining_power"):
		return float(it.stats.mining_power)
	return 1.0

func _spawn_muzzle_flash(local_pos: Vector2, color: Color, size: float) -> void:
	var flash := Sprite2D.new()
	flash.texture = Art.light_texture()
	flash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	flash.modulate = color
	flash.scale = Vector2(size, size)
	flash.position = local_pos
	flash.z_index = 1
	add_child(flash)
	var lt := PointLight2D.new()
	lt.texture = Art.light_texture()
	lt.color = color
	lt.energy = 1.8
	lt.scale = Vector2(size * 1.3, size * 1.3)
	flash.add_child(lt)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(size * 0.2, size * 0.2), 0.12)
	tw.tween_property(flash, "modulate:a", 0.0, 0.12)
	tw.tween_property(lt, "energy", 0.0, 0.12)
	tw.finished.connect(flash.queue_free)

func _try_consume(item_id: String) -> void:
	if _place_cd > 0.0:
		return
	var it := ItemDB.get_item(item_id)
	if Game.health >= Game.max_health or it.heal <= 0.0:
		return
	Game.heal_player(it.heal)
	inv.consume_selected(1)
	_place_cd = 0.4

# ---------------------------------------------------------------------------
func take_damage(amount: float) -> void:
	if _invuln > 0.0:
		return
	_invuln = INVULN
	Sfx.play("hit")
	_no_dmg = 0.0
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
	draw_rect(Rect2(top_left, Vector2(World.TILE, World.TILE)), col, false, 1.0, true)
