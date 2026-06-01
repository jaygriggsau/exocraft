extends Node
## Spawns enemies in a ring around the player, just off-screen, up to a cap.

const INTERVAL := 2.5
const MAX_ENEMIES := 8
const MIN_TILES := 16    ## spawn no closer than this (off-screen)
const MAX_TILES := 24

var _t := 0.0

func _process(dt: float) -> void:
	if Game.player == null or Game.world == null:
		return
	_t += dt
	if _t < INTERVAL:
		return
	_t = 0.0
	if get_tree().get_nodes_in_group("enemies").size() >= MAX_ENEMIES:
		return
	if randf() < 0.6:
		_spawn_crawler()
	else:
		_spawn_drone()

func _spawn_crawler() -> void:
	var side := 1 if randf() < 0.5 else -1
	var ptile: Vector2i = Game.world.world_to_tile(Game.player.global_position)
	var tx := ptile.x + side * randi_range(MIN_TILES, MAX_TILES)
	var ty: int = Game.world.surface_tile_y(tx) - 2
	var c := Crawler.new()
	c.global_position = Game.world.tile_to_world_center(Vector2i(tx, ty))
	Game.world.add_child(c)

func _spawn_drone() -> void:
	var ang := randf() * TAU
	var dist := randi_range(MIN_TILES, MAX_TILES) * World.TILE
	var d := Drone.new()
	d.setup(Game.player.global_position + Vector2(cos(ang), sin(ang)) * dist)
	Game.world.add_child(d)
