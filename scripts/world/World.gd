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
var chunks := {}                    # Vector2i -> PackedInt32Array
var _loaded := {}                   # Vector2i -> true (currently rendered)
var _chunk_lights := {}             # Vector2i -> Array[PointLight2D]
var _last_center := Vector2i(999999, 999999)

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
	var center := chunk_of_tile(world_to_tile(Game.player.global_position))
	if center == _last_center:
		return
	_last_center = center
	_stream(center)

func _stream(center: Vector2i) -> void:
	var want := {}
	for cy in range(center.y - LOAD_RADIUS, center.y + LOAD_RADIUS + 1):
		for cx in range(center.x - LOAD_RADIUS, center.x + LOAD_RADIUS + 1):
			want[Vector2i(cx, cy)] = true
	# load newly needed chunks
	for cc in want.keys():
		if not _loaded.has(cc):
			_render_chunk(cc)
			_loaded[cc] = true
	# unload chunks that drifted out of range (data is kept in `chunks`)
	for cc in _loaded.keys():
		if not want.has(cc):
			_erase_chunk(cc)
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

func _render_chunk(cc: Vector2i) -> void:
	var data := _get_chunk(cc)
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			var id := data[ly * CHUNK + lx]
			if id != Tiles.AIR:
				tilemap.set_cell(Vector2i(ox + lx, oy + ly), Art.atlas_source_id, Art.tile_atlas_coords(id))

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
		else:
			tilemap.set_cell(t, Art.atlas_source_id, Art.tile_atlas_coords(id))
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
