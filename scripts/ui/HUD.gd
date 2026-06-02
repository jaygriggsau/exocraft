extends CanvasLayer
## All on-screen UI: health, hotbar, the toggleable inventory grid and the
## crafting list. Built entirely in code against a fixed 1280x720 layout (the
## canvas_items stretch mode scales it to any window size).

const VW := 1280
const VH := 720
const SLOT := 40
const PAD := 4

var _normal_sb: StyleBoxFlat
var _select_sb: StyleBoxFlat

var _hp_fill: ColorRect
var _hp_label: Label
var _info_label: Label
var _clock_label: Label
var _peaceful_label: Label
var _death_label: Label

var _hotbar_slots := []          # array of {panel,icon,label}
var _inv_slots := []
var _inv_panel: Control
var _craft_panel: Control
var _craft_rows := []            # array of {button,recipe}
var _sel_label: Label
var _tip: Panel
var _tip_label: Label
var _vig_mat: ShaderMaterial
var _pause_panel: Control

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.25, 0.78, d);
	COLOR = vec4(1.0, 0.1, 0.2, v * amount);
}
"""

const SCANLINE_SHADER := """
shader_type canvas_item;
void fragment() {
	float s = step(0.5, fract(UV.y * 360.0));        // thin dark scanlines
	float d = distance(UV, vec2(0.5));
	float vig = smoothstep(0.6, 1.05, d) * 0.11;      // soft CRT vignette
	COLOR = vec4(0.0, 0.03, 0.06, s * 0.04 + vig);
}
"""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep UI alive while the game is paused
	get_tree().root.theme = _build_theme()    # apply the cyberpunk theme app-wide
	_make_styleboxes()
	_build_health()
	_build_info()
	_build_hotbar()
	_build_selected_label()
	_build_inventory()
	_build_crafting()
	_build_tooltip()
	_build_vignette()
	_build_death_label()
	_build_pause()
	_build_scanlines()

	Game.inventory_changed.connect(_refresh)
	Game.health_changed.connect(_on_health)
	Game.player_died.connect(_on_death)
	call_deferred("_refresh")
	_on_health(Game.health, Game.max_health)

func _process(_dt: float) -> void:
	if Game.player and Game.world:
		var t: Vector2i = Game.world.world_to_tile(Game.player.global_position)
		var depth: int = t.y - Game.world.surface_height(t.x)
		var biome := _biome_name(Game.world.biome_at(t.x))
		_info_label.text = "%s    depth %d" % [biome, maxi(0, depth)]
	_clock_label.text = "Day %d  %s  %s" % [Game.day_count, Game.clock_string(), Game.day_phase()]
	_peaceful_label.visible = not Game.enemies_enabled
	_update_vignette()
	_update_tooltip()

func _update_vignette() -> void:
	# red pulse that grows as health drops below ~35%
	var ratio := Game.health / Game.max_health
	var low := clampf((0.35 - ratio) / 0.35, 0.0, 1.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
	_vig_mat.set_shader_parameter("amount", low * pulse * 0.7)

func _update_tooltip() -> void:
	_tip.visible = false
	if not _inv_panel.visible or Game.inventory == null:
		return
	var mp: Vector2 = _inv_panel.get_global_mouse_position()
	for i in Inventory.SIZE:
		var s: Dictionary = _inv_slots[i]
		if s.panel.get_global_rect().has_point(mp):
			var stack = Game.inventory.slots[i]
			if stack != null:
				var nm := ItemDB.name_of(stack.id)
				_tip_label.text = "%s   x%d" % [nm, stack.count] if stack.count > 1 else nm
				_tip.size = Vector2(_tip_label.get_minimum_size().x + 14, 22)
				_tip.position = mp + Vector2(14, 14)
				_tip.visible = true
			return

func _biome_name(b: int) -> String:
	match b:
		World.TUNDRA: return "CRYO TUNDRA"
		World.DUNES: return "GLASS DUNES"
		World.JUNGLE: return "TOXIC JUNGLE"
		_: return "NEON WASTES"

# ---------------------------------------------------------------------------
func _make_styleboxes() -> void:
	_normal_sb = StyleBoxFlat.new()
	_normal_sb.bg_color = Color(0.05, 0.08, 0.14, 0.88)
	_normal_sb.set_border_width_all(1)
	_normal_sb.border_color = Color(0.18, 0.45, 0.6)
	_normal_sb.set_corner_radius_all(0)

	_select_sb = StyleBoxFlat.new()
	_select_sb.bg_color = Color(0.08, 0.16, 0.22, 0.92)
	_select_sb.set_border_width_all(2)
	_select_sb.border_color = Color("2dffff")
	_select_sb.set_corner_radius_all(0)

# A sharp, neon-framed cyberpunk panel/button box.
func _sb(bg: Color, border: Color, top: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_width_top = top
	s.border_color = border
	s.set_corner_radius_all(0)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _build_theme() -> Theme:
	var th := Theme.new()
	var fg := Color("c8f0ff")
	var cyan := Color("2dffff")
	var mag := Color("ff2bd6")
	# Buttons (fabricator / pause)
	th.set_stylebox("normal", "Button", _sb(Color(0.06, 0.10, 0.17, 0.92), cyan))
	th.set_stylebox("hover", "Button", _sb(Color(0.12, 0.07, 0.17, 0.96), mag))
	th.set_stylebox("pressed", "Button", _sb(Color(0.0, 0.55, 0.62, 0.95), Color("aef6ff")))
	th.set_stylebox("disabled", "Button", _sb(Color(0.05, 0.06, 0.10, 0.6), Color(0.25, 0.3, 0.4), 1))
	th.set_stylebox("focus", "Button", _sb(Color(0, 0, 0, 0), mag))
	th.set_color("font_color", "Button", fg)
	th.set_color("font_hover_color", "Button", Color("ffd0f7"))
	th.set_color("font_pressed_color", "Button", Color("06121a"))
	th.set_color("font_disabled_color", "Button", Color(0.4, 0.46, 0.56))
	# Panels + labels
	th.set_stylebox("panel", "Panel", _panel_sb())
	th.set_stylebox("panel", "PanelContainer", _panel_sb())
	th.set_color("font_color", "Label", fg)
	return th

func _panel_sb() -> StyleBoxFlat:
	var s := _sb(Color(0.03, 0.05, 0.11, 0.94), Color("2dffff"), 2)
	s.border_color = Color(0.16, 0.7, 0.85, 0.9)
	return s

func _build_scanlines() -> void:
	var sc := ColorRect.new()
	sc.position = Vector2.ZERO
	sc.size = Vector2(VW, VH)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.z_index = 15
	var sh := Shader.new()
	sh.code = SCANLINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	sc.material = m
	add_child_control(sc)

func _build_health() -> void:
	var bg := Panel.new()
	var hsb := _sb(Color(0.02, 0.03, 0.06, 0.7), Color("ff3b6b"), 1)
	bg.add_theme_stylebox_override("panel", hsb)
	bg.position = Vector2(16, 16)
	bg.size = Vector2(224, 22)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child_control(bg)
	_hp_fill = ColorRect.new()
	_hp_fill.color = Color("ff3b6b")
	_hp_fill.position = Vector2(18, 18)
	_hp_fill.size = Vector2(220, 18)
	add_child_control(_hp_fill)
	_hp_label = _make_label("100 / 100", 12)
	_hp_label.position = Vector2(22, 18)
	add_child_control(_hp_label)

func _build_info() -> void:
	_info_label = _make_label("NEON WASTES", 13)
	_info_label.modulate = Color("9fb0ff")
	_info_label.position = Vector2(16, 44)
	add_child_control(_info_label)

	var hint := _make_label("Move WAD/Arrows  •  Shift sprint  •  Jump Space  •  L-Click use  •  R-Click mine  •  1-0/Scroll hotbar  •  E inventory  •  P peaceful  •  Esc pause  •  F11 fullscreen", 11)
	hint.modulate = Color(0.7, 0.75, 0.9, 0.8)
	hint.position = Vector2(16, VH - 20)
	add_child_control(hint)

	_clock_label = _make_label("Day 1  06:00  Day", 14)
	_clock_label.modulate = Color("ffe8a8")
	_clock_label.position = Vector2(VW - 220, 16)
	add_child_control(_clock_label)

	_peaceful_label = _make_label("PEACEFUL", 13)
	_peaceful_label.modulate = Color("39ff88")
	_peaceful_label.position = Vector2(VW - 220, 38)
	_peaceful_label.visible = false
	add_child_control(_peaceful_label)

func _build_hotbar() -> void:
	var total := Inventory.HOTBAR * (SLOT + PAD) - PAD
	var x0 := (VW - total) / 2
	var y := VH - SLOT - 28
	for i in Inventory.HOTBAR:
		var s := _make_slot(self, x0 + i * (SLOT + PAD), y, SLOT)
		var num := _make_label(str((i + 1) % 10), 9)
		num.position = Vector2(2, 1)
		num.modulate = Color(0.7, 0.75, 0.9)
		s.panel.add_child(num)
		_hotbar_slots.append(s)

func _build_inventory() -> void:
	_inv_panel = Control.new()
	_inv_panel.visible = false
	add_child_control(_inv_panel)

	var cols := Inventory.HOTBAR
	var rows := int(ceil(float(Inventory.SIZE) / cols))
	var gw := cols * (SLOT + PAD) - PAD
	var gh := rows * (SLOT + PAD) - PAD
	var x0 := (VW - gw) / 2 - 120
	var y0 := (VH - gh) / 2 - 20

	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", _panel_sb())
	bg.position = Vector2(x0 - 16, y0 - 40)
	bg.size = Vector2(gw + 32, gh + 56)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_panel.add_child(bg)
	var title := _make_label("CARGO", 16)
	title.modulate = Color("2dffff")
	title.position = Vector2(x0, y0 - 32)
	_inv_panel.add_child(title)

	for i in Inventory.SIZE:
		var cx := i % cols
		var cy := i / cols
		var s := _make_slot(_inv_panel, x0 + cx * (SLOT + PAD), y0 + cy * (SLOT + PAD), SLOT)
		_inv_slots.append(s)

func _build_crafting() -> void:
	_craft_panel = Control.new()
	_craft_panel.visible = false
	add_child_control(_craft_panel)

	var px := VW / 2 + 150
	var py := 110
	var w := 344
	var h := 500
	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", _panel_sb())
	bg.position = Vector2(px - 16, py - 40)
	bg.size = Vector2(w + 32, h + 56)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_craft_panel.add_child(bg)
	var title := _make_label("FABRICATOR", 16)
	title.modulate = Color("2dffff")
	title.position = Vector2(px, py - 32)
	_craft_panel.add_child(title)

	# scrollable list so the recipe set can keep growing
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(px, py)
	scroll.size = Vector2(w, h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_craft_panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(w - 14, 0)
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	for i in ItemDB.RECIPES.size():
		var r: Dictionary = ItemDB.RECIPES[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(w - 16, 32)
		b.text = _recipe_text(r)
		b.add_theme_font_size_override("font_size", 11)
		b.clip_text = true
		b.pressed.connect(_on_craft.bind(r))
		vbox.add_child(b)
		_craft_rows.append({"button": b, "recipe": r})

func _recipe_text(r: Dictionary) -> String:
	var out := "%s x%d  <=  " % [ItemDB.name_of(r.out[0]), r.out[1]]
	var parts := []
	for c in r.cost:
		parts.append("%dx %s" % [c[1], ItemDB.name_of(c[0])])
	return out + ", ".join(parts)

func _build_selected_label() -> void:
	# name of the currently held item, centred above the hotbar
	_sel_label = _make_label("", 13)
	_sel_label.modulate = Color("e8ecff")
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_label.size = Vector2(VW, 18)
	_sel_label.position = Vector2(0, VH - SLOT - 50)
	add_child_control(_sel_label)

func _build_tooltip() -> void:
	_tip = Panel.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_stylebox_override("panel", _normal_sb)
	_tip.visible = false
	_tip.z_index = 5
	add_child_control(_tip)
	_tip_label = _make_label("", 12)
	_tip_label.position = Vector2(7, 3)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_label)

func _build_vignette() -> void:
	var v := ColorRect.new()
	v.position = Vector2.ZERO
	v.size = Vector2(VW, VH)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vig_mat.set_shader_parameter("amount", 0.0)
	v.material = _vig_mat
	add_child_control(v)

func _build_pause() -> void:
	_pause_panel = Control.new()
	_pause_panel.visible = false
	_pause_panel.z_index = 20
	add_child_control(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.7)
	dim.position = Vector2.ZERO
	dim.size = Vector2(VW, VH)
	_pause_panel.add_child(dim)
	var title := _make_label("PAUSED", 34)
	title.modulate = Color("2dffff")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(VW, 40)
	title.position = Vector2(0, VH / 2 - 150)
	_pause_panel.add_child(title)
	_add_pause_button("Resume", VH / 2 - 70, func(): _set_paused(false))
	_add_pause_button("Toggle Fullscreen", VH / 2 - 20, _toggle_fullscreen)
	_add_pause_button("Toggle Enemies", VH / 2 + 30, func(): Game.toggle_enemies())

func _add_pause_button(text: String, y: int, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.size = Vector2(220, 40)
	b.position = Vector2(VW / 2 - 110, y)
	b.pressed.connect(cb)
	_pause_panel.add_child(b)

func _set_paused(p: bool) -> void:
	get_tree().paused = p
	_pause_panel.visible = p

func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _build_death_label() -> void:
	_death_label = _make_label("SYSTEMS REBOOTING...", 28)
	_death_label.modulate = Color("ff3b6b")
	_death_label.position = Vector2(VW / 2 - 170, VH / 2 - 20)
	_death_label.visible = false
	add_child_control(_death_label)

# ---------------------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_F11:
			_toggle_fullscreen()
		elif k >= KEY_1 and k <= KEY_9:
			Game.inventory.select(k - KEY_1)
		elif k == KEY_0:
			Game.inventory.select(9)
	if get_tree().paused:
		return
	if e is InputEventMouseButton and e.pressed:
		# scroll wheel cycles the hotbar (up = left, down = right)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			Game.inventory.select_relative(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			Game.inventory.select_relative(1)
	if e.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
	elif e.is_action_pressed("toggle_enemies"):
		Game.toggle_enemies()

func _toggle_inventory() -> void:
	var open := not _inv_panel.visible
	_inv_panel.visible = open
	_craft_panel.visible = open
	Game.ui_blocking = open

func _on_craft(r: Dictionary) -> void:
	Game.inventory.craft(r)

# ---------------------------------------------------------------------------
func _refresh() -> void:
	if Game.inventory == null:
		return
	for i in Inventory.HOTBAR:
		_fill_slot(_hotbar_slots[i], Game.inventory.slots[i], i == Game.inventory.selected)
	for i in Inventory.SIZE:
		_fill_slot(_inv_slots[i], Game.inventory.slots[i], false)
	for row in _craft_rows:
		row.button.disabled = not Game.inventory.can_craft(row.recipe)
	var sid := Game.inventory.selected_id()
	_sel_label.text = ItemDB.name_of(sid) if sid != "" else ""

func _fill_slot(s: Dictionary, stack, selected: bool) -> void:
	s.panel.add_theme_stylebox_override("panel", _select_sb if selected else _normal_sb)
	if stack == null:
		s.icon.texture = null
		s.label.text = ""
	else:
		s.icon.texture = Art.item_icon(stack.id)
		s.label.text = str(stack.count) if stack.count > 1 else ""

func _on_health(cur: float, maximum: float) -> void:
	if _hp_fill:
		_hp_fill.size.x = 220.0 * (cur / maximum)
		_hp_label.text = "%d / %d" % [int(round(cur)), int(round(maximum))]

func _on_death() -> void:
	_death_label.visible = true
	get_tree().create_timer(1.2).timeout.connect(func(): _death_label.visible = false)

# ---------------------------------------------------------------------------
# small node builders
func add_child_control(c: Control) -> void:
	add_child(c)

func _make_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l

func _make_slot(parent: Node, x: int, y: int, size: int) -> Dictionary:
	var panel := Panel.new()
	panel.position = Vector2(x, y)
	panel.size = Vector2(size, size)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # non-interactive; let wheel/clicks pass through
	panel.add_theme_stylebox_override("panel", _normal_sb)
	var icon := TextureRect.new()
	icon.position = Vector2(4, 4)
	icon.size = Vector2(size - 8, size - 8)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	var label := _make_label("", 11)
	label.position = Vector2(size - 20, size - 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	parent.add_child(panel)
	return {"panel": panel, "icon": icon, "label": label}
