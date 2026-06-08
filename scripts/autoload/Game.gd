extends Node
## Global state, signals and input setup.
##
## Keeps cross-cutting references (world, player) and the player's inventory so
## that UI and entities can find each other without hard scene paths. Also
## registers the input map in code (keeps project.godot tidy and portable).

signal inventory_changed
signal health_changed(current: float, maximum: float)
signal hunger_changed(current: float, maximum: float)
signal player_died
signal enemies_toggled(enabled: bool)
signal alien_rep_changed(rep: float, friendly: bool)
signal armor_changed

# Untyped on purpose: typing these as World/Player would create a parse-time
# dependency cycle (those scripts reference this autoload back). Call sites
# annotate their own locals instead.
var world = null
var player = null
var inventory: Inventory = null
var environment: Environment = null   ## the WorldEnvironment's Environment (for bloom toggle)

var max_health := 100.0
var health := 100.0

var max_hunger := 100.0
var hunger := 100.0

var world_seed := 0
var ui_blocking := false   ## true while a full-screen panel (inventory) is open

var time_of_day := 0.30    ## 0..1, 0 = midnight, 0.5 = noon (driven by DayNight)
var day_count := 1
var weather := "Clear"     ## current weather label (driven by Weather)
var enemies_enabled := true ## peaceful mode toggle

var crafted := {}          ## ids of recipes/stations ever crafted (gates unlocks)
var max_tier_seen := 0     ## highest item tier obtained (gates "tier>=N")

# Reputation with the underground alien Kin: rises while you spend peaceful time
# near them, falls (and turns them hostile) if you attack them. At FRIEND_AT they
# turn friendly for good and stop being a threat.
const ALIEN_FRIEND_AT := 100.0
var alien_rep := 0.0
var alien_betrayed := false   ## attacked them after befriending — they distrust you

func _ready() -> void:
	randomize()
	world_seed = randi()
	_setup_input()

func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_add_action("toggle_inventory", [KEY_E, KEY_TAB])
	_add_action("toggle_enemies", [KEY_P])
	_add_action("pause", [KEY_ESCAPE])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("interact", [KEY_F])   # open a nearby storage pod
	_add_action("map", [KEY_M])        # toggle the fullscreen map
	_add_action("torch", [KEY_T])      # toggle the player's torch

func _add_action(name: String, keys: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)

func set_health(v: float) -> void:
	health = clampf(v, 0.0, max_health)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		player_died.emit()

func damage_player(amount: float) -> void:
	set_health(health - amount)

func heal_player(amount: float) -> void:
	set_health(health + amount)

func reset_health() -> void:
	set_health(max_health)

func set_hunger(v: float) -> void:
	hunger = clampf(v, 0.0, max_hunger)
	hunger_changed.emit(hunger, max_hunger)

func add_hunger(amount: float) -> void:
	set_hunger(hunger + amount)

func feed_player(amount: float) -> void:
	set_hunger(hunger + amount)

func reset_hunger() -> void:
	set_hunger(max_hunger)

# --- Armor: three equip slots that cut incoming damage (capped) ---
const ARMOR_SLOTS := ["head", "body", "legs"]
const ARMOR_CAP := 0.75
var armor := {"head": "", "body": "", "legs": ""}   # equipped item id per slot

func armor_reduction() -> float:
	var total := 0.0
	for slot in ARMOR_SLOTS:
		var id: String = armor[slot]
		if id != "":
			var it: Item = ItemDB.get_item(id)
			if it:
				total += it.stats.get("armor", 0.0)
	return clampf(total / 100.0, 0.0, ARMOR_CAP)

func armor_percent() -> int:
	return int(round(armor_reduction() * 100.0))

## Equip an armor item id into its slot; returns the id it displaced ("" if none).
func equip_armor(id: String) -> String:
	var it: Item = ItemDB.get_item(id)
	if it == null or not it.stats.has("slot"):
		return id                          # not armor: caller keeps it
	var slot: String = it.stats.slot
	var prev: String = armor.get(slot, "")
	armor[slot] = id
	armor_changed.emit()
	return prev

## Unequip a slot; returns the removed item id ("" if empty).
func unequip_armor(slot: String) -> String:
	var id: String = armor.get(slot, "")
	if id != "":
		armor[slot] = ""
		armor_changed.emit()
	return id

func set_enemies_enabled(v: bool) -> void:
	enemies_enabled = v
	enemies_toggled.emit(v)

func toggle_enemies() -> void:
	set_enemies_enabled(not enemies_enabled)

func aliens_friendly() -> bool:
	return alien_rep >= ALIEN_FRIEND_AT and not alien_betrayed

func add_alien_rep(delta: float) -> void:
	var before := aliens_friendly()
	alien_rep = clampf(alien_rep + delta, 0.0, ALIEN_FRIEND_AT)
	if delta < 0.0 and before:
		alien_betrayed = true        # turning on friends has a lasting cost
	alien_rep_changed.emit(alien_rep, aliens_friendly())

func clock_string() -> String:
	var mins := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [mins / 60, mins % 60]

func day_phase() -> String:
	var t := time_of_day
	if t < 0.23 or t >= 0.77: return "Night"
	if t < 0.30: return "Dawn"
	if t < 0.70: return "Day"
	return "Dusk"
