#!/bin/sh
# Recover exact approved PNG bytes from committed base64 fallback masters.
# The stock Godot 4.3 CI container has no Python. POSIX/coreutils only.
set -eu
base="godot-project"
bundles="$base/assets/critical_sprites"
png_magic="89504e470d0a1a0a"
restored=0

signature() {
  head -c 8 "$1" | od -An -t x1 | tr -d ' \n'
}

restore_one() {
  name="$1"
  target="$2"
  if [ -f "$target" ] && [ "$(signature "$target")" = "$png_magic" ]; then
    echo "[ART-EXPORT] Original intact: $target"
    return
  fi
  input="$bundles/$name.b64"
  if [ ! -f "$input" ]; then
    input="$bundles/$name.png.b64"
  fi
  if [ ! -f "$input" ]; then
    echo "[ART-EXPORT] MISSING exact approved source for $name" >&2
    exit 1
  fi
  tmp="$(mktemp)"
  if ! base64 -d "$input" > "$tmp"; then
    echo "[ART-EXPORT] Cannot decode approved source $input" >&2
    rm -f "$tmp"
    exit 1
  fi
  if [ "$(signature "$tmp")" != "$png_magic" ]; then
    echo "[ART-EXPORT] Not a PNG: $input" >&2
    rm -f "$tmp"
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  mv "$tmp" "$target"
  restored=$((restored + 1))
  echo "[ART-EXPORT] Recovered original source: $target"
}

for view in down up left right; do
  restore_one "form1_walk_${view}_spec384" "$base/sprites/mollosar/form1_walk_${view}_spec384.png"
done
restore_one "form1_idle_down_spec384" "$base/sprites/mollosar/form1_idle_down_spec384.png"
restore_one "p1_bellhollow_bridge_1280x720" "$base/assets/backgrounds/p1_bellhollow_bridge_1280x720.png"
restore_one "mira" "$base/assets/npc/mira.png"
restore_one "wounded_soldier" "$base/assets/npc/wounded_soldier.png"
for creature in dragonthorn gloomcap spinehopper bellmaw wispwillow; do
  restore_one "$creature" "$base/assets/creatures/$creature.png"
done
echo "[ART-EXPORT] Restored $restored approved original PNG files"
