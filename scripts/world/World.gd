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
var water_map: TileMapLayer         # liquid render layer (cellular-automaton water)
var fog_map: TileMapLayer           # fog of war over unexplored underground

# --- liquid simulation ---
const WATER_MAX := 1.0              # a cell is "full" at 1.0
const WATER_MIN := 0.02            # below this a cell is treated as empty
const WATER_FLOW := 0.5            # how fast cells equalise horizontally (0..1)
const WATER_SIM_RADIUS := 56       # tiles around the player that actively simulate
const WATER_TICK := 0.05           # seconds between simulation steps
var _water := {}                    # Vector2i -> float fill (0..1); absent = dry
var _water_active := {}             # Vector2i -> true (cells to simulate next step)
var _watered_chunks := {}           # Vector2i -> true (natural water already seeded)
var _water_accum := 0.0
var _fog := {}                      # Vector2i tile -> fog level (-1 cleared .. FOG_LEVELS-1 solid)
var _mapped := {}                   # Vector2i tile -> true (revealed on the minimap)
var _last_reveal := Vector2i(999999, 999999)
var chunks := {}                    # Vector2i -> PackedInt32Array
var _loaded := {}                   # Vector2i -> true (currently rendered)
var _chunk_lights := {}             # Vector2i -> Array[PointLight2D]
var _chunk_decor := {}              # Vector2i -> Array[Vector2i] decor cells
var _cave_glow := {}                # Vector2i decor cell -> Color (glowing cave flora)
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
var _cave_noise := FastNoiseLite.new()      # shallow pockets just under the crust
var _cavern_noise := FastNoiseLite.new()    # large open chambers, deeper down
var _tunnel_a := FastNoiseLite.new()        # winding worm tunnels (iso-surface A)
var _tunnel_b := FastNoiseLite.new()        # winding worm tunnels (iso-surface B)
var _ore_noise := FastNoiseLite.new()       # where ore appears at all
var _ore_kind_noise := FastNoiseLite.new()  # wobbles the depth->quality bands

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
	water_map = TileMapLayer.new()
	water_map.tile_set = Art.water_tileset
	water_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	water_map.z_index = 1               # in front of the player, so you look submerged
	add_child(water_map)
	fog_map = TileMapLayer.new()
	fog_map.tile_set = Art.fog_tileset
	fog_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fog_map.z_index = 3                 # clouds terrain + creatures until explored
	fog_map.light_mask = 0              # lights never reveal the fog; it stays black
	add_child(fog_map)

func _setup_noise() -> void:
	var s := Game.world_seed
	for n in [_height_noise, _biome_noise, _cave_noise, _cavern_noise, _tunnel_a, _tunnel_b, _ore_noise, _ore_kind_noise]:
		n.noise_type = FastNoiseLite.TYPE_PERLIN
	_height_noise.seed = s
	_height_noise.frequency = 0.018
	_biome_noise.seed = s + 17
	_biome_noise.frequency = 0.0004    # very low -> sprawling, continent-sized biomes
	_cave_noise.seed = s + 31
	_cave_noise.frequency = 0.07
	_cavern_noise.seed = s + 131
	_cavern_noise.frequency = 0.026          # big rooms
	_tunnel_a.seed = s + 211
	_tunnel_a.frequency = 0.034              # long sweeping corridors
	_tunnel_b.seed = s + 307
	_tunnel_b.frequency = 0.038
	_ore_noise.seed = s + 53
	_ore_noise.frequency = 0.12
	_ore_kind_noise.seed = s + 71
	_ore_kind_noise.frequency = 0.05

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
func _physics_process(dt: float) -> void:
	if Game.player == null:
		return
	_tick_water(dt)
	var ptile := world_to_tile(Game.player.global_position)
	if ptile != _last_reveal:
		_last_reveal = ptile
		_reveal_around(ptile)
	var center := chunk_of_tile(ptile)
	if center == _last_center:
		return
	_last_center = center
	_stream(center)

const REVEAL_CLEAR := 3         ## tiles fully cleared of fog around the player
const REVEAL_FADE := 4          ## extra tiles over which the fog fades back to solid
const MAP_RADIUS := 26          ## how far the minimap reveals around the player

# ---------------------------------------------------------------------------
# Liquid simulation (Terraria-style cellular-automaton water)
#
# Each cell holds a fill fraction 0..1. Every tick, active cells flow DOWN into
# any open space below, then equalise sideways with open horizontal neighbours
# toward their shared average (conservative + non-oscillating). Cells settle and
# drop out of the active set, so a still pool costs nothing. Only cells within
# WATER_SIM_RADIUS of the player simulate; the rest stay as frozen data.
# ---------------------------------------------------------------------------
func _tick_water(dt: float) -> void:
	if _water_active.is_empty():
		return
	_water_accum += dt
	if _water_accum < WATER_TICK:
		return
	_water_accum = 0.0
	_sim_water_step()

func water_at(t: Vector2i) -> float:
	return _water.get(t, 0.0)

## True if a tile is filled enough to swim/be submerged in.
func is_water_at(p: Vector2) -> bool:
	return _water.get(world_to_tile(p), 0.0) > 0.35

func _water_solid(t: Vector2i) -> bool:
	# water can't enter solid blocks (uses generated data, bounded by sim radius)
	return Tiles.is_solid(get_tile(t))

## Add liquid to a cell (used by the Hydro Cell tool and natural springs).
func add_water(t: Vector2i, amount: float) -> void:
	if _water_solid(t):
		return
	_water[t] = minf(WATER_MAX, _water.get(t, 0.0) + amount)
	_wake_water(t)
	_render_water_cell(t)
	_render_water_cell(t + Vector2i(0, -1))

## Remove liquid from a cell (the particle gun "drains" water). Returns removed.
func drain_water(t: Vector2i, amount: float) -> float:
	var have: float = _water.get(t, 0.0)
	if have <= 0.0:
		return 0.0
	var taken := minf(have, amount)
	var left := have - taken
	if left <= WATER_MIN:
		_water.erase(t)
		left = 0.0
	else:
		_water[t] = left
	# neighbours may now flow into the gap
	_wake_water(t)
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
		_wake_water(t + o)
	_render_water_cell(t)
	_render_water_cell(t + Vector2i(0, -1))
	return taken

func _wake_water(t: Vector2i) -> void:
	if _water.get(t, 0.0) > 0.0:
		_water_active[t] = true

## A block was placed into a water cell: shove its liquid into open neighbours.
func _displace_water(t: Vector2i) -> void:
	var amt: float = _water.get(t, 0.0)
	_water.erase(t)
	water_map.erase_cell(t)
	for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
		if amt <= 0.0:
			break
		var n: Vector2i = t + o
		if _water_solid(n):
			continue
		var space: float = WATER_MAX - _water.get(n, 0.0)
		if space <= 0.0:
			continue
		var move := minf(amt, space)
		_water[n] = _water.get(n, 0.0) + move
		amt -= move
		_wake_water(n)
		_render_water_cell(n)

func _sim_water_step() -> void:
	var pc := world_to_tile(Game.player.global_position)
	var cells: Array = _water_active.keys()
	_water_active = {}
	var changed := {}
	for cell in cells:
		var amt: float = _water.get(cell, 0.0)
		if amt <= 0.0:
			continue
		# freeze (but keep) cells far from the player
		if absi(cell.x - pc.x) > WATER_SIM_RADIUS or absi(cell.y - pc.y) > WATER_SIM_RADIUS:
			_water_active[cell] = true
			continue
		var moved := false
		# --- flow DOWN ---
		var below := Vector2i(cell.x, cell.y + 1)
		if not _water_solid(below):
			var bw: float = _water.get(below, 0.0)
			var space := WATER_MAX - bw
			if space > 0.001:
				var move := minf(amt, space)
				amt -= move
				_water[below] = bw + move
				changed[below] = true
				_water_active[below] = true
				moved = true
		# --- equalise SIDEWAYS toward the open-neighbour average ---
		if amt > WATER_MIN:
			var opens: Array = []
			for dx in [-1, 1]:
				var s := Vector2i(cell.x + dx, cell.y)
				if not _water_solid(s):
					opens.append(s)
			if not opens.is_empty():
				var total := amt
				var imbalance := false
				for s in opens:
					var sw: float = _water.get(s, 0.0)
					total += sw
					if absf(sw - amt) > WATER_MIN:
						imbalance = true
				if imbalance:
					var avg := total / float(opens.size() + 1)
					amt += (avg - amt) * WATER_FLOW
					for s in opens:
						var sw2: float = _water.get(s, 0.0)
						_water[s] = sw2 + (avg - sw2) * WATER_FLOW
						changed[s] = true
						_water_active[s] = true
					moved = true
		# write the cell back
		if amt <= WATER_MIN:
			if _water.has(cell):
				_water.erase(cell)
			changed[cell] = true
		else:
			_water[cell] = amt
			changed[cell] = true
			if moved:
				_water_active[cell] = true
	# repaint everything that changed (plus the cell above, whose surface may flip)
	for c in changed:
		_render_water_cell(c)
		_render_water_cell(c + Vector2i(0, -1))

func _render_water_cell(t: Vector2i) -> void:
	# only draw water in currently loaded chunks
	if not _loaded.has(chunk_of_tile(t)):
		return
	var amt: float = _water.get(t, 0.0)
	if amt <= WATER_MIN:
		water_map.erase_cell(t)
		return
	# Cells with water above are interior body water -> full, line-free tile.
	# Surface cells (dry above) use a partial tile (1..LEVELS-1) so they show the
	# bright surface line at their fill height.
	var lvl: int
	if _water.get(Vector2i(t.x, t.y - 1), 0.0) > WATER_MIN:
		lvl = Art.WATER_LEVELS
	else:
		lvl = clampi(int(ceil(amt * (Art.WATER_LEVELS - 1))), 1, Art.WATER_LEVELS - 1)
	water_map.set_cell(t, Art.water_source_id, Art.water_atlas_coords(lvl))

func _render_water_chunk(cc: Vector2i) -> void:
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			var t := Vector2i(ox + lx, oy + ly)
			if _water.get(t, 0.0) > WATER_MIN:
				_render_water_cell(t)

func _unrender_water_chunk(cc: Vector2i) -> void:
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for ly in CHUNK:
		for lx in CHUNK:
			water_map.erase_cell(Vector2i(ox + lx, oy + ly))

## Seed natural springs/pools the first time a chunk is shown: water collects in
## cave pockets that have a solid floor, deeper down, gated by noise so it's rare.
func _seed_water_chunk(cc: Vector2i) -> void:
	if _watered_chunks.has(cc):
		return
	_watered_chunks[cc] = true
	var data := _get_chunk(cc)
	var ox := cc.x * CHUNK
	var oy := cc.y * CHUNK
	for lx in CHUNK:
		var tx := ox + lx
		var surf := surface_height(tx)
		for ly in CHUNK:
			var ty := oy + ly
			if ty < surf + 6:
				continue                         # leave the surface dry
			if data[ly * CHUNK + lx] != Tiles.AIR:
				continue                         # only fill cave air
			# needs a solid floor so it actually pools instead of draining
			if not Tiles.is_solid(get_tile(Vector2i(tx, ty + 1))):
				continue
			# aquifer noise: sparse pockets of liquid
			if _ore_kind_noise.get_noise_2d(float(tx) * 0.6 + 1000.0, float(ty) * 0.6) > 0.5:
				_water[Vector2i(tx, ty)] = WATER_MAX
				_water_active[Vector2i(tx, ty)] = true

func _reveal_around(c: Vector2i) -> void:
	# burn the in-world fog away in a soft circle around the player: fully clear
	# within REVEAL_CLEAR, then graded back to solid over REVEAL_FADE tiles
	var r := REVEAL_CLEAR + REVEAL_FADE
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d2 := dx * dx + dy * dy
			if d2 > r * r:
				continue
			var t := Vector2i(c.x + dx, c.y + dy)
			if t.y <= surface_height(t.x) + 2:
				continue
			var d := sqrt(float(d2))
			var target := -1
			if d > REVEAL_CLEAR:
				var f := (d - REVEAL_CLEAR) / float(REVEAL_FADE)   # 0..1 across the ring
				target = clampi(int(floor(f * Art.FOG_LEVELS)), 0, Art.FOG_LEVELS - 1)
			if target < _fog_level(t):                              # only ever clear, never re-fog
				_fog[t] = target
				_apply_fog(t)
	# reveal a wider area on the minimap (everywhere, stays revealed)
	for dy in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for dx in range(-MAP_RADIUS, MAP_RADIUS + 1):
			if dx * dx + dy * dy <= MAP_RADIUS * MAP_RADIUS:
				_mapped[Vector2i(c.x + dx, c.y + dy)] = true

## Fog level for a tile: a stored (revealed) value, else the default that fades
## in from the surface ceiling so the top edge of the fog isn't a hard line.
func _fog_level(t: Vector2i) -> int:
	if _fog.has(t):
		return _fog[t]
	var top := surface_height(t.x) + 3
	if t.y < top:
		return -1
	return clampi(t.y - top, 0, Art.FOG_LEVELS - 1)

func _apply_fog(t: Vector2i) -> void:
	var lvl := _fog_level(t)
	if lvl < 0:
		fog_map.erase_cell(t)
	else:
		fog_map.set_cell(t, Art.fog_source_id, Art.fog_atlas_coords(lvl))

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
			# stored level if revealed, else fade in from the ceiling
			var lvl: int = _fog.get(t, clampi(ty - fog_top, 0, Art.FOG_LEVELS - 1))
			if lvl >= 0:
				fog_map.set_cell(t, Art.fog_source_id, Art.fog_atlas_coords(lvl))

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
			_cave_decorate_chunk(cc)
			_fog_chunk(cc)
			_seed_water_chunk(cc)
			_render_water_chunk(cc)
			_loaded[cc] = true
	# unload chunks that drifted out of range (data is kept in `chunks`)
	for cc in _loaded.keys():
		if not want.has(cc):
			_erase_chunk(cc)
			_undecorate_chunk(cc)
			_unfog_chunk(cc)
			_unrender_water_chunk(cc)
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
	# glowing cave flora in this chunk casts a soft local light too
	for cell in _cave_glow:
		if chunk_of_tile(cell) == cc:
			var gl := PointLight2D.new()
			gl.texture = Art.light_texture()
			gl.color = _cave_glow[cell]
			gl.energy = 0.7
			gl.scale = Vector2(0.28, 0.28)
			gl.position = tile_to_world_center(cell)
			add_child(gl)
			arr.append(gl)
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

## Dress the underground: cave flora on floors (glowing mushrooms, crystal
## clusters, stalagmites, rocks) and stalactites on ceilings, so caverns feel
## alive instead of empty rock. Glowing pieces also seed a point light.
func _cave_decorate_chunk(cc: Vector2i) -> void:
	var oy := cc.y * CHUNK
	if oy + CHUNK <= 8:
		return                                   # nothing to decorate up in the sky
	var ox := cc.x * CHUNK
	var cells: Array = _chunk_decor.get(cc, [])
	for lx in CHUNK:
		var tx := ox + lx
		var surf := surface_height(tx)
		for ly in CHUNK:
			var ty := oy + ly
			if ty <= surf + SOIL_DEPTH:
				continue                         # only the real cave layer
			if get_tile(Vector2i(tx, ty)) != Tiles.AIR:
				continue
			var cell := Vector2i(tx, ty)
			var floor_solid := Tiles.is_solid(get_tile(Vector2i(tx, ty + 1)))
			var ceil_solid := Tiles.is_solid(get_tile(Vector2i(tx, ty - 1)))
			var r := _rand01(tx * 911 + ty, 7)
			var decor_id := -1
			if floor_solid and not ceil_solid:
				if r < 0.025:
					decor_id = Art.CRYSTAL_CLUSTER
				elif r < 0.075:
					decor_id = Art.GLOWSHROOM
				elif r < 0.17:
					decor_id = Art.STALAGMITE
				elif r < 0.25:
					decor_id = Art.ROCK
			elif ceil_solid and not floor_solid and r < 0.12:
				decor_id = Art.STALACTITE
			if decor_id < 0:
				continue
			decor_map.set_cell(cell, Art.decor_source_id, Art.decor_atlas_coords(decor_id))
			cells.append(cell)
			var glow: Color = Art.decor_glow(decor_id)
			if glow.a > 0.0:
				_cave_glow[cell] = glow
	_chunk_decor[cc] = cells

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
	# remove a surface/cave decoration (tuft, rock, mushroom, crystal...) here
	if decor_map.get_cell_source_id(cell) == -1:
		return
	decor_map.erase_cell(cell)
	_cave_glow.erase(cell)
	var cc := chunk_of_tile(cell)
	if _chunk_decor.has(cc):
		_chunk_decor[cc].erase(cell)

func _undecorate_chunk(cc: Vector2i) -> void:
	for cell in _chunk_decor.get(cc, []):
		decor_map.erase_cell(cell)
		_cave_glow.erase(cell)
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
			# liquid above/beside the newly opened cell can now flow into it
			for o in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				_wake_water(t + o)
		else:
			tilemap.set_cell(t, Art.atlas_source_id, Art.tile_atlas_coords(id, _tile_variant(t.x, t.y)))
			_clear_decor(t)                     # a placed block covers any decoration here
			# a block placed in liquid displaces it; push it to neighbours
			if _water.get(t, 0.0) > 0.0:
				_displace_water(t)
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

	# underground stone layer — winding tunnels + open caverns
	if _is_cave(tx, ty, surf):
		return Tiles.AIR

	var stone := Tiles.DARKROCK if ty > DEEP_Y else Tiles.STONE
	var ore := _ore_at(tx, ty)
	return ore if ore != Tiles.AIR else stone

## Carve the underground into something worth exploring: sweeping worm tunnels
## (the intersection of two near-zero noise iso-surfaces traces connected 1-D
## corridors) plus large open caverns that grow more common with depth.
func _is_cave(tx: int, ty: int, surf: int) -> bool:
	var depth := float(ty - surf)
	var df := clampf(depth / 220.0, 0.0, 1.0)        # 0 near surface, 1 deep
	# winding corridors: both fields near zero at once -> a thin 1-D path
	var hw := 0.055 + 0.045 * df                       # tunnels widen with depth
	var a := _tunnel_a.get_noise_2d(float(tx), float(ty))
	var b := _tunnel_b.get_noise_2d(float(tx), float(ty))
	if absf(a) < hw and absf(b) < hw:
		return true
	# big chambers: easier threshold deeper, so the depths open right up
	var cav := _cavern_noise.get_noise_2d(float(tx), float(ty))
	if cav > lerpf(0.50, 0.30, df):
		return true
	return false

## Decide which ore (if any) is embedded in the stone at this tile.
## Ore gets *better* the deeper you go (Ferralite → Vyrite → Ion → Exotic) but
## also *rarer* — the presence threshold climbs with depth, so deep veins are
## sparser even though what you find there is worth more.
func _ore_at(tx: int, ty: int) -> int:
	if ty <= 4:
		return Tiles.AIR                     # no ore right under the surface
	var depth := float(ty)
	# rarity: ~9% of stone near the top can hold ore, thinning toward ~2% deep
	# (the noise tops out near 0.6, so these thresholds stay within its range)
	var presence := lerpf(0.25, 0.38, clampf((depth - 4.0) / 360.0, 0.0, 1.0))
	if _ore_noise.get_noise_2d(float(tx), float(ty)) < presence:
		return Tiles.AIR
	# quality by depth, with a noisy wobble so the bands aren't flat cut-offs
	var d := depth + _ore_kind_noise.get_noise_2d(float(tx), float(ty)) * 22.0
	if d > 170.0:
		return Tiles.EXOTIC                  # tier-3, only very deep
	if d > 75.0:
		return Tiles.ENERGY                  # tier-2
	if d > 28.0:
		return Tiles.CRYSTAL                 # tier-1
	return Tiles.METAL                       # tier-0, shallow

## Scan downward to find the first solid surface tile-y at column tx (for spawns).
func surface_tile_y(tx: int) -> int:
	var start := surface_height(tx) - 2
	for ty in range(start, start + 40):
		if Tiles.is_solid(get_tile(Vector2i(tx, ty))):
			return ty
	return surface_height(tx)
