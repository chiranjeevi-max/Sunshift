class_name BrassMirror
extends InteractiveProp

## A brass window mirror. Two reflective faces: "/" (state 0) and "\" (state 1).
## Reflection itself is computed by LightSolver; this class only names its sound.


func cue_name() -> String:
  return "mirror_click"
