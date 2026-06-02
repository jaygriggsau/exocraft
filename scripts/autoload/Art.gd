extends Node
## Runtime pixel-art factory.
##
## Everything visual in Exocraft is generated here as small RGBA images so the
## project ships with zero binary assets and stays fully deterministic. Swap any
## of these out for hand-drawn PNGs later without touching gameplay code.

const TS := 16  ## tile size in pixels
const TILE_VARIANTS := 4  ## per-tile texture variants so terrain isn't uniform

var tileset: TileSet
var atlas_source_id := 0

var _tile_images := {}   # tile id -> Array[Image] (one per variant)
var _item_icons := {}    # item id -> ImageTexture
var _sprites := {}       # name   -> ImageTexture
var _light_tex: ImageTexture
var _player_frames: SpriteFrames
var _creature_frames := {}       # species name -> SpriteFrames
var decor_tileset: TileSet
var decor_source_id := 0
var fog_tileset: TileSet
var fog_source_id := 0
const FOG_VARIANTS := 3
var _tree_cache := {}    # "biome_seed" -> ImageTexture (each tree is unique)

# decor tile ids (atlas columns in the decor tileset)
enum { TUFT_WASTES, TUFT_TUNDRA, TUFT_DUNES, TUFT_JUNGLE, ROCK, FLOWER, MUSHROOM }
const DECOR_COUNT := 7

func _ready() -> void:
	_build_tile_images()
	_build_tileset()
	_build_item_icons()
	_build_sprites()
	_build_light_texture()
	_build_player_frames()
	_build_decor_tileset()
	_build_fog_tileset()
	_build_creature_frames()

# ---------------------------------------------------------------------------
# Small drawing helpers
# ---------------------------------------------------------------------------
func _new_image(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

func _vary(c: Color, rng: RandomNumberGenerator, amt: float) -> Color:
	var d := rng.randf_range(-amt, amt)
	return Color(
		clampf(c.r + d, 0.0, 1.0),
		clampf(c.g + d, 0.0, 1.0),
		clampf(c.b + d, 0.0, 1.0),
		c.a)

func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if xx >= 0 and yy >= 0 and xx < img.get_width() and yy < img.get_height():
				img.set_pixel(xx, yy, c)

# ---------------------------------------------------------------------------
# Tiles
# ---------------------------------------------------------------------------
func _build_tile_images() -> void:
	for id in Tiles.ids():
		var variants: Array = []
		for v in TILE_VARIANTS:
			variants.append(_make_tile_image(id, v))
		_tile_images[id] = variants

func _make_tile_image(id: int, variant: int) -> Image:
	var d = Tiles.def(id)
	var img := _new_image(TS, TS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + id * 101 + variant * 37
	var style: String = d.style
	var base: Color = d.base

	# Speckled base fill for every style.
	for y in TS:
		for x in TS:
			img.set_pixel(x, y, _vary(base, rng, 0.05))

	match style:
		"grass":
			# Colour the top band like alien turf, with a ragged edge.
			var top: Color = d.top
			for x in TS:
				var h := 3 + (rng.randi() % 2)
				for y in h:
					img.set_pixel(x, y, _vary(top, rng, 0.08))
				# a couple of brighter blades poking down
				if rng.randf() < 0.25:
					img.set_pixel(x, h, top.lightened(0.1))
		"ore":
			# Stone base with clustered glowing mineral veins.
			var ore: Color = d.ore
			var clusters := 3 + (rng.randi() % 3)
			for c in clusters:
				var cx := rng.randi_range(2, TS - 3)
				var cy := rng.randi_range(2, TS - 3)
				var n := 2 + (rng.randi() % 4)
				for i in n:
					var px := clampi(cx + rng.randi_range(-1, 1), 0, TS - 1)
					var py := clampi(cy + rng.randi_range(-1, 1), 0, TS - 1)
					img.set_pixel(px, py, _vary(ore, rng, 0.06))
				if d.get("glow", false):
					img.set_pixel(cx, cy, ore.lightened(0.35))
		"plating":
			# Metallic panel with bevelled edge + rivets.
			var ac: Color = d.accent
			_rect(img, 0, 0, TS, 1, ac.lightened(0.1))
			_rect(img, 0, 0, 1, TS, ac.lightened(0.1))
			_rect(img, 0, TS - 1, TS, 1, base.darkened(0.3))
			_rect(img, TS - 1, 0, 1, TS, base.darkened(0.3))
			img.set_pixel(2, 2, ac)
			img.set_pixel(TS - 3, 2, ac)
			img.set_pixel(2, TS - 3, ac)
			img.set_pixel(TS - 3, TS - 3, ac)
			_rect(img, 4, TS / 2, TS - 8, 1, ac.darkened(0.2))
		"neon":
			# Dark glass with a bright neon frame.
			var nc: Color = d.accent
			_rect(img, 0, 0, TS, 1, nc)
			_rect(img, 0, TS - 1, TS, 1, nc)
			_rect(img, 0, 0, 1, TS, nc)
			_rect(img, TS - 1, 0, 1, TS, nc)
			img.set_pixel(TS / 2, TS / 2, nc.lightened(0.3))
		_:
			# "block" / "soil": subtle depth shade, plus per-variant pebbles and
			# cracks so neighbouring blocks of the same type don't look identical.
			for y in TS:
				for x in TS:
					if x + y > TS + 6:
						img.set_pixel(x, y, _vary(base.darkened(0.12), rng, 0.04))
			for f in 2 + rng.randi() % 3:
				var px := rng.randi_range(2, TS - 3)
				var py := rng.randi_range(2, TS - 3)
				var pc := base.lightened(0.18) if rng.randf() < 0.5 else base.darkened(0.24)
				img.set_pixel(px, py, pc)
				img.set_pixel(px + 1, py, pc)
				img.set_pixel(px, py + 1, _vary(pc, rng, 0.05))
			if rng.randf() < 0.5:
				var cx := rng.randi_range(3, TS - 4)
				var cy := rng.randi_range(2, TS - 6)
				var cl := base.darkened(0.32)
				for k in 2 + rng.randi() % 3:
					img.set_pixel(clampi(cx + rng.randi_range(-1, 1), 0, TS - 1), clampi(cy + k, 0, TS - 1), cl)
	return img

func _build_tileset() -> void:
	var maxid := Tiles.max_id()
	# atlas: one column per tile id, one row per variant
	var atlas := _new_image((maxid + 1) * TS, TILE_VARIANTS * TS)
	for id in Tiles.ids():
		for v in TILE_VARIANTS:
			atlas.blit_rect(_tile_images[id][v], Rect2i(0, 0, TS, TS), Vector2i(id * TS, v * TS))
	var tex := ImageTexture.create_from_image(atlas)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TS, TS)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	# Occlusion layer so every solid block casts 2D light shadows.
	ts.add_occlusion_layer()

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TS, TS)
	# Attach the source first so TileData picks up the tileset's physics +
	# occlusion layers before we start adding polygons.
	atlas_source_id = ts.add_source(src, 0)

	var half := float(TS) / 2.0
	var square := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	var occ := OccluderPolygon2D.new()
	occ.polygon = square

	for id in Tiles.ids():
		for v in TILE_VARIANTS:
			var coord := Vector2i(id, v)
			src.create_tile(coord)
			var td := src.get_tile_data(coord, 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, square)
			td.set_occluder(0, occ)

	tileset = ts

func tile_atlas_coords(id: int, variant: int = 0) -> Vector2i:
	return Vector2i(id, variant)

# ---------------------------------------------------------------------------
# Item icons
# ---------------------------------------------------------------------------
func _build_item_icons() -> void:
	for item_id in ItemDB.ITEMS.keys():
		_item_icons[item_id] = ImageTexture.create_from_image(_make_item_icon(item_id))

func _make_item_icon(item_id: String) -> Image:
	var d = ItemDB.get_item(item_id)
	# Block items just reuse their tile artwork (first variant).
	if d.place_tile >= 0:
		return _tile_images[d.place_tile][0]

	var img := _new_image(TS, TS)
	var c: Color = d.color
	match item_id:
		"pickaxe":
			# Particle gun: body, barrel and a glowing emitter tip.
			_rect(img, 3, 7, 7, 4, Color("4a4e6b"))     # body
			_rect(img, 4, 11, 3, 3, Color("3a3e5b"))    # grip
			_rect(img, 10, 8, 3, 2, Color("6f74a0"))    # barrel
			_rect(img, 13, 7, 1, 4, c)                  # emitter
			img.set_pixel(13, 8, c.lightened(0.5))
			_rect(img, 5, 8, 2, 2, c)                   # power cell
		"blaster":
			# Side-on pistol shape.
			_rect(img, 3, 6, 9, 3, Color("4a4e6b"))
			_rect(img, 11, 6, 2, 2, c)
			_rect(img, 4, 9, 3, 4, Color("3a3e5b"))
			img.set_pixel(12, 6, c.lightened(0.4))
		"med_cell":
			# Vial with a cross.
			_rect(img, 5, 3, 6, 10, Color("203040"))
			_rect(img, 6, 6, 4, 6, c)
			_rect(img, 7, 4, 2, 8, c.lightened(0.2))
			_rect(img, 6, 7, 4, 1, Color.WHITE)
			_rect(img, 7, 6, 2, 3, Color.WHITE)
		_:
			# Generic material: a little faceted nugget.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(item_id)
			for i in 26:
				var x := rng.randi_range(4, 11)
				var y := rng.randi_range(4, 11)
				img.set_pixel(x, y, _vary(c, rng, 0.12))
			img.set_pixel(7, 6, c.lightened(0.4))
	return img

func item_icon(item_id: String) -> Texture2D:
	return _item_icons.get(item_id)

# ---------------------------------------------------------------------------
# Entity sprites
# ---------------------------------------------------------------------------
func _build_sprites() -> void:
	_sprites["player"] = ImageTexture.create_from_image(_make_player())
	_sprites["workbench"] = ImageTexture.create_from_image(_make_workbench())
	_sprites["fabricator"] = ImageTexture.create_from_image(_make_fabricator())
	_sprites["synthesizer"] = ImageTexture.create_from_image(_make_synthesizer())
	_sprites["storage_pod"] = ImageTexture.create_from_image(_make_pod())
	_sprites["bolt"] = ImageTexture.create_from_image(_make_bolt())
	_sprites["star"] = ImageTexture.create_from_image(_make_starfield())
	_sprites["sun"] = ImageTexture.create_from_image(_make_disc(Color("ffe8a8"), Color("ff9a3a")))
	_sprites["moon"] = ImageTexture.create_from_image(_make_disc(Color("dfe6ff"), Color("8f9ad0")))

func _make_player() -> Image:
	return _draw_player(0, 3, 7, 7, 7, 0, 0, false)

## Draws one 12x22 frame of the cyber-suited explorer. Legs and arms are
## parameterised so the same routine produces every animation pose:
##   dy        : vertical body bob
##   lx_l/lh_l : left leg x + height (shorter = lifted)
##   lx_r/lh_r : right leg x + height
##   arm_l/arm_r : per-arm vertical swing offset
##   arms_up   : raised arms (jump / fall)
func _draw_player(dy: int, lx_l: int, lh_l: int, lx_r: int, lh_r: int, arm_l: int, arm_r: int, arms_up: bool) -> Image:
	var img := _new_image(12, 22)
	var suit := Color("353a5c")
	var suit_d := Color("23263f")
	var visor := Color("2dffff")
	var trim := Color("ff2bd6")
	var by := dy
	_rect(img, 3, by, 6, 6, suit)              # head
	_rect(img, 4, by + 2, 5, 2, visor)         # visor
	_rect(img, 3, by + 6, 6, 9, suit)          # torso
	_rect(img, 3, by + 6, 6, 1, trim)          # collar
	_rect(img, 5, by + 9, 2, 2, trim)          # chest core
	if arms_up:
		_rect(img, 1, by + 4, 2, 5, suit_d)
		_rect(img, 9, by + 4, 2, 5, suit_d)
	else:
		_rect(img, 1, by + 7 + arm_l, 2, 6, suit_d)
		_rect(img, 9, by + 7 + arm_r, 2, 6, suit_d)
	var leg_top := by + 15
	_rect(img, lx_l, leg_top, 2, lh_l, suit_d)
	_rect(img, lx_r, leg_top, 2, lh_r, suit_d)
	return img

# --- Animated creatures -----------------------------------------------------
# Each species is drawn as a body (no legs) plus a leg layout; the generic
# frame builder animates the legs into idle / walk cycles. Fliers and the hopper
# use bespoke per-frame generators.

func _body_crawler(img: Image) -> void:
	var body := Color("7a2e8f")
	var body_l := Color("a23db0")
	_rect(img, 3, 3, 12, 6, body)
	_rect(img, 4, 3, 10, 2, body_l)
	_rect(img, 13, 4, 2, 2, Color("ff5a5a"))   # eye
	for lx in [4, 7, 10, 13]:                   # static upper legs
		_rect(img, lx, 0, 1, 3, Color("4a1d57"))

func _body_grazer(img: Image) -> void:
	var body := Color("9aa884")
	var dark := Color("5f6c49")
	_rect(img, 3, 4, 13, 6, body)
	_rect(img, 2, 5, 2, 4, body)
	_rect(img, 15, 3, 5, 5, body)
	_rect(img, 19, 5, 1, 2, dark)
	img.set_pixel(17, 5, Color("20242a"))
	_rect(img, 4, 2, 2, 2, dark)
	_rect(img, 8, 1, 2, 3, dark)

func _body_stalker(img: Image) -> void:
	var body := Color("3a2350")
	var body_l := Color("5a3a78")
	_rect(img, 2, 5, 16, 4, body)
	_rect(img, 3, 5, 14, 1, body_l)
	_rect(img, 16, 3, 6, 5, body)
	_rect(img, 20, 5, 2, 2, Color("ff4d4d"))
	for sx in [5, 8, 11, 14]:
		_rect(img, sx, 3, 1, 2, body_l)

func _body_spitter(img: Image) -> void:
	var body := Color("4a6a3a")
	var body_l := Color("6f9a52")
	_rect(img, 3, 4, 12, 8, body)
	_rect(img, 4, 4, 10, 2, body_l)
	_rect(img, 13, 6, 4, 3, body_l)
	_rect(img, 15, 7, 2, 1, Color("20242a"))
	_rect(img, 9, 3, 3, 3, body)
	_rect(img, 10, 4, 2, 2, Color("ffd23a"))

func _legged_image(w: int, h: int, body_cb: Callable, legs: Array, leg_color: Color, leg_w: int, frame: int) -> Image:
	var img := _new_image(w, h)
	body_cb.call(img)
	for i in legs.size():
		var lg: Array = legs[i]
		var lift := 0
		if frame >= 0 and ((frame == 0 and i % 2 == 0) or (frame == 2 and i % 2 == 1)):
			lift = 1                    # alternate sets of legs lift on the off-beats
		_rect(img, lg[0], lg[1] - lift, leg_w, lg[2] - lift, leg_color)
	return img

func _legged_frames(w: int, h: int, body_cb: Callable, legs: Array, leg_color: Color, leg_w: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 2.0)
	sf.add_frame("idle", _ptex(_legged_image(w, h, body_cb, legs, leg_color, leg_w, -1)))
	sf.add_animation("move")
	sf.set_animation_loop("move", true)
	sf.set_animation_speed("move", 9.0)
	for f in 4:
		sf.add_frame("move", _ptex(_legged_image(w, h, body_cb, legs, leg_color, leg_w, f)))
	if sf.has_animation("default"):
		sf.remove_animation("default")
	return sf

func _hopper_image(frame: int) -> Image:
	var img := _new_image(12, 12)
	var body := Color("b06ad0")
	var dark := Color("6f3f8f")
	var dy := 0
	var llen := 4
	if frame >= 0:
		dy = [0, -2, -3, -1][frame]   # hop arc
		llen = [3, 5, 6, 4][frame]
	_rect(img, 3, 3 + dy, 6, 5, body)
	img.set_pixel(4, 5 + dy, Color("20242a"))
	img.set_pixel(7, 5 + dy, Color("20242a"))
	_rect(img, 2, 8 + dy, 2, llen, dark)
	_rect(img, 8, 8 + dy, 2, llen, dark)
	_rect(img, 4, 9 + dy, 4, 3, body)
	return img

func _floater_image(frame: int) -> Image:
	var img := _new_image(16, 18)
	var bell := Color("6fd0e0")
	var bell_l := Color("aef0ff")
	for y in 8:
		var ww := 14 - absi(4 - y)
		_rect(img, 8 - ww / 2, y, ww, 1, bell if y % 2 == 0 else bell_l)
	_rect(img, 5, 8, 6, 1, bell_l)
	img.set_pixel(6, 4, Color("20242a"))
	img.set_pixel(9, 4, Color("20242a"))
	var base := [4, 7, 10]
	for i in base.size():
		var dx := 0
		var tlen := 8
		if frame >= 0:
			dx = [0, 1, 0, -1][(frame + i) % 4]
			tlen = 7 + [0, 1, 0, 1][(frame + i) % 4]   # tentacles sway + wiggle
		_rect(img, clampi(base[i] + dx, 1, 14), 9, 1, tlen, bell)
	return img

func _drone_image(frame: int) -> Image:
	var img := _new_image(14, 14)
	var sh := Color("2a3350")
	var sh_l := Color("3f4d78")
	var eye := Color("ff5a5a")
	for y in 14:
		for x in 14:
			var dx := x - 7
			var dy := y - 7
			if dx * dx + dy * dy <= 36:
				img.set_pixel(x, y, sh if (x + y) % 2 == 0 else sh_l)
	var ex := 5
	var tw := 2
	if frame >= 0:
		ex = 5 + [0, 1, 2, 1][frame]    # scanning eye
		tw = 3 if frame % 2 == 1 else 2  # thruster flicker
	_rect(img, ex, 6, 3, 2, eye)
	img.set_pixel(ex, 6, eye.lightened(0.4))
	_rect(img, 0, 6, tw, 2, sh_l)
	_rect(img, 14 - tw, 6, tw, 2, sh_l)
	return img

func _simple_frames(gen: Callable, count: int, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", maxf(2.0, fps * 0.5))
	sf.add_frame("idle", _ptex(gen.call(-1)))
	sf.add_animation("move")
	sf.set_animation_loop("move", true)
	sf.set_animation_speed("move", fps)
	for f in count:
		sf.add_frame("move", _ptex(gen.call(f)))
	if sf.has_animation("default"):
		sf.remove_animation("default")
	return sf

func _build_creature_frames() -> void:
	_creature_frames["crawler"] = _legged_frames(18, 12, _body_crawler, [[4, 9, 3], [7, 9, 3], [10, 9, 3], [13, 9, 3]], Color("4a1d57"), 1)
	_creature_frames["grazer"] = _legged_frames(20, 14, _body_grazer, [[4, 10, 4], [8, 10, 4], [12, 10, 4], [15, 10, 4]], Color("5f6c49"), 2)
	_creature_frames["stalker"] = _legged_frames(22, 12, _body_stalker, [[4, 9, 3], [8, 9, 3], [12, 9, 3], [15, 9, 3]], Color("3a2350"), 2)
	_creature_frames["spitter"] = _legged_frames(18, 14, _body_spitter, [[3, 11, 3], [13, 11, 3]], Color("4a6a3a"), 3)
	_creature_frames["hopper"] = _simple_frames(_hopper_image, 4, 9.0)
	_creature_frames["floater"] = _simple_frames(_floater_image, 4, 6.0)
	_creature_frames["drone"] = _simple_frames(_drone_image, 4, 6.0)

func creature_frames(name: String) -> SpriteFrames:
	return _creature_frames.get(name)

func _make_workbench() -> Image:
	var img := _new_image(30, 20)
	var top := Color("7a5a3a")
	var leg := Color("5a4028")
	_rect(img, 2, 6, 26, 4, top)
	_rect(img, 2, 6, 26, 1, top.lightened(0.15))
	_rect(img, 4, 10, 3, 10, leg)
	_rect(img, 23, 10, 3, 10, leg)
	_rect(img, 18, 2, 5, 4, Color("8a93b8"))   # vice / tool
	_rect(img, 7, 1, 2, 5, Color("9aa"))        # hammer handle
	_rect(img, 6, 1, 5, 2, Color("c4c4d6"))     # hammer head
	return img

func _make_fabricator() -> Image:
	var img := _new_image(30, 28)
	var body := Color("3a4a6a")
	_rect(img, 2, 6, 26, 22, body)
	_rect(img, 2, 6, 26, 1, Color("2dffff"))    # neon trim
	_rect(img, 6, 3, 18, 4, Color("2a3a55"))    # vent
	_rect(img, 5, 10, 20, 9, Color("0a1018"))   # screen
	for i in 4:
		_rect(img, 7 + i * 4, 12, 2, 5, Color("2dffff").darkened(randf_range(0.0, 0.4)))
	_rect(img, 6, 21, 18, 3, Color("23314a"))   # output tray
	return img

func _make_synthesizer() -> Image:
	var img := _new_image(30, 32)
	var dark := Color("241a30")
	_rect(img, 3, 20, 24, 12, Color("2a2440"))  # base
	_rect(img, 3, 20, 24, 1, Color("b06aff"))   # trim
	for tx in [8, 19]:
		_rect(img, tx, 6, 3, 15, dark)
		_rect(img, tx, 6 + (Time.get_ticks_msec() % 2), 3, 14, dark)  # tube
		_rect(img, tx + 1, 7, 1, 12, Color("b06aff"))                  # purple core
	# core orb
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	_blob(img, 15, 6, 5, Color("b06aff"), rng)
	img.set_pixel(15, 5, Color("eaccff"))
	return img

func _make_pod() -> Image:
	var img := _new_image(24, 22)
	var body := Color("2a3a45")
	_rect(img, 3, 4, 18, 18, body)
	_rect(img, 3, 3, 18, 2, Color("3f5a66"))    # lid
	_rect(img, 6, 7, 12, 9, Color("6fd0e0"))    # window
	_rect(img, 7, 8, 10, 7, Color("123040"))    # interior
	_rect(img, 8, 11, 3, 3, Color("ff9a3a"))    # hint of stored items
	_rect(img, 13, 10, 3, 4, Color("3aff8f"))
	# cyan corner bolts
	for p in [[3, 4], [20, 4], [3, 21], [20, 21]]:
		img.set_pixel(p[0], p[1], Color("2dffff"))
	return img

func _make_bolt() -> Image:
	var img := _new_image(6, 6)
	var c := Color("ff2bd6")
	for y in 6:
		for x in 6:
			var dx := x - 2.5
			var dy := y - 2.5
			if dx * dx + dy * dy <= 6.25:
				img.set_pixel(x, y, c)
	img.set_pixel(2, 2, Color.WHITE)
	img.set_pixel(3, 2, Color.WHITE)
	return img

func _make_starfield() -> Image:
	# A seamless, transparent 512x512 star overlay (the sky gradient + nebula are
	# drawn behind it by the sky shader, so there are no visible tiling bands).
	var size := 512
	var img := _new_image(size, size)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var palette := [Color(1, 1, 1), Color("bfe9ff"), Color("ffd0f0"), Color("cdd4ff")]
	for i in 760:
		var x := rng.randi_range(2, size - 3)
		var y := rng.randi_range(2, size - 3)
		var b := rng.randf_range(0.22, 1.0)
		var tint: Color = palette[rng.randi() % palette.size()]
		img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, b))
		if rng.randf() < 0.12:
			# soft halo around a fraction of the stars
			var halo := Color(tint.r, tint.g, tint.b, b * 0.3)
			img.set_pixel(x + 1, y, halo)
			img.set_pixel(x - 1, y, halo)
			img.set_pixel(x, y + 1, halo)
			img.set_pixel(x, y - 1, halo)
		if rng.randf() < 0.04:
			# rare bright star with cross glints
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, 1.0))
			var g := Color(tint.r, tint.g, tint.b, 0.22)
			img.set_pixel(x + 2, y, g)
			img.set_pixel(x - 2, y, g)
			img.set_pixel(x, y + 2, g)
			img.set_pixel(x, y - 2, g)
	return img

func _make_disc(core: Color, corona: Color) -> Image:
	# 64x64 celestial body: solid core fading into a soft corona.
	var size := 64
	var img := _new_image(size, size)
	var c := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			if d <= 0.42:
				img.set_pixel(x, y, core)
			elif d < 1.0:
				var a := clampf(1.0 - (d - 0.42) / 0.58, 0.0, 1.0)
				img.set_pixel(x, y, Color(corona.r, corona.g, corona.b, a * 0.7))
	return img

func _build_light_texture() -> void:
	# 256x256 soft radial falloff used by every PointLight2D in the game.
	var size := 256
	var img := _new_image(size, size)
	var c := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a            # smoother, rounder falloff
			img.set_pixel(x, y, Color(a, a, a, a))
	_light_tex = ImageTexture.create_from_image(img)

func light_texture() -> Texture2D:
	return _light_tex

func _ptex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

func _build_player_frames() -> void:
	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")

	# idle: a gentle breathing bob
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 2.5)
	sf.set_animation_loop("idle", true)
	sf.add_frame("idle", _ptex(_draw_player(0, 3, 7, 7, 7, 0, 0, false)))
	sf.add_frame("idle", _ptex(_draw_player(1, 3, 6, 7, 6, 0, 0, false)))

	# run: 4-frame leg/arm cycle with a small bounce
	sf.add_animation("run")
	sf.set_animation_speed("run", 10.0)
	sf.set_animation_loop("run", true)
	sf.add_frame("run", _ptex(_draw_player(0, 2, 7, 7, 4, 1, -1, false)))
	sf.add_frame("run", _ptex(_draw_player(1, 3, 6, 7, 6, 0, 0, false)))
	sf.add_frame("run", _ptex(_draw_player(0, 3, 4, 8, 7, -1, 1, false)))
	sf.add_frame("run", _ptex(_draw_player(1, 3, 6, 7, 6, 0, 0, false)))

	# jump (rising) and fall (descending)
	sf.add_animation("jump")
	sf.set_animation_loop("jump", false)
	sf.add_frame("jump", _ptex(_draw_player(0, 3, 4, 7, 4, 0, 0, true)))
	sf.add_animation("fall")
	sf.set_animation_loop("fall", false)
	sf.add_frame("fall", _ptex(_draw_player(0, 2, 5, 8, 5, 0, 0, true)))

	_player_frames = sf

func player_frames() -> SpriteFrames:
	return _player_frames

# ---------------------------------------------------------------------------
# Surface decorations (non-solid: no physics / no occlusion)
# ---------------------------------------------------------------------------
func _blades(img: Image, color: Color, count: int, max_h: int, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for i in count:
		var x := rng.randi_range(1, TS - 2)
		var h := rng.randi_range(max_h / 2, max_h)
		for y in h:
			img.set_pixel(x, TS - 1 - y, _vary(color, rng, 0.08))

func _make_decor(id: int) -> Image:
	var img := _new_image(TS, TS)
	match id:
		TUFT_WASTES: _blades(img, Color("2bf0a0"), 6, 8, 11)
		TUFT_TUNDRA: _blades(img, Color("bfe9ff"), 5, 7, 12)
		TUFT_DUNES: _blades(img, Color("b6a36a"), 6, 6, 13)
		TUFT_JUNGLE:
			_blades(img, Color("a6ff3a"), 7, 11, 14)
			img.set_pixel(4, TS - 9, Color("eaffba"))
			img.set_pixel(10, TS - 7, Color("eaffba"))
		ROCK:
			var rk := Color("4c5070")
			_rect(img, 5, TS - 5, 6, 4, rk)
			_rect(img, 6, TS - 7, 4, 2, rk.lightened(0.12))
			_rect(img, 7, TS - 7, 2, 1, rk.lightened(0.3))
			_rect(img, 5, TS - 2, 7, 1, rk.darkened(0.25))
		FLOWER:
			_rect(img, 7, TS - 7, 1, 6, Color("2bf0a0"))      # stem
			var bloom := Color("ff2bd6")
			_rect(img, 6, TS - 10, 4, 4, bloom)
			img.set_pixel(7, TS - 9, bloom.lightened(0.4))
			img.set_pixel(8, TS - 9, bloom.lightened(0.4))
		MUSHROOM:
			_rect(img, 7, TS - 6, 2, 5, Color("d8e8c0"))      # stalk
			var cap := Color("7aff3a")
			_rect(img, 4, TS - 10, 8, 4, cap)
			_rect(img, 5, TS - 11, 6, 1, cap)
			img.set_pixel(6, TS - 9, cap.lightened(0.4))
			img.set_pixel(9, TS - 9, cap.lightened(0.4))
	return img

func _build_decor_tileset() -> void:
	var atlas := _new_image(DECOR_COUNT * TS, TS)
	for id in DECOR_COUNT:
		atlas.blit_rect(_make_decor(id), Rect2i(0, 0, TS, TS), Vector2i(id * TS, 0))
	var tex := ImageTexture.create_from_image(atlas)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TS, TS)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TS, TS)
	decor_source_id = ts.add_source(src, 0)
	for id in DECOR_COUNT:
		src.create_tile(Vector2i(id, 0))   # no collision, no occluder
	decor_tileset = ts

func decor_atlas_coords(id: int) -> Vector2i:
	return Vector2i(id, 0)

# ---------------------------------------------------------------------------
# Fog of war (cloudy murk over unexplored underground; non-solid)
# ---------------------------------------------------------------------------
func _make_fog_image(v: int) -> Image:
	var img := _new_image(TS, TS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4000 + v
	var base := Color(0.05, 0.07, 0.13)
	for y in TS:
		for x in TS:
			img.set_pixel(x, y, Color(base.r, base.g, base.b, rng.randf_range(0.86, 0.95)))
	# a few lighter/darker cloud clumps for texture
	for c in 5:
		var cx := rng.randi_range(1, TS - 3)
		var cy := rng.randi_range(1, TS - 3)
		var lighter := rng.randf() < 0.5
		var col := base.lightened(0.12) if lighter else base.darkened(0.4)
		for i in 4:
			var px := clampi(cx + rng.randi_range(0, 2), 0, TS - 1)
			var py := clampi(cy + rng.randi_range(0, 2), 0, TS - 1)
			img.set_pixel(px, py, Color(col.r, col.g, col.b, rng.randf_range(0.85, 0.95)))
	return img

func _build_fog_tileset() -> void:
	var atlas := _new_image(FOG_VARIANTS * TS, TS)
	for v in FOG_VARIANTS:
		atlas.blit_rect(_make_fog_image(v), Rect2i(0, 0, TS, TS), Vector2i(v * TS, 0))
	var tex := ImageTexture.create_from_image(atlas)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TS, TS)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TS, TS)
	fog_source_id = ts.add_source(src, 0)
	for v in FOG_VARIANTS:
		src.create_tile(Vector2i(v, 0))
	fog_tileset = ts

func fog_atlas_coords(v: int) -> Vector2i:
	return Vector2i(v, 0)

# ---------------------------------------------------------------------------
# Alien trees (one tall sprite per biome, base at the bottom centre)
# ---------------------------------------------------------------------------
func _blob(img: Image, cx: int, cy: int, r: int, color: Color, rng: RandomNumberGenerator) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x - cx, y - cy).length()
			if d <= r - rng.randf_range(0.0, 1.3):
				img.set_pixel(x, y, _vary(color, rng, 0.06))

func _pset(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

## Grows a wandering, tapering, bark-textured trunk from (bx, by) up to row ty.
## Returns the top-centre tile where the canopy should sit.
func _trunk(img: Image, bx: int, by: int, ty: int, base_w: float, top_w: float, col: Color, dark: Color, rng: RandomNumberGenerator) -> Vector2i:
	var x := float(bx)
	var vx := rng.randf_range(-0.3, 0.3)
	var rows := by - ty
	var margin := int(ceil(base_w)) + 1
	for i in range(rows + 1):
		var y := by - i
		var t := float(i) / float(maxi(rows, 1))
		vx += rng.randf_range(-0.16, 0.16)
		vx = clampf(vx * 0.92, -0.95, 0.95)         # damped random walk = gentle curve
		x = clampf(x + vx, float(margin), float(img.get_width() - margin))
		var w := lerpf(base_w, top_w, t) + rng.randf_range(-0.5, 0.5)
		var half := maxf(1.0, w / 2.0)
		var x0 := int(round(x - half))
		var x1 := int(round(x + half))
		for px in range(x0, x1 + 1):
			var c := col
			if px == x0 or px == x1:
				c = dark                              # shaded bark edges
			elif rng.randf() < 0.16:
				c = dark.lerp(col, 0.5)               # vertical streaks
			_pset(img, px, y, c)
		if rng.randf() < 0.05:                        # knots
			_pset(img, int(round(x)) + (1 if rng.randf() < 0.5 else -1), y, dark.darkened(0.25))
	return Vector2i(int(round(x)), ty)

func _branch(img: Image, x: int, y: int, dir: float, length: int, col: Color, dark: Color, rng: RandomNumberGenerator) -> void:
	var fx := float(x)
	var fy := float(y)
	var w := 2.4
	for i in length:
		fx += dir
		fy -= rng.randf_range(0.35, 1.0)
		var half := maxf(0.5, w / 2.0)
		for px in range(int(fx - half), int(fx + half) + 1):
			_pset(img, px, int(fy), col if rng.randf() < 0.8 else dark)
		w = maxf(1.0, w - 0.18)

func _canopy_blobs(img: Image, cx: int, cy: int, color: Color, dots: Color, rng: RandomNumberGenerator) -> void:
	var main_r := rng.randi_range(9, 14)
	_blob(img, cx, cy, main_r, color, rng)
	for i in rng.randi_range(2, 4):
		var ox := rng.randi_range(-main_r, main_r)
		var oy := rng.randi_range(-5, main_r / 2)
		_blob(img, cx + ox, cy + oy, rng.randi_range(5, maxi(6, main_r - 3)), color, rng)
	for i in rng.randi_range(5, 11):
		_pset(img, cx + rng.randi_range(-main_r, main_r), cy + rng.randi_range(-main_r, main_r / 2), dots)

func _canopy_ice(img: Image, cx: int, cy: int, color: Color, rng: RandomNumberGenerator) -> void:
	var layers := rng.randi_range(4, 7)
	var y := float(cy)
	for i in layers:
		var ww := (layers - i) * 2 + rng.randi_range(1, 3)
		_rect(img, cx - ww, int(y), ww * 2, 2, _vary(color, rng, 0.05))
		y -= rng.randf_range(3.0, 5.0)
	_rect(img, cx - 1, int(y) - 4, 2, 7, color.lightened(0.2))

func _make_tree(biome: int, rng: RandomNumberGenerator) -> Image:
	# 38 wide x 96 tall image, trunk base centred at the bottom
	var w := 38
	var h := 96
	var img := _new_image(w, h)
	var bx := w / 2
	var by := h - 1
	var height := rng.randi_range(52, 74)
	var top_y := by - height
	match biome:
		World.TUNDRA:
			var trunk := Color("9fb8d0")
			var dark := Color("6f86a0")
			var top := _trunk(img, bx, by, top_y + 6, rng.randf_range(4.0, 6.0), 2.0, trunk, dark, rng)
			_canopy_ice(img, top.x, top.y, Color("8fe8ff"), rng)
		World.DUNES:
			var body := Color("8aa86a")
			var dark := Color("5f7a45")
			var top := _trunk(img, bx, by, top_y + 4, rng.randf_range(5.0, 7.0), 3.0, body, dark, rng)
			for i in rng.randi_range(1, 3):           # succulent arms
				var ay := rng.randi_range(top.y + 10, by - 16)
				var d := 1.0 if rng.randf() < 0.5 else -1.0
				_branch(img, bx, ay, d, rng.randi_range(8, 14), body, dark, rng)
			for i in rng.randi_range(3, 6):           # bristly tip
				_rect(img, top.x - 3 + i, top.y - rng.randi_range(2, 6), 1, rng.randi_range(3, 6), Color("c8e0a0"))
		World.JUNGLE:
			var trunk := Color("3b5a2a")
			var dark := Color("26401a")
			var top := _trunk(img, bx, by, top_y, rng.randf_range(5.0, 7.5), 3.0, trunk, dark, rng)
			for i in rng.randi_range(0, 2):
				var ay := rng.randi_range(top.y + 14, by - 20)
				_branch(img, bx, ay, (1.0 if rng.randf() < 0.5 else -1.0), rng.randi_range(6, 11), trunk, dark, rng)
			_canopy_blobs(img, top.x, top.y, Color("7aff3a"), Color("eaffba"), rng)
		_:  # WASTES neon
			var trunk := Color("2a6e5a")
			var dark := Color("1d4c3e")
			var top := _trunk(img, bx, by, top_y, rng.randf_range(3.5, 5.5), 2.0, trunk, dark, rng)
			for i in rng.randi_range(0, 2):
				var ay := rng.randi_range(top.y + 12, by - 18)
				_branch(img, bx, ay, (1.0 if rng.randf() < 0.5 else -1.0), rng.randi_range(5, 10), trunk, dark, rng)
			_canopy_blobs(img, top.x, top.y, Color("ff4df0"), Color("ffd0f7"), rng)
	return img

func make_tree(biome: int, seed_v: int) -> Texture2D:
	var key := "%d_%d" % [biome, seed_v]
	if _tree_cache.has(key):
		return _tree_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v * 1009 + biome * 97 + 54321
	var tex := ImageTexture.create_from_image(_make_tree(biome, rng))
	_tree_cache[key] = tex
	return tex

func sprite(name: String) -> Texture2D:
	return _sprites.get(name)
