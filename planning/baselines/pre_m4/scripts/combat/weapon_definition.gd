extends Resource
## Immutable weapon tuning; all runtime ammunition/timers live in WeaponController.

@export var id: StringName = &"rifle"
@export var display_name := "制式步枪"
@export var ammo_type: StringName = &"standard_rifle"
@export var magazine_size := 24
@export var starting_reserve := 120
@export var fire_interval := 0.16
@export var reload_duration := 1.6
@export var max_range := 60.0
@export var base_damage := 32.0
@export var head_multiplier := 2.0
@export var torso_multiplier := 1.0
@export var limb_multiplier := 0.65
@export var falloff_start := 20.0
@export var falloff_end := 60.0
@export var minimum_damage_factor := 0.65
@export_range(0.0,1.0) var armor_penetration := 0.35
## Cone half-angles in radians. Presentation never changes the damage calculation.
@export var hip_spread := 0.006
@export var aim_spread := 0.0012
@export var move_spread := 0.018
@export var air_spread := 0.04

func zone_multiplier(zone: StringName) -> float:
 match zone:
  &"head": return head_multiplier
  &"limbs": return limb_multiplier
  _: return torso_multiplier

func damage_at(distance: float, zone: StringName) -> float:
 var weight := clampf((distance-falloff_start)/maxf(0.001,falloff_end-falloff_start),0.0,1.0)
 var falloff := lerpf(1.0,clampf(minimum_damage_factor,0.0,1.0),weight)
 return maxf(0.0,base_damage)*maxf(0.0,zone_multiplier(zone))*falloff
