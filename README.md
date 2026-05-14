# 🎮 Wine Sandbox Game Manager

A bash script for safely installing, launching, and managing Windows games on Linux using Wine + Firejail sandboxing. Games run in an isolated environment with no network access during gameplay, protecting your system from potentially unsafe executables.

> Tested on **CachyOS** (Arch-based) with KDE Plasma. Should work on any Arch-based distro.

---

## 📋 Table of Contents

- [Features](#features)
- [How it Works](#how-it-works)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Usage](#usage)
- [Menu Options](#menu-options)
- [Play Time Tracking](#play-time-tracking)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

---

## Features

- Install Windows games into a shared Wine sandbox
- Auto-detect game executables after install
- Auto-create KDE desktop shortcuts
- Launch games directly from the menu
- Track play time per game — works from both the menu and desktop shortcuts
- View play time stats: total time, sessions, last played date
- Uninstall games and clean up all associated files
- Toggle network access per game
- Repair broken shortcuts
- Sandbox health check
- Auto-migrates existing launcher scripts to support new features on first run

---

## How it Works

Each game is installed into a shared Wine prefix (`~/.sandbox-game`) and launched inside a Firejail sandbox. The sandbox:

- **Blocks all network access** during gameplay
- **Prevents root escalation**
- **Filters system calls** via seccomp

A launch script and KDE desktop shortcut are automatically created for every game. Play time is recorded by each launcher script — so sessions are tracked whether you launch from the menu or the desktop icon.

---

## Prerequisites

Install the required packages:

```bash
sudo pacman -S wine wine-mono winetricks firejail
```

---

## Initial Setup

This only needs to be done **once**.

**1. Create the Wine sandbox prefix:**

```bash
mkdir -p ~/.sandbox-game
WINEPREFIX=~/.sandbox-game wineboot -i
```

**2. Install common game dependencies into the prefix:**

```bash
WINEPREFIX=~/.sandbox-game winetricks -q vcrun2019
WINEPREFIX=~/.sandbox-game winetricks -q vcrun2022
WINEPREFIX=~/.sandbox-game winetricks -q dotnet48
```

**3. Install the script as a terminal command:**

```bash
mkdir -p ~/.local/bin
mv game-manager.sh ~/.local/bin/game-manager
chmod +x ~/.local/bin/game-manager
```

**4. Add `~/.local/bin` to your PATH:**

For **fish shell** (default on CachyOS):
```fish
fish_add_path ~/.local/bin
```

For **bash/zsh**, add this to your `~/.bashrc` or `~/.zshrc`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Usage

Run from any terminal:

```bash
game-manager
```

---

## Menu Options

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        🎮  Wine Sandbox Game Manager
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [1] Install a new game
  [2] List installed games
  [3] Launch a game
  [4] Uninstall a game
  [5] Repair shortcut
  [6] Toggle network access
  [7] Sandbox health check
  [8] Play time stats
  [9] Quit
```

### [1] Install a new game

Paste the full path to a Windows installer `.exe`. The script will:

1. Sanitize the filename — strips spaces and special characters that break Wine
2. Run the installer inside Firejail (network open during install only)
3. Wait for you to close the installer window
4. Detect newly installed executables automatically
5. Prompt you to pick the correct exe if multiple are found
6. Prompt for a display name with a smart default
7. Create a tracked launch script at `~/.game-launchers/<slug>.sh`
8. Create a `.desktop` entry and drop a shortcut on your KDE Desktop

> **KDE tip:** Right-click the new desktop icon and select **"Allow Launch"** — KDE requires this one-time confirmation for new `.desktop` files.

### [2] List installed games

Shows all installed games with size, play time, and status:

```
  No.  Name                   Size       Played       Status
  ────────────────────────────────────────────────────────
  [1]  Game One               1.2 GB     2h 14m       ✓ Ready
  [2]  Game Two               4.7 GB     45m          ✓ Ready
  [3]  Old Game               800 MB     < 1m         ✗ Exe missing

  Total sandbox size: 6.7 GB
```

### [3] Launch a game

Pick a game from the list and launch it directly from the terminal. Play time is recorded automatically.

### [4] Uninstall a game

Removes all traces of a selected game:

- Game files from the Wine prefix
- Launch script from `~/.game-launchers/`
- `.desktop` entry from `~/.local/share/applications/`
- Desktop shortcut from `~/Desktop/`

Play time history in the log is preserved so stats aren't lost if you reinstall later.

### [5] Repair shortcut

Recreates missing `.desktop` files and desktop icons for an existing game without reinstalling.

### [6] Toggle network access

Shows current network status per game and toggles it:

```
  [1] Game One               🔴 Blocked
  [2] Game Two               🟢 Allowed
```

Useful for games that require an online connection to run.

### [7] Sandbox health check

Verifies your environment is set up correctly:

```
✓ Wine prefix exists: /home/user/.sandbox-game
✓ Wine installed: wine-11.8
✓ Firejail installed: firejail version 0.9.80
✓ Winetricks installed
✓ Launchers dir exists (2 game(s) registered)

  Total sandbox disk usage: 8.1 GB
```

### [8] Play time stats

Full breakdown of play time across all games:

```
  Game                   Total Time   Sessions   Last Played
  ──────────────────────────────────────────────────────────
  Game One               2h 14m       5          13 May 2026 21:30
  Game Two               45m          2          10 May 2026 18:05

  Total across all games: 2h 59m
```

---

## Play Time Tracking

Play time is tracked inside each game's launcher script. When a game is launched, the script records the start timestamp. When the game closes, it records the end timestamp, calculates the duration, and appends a line to `~/.game-launchers/playtime.log`:

```
game-one|1747123800|1747131960|8160
```

Format: `slug|start_unix|end_unix|duration_seconds`

### Works from both launch methods

Since tracking lives in the launcher script itself, play time is recorded whether you:
- Launch from option `[3]` in the game-manager menu
- Double-click the desktop shortcut

### Existing games

On first run, `game-manager` automatically migrates any existing launcher scripts to include play time tracking — no manual steps needed.

---

## File Structure

```
~/.sandbox-game/                      # Shared Wine prefix
│   └── drive_c/
│       └── Games/
│           ├── Game One/
│           └── Game Two/
│
~/.game-launchers/                    # Per-game launcher scripts
│   ├── game-one.sh                   # Includes playtime tracking
│   ├── game-two.sh
│   └── playtime.log                  # Play time session log
│
~/.local/share/applications/          # .desktop entries (app launcher)
│   ├── game-one.desktop
│   └── game-two.desktop
│
~/Desktop/                            # KDE desktop shortcuts
    ├── game-one.desktop
    └── game-two.desktop
```

---

## Troubleshooting

**Installer crashes immediately**

Run without Firejail to isolate whether it's a Wine or sandbox issue:
```bash
WINEPREFIX=~/.sandbox-game wine "/path/to/installer.exe"
```

**Game needs a specific DLL**

Install it into the sandbox prefix with winetricks:
```bash
WINEPREFIX=~/.sandbox-game winetricks <verb>
```
Find the right verb at [winetricks on GitHub](https://github.com/Winetricks/winetricks).

**Desktop icon won't launch**

Right-click the icon → **Allow Launch**. KDE requires this for every new `.desktop` file.

**Game needs internet to run**

Use option `[6] Toggle network access` in the menu to allow network for that specific game.

**Play time not being recorded**

Run option `[7] Sandbox health check` to verify the setup, then re-launch the game from option `[3]` or the desktop shortcut. If the launcher script is missing tracking, use option `[5] Repair shortcut` and re-launch — or simply run `game-manager` once, which triggers the auto-migration on startup.

**`game-manager` command not found**

```fish
fish_add_path ~/.local/bin
```

Then open a new terminal and try again.
