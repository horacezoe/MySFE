extends RefCounted

var raise_time := 0.0
var was_sprinting := false

func step(frame: Dictionary, reloading: bool, delta: float, crouching := false) -> bool:
 raise_time = maxf(0.0,raise_time-delta)
 var wants_sprint: bool = frame.sprint and not frame.fire and not frame.get("aim",false) and not reloading and not crouching and frame.move.length()>0.1
 if was_sprinting and not wants_sprint: raise_time = 0.18
 was_sprinting = wants_sprint
 return wants_sprint

func can_fire(reloading: bool) -> bool:
 return not reloading and not was_sprinting and raise_time<=0.0

func cancel_all() -> void:
 raise_time = 0.0
 was_sprinting = false
