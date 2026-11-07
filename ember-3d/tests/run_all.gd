extends SceneTree

func _initialize():
 call_deferred("run_suites")

func run_suites():
 var failed=0
 var suites=["test_input_router","test_foundation","test_combat","test_ai","test_inventory","test_save","test_profile","test_inventory_ui","test_game","test_actions","test_phase2","test_phase3","test_phase3_disk","test_phase3_review","test_extraction","test_phase4_profile","test_phase4_map","test_phase4_ui","test_phase4_game","test_phase4_legacy","test_character_visual","test_rifle_visual","test_combat_feedback","test_phase5_integration","test_corpse_profile","test_corpse_ui","test_corpse_game"]
 for suite in suites:
  var output: Array=[]
  var code=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/"+suite+".gd"]),output,true)
  for line in output: print(line)
  if code!=0: failed+=1
  # Godot may report script compilation failures with exit 0; reject those too.
  elif str(output).contains("SCRIPT ERROR") or str(output).contains("ERROR:") or str(output).contains("instances were leaked"): failed+=1
 print("PHASE 5 + CORPSE LOOT: ",suites.size()-failed,"/",suites.size()," suites passed")
 quit(1 if failed else 0)
