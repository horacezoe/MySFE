extends SceneTree
## Standalone behavioral checks for the event-driven input router.
## Run: godot --headless --path ember-3d --script res://tests/test_input_router.gd

const ROUTER = preload("res://scripts/input/input_router.gd")
const VIEWPORT_SIZE = Vector2(1200, 800)
var _failures = 0
var _checks = 0
var _router

func _check(ok: bool, label: String) -> void:
 _checks += 1
 if not ok:
  _failures += 1
  printerr("FAIL: " + label)

func _key(code: int, down: bool, echoing: bool = false) -> InputEventKey:
 var event = InputEventKey.new()
 event.device = 0
 event.physical_keycode = code
 event.pressed = down
 event.echo = echoing
 return event

func _virtual_key(code: int, down: bool, device_id := 0) -> InputEventKey:
 var event = InputEventKey.new()
 event.device = device_id
 event.keycode = code
 event.pressed = down
 return event

func _mouse(button: int, down: bool) -> InputEventMouseButton:
 var event = InputEventMouseButton.new()
 event.button_index = button
 event.pressed = down
 return event

func _touch(index: int, position: Vector2, down: bool) -> InputEventScreenTouch:
 var event = InputEventScreenTouch.new()
 event.index = index
 event.position = position
 event.pressed = down
 return event

func _drag(index: int, position: Vector2, movement: Vector2) -> InputEventScreenDrag:
 var event = InputEventScreenDrag.new()
 event.index = index
 event.position = position
 event.screen_relative = movement
 return event

func _handle(event: InputEvent, captured: bool = false) -> StringName:
 return _router.handle(event, VIEWPORT_SIZE, captured)

func _initialize() -> void:
 _router = ROUTER.new()
 _router.setup_actions()
 _router.set_enabled(true)
 _check_keyboard_and_cancellation()
 _check_virtual_keyboard()
 _check_keyboard_devices()
 _check_mouse_capture_and_look()
 _check_short_fire_clicks()
 _check_action_edges()
 _check_touch_ownership_and_scaling()
 _check_three_finger_release()
 _check_context_switches()
 _check_existing_remapping()
 print("Input router checks: %d passed / %d total" % [_checks - _failures, _checks])
 quit(1 if _failures > 0 else 0)

func _check_keyboard_and_cancellation() -> void:
 _handle(_key(KEY_W, true))
 _check(_router.consume_frame().move == Vector2(0, -1), "physical W starts move")
 _router.cancel_all()
 _check(_router.consume_frame().move == Vector2.ZERO, "cancel clears keyboard")
 _handle(_key(KEY_W, true, true))
 _check(_router.consume_frame().move == Vector2.ZERO, "key echo cannot revive canceled move")
 _router.release_event(_key(KEY_W, false))
 _handle(_key(KEY_W, true))
 _router.set_action(&"move_right", true)
 _check(_router.consume_frame().move.is_equal_approx(Vector2(1, -1).normalized()), "mixed keyboard and touch diagonal normalized")
 _router.release_event(_key(KEY_W, false))
 _check(_router.consume_frame().move == Vector2.RIGHT, "keyboard release preserves touch")
 _router.cancel_all()

func _check_virtual_keyboard() -> void:
 _handle(_virtual_key(KEY_W, true))
 _check(_router.consume_frame().move == Vector2(0, -1), "virtual W without physical code starts move")
 _router.release_event(_virtual_key(KEY_W, false))
 _check(_router.consume_frame().move == Vector2.ZERO, "virtual W release over GUI stops move")
 _handle(_virtual_key(KEY_V, true))
 _check(_router.consume_frame().view, "virtual V triggers view action")
 _router.release_event(_virtual_key(KEY_V, false))
 _handle(_virtual_key(KEY_V, true))
 _check(_router.consume_frame().view, "virtual V release rearms view edge")
 _router.release_event(_virtual_key(KEY_V, false))
 var physical_event = _key(KEY_B, true)
 physical_event.keycode = KEY_V
 _handle(physical_event)
 _check(not _router.consume_frame().view, "logical fallback never overrides a supplied physical code")
 _router.cancel_all()

func _check_keyboard_devices() -> void:
 _check(InputMap.action_get_events(&"ember_view")[0].device == -1, "default binding accepts all keyboard devices")
 for device_id in [0, 1]:
  var native_event = _key(KEY_V, true)
  native_event.keycode = KEY_V
  native_event.device = device_id
  _handle(native_event)
  _check(_router.consume_frame().view, "native-format physical V from device %d triggers view" % device_id)
  native_event.pressed = false
  _router.release_event(native_event)
  var virtual_event = _virtual_key(KEY_V, true)
  virtual_event.device = device_id
  _handle(virtual_event)
  _check(_router.consume_frame().view, "virtual V from device %d works after native release" % device_id)
  virtual_event.pressed = false
  _router.release_event(virtual_event)
 _router.cancel_all()

func _check_mouse_capture_and_look() -> void:
 _check(_handle(_mouse(MOUSE_BUTTON_LEFT, true)) == &"capture", "first click requests capture")
 _check(not _router.consume_frame().fire, "capture click does not shoot")
 _router.release_event(_mouse(MOUSE_BUTTON_LEFT, false))
 _handle(_mouse(MOUSE_BUTTON_LEFT, true), true)
 _check(_router.consume_frame().fire, "captured press fires")
 _router.release_event(_mouse(MOUSE_BUTTON_LEFT, false))
 _check(not _router.consume_frame().fire, "GUI release clears firing")
 var motion = InputEventMouseMotion.new()
 motion.screen_relative = Vector2(10, -5)
 motion.relative = Vector2(100, 100)
 _handle(motion)
 _check(_router.consume_frame().look == Vector2.ZERO, "free mouse does not look")
 _handle(_mouse(MOUSE_BUTTON_RIGHT, true))
 _handle(motion)
 _check(_router.consume_frame().look.is_equal_approx(Vector2(-0.03, 0.015)), "RMB look uses raw screen delta")
 _check(_router.consume_frame().look == Vector2.ZERO, "look consumed once")
 _router.release_event(_mouse(MOUSE_BUTTON_RIGHT, false))
 _handle(motion)
 _check(_router.consume_frame().look == Vector2.ZERO, "RMB release over GUI ends look")

func _check_short_fire_clicks() -> void:
 _handle(_mouse(MOUSE_BUTTON_LEFT, true), true)
 _router.release_event(_mouse(MOUSE_BUTTON_LEFT, false))
 _check(_router.consume_frame().fire, "mouse click between physics frames fires once")
 _check(not _router.consume_frame().fire, "released mouse click does not fire next frame")
 _router.set_action(&"fire", true)
 _router.set_action(&"fire", false)
 _check(_router.consume_frame().fire, "UI fire tap between physics frames fires once")
 _check(not _router.consume_frame().fire, "released UI tap does not fire next frame")
 _handle(_mouse(MOUSE_BUTTON_LEFT, true), true)
 _router.release_event(_mouse(MOUSE_BUTTON_LEFT, false))
 _router.cancel_all()
 _check(not _router.consume_frame().fire, "cancel clears pending mouse fire edge")
 _router.set_action(&"fire", true)
 _router.set_action(&"fire", false)
 _router.cancel_all()
 _check(not _router.consume_frame().fire, "cancel clears pending UI fire edge")

func _check_action_edges() -> void:
 _handle(_key(KEY_SPACE, true), true)
 _check(_router.consume_frame().jump, "jump rising edge")
 _handle(_key(KEY_SPACE, true), true)
 _check(not _router.consume_frame().jump, "repeated down suppresses jump edge")
 _router.release_event(_key(KEY_SPACE, false))
 _handle(_key(KEY_SPACE, true), true)
 _check(_router.consume_frame().jump, "jump rearmed after release")
 _router.cancel_all()

func _check_touch_ownership_and_scaling() -> void:
 _handle(_touch(10, Vector2(100, 400), true))
 _handle(_touch(20, Vector2(900, 400), true))
 _handle(_drag(10, Vector2(800, 400), Vector2(700, 0)))
 var frame: Dictionary = _router.consume_frame()
 _check(frame.move == Vector2.RIGHT and frame.look == Vector2.ZERO, "left touch retains movement after crossing halves")
 _handle(_drag(20, Vector2(100, 400), Vector2(-80, 0)))
 frame = _router.consume_frame()
 _check(frame.look.is_equal_approx(Vector2(0.3, 0)), "right touch retains look after crossing halves")
 _router.release_event(_touch(10, Vector2(800, 400), false))
 _check(_router.consume_frame().move == Vector2.ZERO, "touch release over GUI stops movement")
 var canceled_touch = _touch(20, Vector2(100, 400), true)
 canceled_touch.canceled = true
 _router.release_event(canceled_touch)
 _handle(_drag(20, Vector2(100, 400), Vector2(80, 0)))
 _check(_router.consume_frame().look == Vector2.ZERO, "canceled right touch cannot keep looking")
 _router.screen_size = Vector2(2400, 1600)
 _handle(_touch(30, Vector2(900, 400), true))
 _handle(_drag(30, Vector2(980, 400), Vector2(160, 0)))
 _check(_router.consume_frame().look.is_equal_approx(Vector2(-0.3, 0)), "touch look normalized to physical short side")

func _check_three_finger_release() -> void:
 _router.cancel_all()
 _router.screen_size = VIEWPORT_SIZE
 _handle(_touch(41, Vector2(100, 400), true))
 _handle(_touch(42, Vector2(900, 400), true))
 # The third pointer belongs to the GUI fire button, not the world router.
 _router.set_action(&"fire", true)
 _handle(_drag(41, Vector2(180, 400), Vector2(80, 0)))
 _handle(_drag(42, Vector2(980, 400), Vector2(80, 0)))
 var frame: Dictionary = _router.consume_frame()
 _check(frame.fire and frame.move == Vector2.RIGHT and frame.look.x < 0, "three fingers move look and fire concurrently")
 # Consume the down edge before testing release of a sustained button hold.
 _router.set_action(&"fire", false)
 frame = _router.consume_frame()
 _check(not frame.fire and frame.move == Vector2.RIGHT, "releasing fire finger preserves movement without sticky firing")
 _router.release_event(_touch(41, Vector2(180, 400), false))
 _handle(_drag(42, Vector2(1000, 400), Vector2(20, 0)))
 frame = _router.consume_frame()
 _check(frame.move == Vector2.ZERO and frame.look.x < 0 and not frame.fire, "releasing move finger preserves independent look finger")
 _router.cancel_all()

func _check_context_switches() -> void:
 _router.set_action(&"fire", true)
 _router.set_action(&"sprint", true)
 _check(_handle(_key(KEY_ESCAPE, true), true) == &"pause", "escape requests pause")
 var frame: Dictionary = _router.consume_frame()
 _check(not frame.fire and not frame.sprint and frame.move == Vector2.ZERO and frame.look == Vector2.ZERO, "pause clears all state")
 _router.set_action(&"fire", true)
 _router.set_enabled(false)
 _router.set_action(&"sprint", true)
 _handle(_key(KEY_W, true), true)
 _router.set_enabled(true)
 frame = _router.consume_frame()
 _check(not frame.fire and not frame.sprint and frame.move == Vector2.ZERO, "disabled context ignores input")

func _check_existing_remapping() -> void:
 var remap = InputEventKey.new()
 remap.device = 17
 remap.physical_keycode = KEY_I
 InputMap.action_erase_events(&"ember_move_forward")
 InputMap.action_add_event(&"ember_move_forward", remap)
 _router.setup_actions()
 var events = InputMap.action_get_events(&"ember_move_forward")
 _check(events.size() == 1 and events[0].physical_keycode == KEY_I, "setup preserves remapped binding")
 _handle(_virtual_key(KEY_W, true))
 _check(_router.consume_frame().move == Vector2.ZERO, "virtual default key is inactive after remapping")
 _handle(_virtual_key(KEY_I, true, 17))
 _check(_router.consume_frame().move == Vector2(0, -1), "virtual key uses configured physical remapping")
 _router.release_event(_virtual_key(KEY_I, false, 17))
 _check(_router.consume_frame().move == Vector2.ZERO, "virtual remapped key release stops move")
 _check(events[0].device == 17, "setup retains configured device restriction")
 var other_device_event = _virtual_key(KEY_I, true)
 other_device_event.device = 1
 _handle(other_device_event)
 _check(_router.consume_frame().move == Vector2.ZERO, "custom device-specific mapping rejects other devices")
