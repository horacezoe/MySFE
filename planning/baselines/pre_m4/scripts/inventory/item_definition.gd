extends Resource
## Immutable catalog data. Quantities, durability and runtime belong to instances.

@export var id: StringName = &""
@export var display_name := "物品"
@export var category: StringName = &"loot"
@export var width := 1
@export var height := 1
@export var unit_weight := 0.1
@export var max_stack := 1
@export var value := 0
@export var equipment_slot: StringName = &""
@export var color := Color("a3b88b")

func footprint(rotated := false) -> Vector2i:
 return Vector2i(height,width) if rotated else Vector2i(width,height)
