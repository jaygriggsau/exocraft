extends Node
## Global state, signals and input setup.
##
## Keeps cross-cutting references (world, player) and the player's inventory so
## that UI and entities can find each other without hard scene paths. Also
## registers the input map in code (keeps project.godot tidy and portable).

signal inventory_changed
signal health_changed(current: float, maximum: float)
signal player_died

# Untyped on purpose: typing these as World/Player would create a parse-time
# dependency cycle (those scripts reference this autoload back). Call sites
# annotate their own locals instead.
var world = null
var player = null
var inventory: Inventory = null

var max_health := 100.0
var health := 100.0

var world_seed := 0
var ui_blocking := false   ## true while a full-screen panel (inventory) is open

func _ready() -> void:
	randomize()
	world_seed = randi()
	_setup_input()

func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_add_action("toggle_inventory", [KEY_E, KEY_TAB])

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
