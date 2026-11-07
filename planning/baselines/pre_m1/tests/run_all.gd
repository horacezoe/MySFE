extends SceneTree

func _initialize():
 call_deferred("run_suites")

func run_suites():
 var failed=0
 for suite in ["test_input_router","test_foundation","test_game"]:
  var output: Array=[]
  var code=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/"+suite+".gd"]),output,true)
  for line in output: print(line)
  if code!=0: failed+=1
  # Godot may report script compilation failures with exit 0; reject those too.
  elif str(output).contains("SCRIPT ERROR") or str(output).contains("ERROR:"): failed+=1
 print("PHASE 1: ",3-failed,"/3 suites passed")
 quit(1 if failed else 0)
