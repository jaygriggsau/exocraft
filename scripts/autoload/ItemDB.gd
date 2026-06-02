extends Node
## Item + recipe registry.
##
## Items are referenced everywhere by their string id. Each item has a `type`
## that decides what happens when it is the selected hotbar item and the player
## "uses" it (left click):
##   TOOL       -> mine the tile under the cursor
##   WEAPON     -> fire a projectile toward the cursor
##   BLOCK      -> place its `tile` at the cursor
##   CONSUMABLE -> apply its effect (e.g. heal) and consume one
##   MATERIAL   -> crafting ingredient only, no use action

enum { TOOL, WEAPON, BLOCK, CONSUMABLE, MATERIAL }

## id -> definition. Fields vary by type; common ones:
##   name, type, max_stack, color (icon tint / accent)
##   tile (BLOCK), damage/cooldown/speed (WEAPON), heal (CONSUMABLE)
var ITEMS := {
	"pickaxe":     {"name": "Particle Gun",  "type": TOOL,       "max_stack": 1,   "color": Color("2dffff")},
	"blaster":     {"name": "Ion Blaster",   "type": WEAPON,     "max_stack": 1,   "color": Color("ff2bd6"), "damage": 12.0, "cooldown": 0.22, "speed": 360.0},
	"med_cell":    {"name": "Med-Cell",      "type": CONSUMABLE, "max_stack": 20,  "color": Color("39ff88"), "heal": 40.0},

	"dirt":        {"name": "Regolith",      "type": BLOCK, "max_stack": 999, "tile": Tiles.DIRT,     "color": Color("564470")},
	"stone":       {"name": "Slate",         "type": BLOCK, "max_stack": 999, "tile": Tiles.STONE,    "color": Color("43465e")},
	"ice":         {"name": "Cryo-Ice",      "type": BLOCK, "max_stack": 999, "tile": Tiles.ICE,      "color": Color("8fd6ef")},
	"biomass":     {"name": "Biomass",       "type": BLOCK, "max_stack": 999, "tile": Tiles.JUNGLE,   "color": Color("a6ff3a")},
	"sand":        {"name": "Glass-Sand",    "type": BLOCK, "max_stack": 999, "tile": Tiles.SAND,     "color": Color("d9c27a")},
	"darkrock":    {"name": "Obsidite",      "type": BLOCK, "max_stack": 999, "tile": Tiles.DARKROCK, "color": Color("2e2138")},
	"wood_block":  {"name": "Bio-Timber",    "type": BLOCK, "max_stack": 999, "tile": Tiles.WOOD,     "color": Color("7c6b4e")},
	"plating":     {"name": "Hull Plating",  "type": BLOCK, "max_stack": 999, "tile": Tiles.PLATING,  "color": Color("7a80b0")},
	"neon_glass":  {"name": "Neon Glass",    "type": BLOCK, "max_stack": 999, "tile": Tiles.NEON,     "color": Color("ff2bd6")},

	"wood":        {"name": "Xylo-Timber",   "type": MATERIAL, "max_stack": 999, "color": Color("9a7a52")},
	"crystal":     {"name": "Vyrite Crystal","type": MATERIAL, "max_stack": 999, "color": Color("ff4df0")},
	"metal_ore":   {"name": "Ferralite",     "type": MATERIAL, "max_stack": 999, "color": Color("c4c4d6")},
	"energy_core": {"name": "Ion Core",      "type": MATERIAL, "max_stack": 999, "color": Color("2dffff")},
	"scrap":       {"name": "Alien Scrap",   "type": MATERIAL, "max_stack": 999, "color": Color("ff8a3a")},

	# --- The 10 foundational building resources (refined crafting components) ---
	# Tier 1: refined directly from raw drops
	"metal_ingot":  {"name": "Metal Ingot",   "type": MATERIAL, "max_stack": 999, "color": Color("b8bcd0")},
	"glass_pane":   {"name": "Glass Pane",     "type": MATERIAL, "max_stack": 999, "color": Color("aee8ff")},
	"polymer":      {"name": "Bio-Polymer",    "type": MATERIAL, "max_stack": 999, "color": Color("a06cff")},
	"power_cell":   {"name": "Power Cell",      "type": MATERIAL, "max_stack": 999, "color": Color("2dffff")},
	"crystal_lens": {"name": "Crystal Lens",    "type": MATERIAL, "max_stack": 999, "color": Color("ff7ae0")},
	# Tier 2/3: combined from the tier-1 components
	"alloy_plate":  {"name": "Alloy Plate",     "type": MATERIAL, "max_stack": 999, "color": Color("8a93b8")},
	"circuit_board":{"name": "Circuit Board",   "type": MATERIAL, "max_stack": 999, "color": Color("3aff8f")},
	"conduit":      {"name": "Conduit",         "type": MATERIAL, "max_stack": 999, "color": Color("ff9a3a")},
	"composite":    {"name": "Composite Panel", "type": MATERIAL, "max_stack": 999, "color": Color("5ad0c0")},
	"nanocore":     {"name": "Nanocore",        "type": MATERIAL, "max_stack": 999, "color": Color("eaffff")},
}

## Recipes craftable anywhere (no station system in this slice).
## Each recipe: {out:[id,count], cost:[[id,count], ...]}
var RECIPES := [
	# --- foundation: refine raw drops into the 10 building resources ---
	{"out": ["metal_ingot", 1],  "cost": [["metal_ore", 2]]},
	{"out": ["glass_pane", 1],    "cost": [["sand", 2]]},
	{"out": ["polymer", 1],       "cost": [["wood", 2]]},
	{"out": ["power_cell", 1],    "cost": [["energy_core", 1], ["scrap", 1]]},
	{"out": ["crystal_lens", 1],  "cost": [["crystal", 1]]},
	{"out": ["alloy_plate", 1],   "cost": [["metal_ingot", 2]]},
	{"out": ["circuit_board", 1], "cost": [["metal_ingot", 1], ["crystal_lens", 1]]},
	{"out": ["conduit", 1],       "cost": [["metal_ingot", 1], ["power_cell", 1]]},
	{"out": ["composite", 1],     "cost": [["polymer", 1], ["alloy_plate", 1]]},
	{"out": ["nanocore", 1],      "cost": [["circuit_board", 1], ["power_cell", 1]]},

	# --- buildables / gear, now built from the foundation resources ---
	{"out": ["plating", 2],    "cost": [["alloy_plate", 1]]},
	{"out": ["neon_glass", 4], "cost": [["glass_pane", 2], ["power_cell", 1]]},
	{"out": ["wood_block", 4], "cost": [["wood", 2]]},
	{"out": ["med_cell", 1],   "cost": [["biomass", 4], ["crystal", 1]]},
	{"out": ["blaster", 1],    "cost": [["circuit_board", 1], ["alloy_plate", 1], ["power_cell", 1]]},
	{"out": ["stone", 1],      "cost": [["darkrock", 1]]},
]

func get_item(id: String) -> Variant:
	return ITEMS.get(id, null)

func name_of(id: String) -> String:
	var d = ITEMS.get(id)
	return d.name if d != null else id

func type_of(id: String) -> int:
	var d = ITEMS.get(id)
	return d.type if d != null else MATERIAL

func max_stack(id: String) -> int:
	var d = ITEMS.get(id)
	return d.max_stack if d != null else 999

func place_tile(id: String) -> int:
	## Tile id this item places, or Tiles.AIR if it is not placeable.
	var d = ITEMS.get(id)
	if d != null and d.type == BLOCK:
		return d.tile
	return Tiles.AIR

func color_of(id: String) -> Color:
	var d = ITEMS.get(id)
	return d.color if d != null else Color.WHITE
