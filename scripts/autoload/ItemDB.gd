extends Node
## Data-driven item/recipe registry.
##
## The ENGINE lives here; all CONTENT lives in editable .tres assets under
## res://data/. Add or rebalance items/recipes by editing those assets — no code
## change required. This autoload just scans the folders, exposes lookups +
## crafting rules, and runs a validation pass on load.

enum { TOOL, WEAPON, BLOCK, CONSUMABLE, MATERIAL, DEPLOYABLE }   # gameplay use, derived from data
enum { LOCKED, AVAILABLE, CRAFTABLE }                # recipe UI states

const ITEM_DIR := "res://data/items"
const RECIPE_DIR := "res://data/recipes"

var ITEMS := {}        # id -> Item
var RECIPES: Array = []  # Array[Recipe]

func _ready() -> void:
	_load_items()
	_load_recipes()
	_validate()

func _load_items() -> void:
	var d := DirAccess.open(ITEM_DIR)
	if d == null:
		push_warning("ItemDB: missing %s" % ITEM_DIR)
		return
	for f in d.get_files():
		if f.ends_with(".tres"):
			var it: Item = load(ITEM_DIR + "/" + f)
			if it and it.id != "":
				ITEMS[it.id] = it

func _load_recipes() -> void:
	var d := DirAccess.open(RECIPE_DIR)
	if d == null:
		push_warning("ItemDB: missing %s" % RECIPE_DIR)
		return
	for f in d.get_files():
		if f.ends_with(".tres"):
			var r: Recipe = load(RECIPE_DIR + "/" + f)
			if r and r.output_item:
				RECIPES.append(r)

# ---------------------------------------------------------------------------
# Item lookups
# ---------------------------------------------------------------------------
func get_item(id: String) -> Item:
	return ITEMS.get(id)

func has_item(id: String) -> bool:
	return ITEMS.has(id)

func name_of(id: String) -> String:
	var it: Item = ITEMS.get(id)
	return it.display_name if it else id

func max_stack(id: String) -> int:
	var it: Item = ITEMS.get(id)
	return it.stack_size if it else 999

func color_of(id: String) -> Color:
	var it: Item = ITEMS.get(id)
	return it.color if it else Color.WHITE

func tier_of(id: String) -> int:
	var it: Item = ITEMS.get(id)
	return it.tier if it else 0

func place_tile(id: String) -> int:
	var it: Item = ITEMS.get(id)
	return it.place_tile if (it and it.place_tile >= 0) else Tiles.AIR

func type_of(id: String) -> int:
	var it: Item = ITEMS.get(id)
	if it == null:
		return MATERIAL
	if it.place_tile >= 0:
		return BLOCK
	if it.stats.has("damage"):
		return WEAPON
	if it.heal > 0.0:
		return CONSUMABLE
	if it.category == "tool" or it.stats.has("mining_power"):
		return TOOL
	if it.category == "structure":
		return DEPLOYABLE          # stations + storage pods are placed in the world
	return MATERIAL

# ---------------------------------------------------------------------------
# Crafting rules
# ---------------------------------------------------------------------------
func recipe_state(r: Recipe) -> int:
	if not is_unlocked(r):
		return LOCKED
	if Game.inventory and _has_inputs(r):
		return CRAFTABLE
	return AVAILABLE

func is_unlocked(r: Recipe) -> bool:
	# must be standing near the required station (built + placed in the world)
	if r.station != "":
		if Game.world == null or Game.player == null:
			return false
		if not Game.world.has_station_near(Game.player.global_position, r.station):
			return false
	return _check_condition(r.unlock_condition)

## How many of an id the player can use to craft: inventory + nearby storage pods.
func available_count(id: String) -> int:
	var n := Game.inventory.count(id)
	if Game.world and Game.player:
		for pod in Game.world.pods_near(Game.player.global_position):
			n += pod.count(id)
	return n

func _consume(id: String, qty: int) -> void:
	var take: int = mini(qty, Game.inventory.count(id))
	if take > 0:
		Game.inventory.remove(id, take)
		qty -= take
	if qty > 0 and Game.world and Game.player:
		for pod in Game.world.pods_near(Game.player.global_position):
			if qty <= 0:
				break
			var t: int = mini(qty, pod.count(id))
			if t > 0:
				pod.remove(id, t)
				qty -= t

func _check_condition(cond: String) -> bool:
	if cond == "":
		return true
	if cond.begins_with("tier>="):
		return Game.max_tier_seen >= int(cond.substr(6))
	if cond.begins_with("crafted:"):
		return Game.crafted.has(cond.substr(8))
	return true

func _has_inputs(r: Recipe) -> bool:
	for inp in r.inputs:
		if inp.item == null:
			continue
		if available_count(inp.item.id) < inp.quantity:
			return false
	return true

func try_craft(r: Recipe) -> bool:
	if recipe_state(r) != CRAFTABLE:
		return false
	for inp in r.inputs:
		if inp.item:
			_consume(inp.item.id, inp.quantity)
	Game.inventory.add(r.output_item.id, r.output_quantity)
	Game.crafted[r.output_item.id] = true
	return true

## Short human reason a recipe is locked, for the UI ("needs Fabricator", etc.)
func lock_reason(r: Recipe) -> String:
	if r.station != "" and (Game.world == null or Game.player == null \
			or not Game.world.has_station_near(Game.player.global_position, r.station)):
		return "needs " + name_of(r.station) + " nearby"
	var c := r.unlock_condition
	if c.begins_with("tier>="):
		return "reach tier " + c.substr(6)
	if c.begins_with("crafted:"):
		return "needs " + name_of(c.substr(8))
	return "locked"

# ---------------------------------------------------------------------------
# Validation: orphan items + balance smells (run once on load)
# ---------------------------------------------------------------------------
func _validate() -> void:
	var used := {}
	for r in RECIPES:
		for inp in r.inputs:
			if inp.item:
				used[inp.item.id] = true
				if r.output_item and inp.item.tier > r.output_item.tier:
					push_warning("[balance] '%s' needs '%s' (t%d) > output t%d" % [
						r.output_item.id, inp.item.id, inp.item.tier, r.output_item.tier])
	for id in ITEMS:
		var it: Item = ITEMS[id]
		var end_use := type_of(id) != MATERIAL or it.category == "structure"
		if not used.has(id) and not end_use:
			push_warning("[orphan] '%s' is never a recipe input and not an end item" % id)
	print("ItemDB: loaded %d items, %d recipes" % [ITEMS.size(), RECIPES.size()])
