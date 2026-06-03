class_name World
extends Node2D
## Endless, chunk-streamed tile world.
##
## Tile data lives in `chunks` (a dict of chunk-coord -> PackedInt32Array) and is
## generated on demand, so the world is effectively infinite in every direction.
## A single TileMapLayer is used purely for rendering + collision: cells near the
## player are streamed in and far cells are streamed out, while the underlying
## data (including the player's edits) is kept in memory so it persists.

const TILE := 16                    # px per tile (must match Art.TS)
const CHUNK := 16                   # tiles per chunk side
const LOAD_RADIUS := 3              # chunks loaded around the player
const LIGHT_RADIUS := 1            # chunks (around player) that emit block lights

const SURFACE_BASE := 0            # tile-y around which the surface sits
const SURFACE_AMP := 10.0
const SOIL_DEPTH := 5
const DEEP_Y := 110                # below here it becomes the Obsidite biome

# biome ids
enum { TUNDRA, DUNES, WASTES, JUNGLE }

var tilemap: TileMapLayer
var decor_map: TileMapLayer         # non-solid surface decorations
var fog_map: TileMapLayer           # fog of war over unexplored underground
var _explored := {}                 # Vector2i tile -> true (revealed)
var _mapped := {}                   # Vector2i tile -> true (revealed on the minimap)
var _last_reveal := Vector2i(999999, 999999)
var chunks := {}                    # Vector2i -> PackedInt32Array
var _loaded := {}                   # Vector2i -> true (currently rendered)
var _chunk_lights := {}             # Vector2i -> Array[PointLight2D]
var _chunk_decor := {}              # Vector2i -> Array[Vector2i] decor cells
var _chunk_trees := {}              # Vector2i -> Array[AlienTree]
var _tree_at := {}                  # Vector2i tile -> AlienTree (harvest lookup)
var _tree_removed := {}             # world tile-x -> true (harvested, don't respawn)
var _stations := []                 # deployed Station entities
var _pods := []                     # deployed StoragePod entities
var _last_center := Vector2i(999999, 999999)

const STATION_RANGE := 88.0         # px: how close you must be to use a station
const STORAGE_RANGE := 112.0        # px: how close a pod feeds a station

var _height_noise := FastNoiseLite.new()
var _biome_noise := FastNoiseLite.new()
var _cave_noise := FastNoiseLite.new()
var _metal_noise := FastNoiseLite.new()
var _crystal_noise := FastNoiseLite.new()
var _energy_noise := FastNoiseLite.new()

func _ready() -> void:
	_setup_noise()
	tilemap = TileMapLayer.new()
	tilemap.tile_set = Art.tileset
	tilemap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(tilemap)
	decor_map = TileMapLayer.new()
	decor_map.tile_set = Art.decor_tileset
	decor_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decor_map.z_index = 1               # in front of terrain, behind the player
	add_child(decor_map)
	fog_map = TileMapLayer.new()
	fog_map.tile_set = Art.fog_tileset
	fog_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fog_map.z_index = 3                 # clouds terrain + creatures until explored
	fog_map.light_mask = 0              # lights never reveal the fog; it stays black
	add_child(fog_map)

func _setup_noise() -> void:
	var s := Game.world_seed
	for n in [_height_noise, _biome_noise, _cave_noise, _metal_noise, _crystal_noise, _energy_noise]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
	_height_noise.seed = s
	_height_noise.frequency = 0.018
	_biome_noise.seed = s + 17
	_biome_noise.frequency = 0.004
	_cave_noise.seed = s + 31
	_cave_noise.frequency = 0.07
	_metal_noise.seed = s + 53
	_metal_noise.frequency = 0.12
	_crystal_noise.seed = s + 71
	_crystal_noise.frequency = 0.13
	_energy_noise.seed = s + 97
	_energy_noise.frequency = 0.14

# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------
static func _fdiv(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))

func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(_fdiv(int(floor(p.x)), TILE), _fdiv(int(floor(p.y)), TILE))

func tile_to_world_center(t: Vector2i) -> Vector2:
	return Vector2((t.x + 0.5) * TILE, (t.y + 0.5) * TILE)

func chunk_of_tile(t: Vector2i) -> Vector2i:
	return Vector2i(_fdiv(t.x, CHUNK), _fdiv(t.y, CHUNK))

# ---------------------------------------------------------------------------
# Streaming
# ---------------------------------------------------------------------------
func _physics_process(_dt: float) -> void:
	if Game.player == null:
		return
	var ptile := world_to_tile(Game.player.global_position)
	if ptile != _last_reveal:
		_last_reveal = ptile
		_reveal_around(ptile)
	var center := chunk_of_tile(ptile)
	if center == _last_center:
		return
	_last_center = center
	_stream(center)

const REVEAL_RADIUS := 7        ## in-world black-fog vision radius (kept tighter than the view)
const MAP_RADIUS := 26          ## how far the minimap reveals around the player

func _reveal_around(c: Vector2i) -> void:
	# clear the in-world fog within a circle of the player (underground only)
	for dy in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
		for dx in range(-REVEAL_RADIUS, REVEAL_RADIUS + 1):
			if dx * dx + dy * dy > REVEAL_RADIUS * REVEAL_RADIUS:
				continue
			var t := Vector2i(c.x + dx, c.y + dy)
			if _explored.has(t):
				continue
			if t.y <= surface_height(t.x) + 2:
				continue
			_explored[t] = true
			fog_map.erase_cell(t)
	# reveal a wider area on the minimap (everywhere, stays revealed)
	for dy in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for dx in range(-MAP_RADIUS, MAP_RADIUS + 1):
			if dx * dx + dy * dy <= MAP_RADIUS * MAP_RADIUS:
				_mapped[Vector2i(c.x + dx, c.y + dy)] = true

func is_explored(t: Vector2i) -> bool:
	return _mapped.has(t)

func deployed() -> Array:
	return _stations + _pods

func _fog_chunk(cc: Vector2i) -> void:
	var oy := cc.y * CHUNK
	if oy + CHUNK <= -8:                 # purely sky chunks never need fog
		return
	var ox := cc.x * CHUNK
	for lx in CHUNK:
		var tx := ox + lx
		var fog_top := surface_height(tx) + 3
		for ly in CHUNK:
			var ty := oy + ly
			if ty < fog_top:
				continue
			var t := Vector2i(tx, ty)
			if _explored.has(t):
				continue
			var v: int = absi(tx * 49297 + ty * 233) % Art.FOG_VARIANTS
			fog_map.set_cell(t, Art.fog_source_id, Art.fog_atlas_coords(v))

func _unfog_chunk(cc: Vector2i) -> void:
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			fog_map.erase_cell(Vector2i(ox + lx, oy + ly))

func _stream(center: Vector2i) -> void:
	var want := {}
	for cy in range(center.y - LOAD_RADIUS, center.y + LOAD_RADIUS + 1):
		for cx in range(center.x - LOAD_RADIUS, center.x + LOAD_RADIUS + 1):
			want[Vector2i(cx, cy)] = true
	# load newly needed chunks
	for cc in want.keys():
		if not _loaded.has(cc):
			_render_chunk(cc)
			_decorate_chunk(cc)
			_fog_chunk(cc)
			_loaded[cc] = true
	# unload chunks that drifted out of range (data is kept in `chunks`)
	for cc in _loaded.keys():
		if not want.has(cc):
			_erase_chunk(cc)
			_undecorate_chunk(cc)
			_unfog_chunk(cc)
			_loaded.erase(cc)

	# stream glowing-block lights for just the nearest chunks (perf)
	var want_l := {}
	for cy in range(center.y - LIGHT_RADIUS, center.y + LIGHT_RADIUS + 1):
		for cx in range(center.x - LIGHT_RADIUS, center.x + LIGHT_RADIUS + 1):
			want_l[Vector2i(cx, cy)] = true
	for cc in want_l.keys():
		if not _chunk_lights.has(cc):
			_build_chunk_lights(cc)
	for cc in _chunk_lights.keys():
		if not want_l.has(cc):
			_free_chunk_lights(cc)

func _build_chunk_lights(cc: Vector2i) -> void:
	var data := _get_chunk(cc)
	var arr: Array = []
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			var id := data[ly * CHUNK + lx]
			if Tiles.is_glowing(id):
				var lite := PointLight2D.new()
				lite.texture = Art.light_texture()
				lite.color = Tiles.glow_color(id)
				lite.energy = Tiles.glow_energy(id)
				lite.scale = Vector2(0.4, 0.4)
				lite.position = tile_to_world_center(Vector2i(ox + lx, oy + ly))
				add_child(lite)
				arr.append(lite)
	_chunk_lights[cc] = arr

func _free_chunk_lights(cc: Vector2i) -> void:
	for l in _chunk_lights.get(cc, []):
		if is_instance_valid(l):
			l.queue_free()
	_chunk_lights.erase(cc)

# ---------------------------------------------------------------------------
# Surface decorations + harvestable trees
# ---------------------------------------------------------------------------
func _rand01(a: int, salt: int) -> float:
	var h: int = (a * 73856093) ^ (salt * 19349663) ^ (Game.world_seed * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0x7fffffff) / 2147483647.0

func _tree_chance(biome: int) -> float:
	match biome:
		JUNGLE: return 0.16
		WASTES: return 0.11
		TUNDRA: return 0.06
		_: return 0.04   # dunes are sparse

func _biome_plant(biome: int, tx: int) -> int:
	match biome:
		TUNDRA: return Art.TUFT_TUNDRA
		DUNES: return Art.TUFT_DUNES
		JUNGLE: return Art.MUSHROOM if _rand01(tx, 3) < 0.3 else Art.TUFT_JUNGLE
		_: return Art.FLOWER if _rand01(tx, 3) < 0.25 else Art.TUFT_WASTES

func _decorate_chunk(cc: Vector2i) -> void:
	var oy := cc.y * CHUNK
	# only surface-band chunks can hold decorations
	if oy > 24 or oy + CHUNK < -24:
		return
	var ox := cc.x * CHUNK
	var cells: Array = []
	var trees: Array = []
	var last_tree_lx := -10
	for lx in CHUNK:
		var tx := ox + lx
		var surf_y := surface_tile_y(tx)
		var deco_y := surf_y - 1
		if deco_y < oy or deco_y >= oy + CHUNK:
			continue
		var biome := biome_at(tx)
		if _rand01(tx, 1) < _tree_chance(biome) and lx - last_tree_lx >= 3 and not _tree_removed.has(tx):
			_spawn_tree(tx, surf_y, biome, trees)
			last_tree_lx = lx
			continue
		var r := _rand01(tx, 2)
		var decor_id := -1
		if r < 0.40:
			decor_id = _biome_plant(biome, tx)
		elif r < 0.50:
			decor_id = Art.ROCK
		if decor_id >= 0:
			var cell := Vector2i(tx, deco_y)
			decor_map.set_cell(cell, Art.decor_source_id, Art.decor_atlas_coords(decor_id))
			cells.append(cell)
	_chunk_decor[cc] = cells
	_chunk_trees[cc] = trees

func _spawn_tree(tx: int, surf_y: int, biome: int, trees: Array) -> void:
	var occ: Array = []
	for ty in range(surf_y - 1, surf_y - 5, -1):
		occ.append(Vector2i(tx, ty))
	for ddx in [-1, 1]:
		occ.append(Vector2i(tx + ddx, surf_y - 3))
		occ.append(Vector2i(tx + ddx, surf_y - 4))
	var tr := AlienTree.new()
	tr.occupied = occ
	tr.drops = _tree_drops(biome)
	tr.harvest_time = 6.0
	tr.seed_v = tx ^ (Game.world_seed * 31)
	tr.setup(biome, Vector2(tx * TILE + TILE / 2.0, surf_y * TILE), tx)
	add_child(tr)
	tr.z_index = 1
	for c in occ:
		_tree_at[c] = tr
	trees.append(tr)

func _tree_drops(biome: int) -> Array:
	var drops: Array = [["wood", 2 + randi() % 3]]
	if biome == JUNGLE:
		drops.append(["biomass", 1 + randi() % 2])
	elif biome == TUNDRA:
		drops.append(["ice", 1])
	return drops

func _clear_decor(cell: Vector2i) -> void:
	# remove a surface decoration (grass tuft, rock, flower...) at this cell
	if decor_map.get_cell_source_id(cell) == -1:
		return
	decor_map.erase_cell(cell)
	var cc := chunk_of_tile(cell)
	if _chunk_decor.has(cc):
		_chunk_decor[cc].erase(cell)

func _undecorate_chunk(cc: Vector2i) -> void:
	for cell in _chunk_decor.get(cc, []):
		decor_map.erase_cell(cell)
	_chunk_decor.erase(cc)
	for tr in _chunk_trees.get(cc, []):
		if is_instance_valid(tr):
			for c in tr.occupied:
				if _tree_at.get(c) == tr:
					_tree_at.erase(c)
			tr.queue_free()
	_chunk_trees.erase(cc)

func tree_at(t: Vector2i) -> AlienTree:
	return _tree_at.get(t)

# ---------------------------------------------------------------------------
# Deployed stations + storage pods
# ---------------------------------------------------------------------------
func register_station(s) -> void:
	_stations.append(s)

func unregister_station(s) -> void:
	_stations.erase(s)

func register_pod(p) -> void:
	_pods.append(p)

func unregister_pod(p) -> void:
	_pods.erase(p)

func has_station_near(pos: Vector2, id: String) -> bool:
	for s in _stations:
		if is_instance_valid(s) and s.station_id == id and s.global_position.distance_to(pos) <= STATION_RANGE:
			return true
	return false

func pods_near(pos: Vector2) -> Array:
	var out := []
	for p in _pods:
		if is_instance_valid(p) and p.global_position.distance_to(pos) <= STORAGE_RANGE:
			out.append(p)
	return out

## Find a deployed station/pod whose body contains a world point (for dismantling).
func structure_at(pos: Vector2):
	for s in _stations:
		if is_instance_valid(s) and s.contains_point(pos):
			return s
	for p in _pods:
		if is_instance_valid(p) and p.contains_point(pos):
			return p
	return null

## Recover a deployed structure: its item (and a pod's contents) go to the
## player, then it plays its collapse animation and frees itself.
func dismantle(struct) -> void:
	var item_id := "storage_pod"
	if struct is Station:
		item_id = struct.station_id
	if struct is StoragePod:
		for slot in struct.slots:
			if slot != null:
				var left := Game.inventory.add(slot.id, slot.count)
				if left > 0:
					var pk := ItemPickup.new()
					pk.setup(slot.id, left, struct.global_position + Vector2(0, -12))
					add_child(pk)
		struct.slots.clear()
	Game.inventory.add(item_id, 1)
	struct.collapse_and_free()

func nearest_pod(pos: Vector2) -> StoragePod:
	var best: StoragePod = null
	var bd := STORAGE_RANGE
	for p in _pods:
		if is_instance_valid(p):
			var d: float = p.global_position.distance_to(pos)
			if d <= bd:
				bd = d
				best = p
	return best

## Place a station / storage pod at the bottom of tile `t` (sitting on the ground).
func spawn_structure(item_id: String, t: Vector2i) -> void:
	var pos := Vector2((t.x + 0.5) * TILE, (t.y + 1) * TILE)
	if item_id == "storage_pod":
		var p := StoragePod.new()
		p.global_position = pos
		add_child(p)
	else:
		var s := Station.new()
		s.station_id = item_id
		s.global_position = pos
		add_child(s)

func harvest_tree(tree: AlienTree, _t: Vector2i) -> void:
	_tree_removed[tree.column] = true
	for c in tree.occupied:
		if _tree_at.get(c) == tree:
			_tree_at.erase(c)
	var cc := chunk_of_tile(tree.occupied[0]) if not tree.occupied.is_empty() else Vector2i.ZERO
	if _chunk_trees.has(cc):
		_chunk_trees[cc].erase(tree)
	for d in tree.drops:
		var pk := ItemPickup.new()
		pk.setup(d[0], d[1], tree.global_position + Vector2(randf_range(-6, 6), -20))
		add_child(pk)
	tree.queue_free()

func _render_chunk(cc: Vector2i) -> void:
	var data := _get_chunk(cc)
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			var id := data[ly * CHUNK + lx]
			if id != Tiles.AIR:
				var tx := ox + lx
				var ty := oy + ly
				tilemap.set_cell(Vector2i(tx, ty), Art.atlas_source_id, Art.tile_atlas_coords(id, _tile_variant(tx, ty)))

func _tile_variant(tx: int, ty: int) -> int:
	var h: int = tx * 374761393 + ty * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h) % Art.TILE_VARIANTS

func _erase_chunk(cc: Vector2i) -> void:
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			tilemap.erase_cell(Vector2i(ox + lx, oy + ly))

# ---------------------------------------------------------------------------
# Tile access (generates chunks lazily)
# ---------------------------------------------------------------------------
func _get_chunk(cc: Vector2i) -> PackedInt32Array:
	var data = chunks.get(cc)
	if data == null:
		data = _generate_chunk(cc)
		chunks[cc] = data
	return data

func get_tile(t: Vector2i) -> int:
	var cc := chunk_of_tile(t)
	var data := _get_chunk(cc)
	var lx := t.x - cc.x * CHUNK
	var ly := t.y - cc.y * CHUNK
	return data[ly * CHUNK + lx]

func get_tile_at(world_pos: Vector2) -> int:
	return get_tile(world_to_tile(world_pos))

func is_solid_at(world_pos: Vector2) -> bool:
	return Tiles.is_solid(get_tile_at(world_pos))

## Change a tile and keep the rendered map in sync. Returns the previous id.
func set_tile(t: Vector2i, id: int) -> int:
	var cc := chunk_of_tile(t)
	var data := _get_chunk(cc)
	var lx := t.x - cc.x * CHUNK
	var ly := t.y - cc.y * CHUNK
	var prev: int = data[ly * CHUNK + lx]
	data[ly * CHUNK + lx] = id
	if _loaded.has(cc):
		if id == Tiles.AIR:
			tilemap.erase_cell(t)
			_clear_decor(t + Vector2i(0, -1))   # destroy a decoration resting on the mined block
		else:
			tilemap.set_cell(t, Art.atlas_source_id, Art.tile_atlas_coords(id, _tile_variant(t.x, t.y)))
			_clear_decor(t)                     # a placed block covers any decoration here
	# refresh block lights for this chunk if it is in the lit zone
	if _chunk_lights.has(cc):
		_free_chunk_lights(cc)
		_build_chunk_lights(cc)
	return prev

# ---------------------------------------------------------------------------
# Procedural generation
# ---------------------------------------------------------------------------
func surface_height(tx: int) -> int:
	var n := _height_noise.get_noise_1d(float(tx))
	var n2 := _height_noise.get_noise_1d(float(tx) * 0.35 + 5000.0) * 0.5
	return SURFACE_BASE + int(round((n + n2) * SURFACE_AMP))

func biome_at(tx: int) -> int:
	var b := _biome_noise.get_noise_1d(float(tx))
	if b < -0.45:
		return TUNDRA
	elif b < -0.1:
		return DUNES
	elif b < 0.3:
		return WASTES
	return JUNGLE

func _surface_tile(biome: int) -> int:
	match biome:
		TUNDRA: return Tiles.ICE
		DUNES: return Tiles.SAND
		JUNGLE: return Tiles.JUNGLE
		_: return Tiles.GRASS

func _soil_tile(biome: int) -> int:
	match biome:
		DUNES: return Tiles.SAND
		TUNDRA: return Tiles.DIRT
		_: return Tiles.DIRT

func _generate_chunk(cc: Vector2i) -> PackedInt32Array:
	var data := PackedInt32Array()
	data.resize(CHUNK * CHUNK)
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for lx in CHUNK:
		var tx := ox + lx
		var surf := surface_height(tx)
		var biome := biome_at(tx)
		for ly in CHUNK:
			var ty := oy + ly
			data[ly * CHUNK + lx] = _gen_tile(tx, ty, surf, biome)
	return data

func _gen_tile(tx: int, ty: int, surf: int, biome: int) -> int:
	if ty < surf:
		return Tiles.AIR                     # sky / open air
	if ty == surf:
		return _surface_tile(biome)          # top crust
	if ty <= surf + SOIL_DEPTH:
		# carve the occasional shallow cave but keep just below the crust solid
		if ty > surf + 2 and _cave_noise.get_noise_2d(float(tx), float(ty)) > 0.5:
			return Tiles.AIR
		return _soil_tile(biome)

	# underground stone layer
	if _cave_noise.get_noise_2d(float(tx), float(ty)) > 0.45:
		return Tiles.AIR                     # caves

	var stone := Tiles.DARKROCK if ty > DEEP_Y else Tiles.STONE
	# ores, deepest/rarest first
	if ty > 150 and _energy_noise.get_noise_2d(float(tx) + 7000.0, float(ty)) > 0.82:
		return Tiles.EXOTIC                  # tier-3, only very deep
	if ty > 60 and _energy_noise.get_noise_2d(float(tx), float(ty)) > 0.8:
		return Tiles.ENERGY
	if ty > 20 and _crystal_noise.get_noise_2d(float(tx), float(ty)) > 0.78:
		return Tiles.CRYSTAL
	if ty > 4 and _metal_noise.get_noise_2d(float(tx), float(ty)) > 0.72:
		return Tiles.METAL
	return stone

## Scan downward to find the first solid surface tile-y at column tx (for spawns).
func surface_tile_y(tx: int) -> int:
	var start := surface_height(tx) - 2
	for ty in range(start, start + 40):
		if Tiles.is_solid(get_tile(Vector2i(tx, ty))):
			return ty
	return surface_height(tx)
