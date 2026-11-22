extends Node

## Shared signals let the HUD and audio respond to the simulation independently.

signal board_evaluated(warmth_factor: float, satisfied: int, total: int)
signal warmth_changed(warmth_factor: float)
signal sun_shifted(angle: int)
signal prop_shifted(prop_id: String, state: int)
signal lantern_charge_changed(lantern_id: String, charge: int)
signal level_loaded(level_id: String, act: int)
signal level_solved(level_id: String, act: int)
signal level_reset(level_id: String)
signal journal_postcard_unlocked(level_id: String)
signal undo_performed()
signal audio_cue(cue: String, pitch: float)
