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

func _ready() -> void:
	_build_tile_images()
	_build_tileset()
	_build_item_icons()
	_build_sprites()
	_build_light_texture()
	_build_player_frames()

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
			# Drill: handle + glowing bit.
			_rect(img, 7, 4, 2, 9, Color("6f74a0"))
			_rect(img, 4, 11, 8, 3, Color("4a4e6b"))
			_rect(img, 6, 13, 4, 2, c)
			img.set_pixel(7, 14, c.lightened(0.4))
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

func sprite(name: String) -> Texture2D:
	return _sprites.get(name)
