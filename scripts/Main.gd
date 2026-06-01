extends Node2D
## Boots the game: builds the parallax space backdrop, the world, the player,
## the enemy spawner and the HUD, then drops the player onto the surface.

const HUDScript := preload("res://scripts/ui/HUD.gd")
const SpawnerScript := preload("res://scripts/world/EnemySpawner.gd")

func _ready() -> void:
	_build_background()

	var world := World.new()
	world.name = "World"
	add_child(world)
	Game.world = world

	var player := Player.new()
	player.name = "Player"
	add_child(player)
	# place the player just above the surface at world origin
	var spawn_y := (world.surface_tile_y(0) - 4) * World.TILE
	player.global_position = Vector2(0, spawn_y)

	var spawner := Node.new()
	spawner.set_script(SpawnerScript)
	spawner.name = "EnemySpawner"
	add_child(spawner)

	var hud := CanvasLayer.new()
	hud.set_script(HUDScript)
	hud.name = "HUD"
	add_child(hud)

func _build_background() -> void:
	var bg := ParallaxBackground.new()
	bg.layer = -100
	var layer := ParallaxLayer.new()
	layer.motion_scale = Vector2(0.2, 0.2)
	layer.motion_mirroring = Vector2(256, 256)
	var sprite := Sprite2D.new()
	sprite.texture = Art.sprite("star")
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(sprite)
	bg.add_child(layer)
	add_child(bg)
