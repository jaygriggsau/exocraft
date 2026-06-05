extends Node
## Drives the two factions:
##   CORP - fixed surface bases at deterministic, spaced-out sites. A base spawns
##          near the player as they approach its site and tears down once they
##          leave, so the world feels populated without being tracked globally.
##   KIN  - the underground alien race: spawned in cave pockets near the player
##          while they're below ground, up to a cap. Neutral (see Creature).

# --- Corp surface bases ---
const CORP_SPACING := 84            # tiles between candidate base sites
const CORP_VIEW := 70              # tiles: materialise a base within this of the player
const CORP_PATROL := 150.0         # px patrol radius for a base's garrison

# --- Kin cave dwellers ---
const KIN_INTERVAL := 3.0
const KIN_MAX := 6
const KIN_MIN_DEPTH := 12           # tiles below the surface before Kin appear

var _bases := {}                    # site index -> CorpBase node (present only when near)
var _built := {}                    # site index -> true once its blocks are stamped
var _kt := 0.0

func _process(dt: float) -> void:
	if Game.player == null or Game.world == null:
		return
	_update_corp(dt)
	_update_kin(dt)

# ---------------------------------------------------------------------------
# Corp bases
# ---------------------------------------------------------------------------
func _site_tx(site: int) -> int:
	# deterministic, slightly jittered x for each base site
	var h: int = (site * 2654435761) ^ (Game.world_seed * 40503)
	h = (h ^ (h >> 13)) * 1274126177
	var jitter := (absi(h) % 31) - 15
	return site * CORP_SPACING + jitter

func _update_corp(_dt: float) -> void:
	var w = Game.world
	var ptx: int = w.world_to_tile(Game.player.global_position).x
	var center := int(round(float(ptx) / float(CORP_SPACING)))
	var want := {}
	for s in range(center - 1, center + 2):
		var tx := _site_tx(s)
		if absi(tx - ptx) <= CORP_VIEW:
			want[s] = true
			if not _bases.has(s):
				_spawn_base(s, tx)
	for s in _bases.keys():
		if not want.has(s):
			if is_instance_valid(_bases[s]):
				_bases[s].despawn()
			_bases.erase(s)

func _spawn_base(site: int, tx: int) -> void:
	var w = Game.world
	# flat floor for the bunker = the highest ground across its footprint, so the
	# building never floats (foundation pillars fill any dips beneath it)
	var fy: int = w.surface_tile_y(tx)
	for col in range(tx - CorpBase.HALF, tx + CorpBase.HALF + 1):
		fy = mini(fy, w.surface_tile_y(col))
	var base := CorpBase.new()
	base.patrol_radius = CORP_PATROL
	base.center_tx = tx
	base.floor_y = fy
	base.global_position = Vector2((tx + 0.5) * World.TILE, fy * World.TILE)
	w.add_child(base)
	if not _built.has(site):
		base.build_structure()       # stamp the blocks once; they persist after
		_built[site] = true
	_bases[site] = base

# ---------------------------------------------------------------------------
# Kin cave dwellers
# ---------------------------------------------------------------------------
func _update_kin(dt: float) -> void:
	_kt += dt
	if _kt < KIN_INTERVAL:
		return
	_kt = 0.0
	var w = Game.world
	var ptile: Vector2i = w.world_to_tile(Game.player.global_position)
	if ptile.y - w.surface_height(ptile.x) < KIN_MIN_DEPTH:
		return                                   # only underground
	if get_tree().get_nodes_in_group("kin").size() >= KIN_MAX:
		return
	var spot = _find_cave_spot(ptile)
	if spot == null:
		return
	_spawn_kin(spot)

func _find_cave_spot(ptile: Vector2i):
	var w = Game.world
	for _i in 18:
		var dx := randi_range(6, 18) * (1 if randf() < 0.5 else -1)
		var dy := randi_range(-6, 8)
		var cell := Vector2i(ptile.x + dx, ptile.y + dy)
		# stand on a solid floor, head-room above, not on top of the player
		if w.get_tile(cell) != Tiles.AIR:
			continue
		if w.get_tile(Vector2i(cell.x, cell.y - 1)) != Tiles.AIR:
			continue
		if not Tiles.is_solid(w.get_tile(Vector2i(cell.x, cell.y + 1))):
			continue
		return cell
	return null

func _spawn_kin(cell: Vector2i) -> void:
	var w = Game.world
	var c := Creature.new()
	c.faction = "kin"
	c.species = "kin"
	c.sprite_name = "kin"
	c.behavior = Creature.NEUTRAL
	c.max_hp = 42.0
	c.move_speed = 38.0
	c.body_size = Vector2(14, 12)
	c.detect_range = 150.0
	c.touch_damage = 11.0
	c.can_mine = true
	c.rep_gain = 1.2
	c.tint = Color.WHITE.lerp(Color("5fd0b0"), randf_range(0.0, 0.25))
	c.drops = [["crystal", 1, 0.3], ["biomass", 1, 0.4], ["exotic_matter", 1, 0.05]]
	c.global_position = w.tile_to_world_center(cell)
	w.add_child(c)
