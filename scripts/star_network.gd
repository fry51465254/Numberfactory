class_name StarNetwork
extends RefCounted

var stock: Dictionary = {}
var capacity: int = 0
var used: int = 0
var unlocked: bool = false
var last_planet: int = -1

func count(value: int) -> int:
	return int(stock.get(str(value), 0))
