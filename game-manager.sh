#!/bin/bash
# game-manager.sh — All-in-one Wine sandbox game manager
# Usage: game-manager
# Version: 0.1

set -e

# ── Config ────────────────────────────────────────────────────────────────────
VERSION="0.1"
WINEPREFIX="$HOME/.sandbox-game"
LAUNCHERS_DIR="$HOME/.game-launchers"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_LINK_DIR="$HOME/Desktop"
ICON_DEFAULT="wine"
PLAYTIME_LOG="$HOME/.game-launchers/playtime.log"
# ─────────────────────────────────────────────────────────────────────────────

# ── UI Helpers ────────────────────────────────────────────────────────────────

print_header() {
  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "        🎮  Wine Sandbox Game Manager     v$VERSION"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

press_enter() {
  echo ""
  read -rp "Press Enter to return to menu..."
}

confirm() {
  local prompt="$1"
  read -rp "$prompt [y/N]: " REPLY
  [[ "$REPLY" == "y" || "$REPLY" == "Y" ]]
}

format_size() {
  local path="$1"
  if [[ -d "$path" ]]; then
    du -sh "$path" 2>/dev/null | cut -f1
  else
    echo "N/A"
  fi
}

# ── Playtime Helpers ─────────────────────────────────────────────────────────

# Convert raw seconds to "Xh Ym" or "Ym" or "< 1m"
format_duration() {
  local secs=$1
  local hours=$(( secs / 3600 ))
  local mins=$(( (secs % 3600) / 60 ))
  if [[ $hours -gt 0 ]]; then
    echo "${hours}h ${mins}m"
  elif [[ $mins -gt 0 ]]; then
    echo "${mins}m"
  else
    echo "< 1m"
  fi
}

# Get total seconds played for a given slug from the log
get_playtime() {
  local slug="$1"
  local total=0
  if [[ ! -f "$PLAYTIME_LOG" ]]; then
    echo 0
    return
  fi
  while IFS='|' read -r log_slug _start _end duration; do
    if [[ "$log_slug" == "$slug" ]]; then
      total=$(( total + duration ))
    fi
  done < "$PLAYTIME_LOG"
  echo "$total"
}

# Get last played date for a slug
get_last_played() {
  local slug="$1"
  local last=0
  if [[ ! -f "$PLAYTIME_LOG" ]]; then
    echo "Never"
    return
  fi
  while IFS='|' read -r log_slug _start end_ts _duration; do
    if [[ "$log_slug" == "$slug" ]] && [[ "$end_ts" -gt "$last" ]]; then
      last=$end_ts
    fi
  done < "$PLAYTIME_LOG"
  if [[ $last -eq 0 ]]; then
    echo "Never"
  else
    date -d "@$last" "+%d %b %Y %H:%M" 2>/dev/null || echo "Unknown"
  fi
}

# Get session count for a slug
get_session_count() {
  local slug="$1"
  if [[ ! -f "$PLAYTIME_LOG" ]]; then
    echo 0
    return
  fi
  grep -c "^${slug}|" "$PLAYTIME_LOG" 2>/dev/null || echo 0
}

# ── Migration — silently update old launchers to include playtime tracking ────

migrate_launchers() {
  [[ ! -d "$LAUNCHERS_DIR" ]] && return
  for launcher in "$LAUNCHERS_DIR"/*.sh; do
    [[ -f "$launcher" ]] || continue
    # Skip if already has playtime tracking
    grep -q "PLAYTIME_LOG" "$launcher" && continue

    SLUG=$(basename "$launcher" .sh)
    EXE=$(grep -oP 'wine "\K[^"]+' "$launcher" | head -1)
    NET_FLAG=""
    grep -q "\-\-net=none" "$launcher" && NET_FLAG="--net=none "

    # Rewrite launcher with tracking baked in
    cat > "$launcher" << SCRIPT
#!/bin/bash
PLAYTIME_LOG="\$HOME/.game-launchers/playtime.log"
START=\$(date +%s)
WINEPREFIX="$WINEPREFIX" firejail ${NET_FLAG}--noroot --seccomp wine "$EXE"
END=\$(date +%s)
DURATION=\$((END - START))
echo "${SLUG}|\${START}|\${END}|\${DURATION}" >> "\$PLAYTIME_LOG"
SCRIPT
    chmod +x "$launcher"
  done
}

# ── Game List Builder ─────────────────────────────────────────────────────────

get_games() {
  GAME_NAMES=()
  GAME_EXES=()
  GAME_SLUGS=()
  GAME_SIZES=()

  if [[ ! -d "$LAUNCHERS_DIR" ]] || [[ -z "$(ls -A "$LAUNCHERS_DIR" 2>/dev/null)" ]]; then
    return
  fi

  for launcher in "$LAUNCHERS_DIR"/*.sh; do
    [[ -f "$launcher" ]] || continue
    EXE=$(grep -oP 'wine "\K[^"]+' "$launcher" | head -1)
    SLUG=$(basename "$launcher" .sh)
    NAME=$(echo "$SLUG" | tr '-' ' ' | sed 's/\b\w/\u&/g')
    GAME_DIR=$(dirname "$EXE")
    SIZE=$(format_size "$GAME_DIR")

    GAME_NAMES+=("$NAME")
    GAME_EXES+=("$EXE")
    GAME_SLUGS+=("$SLUG")
    GAME_SIZES+=("$SIZE")
  done
}

# ── Main Menu ─────────────────────────────────────────────────────────────────

main_menu() {
  print_header
  echo "  [1] Install a new game"
  echo "  [2] List installed games"
  echo "  [3] Launch a game"
  echo "  [4] Uninstall a game"
  echo "  [5] Repair shortcut"
  echo "  [6] Toggle network access"
  echo "  [7] Sandbox health check"
  echo "  [8] Play time stats"
  echo "  [9] Quit"
  echo ""
  read -rp "Choice: " CHOICE

  case "$CHOICE" in
    1) install_game ;;
    2) list_games ;;
    3) launch_game ;;
    4) uninstall_game ;;
    5) repair_shortcut ;;
    6) toggle_network ;;
    7) health_check ;;
    8) playtime_stats ;;
    9) echo "Bye!" && exit 0 ;;
    *) echo "Invalid choice." && sleep 1 ;;
  esac
}

# ── 1. Install Game ───────────────────────────────────────────────────────────

install_game() {
  print_header
  echo "── Install New Game ──"
  echo ""
  read -rp "Paste the full path to the installer .exe: " ORIGINAL_PATH

  # Strip surrounding double quotes
  ORIGINAL_PATH="${ORIGINAL_PATH%\"}"
  ORIGINAL_PATH="${ORIGINAL_PATH#\"}"
  # Strip surrounding single quotes
  ORIGINAL_PATH="${ORIGINAL_PATH%\'}"
  ORIGINAL_PATH="${ORIGINAL_PATH#\'}"
  # Strip leading/trailing whitespace
  ORIGINAL_PATH="${ORIGINAL_PATH#"${ORIGINAL_PATH%%[![:space:]]*}"}"
  ORIGINAL_PATH="${ORIGINAL_PATH%"${ORIGINAL_PATH##*[![:space:]]}"}"

  if [[ ! -f "$ORIGINAL_PATH" ]]; then
    echo ""
    echo "Error: File not found: $ORIGINAL_PATH"
    press_enter
    return
  fi

  DIR=$(dirname "$ORIGINAL_PATH")
  BASENAME=$(basename "$ORIGINAL_PATH")
  CLEAN_BASENAME=$(echo "$BASENAME" | tr ' []()&!#$%^' '_________' | tr -s '_')
  CLEAN_PATH="$DIR/$CLEAN_BASENAME"

  if [[ "$ORIGINAL_PATH" != "$CLEAN_PATH" ]]; then
    echo ""
    echo "Renaming installer:"
    echo "  From: $BASENAME"
    echo "  To:   $CLEAN_BASENAME"
    mv "$ORIGINAL_PATH" "$CLEAN_PATH"
  fi

  echo ""
  echo "Scanning sandbox before install..."
  BEFORE_EXES=$(find "$WINEPREFIX/drive_c" -name "*.exe" 2>/dev/null | grep -v -E "(unins|uninst|setup|install|redist|vcredist|dotnet|directx|vc_)" | sort || true)

  echo "Launching installer. Close the window when installation is complete."
  echo ""
  set +e
  WINEPREFIX="$WINEPREFIX" firejail --noroot --seccomp wine "$CLEAN_PATH"
  set -e

  echo ""
  echo "Installer closed. Searching for new executables..."

  AFTER_EXES=$(find "$WINEPREFIX/drive_c" -name "*.exe" 2>/dev/null | grep -v -E "(unins|uninst|setup|install|redist|vcredist|dotnet|directx|vc_)" | sort || true)
  NEW_EXES=$(comm -13 <(echo "$BEFORE_EXES") <(echo "$AFTER_EXES") || true)

  GAME_EXE=""

  if [[ -z "$NEW_EXES" ]]; then
    echo ""
    echo "No new executables detected automatically."
    find "$WINEPREFIX/drive_c" -name "*.exe" 2>/dev/null | grep -v -E "(unins|setup|redist)" || true
    echo ""
    read -rp "Enter the full path to the game exe manually: " GAME_EXE
  else
    NEW_EXE_ARRAY=()
    while IFS= read -r line; do
      NEW_EXE_ARRAY+=("$line")
    done <<< "$NEW_EXES"

    if [[ ${#NEW_EXE_ARRAY[@]} -eq 1 ]]; then
      GAME_EXE="${NEW_EXE_ARRAY[0]}"
      echo "Found: $GAME_EXE"
    else
      echo ""
      echo "Multiple new executables found. Pick the main game exe:"
      for i in "${!NEW_EXE_ARRAY[@]}"; do
        echo "  [$((i+1))] ${NEW_EXE_ARRAY[$i]}"
      done
      read -rp "Enter number: " PICK
      GAME_EXE="${NEW_EXE_ARRAY[$((PICK-1))]}"
    fi
  fi

  GAME_NAME=$(basename "$GAME_EXE" .exe | tr '_-' '  ' | sed 's/\b\w/\u&/g')
  read -rp "Game name for shortcut [$GAME_NAME]: " CUSTOM_NAME
  GAME_NAME="${CUSTOM_NAME:-$GAME_NAME}"
  GAME_SLUG=$(echo "$GAME_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')

  mkdir -p "$LAUNCHERS_DIR"
  LAUNCH_SCRIPT="$LAUNCHERS_DIR/${GAME_SLUG}.sh"
  cat > "$LAUNCH_SCRIPT" << SCRIPT
#!/bin/bash
PLAYTIME_LOG="\$HOME/.game-launchers/playtime.log"
START=\$(date +%s)
WINEPREFIX="$WINEPREFIX" firejail --net=none --noroot --seccomp wine "$GAME_EXE"
END=\$(date +%s)
DURATION=\$((END - START))
echo "${GAME_SLUG}|\${START}|\${END}|\${DURATION}" >> "\$PLAYTIME_LOG"
SCRIPT
  chmod +x "$LAUNCH_SCRIPT"

  mkdir -p "$DESKTOP_DIR"
  DESKTOP_FILE="$DESKTOP_DIR/${GAME_SLUG}.desktop"
  cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=$GAME_NAME
Exec=$LAUNCH_SCRIPT
Icon=$ICON_DEFAULT
Terminal=false
Type=Application
Categories=Game;
DESKTOP
  chmod +x "$DESKTOP_FILE"

  mkdir -p "$DESKTOP_LINK_DIR"
  cp "$DESKTOP_FILE" "$DESKTOP_LINK_DIR/${GAME_SLUG}.desktop"
  chmod +x "$DESKTOP_LINK_DIR/${GAME_SLUG}.desktop"

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✓ Installed:     $GAME_NAME"
  echo "  ✓ Launch script: $LAUNCH_SCRIPT"
  echo "  ✓ Desktop icon:  ~/Desktop/${GAME_SLUG}.desktop"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Tip: Right-click the desktop icon and hit 'Allow Launch' in KDE."
  press_enter
}

# ── 2. List Games ─────────────────────────────────────────────────────────────

list_games() {
  print_header
  echo "── Installed Games ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet. Use option 1 to install one."
    press_enter
    return
  fi

  printf "  %-4s %-22s %-10s %-12s %s\n" "No." "Name" "Size" "Played" "Status"
  echo "  ────────────────────────────────────────────────────────"
  for i in "${!GAME_NAMES[@]}"; do
    if [[ -f "${GAME_EXES[$i]}" ]]; then
      STATUS="✓ Ready"
    else
      STATUS="✗ Exe missing"
    fi
    SECS=$(get_playtime "${GAME_SLUGS[$i]}")
    PLAYTIME=$(format_duration "$SECS")
    printf "  [%d]  %-22s %-10s %-12s %s\n" "$((i+1))" "${GAME_NAMES[$i]}" "${GAME_SIZES[$i]}" "$PLAYTIME" "$STATUS"
  done

  echo ""
  TOTAL=$(format_size "$WINEPREFIX/drive_c")
  echo "  Total sandbox size: $TOTAL"
  press_enter
}

# ── 3. Launch Game ────────────────────────────────────────────────────────────

launch_game() {
  print_header
  echo "── Launch a Game ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet."
    press_enter
    return
  fi

  for i in "${!GAME_NAMES[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${GAME_NAMES[$i]}"
  done

  echo ""
  read -rp "Enter number (or Enter to cancel): " CHOICE
  [[ -z "$CHOICE" ]] && return

  IDX=$((CHOICE - 1))
  if [[ $IDX -lt 0 ]] || [[ $IDX -ge ${#GAME_NAMES[@]} ]]; then
    echo "Invalid selection."
    press_enter
    return
  fi

  echo ""
  echo "Launching ${GAME_NAMES[$IDX]}..."
  bash "${LAUNCHERS_DIR}/${GAME_SLUGS[$IDX]}.sh" &
}

# ── 4. Uninstall Game ─────────────────────────────────────────────────────────

uninstall_game() {
  print_header
  echo "── Uninstall a Game ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet."
    press_enter
    return
  fi

  for i in "${!GAME_NAMES[@]}"; do
    printf "  [%d] %-25s %s\n" "$((i+1))" "${GAME_NAMES[$i]}" "${GAME_SIZES[$i]}"
  done

  echo ""
  read -rp "Enter number to uninstall (or Enter to cancel): " CHOICE
  [[ -z "$CHOICE" ]] && return

  IDX=$((CHOICE - 1))
  if [[ $IDX -lt 0 ]] || [[ $IDX -ge ${#GAME_NAMES[@]} ]]; then
    echo "Invalid selection."
    press_enter
    return
  fi

  local name="${GAME_NAMES[$IDX]}"
  local exe="${GAME_EXES[$IDX]}"
  local slug="${GAME_SLUGS[$IDX]}"
  local game_dir
  game_dir=$(dirname "$exe")

  echo ""
  echo "You are about to delete: $name"
  echo ""
  echo "This will remove:"
  echo "  • Game files:    $game_dir"
  echo "  • Launch script: $LAUNCHERS_DIR/${slug}.sh"
  echo "  • Desktop icon:  $DESKTOP_LINK_DIR/${slug}.desktop"
  echo "  • App entry:     $DESKTOP_DIR/${slug}.desktop"
  echo ""

  if confirm "Are you sure?"; then
    [[ -d "$game_dir" ]]                         && rm -rf "$game_dir"                       && echo "✓ Removed game files"
    [[ -f "$LAUNCHERS_DIR/${slug}.sh" ]]         && rm "$LAUNCHERS_DIR/${slug}.sh"           && echo "✓ Removed launch script"
    [[ -f "$DESKTOP_DIR/${slug}.desktop" ]]      && rm "$DESKTOP_DIR/${slug}.desktop"        && echo "✓ Removed app entry"
    [[ -f "$DESKTOP_LINK_DIR/${slug}.desktop" ]] && rm "$DESKTOP_LINK_DIR/${slug}.desktop"   && echo "✓ Removed desktop icon"
    echo ""
    echo "✓ $name has been removed."
  else
    echo "Cancelled."
  fi

  press_enter
}

# ── 5. Repair Shortcut ────────────────────────────────────────────────────────

repair_shortcut() {
  print_header
  echo "── Repair Shortcut ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet."
    press_enter
    return
  fi

  for i in "${!GAME_NAMES[@]}"; do
    printf "  [%d] %s\n" "$((i+1))" "${GAME_NAMES[$i]}"
  done

  echo ""
  read -rp "Enter number to repair (or Enter to cancel): " CHOICE
  [[ -z "$CHOICE" ]] && return

  IDX=$((CHOICE - 1))
  if [[ $IDX -lt 0 ]] || [[ $IDX -ge ${#GAME_NAMES[@]} ]]; then
    echo "Invalid selection."
    press_enter
    return
  fi

  local name="${GAME_NAMES[$IDX]}"
  local slug="${GAME_SLUGS[$IDX]}"

  mkdir -p "$DESKTOP_DIR" "$DESKTOP_LINK_DIR"
  DESKTOP_FILE="$DESKTOP_DIR/${slug}.desktop"
  cat > "$DESKTOP_FILE" << DESKTOP
[Desktop Entry]
Name=$name
Exec=$LAUNCHERS_DIR/${slug}.sh
Icon=$ICON_DEFAULT
Terminal=false
Type=Application
Categories=Game;
DESKTOP
  chmod +x "$DESKTOP_FILE"
  cp "$DESKTOP_FILE" "$DESKTOP_LINK_DIR/${slug}.desktop"
  chmod +x "$DESKTOP_LINK_DIR/${slug}.desktop"

  echo ""
  echo "✓ Shortcut repaired for $name"
  echo "  Remember to right-click → Allow Launch in KDE."
  press_enter
}

# ── 6. Toggle Network ─────────────────────────────────────────────────────────

toggle_network() {
  print_header
  echo "── Toggle Network Access ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet."
    press_enter
    return
  fi

  for i in "${!GAME_NAMES[@]}"; do
    LAUNCHER="$LAUNCHERS_DIR/${GAME_SLUGS[$i]}.sh"
    if grep -q "\-\-net=none" "$LAUNCHER" 2>/dev/null; then
      NET_STATUS="🔴 Blocked"
    else
      NET_STATUS="🟢 Allowed"
    fi
    printf "  [%d] %-25s %s\n" "$((i+1))" "${GAME_NAMES[$i]}" "$NET_STATUS"
  done

  echo ""
  read -rp "Enter number to toggle (or Enter to cancel): " CHOICE
  [[ -z "$CHOICE" ]] && return

  IDX=$((CHOICE - 1))
  if [[ $IDX -lt 0 ]] || [[ $IDX -ge ${#GAME_NAMES[@]} ]]; then
    echo "Invalid selection."
    press_enter
    return
  fi

  LAUNCHER="$LAUNCHERS_DIR/${GAME_SLUGS[$IDX]}.sh"

  if grep -q "\-\-net=none" "$LAUNCHER"; then
    sed -i 's/ --net=none//' "$LAUNCHER"
    echo ""
    echo "✓ Network ALLOWED for ${GAME_NAMES[$IDX]}"
  else
    sed -i 's/firejail/firejail --net=none/' "$LAUNCHER"
    echo ""
    echo "✓ Network BLOCKED for ${GAME_NAMES[$IDX]}"
  fi

  press_enter
}

# ── 8. Play Time Stats ────────────────────────────────────────────────────────

playtime_stats() {
  print_header
  echo "── Play Time Stats ──"
  echo ""
  get_games

  if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
    echo "No games installed yet."
    press_enter
    return
  fi

  GRAND_TOTAL=0

  printf "  %-22s %-12s %-10s %s\n" "Game" "Total Time" "Sessions" "Last Played"
  echo "  ──────────────────────────────────────────────────────────────"

  for i in "${!GAME_NAMES[@]}"; do
    SLUG="${GAME_SLUGS[$i]}"
    SECS=$(get_playtime "$SLUG")
    SESSIONS=$(get_session_count "$SLUG")
    LAST=$(get_last_played "$SLUG")
    PLAYTIME=$(format_duration "$SECS")
    GRAND_TOTAL=$(( GRAND_TOTAL + SECS ))
    printf "  %-22s %-12s %-10s %s\n" "${GAME_NAMES[$i]}" "$PLAYTIME" "$SESSIONS" "$LAST"
  done

  echo ""
  echo "  ──────────────────────────────────────────────────────────────"
  printf "  %-22s %s\n" "Total across all games:" "$(format_duration "$GRAND_TOTAL")"
  press_enter
}

# ── 7. Health Check ───────────────────────────────────────────────────────────

health_check() {
  print_header
  echo "── Sandbox Health Check ──"
  echo ""

  if [[ -d "$WINEPREFIX" ]]; then
    echo "✓ Wine prefix exists: $WINEPREFIX"
  else
    echo "✗ Wine prefix missing: $WINEPREFIX"
    echo "  Run: mkdir -p $WINEPREFIX && WINEPREFIX=$WINEPREFIX wineboot -i"
  fi

  if command -v wine &>/dev/null; then
    WINE_VER=$(wine --version 2>/dev/null)
    echo "✓ Wine installed: $WINE_VER"
  else
    echo "✗ Wine not found. Install: sudo pacman -S wine"
  fi

  if command -v firejail &>/dev/null; then
    FJ_VER=$(firejail --version 2>/dev/null | head -1)
    echo "✓ Firejail installed: $FJ_VER"
  else
    echo "✗ Firejail not found. Install: sudo pacman -S firejail"
  fi

  if command -v winetricks &>/dev/null; then
    echo "✓ Winetricks installed"
  else
    echo "  Winetricks not found (optional). Install: sudo pacman -S winetricks"
  fi

  if [[ -d "$LAUNCHERS_DIR" ]]; then
    COUNT=$(ls "$LAUNCHERS_DIR"/*.sh 2>/dev/null | wc -l)
    echo "✓ Launchers dir exists ($COUNT game(s) registered)"
  else
    echo "  No launchers directory yet (will be created on first install)"
  fi

  echo ""
  TOTAL=$(format_size "$WINEPREFIX")
  echo "  Total sandbox disk usage: $TOTAL"

  press_enter
}

# ── Entry Point ───────────────────────────────────────────────────────────────

migrate_launchers

while true; do
  main_menu
done
