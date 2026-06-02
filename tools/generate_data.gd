extends SceneTree
## One-off content generator. Run with:
##   godot --headless --script res://tools/generate_data.gd
## Builds the starter Item/Recipe .tres assets under res://data/. Jason can then
## edit them in the inspector or add new ones; the game just loads the folder.

const T = preload("res://scripts/autoload/Tiles.gd")

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/items")
	DirAccess.make_dir_recursive_absolute("res://data/recipes")

	# id, name, tier, category, stack, value, color, tile(-1), heal, stats
	var items := [
		# --- raw (gathered from the world) ---
		["scrap", "Alien Scrap", 0, "raw", 999, 2, "ff8a3a", -1, 0.0, {}],
		["dirt", "Regolith", 0, "raw", 999, 1, "564470", T.DIRT, 0.0, {}],
		["stone", "Slate", 0, "raw", 999, 1, "43465e", T.STONE, 0.0, {}],
		["sand", "Glass-Sand", 0, "raw", 999, 1, "d9c27a", T.SAND, 0.0, {}],
		["wood", "Xylo-Timber", 0, "raw", 999, 2, "9a7a52", -1, 0.0, {}],
		["darkrock", "Obsidite", 1, "raw", 999, 3, "2e2138", T.DARKROCK, 0.0, {}],
		["ice", "Cryo-Ice", 1, "raw", 999, 2, "8fd6ef", T.ICE, 0.0, {}],
		["biomass", "Biomass", 1, "raw", 999, 3, "a6ff3a", T.JUNGLE, 0.0, {}],
		["metal_ore", "Ferralite", 1, "raw", 999, 4, "c4c4d6", -1, 0.0, {}],
		["energy_core", "Ion Core", 2, "raw", 999, 12, "2dffff", -1, 0.0, {}],
		["crystal", "Vyrite Crystal", 2, "raw", 999, 8, "ff4df0", -1, 0.0, {}],
		["exotic_matter", "Exotic Matter", 3, "raw", 999, 40, "b06aff", -1, 0.0, {}],
		# --- refined + components ---
		["metal_ingot", "Metal Ingot", 1, "refined", 999, 10, "b8bcd0", -1, 0.0, {}],
		["glass_pane", "Glass Pane", 1, "refined", 999, 4, "aee8ff", -1, 0.0, {}],
		["polymer", "Bio-Polymer", 1, "refined", 999, 6, "a06cff", -1, 0.0, {}],
		["alloy_plate", "Alloy Plate", 2, "refined", 999, 22, "8a93b8", -1, 0.0, {}],
		["crystal_lens", "Crystal Lens", 2, "component", 999, 14, "ff7ae0", -1, 0.0, {}],
		["power_cell", "Power Cell", 2, "component", 999, 16, "2dffff", -1, 0.0, {}],
		["circuit_board", "Circuit Board", 2, "component", 999, 30, "3aff8f", -1, 0.0, {}],
		["conduit", "Conduit", 2, "component", 999, 24, "ff9a3a", -1, 0.0, {}],
		["composite", "Composite Panel", 2, "refined", 999, 40, "5ad0c0", -1, 0.0, {}],
		["nanocore", "Nanocore", 3, "component", 999, 80, "eaffff", -1, 0.0, {}],
		# --- gear / blocks / consumable ---
		["pickaxe", "Particle Gun", 0, "tool", 1, 0, "2dffff", -1, 0.0, {"mining_power": 1.0}],
		["blaster", "Ion Blaster", 2, "weapon", 1, 24, "ff2bd6", -1, 0.0, {"damage": 12.0, "cooldown": 0.22, "speed": 360.0}],
		["med_cell", "Med-Cell", 2, "component", 20, 8, "39ff88", -1, 40.0, {}],
		["plating", "Hull Plating", 2, "structure", 999, 12, "7a80b0", T.PLATING, 0.0, {}],
		["neon_glass", "Neon Glass", 2, "structure", 999, 10, "ff2bd6", T.NEON, 0.0, {}],
		["wood_block", "Bio-Timber", 0, "structure", 999, 3, "7c6b4e", T.WOOD, 0.0, {}],
		["plasma_cutter", "Plasma Cutter", 3, "tool", 1, 60, "ffd23a", -1, 0.0, {"mining_power": 3.0}],
		["quantum_blade", "Quantum Lance", 3, "weapon", 1, 120, "b06aff", -1, 0.0, {"damage": 30.0, "cooldown": 0.30, "speed": 420.0}],
		# --- stations + storage (deployed in the world) ---
		["storage_pod", "Storage Pod", 1, "structure", 1, 30, "6fd0e0", -1, 0.0, {}],
		["workbench", "Workbench", 0, "structure", 1, 20, "b89060", -1, 0.0, {}],
		["fabricator", "Fabricator", 1, "structure", 1, 80, "2dffff", -1, 0.0, {}],
		["synthesizer", "Synthesizer", 2, "structure", 1, 120, "b06aff", -1, 0.0, {}],
	]

	var by_id := {}
	for d in items:
		var it := Item.new()
		it.id = d[0]
		it.display_name = d[1]
		it.tier = d[2]
		it.category = d[3]
		it.stack_size = d[4]
		it.base_value = d[5]
		it.color = Color(d[6])
		it.place_tile = d[7]
		it.heal = d[8]
		it.stats = d[9]
		ResourceSaver.save(it, "res://data/items/%s.tres" % it.id)
		by_id[it.id] = it
	print("Generated %d items" % items.size())
	# reload from disk so recipes reference the saved .tres (ext_resource), not copies
	for d in items:
		by_id[d[0]] = load("res://data/items/%s.tres" % d[0])

	# out, qty, [[input_id, qty], ...], station, unlock
	# station = the structure you must stand near; unlock = extra progression gate
	var recipes := [
		["workbench", 1, [["scrap", 5], ["stone", 3]], "", ""],
		["metal_ingot", 1, [["metal_ore", 2]], "workbench", ""],
		["glass_pane", 1, [["sand", 2]], "workbench", ""],
		["polymer", 1, [["wood", 2]], "workbench", ""],
		["wood_block", 4, [["wood", 2]], "workbench", ""],
		["storage_pod", 1, [["metal_ingot", 4], ["glass_pane", 2]], "workbench", ""],
		["fabricator", 1, [["metal_ingot", 8], ["glass_pane", 2]], "workbench", "tier>=1"],
		["power_cell", 1, [["energy_core", 1], ["scrap", 1]], "fabricator", ""],
		["crystal_lens", 1, [["crystal", 1]], "fabricator", ""],
		["alloy_plate", 1, [["metal_ingot", 2]], "fabricator", ""],
		["circuit_board", 1, [["metal_ingot", 1], ["crystal_lens", 1]], "fabricator", ""],
		["conduit", 1, [["metal_ingot", 1], ["power_cell", 1]], "fabricator", ""],
		["composite", 1, [["polymer", 1], ["alloy_plate", 1]], "fabricator", ""],
		["plating", 2, [["alloy_plate", 1]], "fabricator", ""],
		["neon_glass", 4, [["glass_pane", 2], ["power_cell", 1]], "fabricator", ""],
		["med_cell", 1, [["biomass", 4], ["crystal", 1]], "fabricator", ""],
		["blaster", 1, [["circuit_board", 1], ["conduit", 1], ["power_cell", 1]], "fabricator", ""],
		["synthesizer", 1, [["alloy_plate", 6], ["circuit_board", 4], ["power_cell", 2]], "fabricator", "tier>=2"],
		["nanocore", 1, [["circuit_board", 1], ["power_cell", 1], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		["plasma_cutter", 1, [["composite", 1], ["circuit_board", 2], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		["quantum_blade", 1, [["nanocore", 1], ["composite", 2], ["exotic_matter", 2]], "synthesizer", "tier>=3"],
	]

	for d in recipes:
		var r := Recipe.new()
		r.output_item = by_id[d[0]]
		r.output_quantity = d[1]
		var ins: Array[RecipeInput] = []
		for c in d[2]:
			var ri := RecipeInput.new()
			ri.item = by_id[c[0]]
			ri.quantity = c[1]
			ins.append(ri)
		r.inputs = ins
		r.station = d[3]
		r.unlock_condition = d[4]
		ResourceSaver.save(r, "res://data/recipes/%s.tres" % d[0])
	print("Generated %d recipes" % recipes.size())
	quit()
