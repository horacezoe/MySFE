extends RefCounted
## Shared local weapon state. Pause freezes it by not calling tick().

var definition: Resource
var ammo := 0
var reserve := 0
var reload_remaining := 0.0
var cooldown := 0.0
var disabled := false
var shots_fired := 0
var _generation := 0
var rng := RandomNumberGenerator.new()

func configure(tuning: Resource, random_seed := 1) -> void:
 definition=tuning
 ammo=maxi(1,definition.magazine_size)
 reserve=maxi(0,definition.starting_reserve)
 reload_remaining=0.0
 cooldown=0.0
 disabled=false
 shots_fired=0
 _generation+=1
 rng.seed=random_seed

func tick(delta: float) -> void:
 if disabled: return
 delta=maxf(0.0,delta)
 cooldown=maxf(0.0,cooldown-delta)
 if reload_remaining>0:
  reload_remaining=maxf(0.0,reload_remaining-delta)
  if reload_remaining<=0:
   var transferred := mini(maxi(0,definition.magazine_size-ammo),reserve)
   ammo+=transferred
   reserve-=transferred

func request_reload() -> bool:
 if disabled or definition==null or reload_remaining>0 or reserve<=0 or ammo>=definition.magazine_size: return false
 reload_remaining=maxf(0.001,definition.reload_duration)
 return true

func cancel_reload() -> void:
 reload_remaining=0.0

func disable() -> void:
 disabled=true
 cancel_reload()

func can_fire() -> bool:
 return definition!=null and not disabled and ammo>0 and cooldown<=0 and reload_remaining<=0

func request_fire(shooter: CharacterBody3D, solution: Dictionary, resolver: RefCounted, spread := 0.0) -> Dictionary:
 var reason := ""
 if disabled: reason="disabled"
 elif definition==null: reason="no_weapon"
 elif reload_remaining>0: reason="reloading"
 elif cooldown>0: reason="cooldown"
 elif ammo<=0: reason="no_ammo"
 if not reason.is_empty(): return {"accepted":false,"reason":reason}
 # A new controller gets a unique instance prefix; bounded resolver deduplication
 # prevents repeated presentation/event delivery from applying damage twice.
 var shot_id := "%d:%d:%d" % [get_instance_id(),_generation,shots_fired+1]
 var result: Dictionary=resolver.resolve(shooter,solution,definition,shot_id,spread,rng)
 if result.get("accepted",false):
  ammo-=1
  cooldown=maxf(0.001,definition.fire_interval)
  shots_fired+=1
 return result
