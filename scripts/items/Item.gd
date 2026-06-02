class_name Item
extends Resource
## A single item definition. Authored as a .tres asset and edited in the
## inspector — no code changes needed to add or rebalance items.

@export var id: String = ""                 ## unique, stable (e.g. "metal_ore")
@export var display_name: String = ""
@export var tier: int = 0                    ## 0..3, gates progression
@export var category: String = "raw"         ## raw / refined / component / tool / weapon / structure
@export var stack_size: int = 999
@export var base_value: int = 1              ## economy / trade math; tracks power
@export var stats: Dictionary = {}           ## gear only: {"damage":12, "mining_power":2, "cooldown":0.2, "speed":360}
@export var icon: Texture2D                  ## optional; a tinted icon is generated if null
@export var color: Color = Color.WHITE       ## icon tint + UI theming
@export var place_tile: int = -1             ## Tiles id if placeable as a block, else -1
@export var heal: float = 0.0                ## consumable heal amount
