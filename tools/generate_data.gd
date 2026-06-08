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
		["dirt", "Regolith", 0, "raw", 999, 1, "8975ac", T.DIRT, 0.0, {}],
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
		["hydro_cell", "Hydro Cell", 1, "tool", 1, 14, "3aa0ff", -1, 0.0, {"pour_water": 1.0}],
		["blaster", "Ion Blaster", 2, "weapon", 1, 24, "ff2bd6", -1, 0.0, {"damage": 12.0, "cooldown": 0.22, "speed": 360.0}],
		["slug_rifle", "Kinetic Rifle", 2, "weapon", 1, 70, "d8d2c0", -1, 0.0, {"damage": 7.0, "cooldown": 0.10, "speed": 760.0, "spread": 0.06, "projectile": "bullet"}],
		["plasma_saber", "Plasma Saber", 2, "weapon", 1, 90, "39ff9f", -1, 0.0, {"melee": true, "damage": 26.0, "cooldown": 0.35, "reach": 34.0}],
		["med_cell", "Med-Cell", 2, "component", 20, 8, "39ff88", -1, 40.0, {}],
		# --- food (restores hunger; stew also heals a little) ---
		["ration", "Protein Ration", 1, "food", 20, 6, "c8e87a", -1, 0.0, {"food": 45.0}],
		["nutrient_stew", "Nutrient Stew", 2, "food", 10, 16, "ff9a5a", -1, 25.0, {"food": 85.0}],
		["plating", "Hull Plating", 2, "structure", 999, 12, "7a80b0", T.PLATING, 0.0, {}],
		["neon_glass", "Neon Glass", 2, "structure", 999, 10, "ff2bd6", T.NEON, 0.0, {}],
		["wood_block", "Bio-Timber", 0, "structure", 999, 3, "7c6b4e", T.WOOD, 0.0, {}],
		["plasma_cutter", "Plasma Cutter", 3, "tool", 1, 60, "ffd23a", -1, 0.0, {"mining_power": 3.0}],
		["quantum_blade", "Quantum Lance", 3, "weapon", 1, 120, "b06aff", -1, 0.0, {"damage": 30.0, "cooldown": 0.30, "speed": 420.0}],
		# --- building sub-parts (the bits doors / windows need) ---
		["frame", "Metal Frame", 1, "component", 999, 14, "9aa0c0", -1, 0.0, {}],
		["hinge", "Hinge", 1, "component", 999, 6, "b8bcd0", -1, 0.0, {}],
		# --- crafted walls ---
		["stone_brick", "Slate Brick", 0, "structure", 999, 3, "555876", T.STONE_BRICK, 0.0, {}],
		["metal_wall", "Metal Wall", 1, "structure", 999, 14, "9aa0c0", T.METAL_WALL, 0.0, {}],
		["obsidian_brick", "Obsidite Brick", 2, "structure", 999, 18, "3e2e52", T.OBSIDIAN_BRICK, 0.0, {}],
		# --- windows (transparent) ---
		["glass_window", "Glass Window", 1, "structure", 999, 8, "aee8ff", T.GLASS_WINDOW, 0.0, {}],
		["reinforced_window", "Reinforced Window", 2, "structure", 999, 20, "bfeaff", T.REINFORCED_WINDOW, 0.0, {}],
		# --- doors (place the closed tile; open / close in-world) ---
		["wood_door", "Timber Door", 1, "structure", 99, 8, "6b4f34", T.WOOD_DOOR, 0.0, {}],
		["metal_door", "Metal Door", 1, "structure", 99, 18, "9aa0c0", T.METAL_DOOR, 0.0, {}],
		["blast_door", "Blast Door", 2, "structure", 99, 34, "ff5a4a", T.BLAST_DOOR, 0.0, {}],
		# --- upgraded particle guns (harvest faster) ---
		["pulse_drill", "Pulse Drill", 2, "tool", 1, 40, "7df0ff", -1, 0.0, {"mining_power": 1.8}],
		["singularity_bore", "Singularity Bore", 3, "tool", 1, 140, "b06aff", -1, 0.0, {"mining_power": 4.5}],
		# --- more refined / components ---
		["ceramic", "Ceramic Plate", 1, "refined", 999, 8, "d8cfc0", -1, 0.0, {}],
		["servo", "Servo", 2, "component", 999, 18, "b0b6cc", -1, 0.0, {}],
		# --- a scatter weapon + more sustenance ---
		["scatter_gun", "Scatter Gun", 2, "weapon", 1, 75, "d8b070", -1, 0.0, {"damage": 5.0, "cooldown": 0.55, "speed": 600.0, "spread": 0.2, "pellets": 5, "projectile": "bullet"}],
		["energy_bar", "Energy Bar", 1, "food", 20, 7, "ffd86a", -1, 12.0, {"food": 35.0}],
		["stim_pack", "Stim-Pack", 2, "consumable", 10, 20, "ff5a8f", -1, 80.0, {}],
		# --- armour (worn in head/body/legs slots; cuts incoming damage) ---
		["scrap_helm", "Scrap Helm", 1, "armor", 1, 10, "9a8c78", -1, 0.0, {"armor": 6.0, "slot": "head"}],
		["scrap_vest", "Scrap Vest", 1, "armor", 1, 16, "9a8c78", -1, 0.0, {"armor": 10.0, "slot": "body"}],
		["scrap_greaves", "Scrap Greaves", 1, "armor", 1, 12, "9a8c78", -1, 0.0, {"armor": 7.0, "slot": "legs"}],
		["alloy_helm", "Alloy Helm", 2, "armor", 1, 28, "8a93b8", -1, 0.0, {"armor": 10.0, "slot": "head"}],
		["alloy_cuirass", "Alloy Cuirass", 2, "armor", 1, 44, "8a93b8", -1, 0.0, {"armor": 16.0, "slot": "body"}],
		["alloy_greaves", "Alloy Greaves", 2, "armor", 1, 30, "8a93b8", -1, 0.0, {"armor": 11.0, "slot": "legs"}],
		["exo_helm", "Exo Helm", 3, "armor", 1, 60, "b06aff", -1, 0.0, {"armor": 15.0, "slot": "head"}],
		["exo_cuirass", "Exo Cuirass", 3, "armor", 1, 90, "b06aff", -1, 0.0, {"armor": 24.0, "slot": "body"}],
		["exo_greaves", "Exo Greaves", 3, "armor", 1, 64, "b06aff", -1, 0.0, {"armor": 16.0, "slot": "legs"}],
		# --- decor props (placeable; some glow) ---
		["lamp_post", "Lamp Post", 1, "decor", 99, 10, "2dffff", T.LAMP_POST, 0.0, {}],
		["crate", "Supply Crate", 0, "decor", 99, 5, "9a7a4a", T.CRATE, 0.0, {}],
		["console", "Control Console", 2, "decor", 99, 24, "2dffff", T.CONSOLE, 0.0, {}],
		["vat", "Bio-Vat", 2, "decor", 99, 22, "39ff9f", T.VAT, 0.0, {}],
		["banner", "Banner", 1, "decor", 99, 6, "ff2bd6", T.BANNER, 0.0, {}],
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
		["hydro_cell", 1, [["metal_ingot", 2], ["glass_pane", 1]], "workbench", ""],
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
		["ration", 2, [["biomass", 3]], "workbench", ""],
		["nutrient_stew", 1, [["biomass", 4], ["ration", 1]], "fabricator", ""],
		["blaster", 1, [["circuit_board", 1], ["conduit", 1], ["power_cell", 1]], "fabricator", ""],
		["slug_rifle", 1, [["alloy_plate", 2], ["circuit_board", 1], ["conduit", 1]], "fabricator", ""],
		["plasma_saber", 1, [["crystal_lens", 1], ["power_cell", 1], ["alloy_plate", 1]], "fabricator", ""],
		["synthesizer", 1, [["alloy_plate", 6], ["circuit_board", 4], ["power_cell", 2]], "fabricator", "tier>=2"],
		["nanocore", 1, [["circuit_board", 1], ["power_cell", 1], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		["plasma_cutter", 1, [["composite", 1], ["circuit_board", 2], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		["quantum_blade", 1, [["nanocore", 1], ["composite", 2], ["exotic_matter", 2]], "synthesizer", "tier>=3"],
		# building sub-parts
		["frame", 1, [["metal_ingot", 2]], "workbench", ""],
		["hinge", 2, [["metal_ingot", 1]], "workbench", ""],
		# walls
		["stone_brick", 4, [["stone", 4]], "workbench", ""],
		["metal_wall", 4, [["metal_ingot", 2]], "workbench", ""],
		["obsidian_brick", 4, [["darkrock", 4]], "fabricator", ""],
		# windows
		["glass_window", 2, [["glass_pane", 2]], "workbench", ""],
		["reinforced_window", 2, [["glass_pane", 2], ["frame", 1]], "fabricator", ""],
		# doors (need hinges; tougher doors need frames/plate)
		["wood_door", 1, [["wood", 6], ["hinge", 2]], "workbench", ""],
		["metal_door", 1, [["metal_wall", 2], ["frame", 1], ["hinge", 2]], "workbench", ""],
		["blast_door", 1, [["alloy_plate", 2], ["frame", 1], ["hinge", 2]], "fabricator", ""],
		# upgraded particle guns
		["pulse_drill", 1, [["alloy_plate", 2], ["crystal_lens", 1], ["power_cell", 1]], "fabricator", ""],
		["singularity_bore", 1, [["nanocore", 1], ["composite", 2], ["exotic_matter", 3]], "synthesizer", "tier>=3"],
		# refined / components
		["ceramic", 2, [["sand", 2], ["stone", 1]], "workbench", ""],
		["servo", 1, [["metal_ingot", 1], ["power_cell", 1]], "fabricator", ""],
		# scatter weapon, food + medicine
		["scatter_gun", 1, [["alloy_plate", 2], ["conduit", 1], ["metal_ingot", 2]], "fabricator", ""],
		["energy_bar", 2, [["biomass", 2], ["polymer", 1]], "workbench", ""],
		["stim_pack", 1, [["med_cell", 1], ["crystal", 1]], "fabricator", ""],
		# armour sets
		["scrap_helm", 1, [["scrap", 6], ["ceramic", 1]], "workbench", ""],
		["scrap_vest", 1, [["scrap", 10], ["ceramic", 2]], "workbench", ""],
		["scrap_greaves", 1, [["scrap", 8], ["ceramic", 1]], "workbench", ""],
		["alloy_helm", 1, [["alloy_plate", 2], ["ceramic", 1]], "fabricator", ""],
		["alloy_cuirass", 1, [["alloy_plate", 4], ["ceramic", 2]], "fabricator", ""],
		["alloy_greaves", 1, [["alloy_plate", 3], ["ceramic", 1]], "fabricator", ""],
		["exo_helm", 1, [["composite", 2], ["servo", 1], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		["exo_cuirass", 1, [["composite", 3], ["servo", 2], ["exotic_matter", 2]], "synthesizer", "tier>=3"],
		["exo_greaves", 1, [["composite", 2], ["servo", 1], ["exotic_matter", 1]], "synthesizer", "tier>=3"],
		# decor props
		["lamp_post", 1, [["metal_ingot", 1], ["glass_pane", 1]], "workbench", ""],
		["crate", 2, [["wood", 3]], "workbench", ""],
		["console", 1, [["alloy_plate", 1], ["circuit_board", 1]], "fabricator", ""],
		["vat", 1, [["glass_pane", 2], ["metal_ingot", 1], ["biomass", 1]], "fabricator", ""],
		["banner", 2, [["polymer", 2]], "workbench", ""],
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
