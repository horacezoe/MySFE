extends RefCounted
## Device input adapter. Look deltas are radians and must not be multiplied by delta.
## Pass viewport_size in the same coordinate space as touch event.position.
## Set screen_size to the physical window size when the viewport is stretched.

const KEY_BINDINGS = {
 &"move_left": KEY_A,
 &"move_right": KEY_D,
 &"move_forward": KEY_W,
 &"move_back": KEY_S,
 &"jump": KEY_SPACE,
 &"sprint": KEY_SHIFT,
 &"crouch": KEY_C,
 &"reload": KEY_R,
 &"interact": KEY_E,
 &"heal": KEY_Q,
 &"view": KEY_V,
 &"aim_toggle": KEY_X,
 &"pause": KEY_ESCAPE,
}
const EDGE_ACTIONS = [&"jump", &"crouch", &"reload", &"interact", &"heal", &"view", &"aim_toggle"]
const HOLD_ACTIONS = [&"move_left", &"move_right", &"move_forward", &"move_back", &"fire", &"sprint"]

var mouse_sensitivity = 0.003
var touch_sensitivity = 3.0
var screen_size = Vector2.ZERO
var enabled = false
var left_id = -1
var right_id = -1
var left_origin = Vector2.ZERO
var _touch_move = Vector2.ZERO
var _look_delta = Vector2.ZERO
var _keyboard_holds: Dictionary = {}
var _ui_holds: Dictionary = {}
var _edges: Dictionary = {}
var _mouse_fire = false
var _fire_pressed = false
var _right_mouse = false

func setup_actions() -> void:
 for action in KEY_BINDINGS:
  var mapped = _map_name(action)
  if not InputMap.has_action(mapped):
   InputMap.add_action(mapped)
  # Preserve existing/remapped bindings. Only initialize an empty action.
  if InputMap.action_get_events(mapped).is_empty():
   var key = InputEventKey.new()
   key.device = -1 # Default keyboard bindings accept every keyboard device.
   key.physical_keycode = KEY_BINDINGS[action]
   InputMap.action_add_event(mapped, key)

func _map_name(action: StringName) -> StringName:
 return StringName("ember_" + String(action))

func _key_matches_action(event: InputEventKey, action: StringName) -> bool:
 var mapped = _map_name(action)
 if event.is_action(mapped):
  return true
 # On-screen keyboards may omit the physical scan code. Match their logical
 # code against the configured mapping without changing native key handling.
 if event.physical_keycode != 0 or event.keycode == 0:
  return false
 var fallback := event.duplicate() as InputEventKey
 fallback.physical_keycode = event.keycode
 return fallback.is_action(mapped)

func set_enabled(value: bool) -> void:
 if enabled != value:
  cancel_all()
 enabled = value

func cancel_all() -> void:
 _keyboard_holds.clear()
 _ui_holds.clear()
 _edges.clear()
 _mouse_fire = false
 _fire_pressed = false
 _right_mouse = false
 _look_delta = Vector2.ZERO
 _touch_move = Vector2.ZERO
 left_id = -1
 right_id = -1
 left_origin = Vector2.ZERO

func set_action(action: StringName, pressed: bool) -> void:
 # Touch buttons own their pointers; they call this instead of injecting mouse events.
 if not EDGE_ACTIONS.has(action) and not HOLD_ACTIONS.has(action):
  return
 if not pressed:
  _ui_holds.erase(action)
  return
 if not enabled:
  return
 var was_down = bool(_ui_holds.get(action, false))
 _ui_holds[action] = true
 if action == &"fire" and not was_down:
  _fire_pressed = true
 if EDGE_ACTIONS.has(action) and not was_down:
  _edges[action] = true

func release_event(event: InputEvent) -> void:
 # Call from _input before GUI routing. A release over a button must still clear
 # the pointer/key that started in the gameplay area. Releasing twice is safe.
 if event is InputEventScreenTouch:
  if not event.pressed or event.canceled:
   if event.index == left_id:
    left_id = -1
    _touch_move = Vector2.ZERO
   if event.index == right_id:
    right_id = -1
 elif event is InputEventMouseButton and not event.pressed:
  if event.button_index == MOUSE_BUTTON_LEFT:
   _mouse_fire = false
  elif event.button_index == MOUSE_BUTTON_RIGHT:
   _right_mouse = false
 elif event is InputEventKey and not event.pressed:
  for action in KEY_BINDINGS:
   if _key_matches_action(event, action):
    _keyboard_holds.erase(action)

func handle(event: InputEvent, viewport_size: Vector2, captured: bool) -> StringName:
 release_event(event)
 if not enabled:
  return &""
 if event is InputEventKey:
  if not event.pressed or event.echo:
   return &""
  for action in KEY_BINDINGS:
   if not _key_matches_action(event, action):
    continue
   if action == &"pause":
    cancel_all()
    return &"pause"
   var was_down = bool(_keyboard_holds.get(action, false))
   _keyboard_holds[action] = true
   if EDGE_ACTIONS.has(action) and not was_down:
    _edges[action] = true
 elif event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
   if not captured:
    _mouse_fire = false
    return &"capture"
   if not _mouse_fire:
    _fire_pressed = true
   _mouse_fire = true
  elif event.button_index == MOUSE_BUTTON_RIGHT:
   _right_mouse = event.pressed
 elif event is InputEventMouseMotion:
  if captured or _right_mouse:
   _look_delta -= event.screen_relative * mouse_sensitivity
 elif event is InputEventScreenTouch:
  if event.pressed and not event.canceled:
   if event.position.x < viewport_size.x * 0.5 and left_id == -1:
    left_id = event.index
    left_origin = event.position
   elif event.position.x >= viewport_size.x * 0.5 and right_id == -1:
    right_id = event.index
 elif event is InputEventScreenDrag:
  if event.index == left_id:
   var radius = maxf(1.0, minf(viewport_size.x, viewport_size.y) * 0.10)
   _touch_move = ((event.position - left_origin) / radius).limit_length(1.0)
  elif event.index == right_id:
   var physical_size = screen_size if screen_size.x > 0 and screen_size.y > 0 else viewport_size
   var short_side = maxf(1.0, minf(physical_size.x, physical_size.y))
   _look_delta -= event.screen_relative * touch_sensitivity / short_side
 return &""

func _held(action: StringName) -> bool:
 return bool(_keyboard_holds.get(action, false)) or bool(_ui_holds.get(action, false))

func consume_frame() -> Dictionary:
 var move = Vector2.ZERO
 if enabled:
  move = Vector2(float(_held(&"move_right")) - float(_held(&"move_left")), float(_held(&"move_back")) - float(_held(&"move_forward")))
  move = (move + _touch_move).limit_length(1.0)
 var frame = {
  "move": move,
  "look": _look_delta if enabled else Vector2.ZERO,
  "fire": enabled and (_mouse_fire or _held(&"fire") or _fire_pressed),
  "aim": enabled and _right_mouse,
  "sprint": enabled and _held(&"sprint"),
 }
 for action in EDGE_ACTIONS:
  frame[action] = enabled and bool(_edges.get(action, false))
 _look_delta = Vector2.ZERO
 _fire_pressed = false
 _edges.clear()
 return frame
