class_name Inventory
extends RefCounted
## Slot-based inventory. The first HOTBAR slots are the hotbar; the rest are
## backpack storage. Mutating methods emit Game.inventory_changed so the UI can
## refresh without being tightly coupled.

const SIZE := 40
const HOTBAR := 10

var slots: Array = []   # each entry is null or {id:String, count:int}
var selected := 0       # selected hotbar slot index (0..HOTBAR-1)

func _init() -> void:
	slots.resize(SIZE)
	for i in SIZE:
		slots[i] = null

func _changed() -> void:
	Game.inventory_changed.emit()

func selected_id() -> String:
	var s = slots[selected]
	return s.id if s != null else ""

func select(i: int) -> void:
	selected = clampi(i, 0, HOTBAR - 1)
	_changed()

## Add `count` of an item, stacking where possible. Returns the leftover that
## did not fit (0 on full success).
func add(id: String, count: int) -> int:
	var ms := ItemDB.max_stack(id)
	# top up existing stacks first
	for i in SIZE:
		if count <= 0:
			break
		var s = slots[i]
		if s != null and s.id == id and s.count < ms:
			var space: int = ms - s.count
			var moved: int = min(space, count)
			s.count += moved
			count -= moved
	# then fill empty slots
	for i in SIZE:
		if count <= 0:
			break
		if slots[i] == null:
			var moved: int = min(ms, count)
			slots[i] = {"id": id, "count": moved}
			count -= moved
	if count >= 0:
		_changed()
	return count

func count(id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s.id == id:
			n += s.count
	return n

## Remove up to `count`; returns true only if the full amount was removed.
func remove(id: String, count: int) -> bool:
	if self.count(id) < count:
		return false
	for i in SIZE:
		if count <= 0:
			break
		var s = slots[i]
		if s != null and s.id == id:
			var taken: int = min(s.count, count)
			s.count -= taken
			count -= taken
			if s.count <= 0:
				slots[i] = null
	_changed()
	return true

## Remove one of the currently selected item (used when placing/consuming).
func consume_selected(n: int = 1) -> void:
	var s = slots[selected]
	if s == null:
		return
	s.count -= n
	if s.count <= 0:
		slots[selected] = null
	_changed()

func can_craft(recipe: Dictionary) -> bool:
	for c in recipe.cost:
		if count(c[0]) < c[1]:
			return false
	return true

func craft(recipe: Dictionary) -> bool:
	if not can_craft(recipe):
		return false
	for c in recipe.cost:
		remove(c[0], c[1])
	add(recipe.out[0], recipe.out[1])
	return true
