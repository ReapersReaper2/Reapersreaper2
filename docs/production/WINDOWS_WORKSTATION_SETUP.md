# Reaper's Reaper — Windows Development Workstation Setup

Status: documented plan only. No device access or local installation is implied.
Linked: Project Rebirth PR #74; workstation issue #75.
Primary platform: Windows laptop; auxiliary: Chromebook for GitHub/Drive/email review.
Target engine: **Godot 4.3 stable**, matching `godot-project/project.godot` and CI. Do not upgrade the project engine during baseline.

## Phase A — Prepare without disrupting the laptop
1. Check Windows version (Settings > System > About), free disk space and RAM. Aim for at least 20 GB of free working space for repository, Git LFS, editor imports, build tools and captures; this is a planning allowance, not a guaranteed minimum.
2. Choose a user-controlled workspace e.g. `C:\ReapersReaper\` (avoid OneDrive-synced working trees, Desktop auto-backup and Syncthing's actively-written folder).
3. Keep personal and development files separate. Do not share remote-desktop credentials or passwords by email/chat. Do not grant Muse bots machine, Drive or production GitHub access.
4. Install Git for Windows with Git LFS support, plus Godot **4.3 stable standard Windows x86_64**, from official sources. VS Code and Python are optional at baseline. For Android export, add the documented JDK/Android SDK later, after desktop visual proof.

## Phase B — Baseline checkout
Open PowerShell and run interactively after verifying Git is installed:

```powershell
git --version
git lfs version
New-Item -ItemType Directory -Force C:\ReapersReaper | Out-Null
Set-Location C:\ReapersReaper
git clone https://github.com/ReapersReaper2/Reapersreaper2.git
Set-Location .\Reapersreaper2
git checkout develop
git lfs pull
git rev-parse HEAD
git lfs ls-files
```

The repo default branch is `develop` (the integrated development baseline); do not checkout or merge planning PRs into it on the machine while establishing a baseline.
If the checkout is already present, do not clone over it: verify the location and branch first. Do not run `git clean`, `git reset --hard`, or force pushes on this setup path.

## Phase C — First desktop proof
1. Download Godot 4.3 stable from https://godotengine.org/download/archive/4.3-stable/ (Windows standard edition, **not** .NET unless project requires it).
2. Unzip Godot to a stable folder e.g. `C:\ReapersReaper\tools\Godot43\`; run executable.
3. Import/open `C:\ReapersReaper\Reapersreaper2\godot-project\project.godot`.
4. Let resources import fully, then run the project's default title scene (F6 for selected scene or F5 for the project); record startup errors and any missing LFS art. Run the opening bridge from an actual in-game path.
5. Capture 2 genuine screenshots and optionally a 10–20-second recording: title and bridge with Mollosar walking and attacking. Save outside the checkout, e.g. `C:\ReapersReaper\captures\<date>\`, along with commit SHA and engine version. Do not label any render as approved yet.

## Phase D — Automated runner (separate ticket)
Build a repeatable Godot scene-launch harness for walking, attacking, damage and transitions; capture log + frame screenshots. Compare real frames and user-approved art references, not just numeric validation. GUI automation is device/access-platform-dependent; do not assume a GitHub connector provides laptop screen control.
Keep Chromebook as review/coordination device; optionally test Linux-on-ChromeOS support separately, not as the baseline.

## Phase E — Android later
Install Android SDK/JDK and signing/export templates only after Phase C passes. Verify exported Android APK matches the commit and is tested on a physical phone; do not treat a successful headless run as on-device proof.

## First report template
```
Windows version:
RAM / free disk:
Godot version:
Git and Git LFS versions:
Git commit:
Project opens: PASS/FAIL
Title screen: PASS/FAIL
Opening bridge movement: PASS/FAIL
Opening bridge attack uses approved clips: PASS/FAIL/UNKNOWN
Missing resources/errors:
Screenshot/recording paths:
```

## Muse isolation
Muse bots communicate via email and designated Syncthing handoff paths (read-only inbound approvals, isolated outgoing submissions). No shared mutable repo working folder via Syncthing; source code changes travel through reviewed GitHub commits/PRs. Never transmit secrets, credentials or private working environment access to bots.
