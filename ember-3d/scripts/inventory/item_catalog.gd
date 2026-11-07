extends RefCounted

const CONTENT_VERSION = "phase4_items_1"
const DEFINITIONS = [
 preload("res://data/items/rifle_basic.tres"),
 preload("res://data/items/helmet_light.tres"),
 preload("res://data/items/vest_light.tres"),
 preload("res://data/items/medkit_basic.tres"),
 preload("res://data/items/ammo_rifle.tres"),
 preload("res://data/items/loot_medical.tres"),
 preload("res://data/items/loot_battery.tres"),
 preload("res://data/items/loot_chip.tres"),
 preload("res://data/items/loot_parts.tres"),
 preload("res://data/items/loot_alloy.tres"),
 preload("res://data/items/loot_ration.tres"),
 preload("res://data/items/loot_watch.tres"),
 preload("res://data/items/loot_electronics.tres"),
 preload("res://data/items/depot_pass.tres"),
]
var _by_id: Dictionary = {}

func _init():
 for definition in DEFINITIONS: _by_id[String(definition.id)]=definition

func get_definition(id: String) -> Resource:
 return _by_id.get(id)

func ids() -> Array:
 return _by_id.keys()

func has(id: String) -> bool:
 return _by_id.has(id)
