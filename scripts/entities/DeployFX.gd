class_name DeployFX
extends RefCounted
## Plays the "build" animation for a deployed structure: a small seed-pod pops
## in, then the structure expands up from its base with a flash, a light pulse,
## and rising assembly sparks. Call DeployFX.play(self, sprite) from _ready.

static func play(host: Node2D, sprite: Sprite2D) -> void:
	var h := float(sprite.texture.get_height())

	# the structure starts collapsed at its base, over-bright
	sprite.scale = Vector2(0.6, 0.0)
	sprite.modulate = Color(1.7, 1.7, 2.0)

	# a little seed-pod orb that pops in first
	var seed := Sprite2D.new()
	seed.texture = Art.light_texture()
	seed.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	seed.modulate = Color("aef6ff")
	seed.scale = Vector2.ZERO
	seed.position = Vector2(0, -6)
	host.add_child(seed)

	# a bright construction light that pulses then fades
	var fl := PointLight2D.new()
	fl.texture = Art.light_texture()
	fl.color = Color("aef6ff")
	fl.energy = 0.0
	fl.scale = Vector2(0.7, 0.7)
	fl.position = Vector2(0, -h / 2.0)
	host.add_child(fl)

	var tw := host.create_tween()
	# phase A — seed pops + flash
	tw.tween_property(seed, "scale", Vector2(0.5, 0.5), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(fl, "energy", 2.4, 0.14)
	# phase B — structure builds up out of the seed
	tw.tween_property(sprite, "scale", Vector2(1, 1), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate", Color(1, 1, 1), 0.45)
	tw.parallel().tween_property(seed, "scale", Vector2.ZERO, 0.30)
	tw.parallel().tween_property(fl, "energy", 0.0, 0.5)
	tw.chain().tween_callback(func() -> void:
		seed.queue_free()
		fl.queue_free())

	# rising assembly sparks
	for i in 9:
		var sp := Sprite2D.new()
		sp.texture = Art.light_texture()
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.modulate = Color("aef6ff")
		sp.scale = Vector2(0.07, 0.07)
		sp.position = Vector2(randf_range(-9.0, 9.0), -randf_range(2.0, h * 0.6))
		host.add_child(sp)
		var t2 := host.create_tween()
		t2.tween_property(sp, "position:y", sp.position.y - randf_range(10.0, 22.0), 0.5)
		t2.parallel().tween_property(sp, "modulate:a", 0.0, 0.5)
		t2.tween_callback(sp.queue_free)

## Reverse of play(): the structure flares, collapses back into a seed and the
## host is freed. Call from the entity's collapse_and_free().
static func dismantle(host: Node2D, sprite: Sprite2D) -> void:
	var h := float(sprite.texture.get_height())
	var fl := PointLight2D.new()
	fl.texture = Art.light_texture()
	fl.color = Color("aef6ff")
	fl.energy = 1.6
	fl.scale = Vector2(0.7, 0.7)
	fl.position = Vector2(0, -h / 2.0)
	host.add_child(fl)
	for i in 8:
		var sp := Sprite2D.new()
		sp.texture = Art.light_texture()
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.modulate = Color("aef6ff")
		sp.scale = Vector2(0.07, 0.07)
		sp.position = Vector2(randf_range(-9.0, 9.0), -randf_range(2.0, h * 0.7))
		host.add_child(sp)
		var t2 := host.create_tween()
		t2.tween_property(sp, "position", Vector2(0, -8), 0.28)
		t2.parallel().tween_property(sp, "modulate:a", 0.0, 0.3)
		t2.tween_callback(sp.queue_free)
	var tw := host.create_tween()
	tw.tween_property(sprite, "modulate", Color(1.9, 2.0, 2.3), 0.12)
	tw.tween_property(sprite, "scale", Vector2(0.0, 0.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(fl, "energy", 0.0, 0.32)
	tw.chain().tween_callback(host.queue_free)
