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

func _ready() -> void:
	layer = 10
	_make_styleboxes()
	_build_health()
	_build_info()
	_build_hotbar()
	_build_inventory()
	_build_crafting()
	_build_death_label()

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

func _biome_name(b: int) -> String:
	match b:
		World.TUNDRA: return "CRYO TUNDRA"
		World.DUNES: return "GLASS DUNES"
		World.JUNGLE: return "TOXIC JUNGLE"
		_: return "NEON WASTES"

# ---------------------------------------------------------------------------
func _make_styleboxes() -> void:
	_normal_sb = StyleBoxFlat.new()
	_normal_sb.bg_color = Color(0.07, 0.08, 0.13, 0.85)
	_normal_sb.set_border_width_all(1)
	_normal_sb.border_color = Color(0.3, 0.34, 0.5)
	_normal_sb.set_corner_radius_all(2)

	_select_sb = StyleBoxFlat.new()
	_select_sb.bg_color = Color(0.10, 0.12, 0.2, 0.9)
	_select_sb.set_border_width_all(2)
	_select_sb.border_color = Color("2dffff")
	_select_sb.set_corner_radius_all(2)

func _build_health() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.position = Vector2(16, 16)
	bg.size = Vector2(224, 22)
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

	var hint := _make_label("Move WAD/Arrows  •  Jump Space  •  L-Click use item  •  R-Click mine  •  1-0 hotbar  •  E inventory  •  P peaceful", 11)
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

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.92)
	bg.position = Vector2(x0 - 16, y0 - 40)
	bg.size = Vector2(gw + 32, gh + 56)
	_inv_panel.add_child(bg)
	var title := _make_label("CARGO", 16)
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

	var px := VW / 2 + 170
	var py := 150
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.06, 0.92)
	bg.position = Vector2(px - 16, py - 40)
	bg.size = Vector2(330, ItemDB.RECIPES.size() * 40 + 56)
	_craft_panel.add_child(bg)
	var title := _make_label("FABRICATOR", 16)
	title.position = Vector2(px, py - 32)
	_craft_panel.add_child(title)

	for i in ItemDB.RECIPES.size():
		var r: Dictionary = ItemDB.RECIPES[i]
		var b := Button.new()
		b.position = Vector2(px, py + i * 40)
		b.size = Vector2(300, 34)
		b.text = _recipe_text(r)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_craft.bind(r))
		_craft_panel.add_child(b)
		_craft_rows.append({"button": b, "recipe": r})

func _recipe_text(r: Dictionary) -> String:
	var out := "%s x%d  <=  " % [ItemDB.name_of(r.out[0]), r.out[1]]
	var parts := []
	for c in r.cost:
		parts.append("%dx %s" % [c[1], ItemDB.name_of(c[0])])
	return out + ", ".join(parts)

func _build_death_label() -> void:
	_death_label = _make_label("SYSTEMS REBOOTING...", 28)
	_death_label.modulate = Color("ff3b6b")
	_death_label.position = Vector2(VW / 2 - 170, VH / 2 - 20)
	_death_label.visible = false
	add_child_control(_death_label)

# ---------------------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			Game.inventory.select(k - KEY_1)
		elif k == KEY_0:
			Game.inventory.select(9)
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
