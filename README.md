# Reaper's Reaper

Dark-fantasy 2D story RPG — Godot 4.3, Steam target.

## Branches

- `develop` — integrated development; CI runs the GDScript test suite headless on every push.
- `main` — releasable. Merge from `develop` only when CI is green.

## Push discipline

One calm push at a time. Git CLI over API for anything substantial.
If a push fails: stop, diagnose, ask — never retry-blast.

## Layout

- `godot-project/` — the game (scripts, scenes, sprites, assets, project.godot)
- `.github/workflows/ci.yml` — headless test workflow
