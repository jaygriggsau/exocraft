class_name MiningFX
extends Node2D
## The "particle gun" disintegration effect. While the player mines a block this
## draws a beam from the gun to the block, erodes the block pixel-by-pixel in step
## with mining progress, and spawns the dissolved bits as particles that are
## sucked back into the gun. Lives in world space (child of World) so it can draw
## with raw world coordinates.

const TILE := 16
const ATTRACT := 1500.0      # how hard particles are pulled toward the gun
const SPAWN_RATE := 90.0     # dissolve particles per second while mining

var active := false
var _tile := Vector2i.ZERO
var _muzzle := Vector2.ZERO
var _base := Color.WHITE
var _accent := Color.WHITE
var _progress := 0.0
var _dissolve := true

var _perm: Array = []        # deterministic shuffle of the 256 tile pixels
var _parts: Array = []       # live particles
var _spawn_acc := 0.0
var _light: PointLight2D

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9173
	for y in TILE:
		for x in TILE:
			_perm.append(Vector2i(x, y))
	for i in range(_perm.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = _perm[i]
		_perm[i] = _perm[j]
		_perm[j] = tmp

	_light = PointLight2D.new()
	_light.texture = Art.light_texture()
	_light.scale = Vector2(0.22, 0.22)
	_light.energy = 0.0
	add_child(_light)

func set_state(a: bool, tile: Vector2i, muzzle: Vector2, base: Color, accent: Color, progress: float, dissolve: bool = true) -> void:
	active = a
	_tile = tile
	_muzzle = muzzle
	_base = base
	_accent = accent
	_progress = progress
	_dissolve = dissolve

func _process(dt: float) -> void:
	if active:
		_spawn_acc += dt * SPAWN_RATE
		while _spawn_acc >= 1.0:
			_spawn_acc -= 1.0
			_spawn_one()
		_light.position = Vector2((_tile.x + 0.5) * TILE, (_tile.y + 0.5) * TILE)
		_light.color = _accent
		_light.energy = lerpf(_light.energy, 1.1, 0.35)
	else:
		_spawn_acc = 0.0
		_light.energy = lerpf(_light.energy, 0.0, 0.35)

	# pull every particle toward the gun muzzle, fading as it goes
	var i := _parts.size() - 1
	while i >= 0:
		var p = _parts[i]
		var to: Vector2 = _muzzle - p.pos
		p.vel += to.normalized() * ATTRACT * dt
		p.vel *= 0.86
		p.pos += p.vel * dt
		p.life -= dt
		if p.life <= 0.0 or to.length() < 5.0:
			_parts.remove_at(i)
		i -= 1

	if active or not _parts.is_empty():
		queue_redraw()
	elif _light.energy < 0.02:
		queue_redraw()  # final clear

func _spawn_one() -> void:
	var removed := int(_progress * 255.0)
	if removed >= 255:
		return
	# peel a still-intact pixel off the block
	var px: Vector2i = _perm[randi_range(removed, 255)]
	var pos := Vector2(_tile.x * TILE + px.x + 0.5, _tile.y * TILE + px.y + 0.5)
	_parts.append({
		"pos": pos,
		"vel": Vector2(randf_range(-22, 22), randf_range(-22, 22)),
		"life": randf_range(0.30, 0.55),
		"maxlife": 0.55,
		"col": _base.lerp(_accent, randf()),
		"size": 1.0 if randf() < 0.6 else 2.0,
	})

func _draw() -> void:
	if active:
		var center := Vector2((_tile.x + 0.5) * TILE, (_tile.y + 0.5) * TILE)
		var c := _accent
		# twin-line glow beam from the gun to the block
		draw_line(_muzzle, center, Color(c.r, c.g, c.b, 0.22), 3.0)
		draw_line(_muzzle, center, Color(c.r, c.g, c.b, 0.9), 1.0)
		# flickering muzzle flash at the gun
		var fl := 1.0 + randf() * 0.8
		draw_circle(_muzzle, 2.2 * fl, Color(c.r, c.g, c.b, 0.9))
		draw_circle(_muzzle, 4.0 * fl, Color(c.r, c.g, c.b, 0.28))
		var r := 4.5 * fl
		draw_line(_muzzle - Vector2(r, 0), _muzzle + Vector2(r, 0), Color(c.r, c.g, c.b, 0.45), 1.0)
		draw_line(_muzzle - Vector2(0, r), _muzzle + Vector2(0, r), Color(c.r, c.g, c.b, 0.45), 1.0)
		# erode the block pixel-by-pixel in step with progress (blocks only)
		if _dissolve:
			var removed := int(_progress * 255.0)
			var ox := _tile.x * TILE
			var oy := _tile.y * TILE
			for k in removed:
				var px: Vector2i = _perm[k]
				draw_rect(Rect2(ox + px.x, oy + px.y, 1, 1), Color(0, 0, 0, 0.55), true)

	for p in _parts:
		var a: float = clampf(p.life / p.maxlife, 0.0, 1.0)
		var col: Color = p.col
		col.a = a
		var s: float = p.size
		draw_rect(Rect2(p.pos.x - s * 0.5, p.pos.y - s * 0.5, s, s), col, true)
