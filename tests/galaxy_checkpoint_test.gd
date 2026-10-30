extends SceneTree

var checks = 0
var failures: Array = []

func verify(condition: bool, message: String):
	checks += 1
	if not condition: failures.append(message)

func _initialize():
	call_deferred("run")

func run():
	var galaxy = GalaxySim.new()
	verify(SaveStore.load_game(galaxy, "res://qa/galaxy-growth-checkpoint.json"), "Final code restores real interplanetary growth checkpoint")
	if not failures.is_empty(): finish(); return
	verify(galaxy.planets.size() == 3 and galaxy.active_planet == 2, "All three real colonies and active hard planet retained")
	verify(galaxy.planets[0].world.expansions == 8 and galaxy.planets[1].world.expansions == 17 and galaxy.planets[2].world.expansions == 17, "Forty-two actual paid expansions retained")
	verify(galaxy.planets[1].world.count(galaxy.planets[1].world.lifetime, 58) > 0 and galaxy.current().world.count(galaxy.current().world.lifetime, 731) > 0 and galaxy.current().world.count(galaxy.current().world.lifetime, 1462) > 0, "Final local primes 29 and 43 were actually mined, multiplied and spent")
	verify(galaxy.current().world.primes[-1] == 43 and galaxy.current().world.next_resource() == 0, "Actual hard planet reaches finite prime cap")
	verify(galaxy.network.used == 3 and galaxy.network.capacity == 16, "Real growth grants only the expected tower pairs")
	verify(galaxy.total_mass() == galaxy.emitted_mass(), "Whole restored star system conserves all factor mass")
	var before = galaxy.current().world.serialize()
	verify(not galaxy.current().world.research_prime() and galaxy.current().world.serialize() == before, "Further prime research after 43 is rejected without consuming resources")
	var count_before = galaxy.planets[0].emitted
	for i in range(300): galaxy.tick()
	verify(galaxy.total_mass() == galaxy.emitted_mass() and galaxy.planets[0].emitted > count_before, "Final restored worlds continue producing off-screen with exact cargo conservation")
	if "--visual" in OS.get_cmdline_user_args():
		var scene = load("res://main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		scene.paused = true
		scene.galaxy = galaxy
		scene.sim = galaxy.current()
		scene.board.sim = scene.sim
		scene.camera.position = Vector2(-4, -3) * 40
		scene._set_tool("select")
		for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
			root.size = size
			scene._layout()
			scene._refresh()
			await process_frame
			await RenderingServer.frame_post_draw
			verify(scene.prime_button.disabled and scene.prime_label.text.contains("43"), "Final hard-cap state appears in real game UI")
			root.get_texture().get_image().save_png("res://qa/galaxy_completed_%dx%d.png" % [size.x, size.y])
		scene.queue_free()
		await process_frame
	finish()

func finish():
	print("Galaxy checkpoint: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
