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
	"plating":     {"name": "Hull Plating",  "type": BLOCK, "max_stack": 999, "tile": Tiles.PLATING,  "color": Color("7a80b0")},
	"neon_glass":  {"name": "Neon Glass",    "type": BLOCK, "max_stack": 999, "tile": Tiles.NEON,     "color": Color("ff2bd6")},

	"crystal":     {"name": "Vyrite Crystal","type": MATERIAL, "max_stack": 999, "color": Color("ff4df0")},
	"metal_ore":   {"name": "Ferralite",     "type": MATERIAL, "max_stack": 999, "color": Color("c4c4d6")},
	"energy_core": {"name": "Ion Core",      "type": MATERIAL, "max_stack": 999, "color": Color("2dffff")},
	"scrap":       {"name": "Alien Scrap",   "type": MATERIAL, "max_stack": 999, "color": Color("ff8a3a")},
}

## Recipes craftable anywhere (no station system in this slice).
## Each recipe: {out:[id,count], cost:[[id,count], ...]}
var RECIPES := [
	{"out": ["plating", 2],    "cost": [["metal_ore", 2]]},
	{"out": ["neon_glass", 4], "cost": [["sand", 2], ["energy_core", 1]]},
	{"out": ["med_cell", 1],   "cost": [["biomass", 4], ["crystal", 1]]},
	{"out": ["blaster", 1],    "cost": [["metal_ore", 6], ["crystal", 3], ["energy_core", 2]]},
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
