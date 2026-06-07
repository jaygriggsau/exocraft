class_name DayNight
extends Node2D
## Drives the time of day and the whole dynamic lighting atmosphere:
##   * a CanvasModulate that sets the global ambient floor,
##   * a sun + moon DirectionalLight2D that arc across the sky and cast shadows
##     off the terrain occluders (bright surface, naturally dark caves),
##   * a shader sky that transitions dawn -> day -> dusk -> night,
##   * fading stars and arcing sun/moon discs.
## Time state is published to Game.time_of_day / Game.day_count for the HUD.

const DAY_LENGTH := 300.0          ## seconds for a full 24h cycle
const SUN_MAX := 1.45
const MOON_MAX := 0.40
const SUN_SHADOWS := true

# tunable palette ----------------------------------------------------------
const AMBIENT_NIGHT := Color(0.035, 0.04, 0.075)   # deep dark night (use a torch!)
const AMBIENT_DAY := Color(0.42, 0.45, 0.52)
const SKY_TOP_NIGHT := Color(0.02, 0.02, 0.06)
const SKY_TOP_DAY := Color(0.10, 0.22, 0.44)
const SKY_HZN_NIGHT := Color(0.05, 0.04, 0.12)
const SKY_HZN_DAY := Color(0.36, 0.50, 0.70)
const TWILIGHT := Color(0.95, 0.32, 0.55)   # cyberpunk magenta dawn/dusk glow

var _ambient: CanvasModulate
var _sun: DirectionalLight2D
var _moon: DirectionalLight2D
var _sky_mat: ShaderMaterial
var _stars: CanvasItem
var _sun_disc: Sprite2D
var _moon_disc: Sprite2D

const NEBULA_A := Color(0.55, 0.10, 0.45)   # magenta cloud
const NEBULA_B := Color(0.12, 0.18, 0.55)   # indigo cloud

const SKY_SHADER := """
shader_type canvas_item;
uniform vec4 top_color : source_color;
uniform vec4 horizon_color : source_color;
uniform vec4 nebula_a : source_color;
uniform vec4 nebula_b : source_color;
uniform float night : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}
void fragment() {
	vec3 col = mix(top_color.rgb, horizon_color.rgb, smoothstep(0.0, 0.85, UV.y));
	// soft procedural nebula, only at night and fading toward the horizon
	float n = smoothstep(0.42, 0.95, fbm(UV * vec2(3.0, 2.2) + vec2(0.0, 1.7)));
	float fall = 1.0 - smoothstep(0.05, 0.72, UV.y);
	vec3 neb = mix(nebula_a.rgb, nebula_b.rgb, fbm(UV * 4.0 + 5.0));
	col += neb * n * fall * night * 0.55;
	COLOR = vec4(col, 1.0);
}
"""

func _ready() -> void:
	_build_lights()
	_build_sky()
	_apply(Game.time_of_day)

func _process(dt: float) -> void:
	var t := fposmod(Game.time_of_day + dt / DAY_LENGTH, 1.0)
	if t < Game.time_of_day:
		Game.day_count += 1
	Game.time_of_day = t
	_apply(t)

# ---------------------------------------------------------------------------
func _build_lights() -> void:
	_ambient = CanvasModulate.new()
	add_child(_ambient)

	_sun = DirectionalLight2D.new()
	_sun.shadow_enabled = SUN_SHADOWS
	_sun.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_sun.color = Color("fff2d8")
	add_child(_sun)

	_moon = DirectionalLight2D.new()
	_moon.shadow_enabled = false
	_moon.color = Color("8fa0d8")
	add_child(_moon)

func _build_sky() -> void:
	# backdrop gradient
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -100
	add_child(sky_layer)
	var rect := ColorRect.new()
	rect.size = Vector2(1280, 720)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SKY_SHADER
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sh
	_sky_mat.set_shader_parameter("nebula_a", NEBULA_A)
	_sky_mat.set_shader_parameter("nebula_b", NEBULA_B)
	rect.material = _sky_mat
	sky_layer.add_child(rect)

	# parallax stars
	var pb := ParallaxBackground.new()
	pb.layer = -99
	add_child(pb)
	var pl := ParallaxLayer.new()
	pl.motion_scale = Vector2(0.15, 0.15)
	pl.motion_mirroring = Vector2(512, 512)
	pb.add_child(pl)
	var star := Sprite2D.new()
	star.texture = Art.sprite("star")
	star.centered = false
	star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pl.add_child(star)
	_stars = star

	# sun + moon discs (frontmost background layer)
	var cel := CanvasLayer.new()
	cel.layer = -98
	add_child(cel)
	_sun_disc = Sprite2D.new()
	_sun_disc.texture = Art.sprite("sun")
	_sun_disc.scale = Vector2(2.0, 2.0)
	cel.add_child(_sun_disc)
	_moon_disc = Sprite2D.new()
	_moon_disc.texture = Art.sprite("moon")
	_moon_disc.scale = Vector2(1.6, 1.6)
	cel.add_child(_moon_disc)

# ---------------------------------------------------------------------------
func _apply(t: float) -> void:
	# sun is up across t in [0.25, 0.75]; moon fills the other half.
	var sun_elev := maxf(0.0, sin(PI * (t - 0.25) / 0.5))
	var moon_t := fposmod(t + 0.5, 1.0)
	var moon_elev := maxf(0.0, sin(PI * (moon_t - 0.25) / 0.5))
	var day := sun_elev   # 0 at night, 1 at noon

	# ambient floor
	_ambient.color = AMBIENT_NIGHT.lerp(AMBIENT_DAY, smoothstep(0.0, 0.6, day))

	# directional lights: energy + a swept angle so shadows shift over the day
	_sun.energy = sun_elev * SUN_MAX
	_sun.visible = sun_elev > 0.001
	_sun.rotation = deg_to_rad(lerpf(-70.0, 70.0, clampf((t - 0.25) / 0.5, 0.0, 1.0)))
	_moon.energy = moon_elev * MOON_MAX
	_moon.visible = moon_elev > 0.001
	_moon.rotation = deg_to_rad(lerpf(-70.0, 70.0, clampf((moon_t - 0.25) / 0.5, 0.0, 1.0)))

	# sky gradient, warmed near sunrise/sunset
	var twilight := clampf(1.0 - minf(absf(t - 0.25), absf(t - 0.75)) / 0.12, 0.0, 1.0)
	var top := SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day)
	var hzn := SKY_HZN_NIGHT.lerp(SKY_HZN_DAY, day).lerp(TWILIGHT, twilight * 0.75)
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", hzn)

	# stars + nebula fade out during the day
	var night := clampf(1.0 - day * 1.6, 0.0, 1.0)
	_stars.self_modulate.a = night
	_sky_mat.set_shader_parameter("night", night)

	# arc the sun / moon discs across the sky (screen space)
	_place_disc(_sun_disc, (t - 0.25) / 0.5, sun_elev)
	_place_disc(_moon_disc, (moon_t - 0.25) / 0.5, moon_elev)

func _place_disc(disc: Sprite2D, p: float, elev: float) -> void:
	disc.visible = elev > 0.001
	if not disc.visible:
		return
	disc.position = Vector2(1280.0 * clampf(p, 0.0, 1.0), 660.0 - sin(clampf(p, 0.0, 1.0) * PI) * 560.0)
	disc.modulate.a = clampf(elev * 2.5, 0.0, 1.0)
