# Mollosar Form 1 approved attacks — integration 2026-10-18
Source: Drive folder 1N3jxwt-CNLWDsCVyNBgTj8EFXTKVfDVR.
Director verification: VERIFY-20261018-form1-attack-set.md (BOT-002).
Producer supplied all 20 directional action strips; exact PNG bytes are preserved.
The Drive source manifest has a `strips` ARRAY with global cell/fps/pivot,
but the existing Godot loader requires a `strips` DICTIONARY keyed
<action>_<direction> with a texture path, frames, cell, fps, and pivot each.
This branch converts only the manifest schema, not the art.
20 strips / 128 frames total, 384x384 per frame, 12.0 FPS metadata,
pivot [192,376], alpha 0 or 255 only, no semitransparency.
Director-accepted visual risk: 19 frames touch the upper cell boundary and
some may visibly clip sword tips. No artwork has been edited to hide this.
Required Android/Godot tests: form1_attack_clips_test.gd,
form1_animation_runtime_test.gd, and full CI art validator.
Previous partial/rejected set still fails closed. Candidate integration branch:
do not promote to develop before director review + green CI.
