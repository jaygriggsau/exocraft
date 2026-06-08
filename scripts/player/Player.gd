class_name Player
extends CharacterBody2D
## The player: platforming movement plus mine / build / shoot interactions that
## all key off the currently selected hotbar item.

const SPEED := 120.0
const SPRINT_MULT := 1.7
const REGEN_DELAY := 4.0            # seconds out of combat before health regens
const REGEN_RATE := 7.0            # health per second
const HUNGER_DRAIN := 0.45         # hunger lost per second at rest
const HUNGER_SPRINT := 1.9         # drain multiplier while sprinting
const WELL_FED := 30.0             # hunger needed for health to regenerate
const STARVE_DMG := 2.5            # health/sec lost while starving (hunger 0)
const STARVE_FLOOR := 20.0         # starvation won't drop you below this health
const ACCEL := 1400.0
const FRICTION := 1600.0
const JUMP_VELOCITY := -270.0
const GRAVITY := 760.0
const MAX_FALL := 520.0
const REACH := 5.5                 # tiles
const MINE_BASE := 0.12            # base unit for tree-harvest / dismantle / drain
const MINE_BLOCK_BASE := 0.75      # seconds per hardness point with the Particle Gun
                                   # (hardest block, Exotic hardness 8 -> 6.0s; upgraded
                                   # guns divide by mining_power so they all scale down)
const PLACE_COOLDOWN := 0.12
const INVULN := 0.6
const FIRE_KICK := 3.5             # blaster recoil impulse (px)
const MINE_RECOIL := 1.3           # steady kickback while mining (px)
const RECOIL_RECOVER := 36.0       # px/s the sprite eases back
const WATER_MOVE := 0.6            # horizontal speed multiplier while submerged
const WATER_GRAVITY := 0.3         # gravity multiplier while submerged (buoyancy)
const POUR_RATE := 0.5             # liquid added per pour tick (cells fill fast)
const DRAIN_RATE := 0.6            # liquid sucked up per mine tick

var inv: Inventory
var sprite: AnimatedSprite2D
var fx: MiningFX
var _torch: PointLight2D
var facing := 1
var _anim := ""
var _recoil := Vector2.ZERO
var _mining_now := false
var _mine_dir := Vector2.RIGHT
var _mine_target := Vector2i(2147483647, 0)
var _mine_obj = null            # station/pod currently being dismantled
var _mine_progress := 0.0
var _place_cd := 0.0
var _door_cd := 0.0
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
	cam.zoom = Vector2(3.5, 3.5)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	add_child(cam)
	cam.make_current()

	# a toggleable torch (key T): a warm, shadow-casting glow ~4 blocks across
	# with a soft fade. Off by default-ish? No — on, but you can douse it.
	_torch = PointLight2D.new()
	_torch.texture = Art.light_texture()
	_torch.color = Color(1.0, 0.82, 0.5)
	_torch.energy = 1.25
	_torch.scale = Vector2(0.7, 0.7)            # ~90px radius (~4 blocks lit, fading out)
	_torch.shadow_enabled = true
	_torch.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_torch.position = Vector2(0, -6)
	add_child(_torch)
	# a faint personal glow that ignores walls, so you're never pitch-invisible
	var aura := PointLight2D.new()
	aura.texture = Art.light_texture()
	aura.color = Color(0.55, 0.72, 1.0)
	aura.energy = 0.35
	aura.scale = Vector2(0.3, 0.3)
	add_child(aura)

	# the particle-gun mining effect lives in world space
	fx = MiningFX.new()
	Game.world.add_child(fx)

	Game.player_died.connect(_on_died)

func _starting_kit() -> void:
	# starter kit: a tool, a few meds, and raws to bootstrap the crafting tree
	inv.add("pickaxe", 1)
	inv.add("hydro_cell", 1)
	inv.add("med_cell", 3)
	inv.add("scrap", 10)
	inv.add("stone", 8)
	inv.add("metal_ore", 4)
	inv.add("wood", 6)
	inv.select(0)

# ---------------------------------------------------------------------------
func _physics_process(dt: float) -> void:
	_place_cd = maxf(0.0, _place_cd - dt)
	_door_cd = maxf(0.0, _door_cd - dt)
	_fire_cd = maxf(0.0, _fire_cd - dt)
	_invuln = maxf(0.0, _invuln - dt)

	if Input.is_action_just_pressed("torch"):
		_torch.visible = not _torch.visible

	# hunger drains over time (faster while sprinting); empty hunger starves you,
	# and you only regenerate health while reasonably well fed
	var sprinting := Input.is_action_pressed("sprint") and absf(velocity.x) > 8.0
	Game.add_hunger(-HUNGER_DRAIN * (HUNGER_SPRINT if sprinting else 1.0) * dt)

	_no_dmg += dt
	if Game.hunger <= 0.0 and Game.health > STARVE_FLOOR:
		Game.damage_player(STARVE_DMG * dt)      # starvation
	elif _no_dmg >= REGEN_DELAY and Game.hunger >= WELL_FED and Game.health < Game.max_health:
		Game.heal_player(REGEN_RATE * dt)

	# submerged? liquid slows you and makes you buoyant (swim with Jump)
	var in_water: bool = Game.world.is_water_at(global_position)

	# horizontal movement (Shift to sprint; water adds drag)
	var spd := SPEED * (SPRINT_MULT if Input.is_action_pressed("sprint") else 1.0)
	if in_water:
		spd *= WATER_MOVE
	var dir := Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * spd, ACCEL * dt)
		facing = signi(int(dir))
		sprite.flip_h = facing < 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * dt)

	# gravity + jump (or buoyant swimming while submerged)
	if in_water:
		# gentle sink, capped fall; Jump kicks off the floor to leap out of
		# shallow pools, or strokes upward while you're actually swimming
		velocity.y = minf(velocity.y + GRAVITY * WATER_GRAVITY * dt, MAX_FALL * 0.32)
		if Input.is_action_pressed("jump"):
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
			elif velocity.y > -SPEED * 0.95:   # don't brake an in-progress leap
				velocity.y = move_toward(velocity.y, -SPEED * 0.95, ACCEL * dt)
	else:
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
	var it := ItemDB.get_item(sel) if sel != "" else null
	var t := ItemDB.type_of(sel) if sel != "" else -1

	if primary:
		var tt := _target_tile()
		if _door_cd <= 0.0 and Tiles.is_door(Game.world.get_tile(tt)) and _in_reach(tt):
			if _toggle_door(tt):           # click a door to open / close it
				_door_cd = 0.3
		elif it and it.stats.has("pour_water"):
			_try_pour()
		else:
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
	var is_door := Tiles.is_door(id)
	if not Tiles.is_solid(id) and not is_door:
		# no block here, but the particle gun can suck up any liquid in the cell
		if Game.world.water_at(t) > 0.0:
			Game.world.drain_water(t, DRAIN_RATE * dt * 60.0 * MINE_BASE * _mining_power())
			var wc := Color(0.4, 0.85, 1.0)
			_mine_dir = (Game.world.tile_to_world_center(t) - global_position).normalized()
			_mining_now = true
			fx.set_state(true, t, global_position + _mine_dir * 6.0, wc, wc, 0.4, false)
			return true
		return false
	# only mine solid blocks exposed to open space, so you can't dig more than one
	# block deep into solid terrain at a time (doors are always reachable)
	if not is_door and not _is_exposed(t):
		return false
	if t != _mine_target:
		_mine_target = t
		_mine_progress = 0.0
	_mine_progress += dt

	# tougher blocks take proportionally longer to absorb (see Tiles hardness)
	var dur: float = MINE_BLOCK_BASE * Tiles.hardness(id) / _mining_power()
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
		if is_door:
			# the whole 2-tall door comes out as one item (it went in as one)
			for c in _door_run(t):
				Game.world.set_tile(c, Tiles.AIR)
		else:
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

func _player_rect() -> Rect2:
	return Rect2(global_position - Vector2(6, 11), Vector2(12, 22))

func _tile_rect(c: Vector2i) -> Rect2:
	return Rect2(c.x * World.TILE, c.y * World.TILE, World.TILE, World.TILE)

## The contiguous vertical run of door tiles a click landed on (a door is 2 tall).
func _door_run(t: Vector2i) -> Array:
	var cells := [t]
	var c := t + Vector2i(0, -1)
	while Tiles.is_door(Game.world.get_tile(c)):
		cells.append(c)
		c += Vector2i(0, -1)
	c = t + Vector2i(0, 1)
	while Tiles.is_door(Game.world.get_tile(c)):
		cells.append(c)
		c += Vector2i(0, 1)
	return cells

func _toggle_door(t: Vector2i) -> bool:
	var cells := _door_run(t)
	var becomes_solid := Tiles.is_solid(Tiles.door_toggle(Game.world.get_tile(t)))
	if becomes_solid:
		var body := _player_rect()
		for c in cells:
			if _tile_rect(c).intersects(body):
				return false               # never shut a door on yourself
	for c in cells:
		var id: int = Game.world.get_tile(c)
		Game.world.set_tile(c, Tiles.door_toggle(id))
	Sfx.play("place")
	return true

func _try_place(item_id: String) -> void:
	if _place_cd > 0.0:
		return
	var tile := ItemDB.place_tile(item_id)
	if Tiles.is_door(tile):
		_try_place_door(tile)
		return
	if tile == Tiles.AIR:
		return
	var t := _target_tile()
	if not _in_reach(t):
		return
	if Tiles.is_solid(Game.world.get_tile(t)):
		return
	# don't entomb ourselves
	if _tile_rect(t).intersects(_player_rect()):
		return
	# require an adjacent solid tile for support
	if not _has_support(t):
		return
	Game.world.set_tile(t, tile)
	inv.consume_selected(1)
	_place_cd = PLACE_COOLDOWN

## Doors are two tiles tall (so the player can walk through). Place the clicked
## cell as the bottom and the cell above as the top, both closed.
func _try_place_door(closed_tile: int) -> void:
	var bottom := _target_tile()
	if not _in_reach(bottom):
		return
	var top := bottom + Vector2i(0, -1)
	var body := _player_rect()
	for c in [bottom, top]:
		if Tiles.is_solid(Game.world.get_tile(c)):
			return
		if _tile_rect(c).intersects(body):
			return
	# support: resting on the ground, or anchored to a wall beside either cell
	var supported := Tiles.is_solid(Game.world.get_tile(bottom + Vector2i(0, 1)))
	for c in [bottom, top]:
		for o in [Vector2i(1, 0), Vector2i(-1, 0)]:
			if Tiles.is_solid(Game.world.get_tile(c + o)):
				supported = true
	if not supported:
		return
	Game.world.set_tile(bottom, closed_tile)
	Game.world.set_tile(top, closed_tile)
	inv.consume_selected(1)
	_place_cd = PLACE_COOLDOWN

func _try_pour() -> void:
	# Hydro Cell: stream liquid into the targeted open cell (an endless source, so
	# you can flood, irrigate or fill basins — the physics does the rest).
	if _place_cd > 0.0:
		return
	var t := _target_tile()
	if not _in_reach(t):
		return
	if Tiles.is_solid(Game.world.get_tile(t)):
		return
	Game.world.add_water(t, POUR_RATE)
	_place_cd = 0.05

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
	if it.stats.has("melee"):
		_try_melee(it)
		return
	var dmg: float = it.stats.get("damage", 10.0)
	var spd: float = it.stats.get("speed", 320.0)
	var cd: float = it.stats.get("cooldown", 0.25)
	var spread: float = it.stats.get("spread", 0.0)
	var style: String = it.stats.get("projectile", "bolt")
	var dir := (get_global_mouse_position() - global_position)
	if dir.length() < 1.0:
		dir = Vector2(facing, 0)
	dir = dir.normalized()
	var pellets: int = int(it.stats.get("pellets", 1))    # scatter guns fire several
	for i in maxi(1, pellets):
		var pd := dir
		if spread > 0.0:
			pd = dir.rotated(randf_range(-spread, spread))
		var p := Projectile.new()
		p.setup(global_position + pd * 10.0, pd, dmg, spd, true, style)
		Game.world.add_child(p)
	Sfx.play("gunshot" if style == "bullet" else "shoot")
	_fire_cd = cd
	# kickback + muzzle flash
	_recoil += -dir * FIRE_KICK
	_spawn_muzzle_flash(dir * 11.0, it.color, 0.5)

## Melee swing (lightsaber): cleave every creature in a short arc in front of
## the player and slice apart incoming enemy bolts, with a glowing slash.
func _try_melee(it: Item) -> void:
	var reach: float = it.stats.get("reach", 30.0)
	var dmg: float = it.stats.get("damage", 20.0)
	var cd: float = it.stats.get("cooldown", 0.35)
	var dir := (get_global_mouse_position() - global_position)
	if dir.length() < 1.0:
		dir = Vector2(facing, 0)
	dir = dir.normalized()
	var center := global_position + dir * reach * 0.6
	for e in get_tree().get_nodes_in_group("creatures"):
		if is_instance_valid(e) and e.has_method("take_damage") \
				and center.distance_to(e.global_position) <= reach:
			e.take_damage(dmg)
	for pr in get_tree().get_nodes_in_group("enemy_projectiles"):
		if is_instance_valid(pr) and center.distance_to(pr.global_position) <= reach:
			pr.queue_free()                       # deflect/slice incoming fire
	_spawn_slash(dir, reach, it.color)
	Sfx.play("slash")
	_fire_cd = cd
	_recoil += dir * 2.5                          # tiny forward lunge

func _spawn_slash(dir: Vector2, reach: float, color: Color) -> void:
	var s := Sprite2D.new()
	s.texture = Art.sprite("slash")
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.modulate = color
	s.global_position = global_position + dir * reach * 0.5
	s.rotation = dir.angle()
	var sc := reach / 11.0
	s.scale = Vector2(sc, sc)
	var l := PointLight2D.new()
	l.texture = Art.light_texture()
	l.color = color
	l.energy = 1.4
	l.scale = Vector2(0.45, 0.45)
	s.add_child(l)
	Game.world.add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "scale", s.scale * 1.45, 0.16)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.16)
	tw.tween_callback(s.queue_free)

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
	var food: float = it.stats.get("food", 0.0)
	# skip if it would do nothing right now (full health and full hunger)
	var can_heal := it.heal > 0.0 and Game.health < Game.max_health
	var can_feed := food > 0.0 and Game.hunger < Game.max_hunger
	if not can_heal and not can_feed:
		return
	if food > 0.0:
		Game.feed_player(food)
	if it.heal > 0.0:
		Game.heal_player(it.heal)
	inv.consume_selected(1)
	Sfx.play("pickup")
	_place_cd = 0.5

# ---------------------------------------------------------------------------
func take_damage(amount: float) -> void:
	if _invuln > 0.0:
		return
	_invuln = INVULN
	Sfx.play("hit")
	_no_dmg = 0.0
	Game.damage_player(amount * (1.0 - Game.armor_reduction()))   # armor soaks part of the hit
	# knockback flash
	modulate = Color(1, 0.5, 0.5)
	create_tween().tween_property(self, "modulate", Color.WHITE, INVULN)

func _on_died() -> void:
	Game.reset_health()
	Game.reset_hunger()
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
