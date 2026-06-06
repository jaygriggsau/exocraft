class_name Weather
extends Node
## Dynamic weather: drifting clouds, rain, and alien green lightning, driven by a
## clear -> cloudy -> storm state machine. Clouds live in a screen-space sky
## layer (behind the terrain); rain + lightning are screen overlays that only
## show while the player is near the surface. Publishes Game.weather for the HUD.

enum { CLEAR, CLOUDY, RAIN }

const WIND := 14.0                 # base cloud drift (px/s)
const EASE := 7.0                  # seconds to ease intensity toward its target
const CLOUD_W := 2048.0
const CLOUD_LIGHT := Color(0.82, 0.80, 0.92)   # pale alien haze
const CLOUD_DARK := Color(0.30, 0.30, 0.42)    # heavy storm cloud
const LIGHTNING := Color(0.45, 1.0, 0.5)       # alien green

var _state := CLEAR
var _timer := 0.0
var _intensity := 0.0              # 0..1 eased coverage / rain density
var _target := 0.0
var _bolt_timer := 4.0
var _drift := 0.0

var _clouds: Array[Sprite2D] = []
var _rain: CPUParticles2D
var _flash: ColorRect
var _bolt: Line2D
var _bolt_glow: Line2D

func _ready() -> void:
	_build_clouds()
	_build_rain()
	_build_lightning()
	_timer = randf_range(18.0, 40.0)

func _build_clouds() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -97              # in front of sun/stars, behind the terrain
	add_child(layer)
	var tex := Art.sprite("clouds")
	for i in 2:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.position = Vector2(i * CLOUD_W, 8)
		layer.add_child(s)
		_clouds.append(s)

func _build_rain() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5                # over the world, under the HUD
	add_child(layer)
	_rain = CPUParticles2D.new()
	_rain.texture = Art.sprite("rain")
	_rain.amount = 280
	_rain.lifetime = 1.2
	_rain.preprocess = 1.2
	_rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_rain.emission_rect_extents = Vector2(700, 8)
	_rain.direction = Vector2(0.12, 1)
	_rain.spread = 3.0
	_rain.gravity = Vector2(40, 520)
	_rain.initial_velocity_min = 620.0
	_rain.initial_velocity_max = 780.0
	_rain.scale_amount_min = 1.0
	_rain.scale_amount_max = 1.6
	_rain.emitting = false
	_rain.modulate.a = 0.0
	layer.add_child(_rain)

func _build_lightning() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_flash = ColorRect.new()
	_flash.color = Color(LIGHTNING.r, LIGHTNING.g, LIGHTNING.b, 0.0)
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)
	_bolt_glow = Line2D.new()
	_bolt_glow.width = 7.0
	_bolt_glow.default_color = Color(LIGHTNING.r, LIGHTNING.g, LIGHTNING.b, 0.4)
	_bolt_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	_bolt_glow.visible = false
	layer.add_child(_bolt_glow)
	_bolt = Line2D.new()
	_bolt.width = 2.5
	_bolt.default_color = Color(0.8, 1.0, 0.85)
	_bolt.joint_mode = Line2D.LINE_JOINT_ROUND
	_bolt.visible = false
	layer.add_child(_bolt)

func _process(dt: float) -> void:
	_timer -= dt
	if _timer <= 0.0:
		_advance_state()
	_intensity = move_toward(_intensity, _target, dt / EASE)

	# clouds: drift with the wind, thicken + darken as a storm builds
	var vw := get_viewport().get_visible_rect().size.x
	_drift = fposmod(_drift - WIND * (0.6 + _intensity) * dt, CLOUD_W)
	for i in _clouds.size():
		_clouds[i].position.x = -_drift + i * CLOUD_W
		while _clouds[i].position.x > vw:
			_clouds[i].position.x -= CLOUD_W * _clouds.size()
	var cov := 0.12 + 0.82 * _intensity
	var tone := CLOUD_LIGHT.lerp(CLOUD_DARK, clampf((_intensity - 0.45) / 0.55, 0.0, 1.0))
	for s in _clouds:
		s.modulate = Color(tone.r, tone.g, tone.b, cov)

	# rain + lightning only where you can see the sky
	var surface := _surface_view()
	var raining := _state == RAIN and surface
	_rain.emitting = raining
	_rain.modulate.a = move_toward(_rain.modulate.a, 1.0 if raining else 0.0, dt * 2.0)
	var vs := get_viewport().get_visible_rect().size
	_rain.position = Vector2(vs.x * 0.5, -30.0)
	_rain.emission_rect_extents = Vector2(vs.x * 0.62, 8.0)

	if _state == RAIN and _intensity > 0.6 and surface:
		_bolt_timer -= dt
		if _bolt_timer <= 0.0:
			_bolt_timer = randf_range(3.5, 9.0)
			_strike()

func _advance_state() -> void:
	match _state:
		CLEAR:
			_state = CLOUDY
			_timer = randf_range(26.0, 52.0)
		CLOUDY:
			if randf() < 0.55:
				_state = RAIN
				_timer = randf_range(24.0, 52.0)
			else:
				_state = CLEAR
				_timer = randf_range(45.0, 95.0)
		RAIN:
			_state = CLOUDY
			_timer = randf_range(18.0, 38.0)
	_target = [0.0, 0.5, 1.0][_state]
	Game.weather = ["Clear", "Cloudy", "Storm"][_state]

func _surface_view() -> bool:
	var p = Game.player
	if p == null or Game.world == null:
		return false
	var t: Vector2i = Game.world.world_to_tile(p.global_position)
	return t.y - Game.world.surface_height(t.x) < 8

## A green lightning strike: jagged bolt + a double-flicker screen flash + thunder.
func _strike() -> void:
	var vs := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	var x := randf_range(vs.x * 0.18, vs.x * 0.82)
	var y := 0.0
	while y < vs.y * 0.74:
		pts.append(Vector2(x, y))
		y += randf_range(16.0, 34.0)
		x += randf_range(-26.0, 26.0)
	pts.append(Vector2(x, vs.y * 0.78))
	_bolt.points = pts
	_bolt_glow.points = pts
	for b in [_bolt, _bolt_glow]:
		b.visible = true
		b.modulate.a = 1.0
	var tb := create_tween()
	tb.tween_interval(0.06)
	tb.tween_property(_bolt, "modulate:a", 0.0, 0.16)
	tb.parallel().tween_property(_bolt_glow, "modulate:a", 0.0, 0.16)
	tb.tween_callback(func():
		_bolt.visible = false
		_bolt_glow.visible = false)

	var tf := create_tween()
	tf.tween_property(_flash, "color:a", 0.5, 0.04)
	tf.tween_property(_flash, "color:a", 0.12, 0.06)
	tf.tween_property(_flash, "color:a", 0.4, 0.05)
	tf.tween_property(_flash, "color:a", 0.0, 0.28)
	Sfx.play("thunder")
