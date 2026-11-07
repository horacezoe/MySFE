extends SceneTree
const Extraction=preload("res://scripts/raid/extraction_controller.gd")
var checks=0
var failures=0
var pass_owned=false
func check(ok: bool,label: String):
 checks+=1
 if not ok: failures+=1; push_error(label)
func _initialize():
 var exits=[{"id":"south_gate","title":"南门","position":Vector3(25,0,25),"radius":3.6,"wait":5.0,"required_item":""},{"id":"service_gate","title":"维修口","position":Vector3(-25,0,24),"radius":3.6,"wait":3.0,"required_item":"depot_pass"}]
 var extraction=Extraction.new(); extraction.configure(exits)
 var owns=func(_id): return pass_owned
 check(not extraction.begin(Vector3.ZERO,true,owns).ok,"must stand at an exit")
 check(not extraction.begin(exits[0].position,false,owns).ok,"dead cannot start")
 check(extraction.begin(exits[0].position,true,owns).ok,"normal exit needs no pass")
 check(extraction.step(1.0,exits[0].position,true,owns).status=="extracting","timer advances")
 check(extraction.remaining==4.0,"normal wait time")
 check(extraction.begin(exits[0].position,true,owns).reason=="already_extracting" and extraction.remaining==4.0,"repeated interaction cannot reset countdown")
 var saved=extraction.snapshot()
 var restored=Extraction.new(); restored.configure(exits); restored.restore(JSON.parse_string(JSON.stringify(saved)))
 check(restored.exit_id=="south_gate" and restored.remaining==4.0,"saved exit identity and countdown restore")
 check(restored.step(3.9,exits[0].position,true,owns).status=="extracting","wait cannot complete early")
 check(restored.step(0.2,exits[0].position,true,owns).status=="complete","countdown completes")
 check(restored.step(1.0,exits[0].position,true,owns).status=="idle","completion only emits once")
 check(extraction.step(0.1,Vector3.ZERO,true,owns).reason=="left_exit" and extraction.exit_id.is_empty(),"leaving cancels countdown")
 check(extraction.begin(exits[1].position,true,owns).reason=="pass_required","conditional exit rejects missing pass")
 pass_owned=true
 check(extraction.begin(exits[1].position,true,owns).ok,"pass opens conditional exit")
 check(extraction.exit_id=="service_gate" and extraction.remaining==3.0,"conditional identity and wait")
 var shortcut=extraction.snapshot(); extraction.cancel(); extraction.restore(shortcut)
 check(extraction.exit_id=="service_gate","conditional identity survives resume")
 pass_owned=false
 check(extraction.step(1.0,exits[1].position,true,owns).reason=="pass_required","losing condition cancels ongoing extraction")
 pass_owned=true; extraction.begin(exits[1].position,true,owns)
 check(extraction.step(5.0,exits[1].position,false,owns).status=="dead" and not extraction.completed,"death wins over simultaneous extraction")
 extraction.restore({"exit_id":"unknown","remaining":100})
 check(extraction.exit_id.is_empty(),"unknown saved exit cannot extract")
 extraction.restore({"exit_id":"south_gate","remaining":-1})
 check(extraction.exit_id.is_empty(),"invalid countdown ignored")
 extraction.restore({"exit_id":"south_gate","remaining":999})
 check(extraction.remaining==5.0,"restored countdown bounded by definition")
 print("Extraction: %d/%d checks passed" % [checks-failures,checks])
 quit(1 if failures else 0)
