class_name LegacyBoardFixture
extends WorldSim

# Empty bounded board keeps the established mouse-routing regression cases stable.
# The production scene always uses WorldSim and its seeded, expanding world.
func _init():
	super(42)
	entities.clear()
	occupancy.clear()
	loaded_chunks.clear()

func ensure_chunk(_chunk: Vector2i):
	pass

func accessible(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < 32 and p.y < 24 and (p.x < 20 or delivered.exploration >= 30)

func splitter_unlocked(mode: int) -> bool:
	return mode == 0 or delivered.research >= (20 if mode == 1 else 60)
