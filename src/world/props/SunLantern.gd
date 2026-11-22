class_name SunLantern
extends InteractiveProp

## A glass lantern that stores one turn of light. Charging and glowing are
## resolved by LightSolver; this node plays the charge cue and shows the glow.


func cue_name() -> String:
  return "lantern_charge"


func set_glowing(on: bool) -> void:
  if _sprite == null or _sprite.sprite_frames == null:
    return
  if on and _sprite.sprite_frames.has_animation("glow"):
    _sprite.play("glow")
  elif not on:
    _play_state_animation()
