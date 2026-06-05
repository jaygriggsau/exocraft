class_name CorpBase
extends Node2D
## A Corp surface outpost built out of real, in-world blocks — Hull Plating walls
## with a Neon Glass-lit control tower and antenna beacon — so it's part of the
## terrain (and can be mined). The node itself only drives the pulsing beacon
## light and garrisons a patrol of robots/drones that hold the ground around it.

const HALF := 5            # bunker half-width in tiles (footprint = 2*HALF+1)
const BODY_H := 5          # wall height above the floor
const TOWER_HALF := 2
const TOWER_H := 4

const MAX_UNITS := 4
const SPAWN_INTERVAL := 7.0
const REINFORCE_RANGE := 900.0     # px: only reinforce while the player is near

var patrol_radius := 150.0
var center_tx := 0                 # centre column of the build
var floor_y := 0                   # flat floor row the bunker sits on

var _units: Array = []
var _t := 3.0                      # first reinforcement comes quickly
var _beacon: PointLight2D
var _pulse := 0.0

func _beacon_row() -> int:
	return floor_y - BODY_H - TOWER_H - 3

func _ready() -> void:
	z_index = 1
	# the only non-block element: a pulsing red alert beacon at the antenna tip
	_beacon = PointLight2D.new()
	_beacon.texture = Art.light_texture()
	_beacon.color = Color("ff3a3a")
	_beacon.energy = 1.1
	_beacon.scale = Vector2(1.3, 1.3)
	# place the beacon light at the antenna-tip block, in this node's local space
	_beacon.position = Vector2(0.0, (_beacon_row() + 0.5) * World.TILE - global_position.y)
	add_child(_beacon)

## Stamp the bunker into the world as Hull Plating + Neon Glass blocks. Called
## once per site (the blocks persist in the chunk data afterwards, so a rebuilt
## base node never overwrites what the player has since mined).
func build_structure() -> void:
	var w = Game.world
	if w == null:
		return
	var cx := center_tx
	var cy := floor_y
	var body_top := cy - BODY_H
	var tower_top := body_top - TOWER_H

	# 1. flat floor + foundation pillars down to the natural ground in any dips
	for col in range(cx - HALF, cx + HALF + 1):
		var gy: int = w.surface_tile_y(col)
		for ry in range(cy, maxi(cy + 1, gy)):
			w.set_tile(Vector2i(col, ry), Tiles.PLATING)

	# 2. clear the interior (in case the highest ground pokes into it) ...
	for col in range(cx - HALF + 1, cx + HALF):
		for ry in range(body_top + 1, cy):
			w.set_tile(Vector2i(col, ry), Tiles.AIR)
	# ... and the side walls + roof
	for ry in range(body_top, cy + 1):
		w.set_tile(Vector2i(cx - HALF, ry), Tiles.PLATING)
		w.set_tile(Vector2i(cx + HALF, ry), Tiles.PLATING)
	for col in range(cx - HALF, cx + HALF + 1):
		w.set_tile(Vector2i(col, body_top), Tiles.PLATING)

	# 3. neon windows + a doorway in the right wall
	w.set_tile(Vector2i(cx - HALF, cy - 3), Tiles.NEON)
	w.set_tile(Vector2i(cx + HALF, cy - 3), Tiles.NEON)
	w.set_tile(Vector2i(cx + HALF, cy - 1), Tiles.AIR)
	w.set_tile(Vector2i(cx + HALF, cy - 2), Tiles.AIR)

	# 4. control tower on the roof
	for ry in range(tower_top, body_top):
		w.set_tile(Vector2i(cx - TOWER_HALF, ry), Tiles.PLATING)
		w.set_tile(Vector2i(cx + TOWER_HALF, ry), Tiles.PLATING)
		for icol in range(cx - TOWER_HALF + 1, cx + TOWER_HALF):
			w.set_tile(Vector2i(icol, ry), Tiles.AIR)
	for col in range(cx - TOWER_HALF, cx + TOWER_HALF + 1):
		w.set_tile(Vector2i(col, tower_top), Tiles.PLATING)
	w.set_tile(Vector2i(cx - TOWER_HALF, tower_top + 1), Tiles.NEON)
	w.set_tile(Vector2i(cx + TOWER_HALF, tower_top + 1), Tiles.NEON)

	# 5. antenna mast + glowing beacon block at the top
	w.set_tile(Vector2i(cx, tower_top - 1), Tiles.PLATING)
	w.set_tile(Vector2i(cx, tower_top - 2), Tiles.PLATING)
	w.set_tile(Vector2i(cx, _beacon_row()), Tiles.NEON)

func _process(dt: float) -> void:
	_pulse += dt
	if _beacon:
		_beacon.energy = 0.8 + 0.5 * (0.5 + 0.5 * sin(_pulse * 3.0))
	_units = _units.filter(func(u): return is_instance_valid(u))
	if Game.player == null or not Game.enemies_enabled:
		return                                   # peaceful mode: no reinforcements
	if global_position.distance_to(Game.player.global_position) > REINFORCE_RANGE:
		return
	_t += dt
	if _t < SPAWN_INTERVAL or _units.size() >= MAX_UNITS:
		return
	_t = 0.0
	_spawn_unit()

func _spawn_unit() -> void:
	var c := Creature.new()
	c.faction = "corp"
	c.behavior = Creature.TERRITORIAL
	c.has_home = true
	c.home = global_position
	c.patrol_radius = patrol_radius
	var roll := randf()
	if roll < 0.34:
		# flying attack drone — launches from above the tower
		c.species = "corpdrone"
		c.sprite_name = "corpdrone"
		c.flying = true
		c.max_hp = 26.0
		c.move_speed = 80.0
		c.body_size = Vector2(14, 10)
		c.detect_range = 240.0
		c.touch_damage = 10.0
		c.drops = [["scrap", 1, 0.6], ["power_cell", 1, 0.15]]
		c.global_position = global_position + Vector2(randf_range(-30, 30), -randf_range(150, 210))
	else:
		# ground robot — musters just outside the bunker so it isn't walled in
		var side := 1.0 if randf() < 0.5 else -1.0
		var gx := side * randf_range(HALF + 1, HALF + 3) * World.TILE
		if roll < 0.62:
			# ranged sentry robot (fires bolts)
			c.species = "robot"
			c.sprite_name = "robot"
			c.max_hp = 44.0
			c.move_speed = 44.0
			c.body_size = Vector2(14, 16)
			c.detect_range = 230.0
			c.ranged = true
			c.shoot_range = 210.0
			c.shoot_cooldown = 1.4
			c.projectile_damage = 9.0
			c.projectile_speed = 220.0
			c.drops = [["scrap", 2, 0.8], ["circuit_board", 1, 0.12]]
		else:
			# heavy melee robot
			c.species = "robot"
			c.sprite_name = "robot"
			c.max_hp = 52.0
			c.move_speed = 54.0
			c.body_size = Vector2(14, 16)
			c.detect_range = 190.0
			c.touch_damage = 13.0
			c.drops = [["scrap", 2, 0.9], ["metal_ingot", 1, 0.3]]
		c.global_position = global_position + Vector2(gx, -24)
	get_parent().add_child(c)
	_units.append(c)

## Free the base node and its garrison (the player roamed too far). The built
## blocks stay in the world.
func despawn() -> void:
	for u in _units:
		if is_instance_valid(u):
			u.queue_free()
	queue_free()
