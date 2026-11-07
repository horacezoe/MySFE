extends RefCounted
## Rule IDs are frozen at deployment and cannot change an active raid.
const VERSION="rules_1"
const RULES={
 "comfort":{"id":"comfort","name":"舒适","duration":600.0,"enemy_damage_scale":0.65,"enemy_view_distance":18.0,"enemy_reaction_time":1.0,"death_keep_equipment":true,"search_pause":true},
 "standard":{"id":"standard","name":"标准","duration":360.0,"enemy_damage_scale":1.0,"enemy_view_distance":22.0,"enemy_reaction_time":0.65,"death_keep_equipment":false,"search_pause":true},
}

func get_rule(id: String) -> Dictionary:
 return RULES.get(id,{}).duplicate(true)

func definitions() -> Array:
 return [get_rule("comfort"),get_rule("standard")]
