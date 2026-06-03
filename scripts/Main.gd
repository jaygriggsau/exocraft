extends Node2D
## Boots the game: neon-bloom environment, the day/night lighting manager, the
## world, the player, the enemy spawner and the HUD.

const HUDScript := preload("res://scripts/ui/HUD.gd")
const SpawnerScript := preload("res://scripts/world/EnemySpawner.gd")

func _ready() -> void:
	_build_environment()

	var daynight := DayNight.new()
	daynight.name = "DayNight"
	add_child(daynight)

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

func _build_environment() -> void:
	# Subtle bloom makes the neon lights and ores glow (Forward+/Mobile only;
	# ignored harmlessly on the Compatibility renderer).
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.0
	env.glow_enabled = Settings.bloom
	Game.environment = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
