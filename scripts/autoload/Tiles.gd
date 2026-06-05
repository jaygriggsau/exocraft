extends Node
## Tile type registry.
##
## Every solid/visible block in the world is one of these ids. The DEFS table
## drives both how a tile is drawn (see Art.gd) and what it is materially
## (solid, what it drops when mined). AIR (0) is the absence of a tile.

const AIR := 0
const DIRT := 1
const STONE := 2
const GRASS := 3      # Neon Wastes surface
const ICE := 4        # Cryo Tundra
const JUNGLE := 5     # Toxic Jungle surface
const SAND := 6       # Dunes
const CRYSTAL := 7    # ore
const METAL := 8      # ore
const ENERGY := 9     # ore (glowing)
const PLATING := 10   # crafted building block
const NEON := 11      # crafted neon glass
const DARKROCK := 12  # deep biome stone
const WOOD := 13      # harvested/crafted alien wood
const EXOTIC := 14    # deep exotic-matter ore (tier 3)
# --- crafted building set (walls / windows / doors) ---
const STONE_BRICK := 15
const METAL_WALL := 16
const OBSIDIAN_BRICK := 17
const GLASS_WINDOW := 18        # solid but transparent (light passes through)
const REINFORCED_WINDOW := 19
const WOOD_DOOR := 20           # doors come in closed/open pairs; open is passable
const WOOD_DOOR_OPEN := 21
const METAL_DOOR := 22
const METAL_DOOR_OPEN := 23
const BLAST_DOOR := 24
const BLAST_DOOR_OPEN := 25

## id -> definition dictionary.
## Fields:
##   name   : display name
##   item   : item id produced when the tile is mined (see ItemDB)
##   style  : how Art renders it ("soil","block","grass","ore","plating","neon")
##   base   : main colour
##   accent : secondary/detail colour
##   top    : (grass style) colour of the top band
##   ore    : (ore style) colour of the mineral specks
##   glow   : whether the tile emits a faint glow (cosmetic)
##   hardness : relative time to absorb — stronger materials take longer to mine
##              (a hardness-1 block ~= 0.35s with the basic Particle Gun; ranges
##              from soft sand ~0.5 up to the deep Exotic vein ~8.0)
var DEFS := {
	DIRT:    {"name": "Regolith",     "item": "dirt",        "style": "soil",    "base": Color("3b2f4a"), "accent": Color("564470"), "glow": false, "hardness": 0.7},
	STONE:   {"name": "Slate",        "item": "stone",       "style": "block",   "base": Color("2e2f3e"), "accent": Color("43465e"), "glow": false, "hardness": 1.8},
	GRASS:   {"name": "Bio-Turf",     "item": "dirt",        "style": "grass",   "base": Color("3b2f4a"), "accent": Color("564470"), "top": Color("2bf0a0"), "glow": false, "hardness": 0.7},
	ICE:     {"name": "Cryo-Ice",     "item": "ice",         "style": "block",   "base": Color("8fd6ef"), "accent": Color("d6f4ff"), "glow": false, "hardness": 1.2},
	JUNGLE:  {"name": "Spore-Turf",   "item": "biomass",     "style": "grass",   "base": Color("33402a"), "accent": Color("48562f"), "top": Color("a6ff3a"), "glow": false, "hardness": 0.7},
	SAND:    {"name": "Glass-Sand",   "item": "sand",        "style": "block",   "base": Color("d9c27a"), "accent": Color("efe0a8"), "glow": false, "hardness": 0.5},
	CRYSTAL: {"name": "Vyrite Ore",   "item": "crystal",     "style": "ore",     "base": Color("2e2f3e"), "accent": Color("43465e"), "ore": Color("ff4df0"), "glow": true,  "light": Color("ff4df0"), "light_energy": 0.9, "hardness": 3.2},
	METAL:   {"name": "Ferralite",    "item": "metal_ore",   "style": "ore",     "base": Color("2e2f3e"), "accent": Color("43465e"), "ore": Color("c4c4d6"), "glow": false, "hardness": 2.6},
	ENERGY:  {"name": "Ion Ore",      "item": "energy_core", "style": "ore",     "base": Color("2e2f3e"), "accent": Color("43465e"), "ore": Color("2dffff"), "glow": true,  "light": Color("2dffff"), "light_energy": 1.3, "hardness": 4.2},
	PLATING: {"name": "Hull Plating", "item": "plating",     "style": "plating", "base": Color("4a4e6b"), "accent": Color("7a80b0"), "glow": false, "hardness": 3.8},
	NEON:    {"name": "Neon Glass",   "item": "neon_glass",  "style": "neon",    "base": Color("10131f"), "accent": Color("ff2bd6"), "glow": true,  "light": Color("ff2bd6"), "light_energy": 1.1, "hardness": 0.9},
	DARKROCK:{"name": "Obsidite",     "item": "darkrock",    "style": "block",   "base": Color("1a1320"), "accent": Color("2e2138"), "glow": false, "hardness": 5.5},
	WOOD:    {"name": "Bio-Timber",   "item": "wood",        "style": "plating", "base": Color("584438"), "accent": Color("7c6b4e"), "glow": false, "hardness": 1.4},
	EXOTIC:  {"name": "Exotic Vein",  "item": "exotic_matter","style": "ore",    "base": Color("1a1320"), "accent": Color("2e2138"), "ore": Color("b06aff"), "glow": true, "light": Color("b06aff"), "light_energy": 1.2, "hardness": 8.0},
	# --- crafted walls ---
	STONE_BRICK: {"name": "Slate Brick",      "item": "stone_brick",      "style": "brick", "base": Color("3a3c4e"), "accent": Color("555876"), "glow": false, "hardness": 2.0},
	METAL_WALL:  {"name": "Metal Wall",       "item": "metal_wall",       "style": "panel", "base": Color("5a6076"), "accent": Color("9aa0c0"), "glow": false, "hardness": 3.0},
	OBSIDIAN_BRICK: {"name": "Obsidite Brick","item": "obsidian_brick",   "style": "brick", "base": Color("241a32"), "accent": Color("3e2e52"), "glow": false, "hardness": 6.0},
	# --- windows (solid, see-through: keep collision, skip light occluder) ---
	GLASS_WINDOW:     {"name": "Glass Window",      "item": "glass_window",     "style": "window", "base": Color("6a7a86"), "accent": Color("aee8ff"), "glow": false, "no_occlude": true, "hardness": 1.0},
	REINFORCED_WINDOW:{"name": "Reinforced Window", "item": "reinforced_window","style": "window", "base": Color("7a80b0"), "accent": Color("bfeaff"), "glow": false, "no_occlude": true, "hardness": 2.6},
	# --- doors (closed = solid wall; open = passable doorway) ---
	WOOD_DOOR:      {"name": "Timber Door", "item": "wood_door",  "style": "door",      "base": Color("6b4f34"), "accent": Color("452f1c"), "handle": Color("d8c060"), "glow": false, "door": true, "door_open": WOOD_DOOR_OPEN, "hardness": 1.5},
	WOOD_DOOR_OPEN: {"name": "Timber Door", "item": "wood_door",  "style": "door_open", "base": Color("6b4f34"), "accent": Color("452f1c"), "handle": Color("d8c060"), "glow": false, "door": true, "passable": true, "door_closed": WOOD_DOOR, "hardness": 1.5},
	METAL_DOOR:      {"name": "Metal Door", "item": "metal_door", "style": "door",      "base": Color("5a6076"), "accent": Color("2a3040"), "handle": Color("c4c4d6"), "glow": false, "door": true, "door_open": METAL_DOOR_OPEN, "hardness": 3.0},
	METAL_DOOR_OPEN: {"name": "Metal Door", "item": "metal_door", "style": "door_open", "base": Color("5a6076"), "accent": Color("2a3040"), "handle": Color("c4c4d6"), "glow": false, "door": true, "passable": true, "door_closed": METAL_DOOR, "hardness": 3.0},
	BLAST_DOOR:      {"name": "Blast Door", "item": "blast_door", "style": "door",      "base": Color("4a4e6b"), "accent": Color("23283a"), "handle": Color("ff3a3a"), "glow": false, "door": true, "door_open": BLAST_DOOR_OPEN, "hardness": 4.5},
	BLAST_DOOR_OPEN: {"name": "Blast Door", "item": "blast_door", "style": "door_open", "base": Color("4a4e6b"), "accent": Color("23283a"), "handle": Color("ff3a3a"), "glow": false, "door": true, "passable": true, "door_closed": BLAST_DOOR, "hardness": 4.5},
}

func def(id: int) -> Variant:
	return DEFS.get(id, null)

func is_solid(id: int) -> bool:
	# passable tiles (an open door) exist in DEFS but don't collide
	var d = DEFS.get(id)
	return d != null and not d.get("passable", false)

## Is this tile part of a door (closed or open)?
func is_door(id: int) -> bool:
	var d = DEFS.get(id)
	return d != null and d.get("door", false)

func is_passable(id: int) -> bool:
	var d = DEFS.get(id)
	return d != null and d.get("passable", false)

## The paired state of a door tile (closed<->open); returns id unchanged if not a door.
func door_toggle(id: int) -> int:
	var d = DEFS.get(id)
	if d == null:
		return id
	return d.get("door_open", d.get("door_closed", id))

func is_glowing(id: int) -> bool:
	var d = DEFS.get(id)
	return d != null and d.get("glow", false)

func glow_color(id: int) -> Color:
	var d = DEFS.get(id)
	return d.get("light", Color.WHITE) if d != null else Color.WHITE

func glow_energy(id: int) -> float:
	var d = DEFS.get(id)
	return d.get("light_energy", 1.0) if d != null else 1.0

func drop_item(id: int) -> String:
	var d = DEFS.get(id)
	return d.item if d != null else ""

func hardness(id: int) -> float:
	var d = DEFS.get(id)
	return d.hardness if d != null else 1.0

func ids() -> Array:
	return DEFS.keys()

func max_id() -> int:
	var m := 0
	for k in DEFS.keys():
		m = max(m, k)
	return m
