extends Node
## Runtime pixel-art factory.
##
## Everything visual in Exocraft is generated here as small RGBA images so the
## project ships with zero binary assets and stays fully deterministic. Swap any
## of these out for hand-drawn PNGs later without touching gameplay code.

const TS := 16  ## tile size in pixels

var tileset: TileSet
var atlas_source_id := 0

var _tile_images := {}   # tile id -> Image
var _item_icons := {}    # item id -> ImageTexture
var _sprites := {}       # name   -> ImageTexture
var _light_tex: ImageTexture
var _player_frames: SpriteFrames
var decor_tileset: TileSet
var decor_source_id := 0
var _trees := {}         # biome -> ImageTexture

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
	_build_trees()

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
		_tile_images[id] = _make_tile_image(id)

func _make_tile_image(id: int) -> Image:
	var d = Tiles.def(id)
	var img := _new_image(TS, TS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + id
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
			# "block" / "soil": add a subtle darker bottom-right shade for depth.
			for y in TS:
				for x in TS:
					if x + y > TS + 6:
						img.set_pixel(x, y, _vary(base.darkened(0.12), rng, 0.04))
	return img

func _build_tileset() -> void:
	var maxid := Tiles.max_id()
	var atlas := _new_image((maxid + 1) * TS, TS)
	for id in Tiles.ids():
		atlas.blit_rect(_tile_images[id], Rect2i(0, 0, TS, TS), Vector2i(id * TS, 0))
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
		var coord := Vector2i(id, 0)
		src.create_tile(coord)
		var td := src.get_tile_data(coord, 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, square)
		td.set_occluder(0, occ)

	tileset = ts

func tile_atlas_coords(id: int) -> Vector2i:
	return Vector2i(id, 0)

# ---------------------------------------------------------------------------
# Item icons
# ---------------------------------------------------------------------------
func _build_item_icons() -> void:
	for item_id in ItemDB.ITEMS.keys():
		_item_icons[item_id] = ImageTexture.create_from_image(_make_item_icon(item_id))

func _make_item_icon(item_id: String) -> Image:
	var d = ItemDB.get_item(item_id)
	# Block items just reuse their tile artwork.
	if d.type == ItemDB.BLOCK:
		return _tile_images[d.tile]

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
	_sprites["crawler"] = ImageTexture.create_from_image(_make_crawler())
	_sprites["drone"] = ImageTexture.create_from_image(_make_drone())
	_sprites["grazer"] = ImageTexture.create_from_image(_make_grazer())
	_sprites["hopper"] = ImageTexture.create_from_image(_make_hopper())
	_sprites["floater"] = ImageTexture.create_from_image(_make_floater())
	_sprites["stalker"] = ImageTexture.create_from_image(_make_stalker())
	_sprites["spitter"] = ImageTexture.create_from_image(_make_spitter())
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

func _make_crawler() -> Image:
	# 18 x 12 multi-legged alien bug.
	var img := _new_image(18, 12)
	var body := Color("7a2e8f")
	var body_l := Color("a23db0")
	var eye := Color("ff5a5a")
	var leg := Color("4a1d57")
	_rect(img, 3, 3, 12, 6, body)
	_rect(img, 4, 3, 10, 2, body_l)
	_rect(img, 13, 4, 2, 2, eye)        # eye toward +x (facing right)
	for lx in [4, 7, 10, 13]:           # legs
		_rect(img, lx, 9, 1, 3, leg)
		_rect(img, lx, 0, 1, 3, leg)
	return img

func _make_drone() -> Image:
	# 14 x 14 floating sentry orb.
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
	_rect(img, 5, 6, 4, 2, eye)
	img.set_pixel(6, 6, eye.lightened(0.4))
	_rect(img, 0, 6, 2, 2, sh_l)        # side thrusters
	_rect(img, 12, 6, 2, 2, sh_l)
	return img

func _make_grazer() -> Image:
	# 20x14 docile six-legged grazer
	var img := _new_image(20, 14)
	var body := Color("9aa884")
	var dark := Color("5f6c49")
	_rect(img, 3, 4, 13, 6, body)
	_rect(img, 2, 5, 2, 4, body)        # rump
	_rect(img, 15, 3, 5, 5, body)       # head
	_rect(img, 19, 5, 1, 2, dark)       # snout
	img.set_pixel(17, 5, Color("20242a"))   # eye
	_rect(img, 4, 2, 2, 2, dark)        # back fins
	_rect(img, 8, 1, 2, 3, dark)
	for lx in [4, 8, 12, 15]:
		_rect(img, lx, 10, 2, 4, dark)
	return img

func _make_hopper() -> Image:
	# 12x12 small skittish hopper
	var img := _new_image(12, 12)
	var body := Color("b06ad0")
	var dark := Color("6f3f8f")
	_rect(img, 3, 3, 6, 5, body)
	img.set_pixel(4, 5, Color("20242a"))
	img.set_pixel(7, 5, Color("20242a"))
	_rect(img, 2, 8, 2, 4, dark)        # big folded legs
	_rect(img, 8, 8, 2, 4, dark)
	_rect(img, 4, 9, 4, 3, body)
	return img

func _make_floater() -> Image:
	# 16x18 drifting jelly-floater
	var img := _new_image(16, 18)
	var bell := Color("6fd0e0")
	var bell_l := Color("aef0ff")
	for y in 8:
		var ww := 14 - absi(4 - y)
		_rect(img, 8 - ww / 2, y, ww, 1, bell if y % 2 == 0 else bell_l)
	_rect(img, 5, 8, 6, 1, bell_l)
	for tx in [4, 7, 10]:               # tentacles
		_rect(img, tx, 9, 1, 8, bell)
	img.set_pixel(6, 4, Color("20242a"))
	img.set_pixel(9, 4, Color("20242a"))
	return img

func _make_stalker() -> Image:
	# 22x12 sleek territorial predator
	var img := _new_image(22, 12)
	var body := Color("3a2350")
	var body_l := Color("5a3a78")
	var eye := Color("ff4d4d")
	_rect(img, 2, 5, 16, 4, body)
	_rect(img, 3, 5, 14, 1, body_l)
	_rect(img, 16, 3, 6, 5, body)       # head
	_rect(img, 20, 5, 2, 2, eye)        # eye
	for sx in [5, 8, 11, 14]:           # back spikes
		_rect(img, sx, 3, 1, 2, body_l)
	for lx in [4, 8, 12, 15]:           # legs
		_rect(img, lx, 9, 2, 3, body)
	return img

func _make_spitter() -> Image:
	# 18x14 squat ranged spitter
	var img := _new_image(18, 14)
	var body := Color("4a6a3a")
	var body_l := Color("6f9a52")
	var eye := Color("ffd23a")
	_rect(img, 3, 4, 12, 8, body)
	_rect(img, 4, 4, 10, 2, body_l)
	_rect(img, 13, 6, 4, 3, body_l)     # snout/mouth
	_rect(img, 15, 7, 2, 1, Color("20242a"))   # mouth slit
	_rect(img, 9, 3, 3, 3, body)        # eye bump
	_rect(img, 10, 4, 2, 2, eye)
	for lx in [3, 13]:
		_rect(img, lx, 11, 3, 3, body)
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

func _make_tree(biome: int) -> Image:
	# 30 wide x 84 tall; trunk base centred at x=15, bottom row y=83
	var w := 30
	var h := 84
	var img := _new_image(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 700 + biome
	var cx := w / 2
	match biome:
		World.TUNDRA:
			var trunk := Color("9fb8d0")
			_rect(img, cx - 2, 40, 4, h - 40, trunk)
			var ice := Color("8fe8ff")
			for i in 5:
				var yy := 14 + i * 6
				var ww := 12 - i * 2
				_rect(img, cx - ww, yy, ww * 2, 3, _vary(ice, rng, 0.05))
			_rect(img, cx - 1, 6, 2, 12, ice.lightened(0.2))
		World.DUNES:
			var body := Color("a7c08a")
			_rect(img, cx - 3, 24, 6, h - 24, body)         # column
			_rect(img, cx - 8, 44, 5, 3, body)              # arms
			_rect(img, cx - 8, 36, 3, 11, body)
			_rect(img, cx + 3, 50, 5, 3, body)
			_rect(img, cx + 5, 40, 3, 13, body)
			_rect(img, cx - 1, 18, 2, 8, body.lightened(0.15))
		World.JUNGLE:
			var trunk := Color("3b5a2a")
			_rect(img, cx - 3, 38, 6, h - 38, trunk)
			var canopy := Color("7aff3a")
			_blob(img, cx, 26, 14, canopy, rng)
			_blob(img, cx - 9, 34, 8, canopy, rng)
			_blob(img, cx + 9, 33, 8, canopy, rng)
			for i in 8:
				img.set_pixel(rng.randi_range(cx - 12, cx + 12), rng.randi_range(16, 40), Color("eaffba"))
		_:  # WASTES neon
			var trunk := Color("2a6e5a")
			_rect(img, cx - 2, 40, 4, h - 40, trunk)
			var canopy := Color("ff4df0")
			_blob(img, cx, 24, 13, canopy, rng)
			_blob(img, cx - 7, 30, 7, canopy, rng)
			_blob(img, cx + 7, 31, 7, canopy, rng)
			for i in 7:
				img.set_pixel(rng.randi_range(cx - 11, cx + 11), rng.randi_range(15, 36), Color("ffd0f7"))
	return img

func _build_trees() -> void:
	for b in [World.WASTES, World.TUNDRA, World.DUNES, World.JUNGLE]:
		_trees[b] = ImageTexture.create_from_image(_make_tree(b))

func tree_texture(biome: int) -> Texture2D:
	return _trees.get(biome, _trees.get(World.WASTES))

func sprite(name: String) -> Texture2D:
	return _sprites.get(name)
