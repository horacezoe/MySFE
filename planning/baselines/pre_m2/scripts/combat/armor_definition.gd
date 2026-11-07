extends Resource

@export var id: StringName = &"light_armor"
@export var display_name := "轻型防护"
@export var head_durability := 20.0
@export var body_durability := 40.0
## Before ammunition penetration, armor can absorb this fraction of raw damage.
@export_range(0.0,1.0) var absorption := 0.65
