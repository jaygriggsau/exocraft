extends Node
## Spawns alien fauna in a ring around the player, up to a cap. Species are
## data-driven (see SPECIES). Passive animals always roam; territorial ones are
## suppressed while peaceful mode is on.

const INTERVAL := 2.0
const MAX_CREATURES := 12
const MIN_TILES := 16
const MAX_TILES := 24

var _t := 0.0
var SPECIES := []

func _ready() -> void:
	Game.enemies_toggled.connect(_on_toggled)
	SPECIES = [
		# --- passive animals ---
		{"id": "grazer", "sprite": "grazer", "behavior": Creature.PASSIVE, "hp": 30.0,
			"speed": 34.0, "size": Vector2(18, 12), "tint_biome": true, "weight": 3.0,
			"drops": [["biomass", 1, 0.9], ["biomass", 1, 0.4]]},
		{"id": "hopper", "sprite": "hopper", "behavior": Creature.PASSIVE, "hp": 14.0,
			"speed": 74.0, "size": Vector2(12, 10), "tint_biome": true, "weight": 3.0,
			"drops": [["biomass", 1, 0.6], ["scrap", 1, 0.3]]},
		{"id": "floater", "sprite": "floater", "behavior": Creature.PASSIVE, "flying": true,
			"hp": 18.0, "speed": 40.0, "size": Vector2(14, 14), "weight": 2.0,
			"drops": [["energy_core", 1, 0.3], ["scrap", 1, 0.4]]},
		# --- territorial animals (attack when player is in range) ---
		{"id": "crawler", "sprite": "crawler", "behavior": Creature.TERRITORIAL, "hp": 30.0,
			"speed": 56.0, "size": Vector2(16, 11), "detect": 150.0, "touch": 8.0, "weight": 2.0,
			"drops": [["scrap", 1, 1.0], ["scrap", 1, 0.4]]},
		{"id": "stalker", "sprite": "stalker", "behavior": Creature.TERRITORIAL, "hp": 38.0,
			"speed": 66.0, "size": Vector2(20, 11), "detect": 175.0, "touch": 11.0,
			"night_only": true, "weight": 2.0,
			"drops": [["scrap", 1, 1.0], ["metal_ore", 1, 0.3]]},
		{"id": "spitter", "sprite": "spitter", "behavior": Creature.TERRITORIAL, "hp": 24.0,
			"speed": 28.0, "size": Vector2(16, 12), "detect": 220.0, "ranged": true,
			"shoot_range": 200.0, "shoot_cd": 1.6, "pdmg": 8.0, "pspeed": 160.0, "weight": 1.0,
			"drops": [["scrap", 1, 0.6], ["energy_core", 1, 0.3]]},
		{"id": "drone", "sprite": "drone", "behavior": Creature.TERRITORIAL, "flying": true,
			"hp": 22.0, "speed": 70.0, "size": Vector2(14, 14), "detect": 210.0, "touch": 10.0,
			"weight": 2.0, "drops": [["energy_core", 1, 0.4], ["scrap", 1, 0.5]]},
	]

func _on_toggled(enabled: bool) -> void:
	if not enabled:
		# peaceful mode only clears hostile creatures; animals keep roaming
		for e in get_tree().get_nodes_in_group("hostile"):
			e.queue_free()

func _process(dt: float) -> void:
	if Game.player == null or Game.world == null:
		return
	_t += dt
	if _t < INTERVAL:
		return
	_t = 0.0
	if get_tree().get_nodes_in_group("creatures").size() >= MAX_CREATURES:
		return
	var pool := _eligible_pool()
	if pool.is_empty():
		return
	_spawn(_pick(pool))

func _eligible_pool() -> Array:
	var peaceful := not Game.enemies_enabled
	var night := Game.day_phase() == "Night"
	var pool := []
	for s in SPECIES:
		if peaceful and s.behavior != Creature.PASSIVE:
			continue
		if s.get("night_only", false) and not night:
			continue
		pool.append(s)
	return pool

func _pick(pool: Array) -> Dictionary:
	var total := 0.0
	for s in pool:
		total += s.weight
	var r := randf() * total
	for s in pool:
		r -= s.weight
		if r <= 0.0:
			return s
	return pool.back()

func _biome_color(biome: int) -> Color:
	match biome:
		World.TUNDRA: return Color("aee8ff")
		World.DUNES: return Color("d9c27a")
		World.JUNGLE: return Color("a6ff3a")
		_: return Color("2bf0a0")

func configure(s: Dictionary, biome: int) -> Creature:
	var c := Creature.new()
	c.species = s.id
	c.sprite_name = s.sprite
	c.behavior = s.behavior
	c.flying = s.get("flying", false)
	c.max_hp = s.hp
	c.move_speed = s.speed
	c.body_size = s.size
	c.detect_range = s.get("detect", 150.0)
	c.touch_damage = s.get("touch", 8.0)
	c.ranged = s.get("ranged", false)
	c.shoot_range = s.get("shoot_range", 170.0)
	c.shoot_cooldown = s.get("shoot_cd", 1.6)
	c.projectile_damage = s.get("pdmg", 8.0)
	c.projectile_speed = s.get("pspeed", 150.0)
	c.drops = s.drops
	if s.get("tint_biome", false):
		c.tint = Color.WHITE.lerp(_biome_color(biome), 0.35)
	return c

func _spawn(s: Dictionary) -> void:
	var ptile: Vector2i = Game.world.world_to_tile(Game.player.global_position)
	var biome: int = Game.world.biome_at(ptile.x)
	var c := configure(s, biome)
	if c.flying:
		var ang := randf() * TAU
		var d := randi_range(MIN_TILES, MAX_TILES) * World.TILE
		c.global_position = Game.player.global_position + Vector2(cos(ang), sin(ang)) * d
	else:
		var side := 1 if randf() < 0.5 else -1
		var tx := ptile.x + side * randi_range(MIN_TILES, MAX_TILES)
		var ty: int = Game.world.surface_tile_y(tx) - 2
		c.global_position = Game.world.tile_to_world_center(Vector2i(tx, ty))
	Game.world.add_child(c)
