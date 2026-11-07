extends RefCounted
## Single health/armor authority for both player and AI.

var max_hp := 100.0
var hp := 100.0
var head_armor := 20.0
var body_armor := 40.0
var max_head_armor := 20.0
var max_body_armor := 40.0
var absorption := 0.65

func _init(health := 100.0, helmet := 20.0, vest := 40.0):
 max_hp=maxf(1.0,health)
 max_head_armor=maxf(0.0,helmet)
 max_body_armor=maxf(0.0,vest)
 reset()

func configure_armor(definition: Resource) -> void:
 max_head_armor=maxf(0.0,definition.head_durability)
 max_body_armor=maxf(0.0,definition.body_durability)
 absorption=clampf(definition.absorption,0.0,1.0)
 head_armor=max_head_armor
 body_armor=max_body_armor

func reset() -> void:
 hp=max_hp
 head_armor=max_head_armor
 body_armor=max_body_armor

func apply_damage(raw_damage: float, zone: StringName, penetration := 0.35) -> Dictionary:
 var before := hp
 if hp<=0 or not is_finite(raw_damage) or raw_damage<=0:
  return {"health_damage":0.0,"armor_damage":0.0,"killed":false}
 var available := head_armor if zone==&"head" else (body_armor if zone==&"torso" else 0.0)
 var absorbed := minf(available,raw_damage*absorption*(1.0-clampf(penetration,0.0,1.0)))
 if zone==&"head": head_armor=maxf(0.0,head_armor-absorbed)
 elif zone==&"torso": body_armor=maxf(0.0,body_armor-absorbed)
 hp=maxf(0.0,hp-(raw_damage-absorbed))
 return {"health_damage":before-hp,"armor_damage":absorbed,"killed":before>0 and hp<=0}

func heal(amount: float) -> float:
 if hp<=0: return 0.0
 var before := hp
 hp=minf(max_hp,hp+maxf(0.0,amount))
 return hp-before
