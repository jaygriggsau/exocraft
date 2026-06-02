class_name Recipe
extends Resource
## A crafting recipe. Authored as a .tres asset. Holds Item references for type
## safety, a required crafting station, and an unlock condition string.

@export var output_item: Item
@export var output_quantity: int = 1
@export var inputs: Array[RecipeInput] = []
@export var station: String = ""              ## "" = hand-craft; else station id you must own
@export var unlock_condition: String = ""     ## "" / "tier>=N" / "crafted:<id>"
