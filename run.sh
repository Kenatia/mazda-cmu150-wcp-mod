#!/bin/sh
# ==============================================================================
# Project: Native Wireless CarPlay (WCP) Mod for Mazda CMU150
# Target Firmware: V74.00.324
# Author: Kenatia
# Description: Installer / Uninstaller script for Wireless CarPlay on Legacy CMU.
#              Features backup, autostart patching (avoids ublox.txt / DTC B119F),
#              sm_WCP.conf tuning (disables reset_board), and Process Spoofing.
# ==============================================================================

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
export PATH
LC_ALL=C
export LC_ALL

hwclock --hctosys 2>/dev/null

# Disable Hardware Watchdog during installation
echo 1 > /sys/class/gpio/Watchdog\ Disable/value 2>/dev/null
mount -o rw,remount / 2>/dev/null

MYDIR=$(dirname "$(readlink -f "$0")")
mount -o rw,remount "${MYDIR}" 2>/dev/null

GBT=/jci/scripts/get_board_type.sh
SMW=/jci/sm/sm_WCP.conf
AUTOSTART=/usr/bin/autostart
BAK=.bak

# Show dialog message, wait 5 seconds then exit (no reboot)
abort_msg()
{
  /jci/tools/jci-dialog --info --title="WCP Mod" --text="$1" --no-cancel &
  sleep 5
  killall -q jci-dialog
  exit "$2"
}

# --- 1. Check Firmware Version V74.00.324 ---
CMU_VER=$(grep '^JCI_SW_VER=' /jci/version.ini 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [ "${CMU_VER}" != "74.00.324" ]; then
  abort_msg "Only CMU firmware V74.00.324 is supported.\nCurrent version: V${CMU_VER}\nOperation cancelled.\nPlease remove USB." 1
fi

# --- 2. Check Hardware via GPIO: only install on legacy CMU (0/0) ---
DI_TP1056=/sys/class/gpio/DI_TP1056/value
DI_TP1029=/sys/class/gpio/DI_TP1029/value

v1=""
v2=""
if [ -e "$DI_TP1056" ] && [ -e "$DI_TP1029" ]; then
  for _ in 0 1 2; do
    v1=$(cat "$DI_TP1056" 2>/dev/null)
    v2=$(cat "$DI_TP1029" 2>/dev/null)
    if { [ "$v1" = "0" ] || [ "$v1" = "1" ]; } && { [ "$v2" = "0" ] || [ "$v2" = "1" ]; }; then
      break
    fi
    sleep 1
  done

  if [ "$v1" = "1" ] || [ "$v2" = "1" ]; then
    abort_msg "Newer CMU hardware with native WCP support detected (GPIO=${v1}/${v2}).\nThis mod is not required.\nPlease remove USB." 0
  fi

  if [ "$v1" != "0" ] || [ "$v2" != "0" ]; then
    abort_msg "Unable to determine hardware type (GPIO=${v1}/${v2}).\nOperation aborted for safety.\nPlease remove USB." 1
  fi
fi

mkdir -p "${MYDIR}/logs" 2>/dev/null

# --- 3. Current Status Check ---
if grep -q "vim_app" "$GBT" 2>/dev/null; then
  MOD_STATUS="INSTALLED"
else
  MOD_STATUS="NOT INSTALLED"
fi

# --- 4. Interactive Menu ---
/jci/tools/jci-dialog --3-button-dialog \
  --title="Wireless CarPlay Mod (V${CMU_VER})" \
  --text="Current Status: ${MOD_STATUS}\nSelect an action:" \
  --ok-label="Install" \
  --cancel-label="Uninstall" \
  --button3-label="Cancel"
CHOICE=$?

# Installation error handler: restore files from .bak then exit (no reboot)
fail()
{
  echo "ERROR: $1"
  for f in "$GBT" "$SMW" "$AUTOSTART"; do
    if [ -e "${f}${BAK}" ]; then
      cp -a "${f}${BAK}" "$f"
      echo "Restored $f from ${BAK}"
    fi
  done
  rm -f "${GBT}.new" "${AUTOSTART}.new"
  sync
  killall -q jci-dialog
  abort_msg "Installation failed: $1\nOriginal files restored.\nCheck logs on USB.\nPlease remove USB." 1
}

if [ "$CHOICE" -eq 0 ]; then
  # ============================================================
  # INSTALL
  # ============================================================
  exec > "${MYDIR}/logs/install_wcp.log" 2>&1
  echo "=== Starting WCP Mod Installation (FW: ${CMU_VER}, GPIO=${v1}/${v2}) ==="

  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Installing WCP Mod...\nPlease DO NOT remove USB." --no-cancel &

  # --- 1. Backup original files (first time only) ---
  for f in "$GBT" "$SMW" "$AUTOSTART"; do
    if [ ! -e "${f}${BAK}" ]; then
      cp -a "$f" "${f}${BAK}"
      echo "Backed up ${f}${BAK}"
    else
      echo "Backup ${f}${BAK} already exists"
    fi
  done

  # --- 2. autostart: replace ublox.txt creation with removal command ---
  if grep -qF 'WCP mod: do not create ublox.txt' "$AUTOSTART"; then
    echo "autostart already modified, skipping"
  else
    if [ "$(grep -cF 'touch "$UBLOX_FILE"' "$AUTOSTART")" != "1" ]; then
      fail "exactly one 'touch \$UBLOX_FILE' line not found in autostart"
    fi
    cp -a "$AUTOSTART" "${AUTOSTART}.new"
    sed '/touch "\$UBLOX_FILE"/s/.*/    test -e "$UBLOX_FILE" \&\& rm -f "$UBLOX_FILE" # WCP mod: do not create ublox.txt/' "$AUTOSTART" > "${AUTOSTART}.new"
    if grep -qF 'touch "$UBLOX_FILE"' "${AUTOSTART}.new" \
       || [ "$(wc -l < "${AUTOSTART}.new")" != "$(wc -l < "$AUTOSTART")" ] \
       || ! sh -n "${AUTOSTART}.new"; then
      fail "New autostart file is invalid"
    fi
    mv -f "${AUTOSTART}.new" "$AUTOSTART"
    echo "Updated autostart successfully"
  fi

  # --- 3. sm_WCP.conf: remove GPS=UBLOX, set reset_board=no, clear jcinavi args ---
  sed -i '/name="jciLDS"/{s/ GPS=UBLOX//;s/reset_board="yes"/reset_board="no"/}' "$SMW"
  sed -i '/name="jcinavi"/{s/args="wcp"/args=""/;s/reset_board="yes"/reset_board="no"/}' "$SMW"
  if grep 'name="jciLDS"' "$SMW" | grep -q 'GPS=UBLOX' \
     || ! grep 'name="jciLDS"' "$SMW" | grep -q 'reset_board="no"' \
     || ! grep 'name="jcinavi"' "$SMW" | grep -q 'args=""'; then
    fail "sm_WCP.conf modification did not match expected criteria"
  fi
  echo "Updated sm_WCP.conf successfully"

  # --- 4. get_board_type.sh (activation switch, written last) ---
  cat << 'EOF' > "${GBT}.new"
#!/bin/sh
if [ -e /data_persist/wcp_force_off ]; then
    exit 1
fi

for p in $PPID $(cut -d' ' -f4 /proc/$PPID/stat 2>/dev/null); do
    if [ "$(cat /proc/$p/comm 2>/dev/null)" = "vim_app" ]; then
        logger -t board "caller=$(cat /proc/$PPID/comm 2>/dev/null) ppid2=$(cut -d' ' -f4 /proc/$PPID/stat 2>/dev/null) ret=1 (Spoofed)"
        echo "$(date +%T) caller=$(cat /proc/$PPID/comm 2>/dev/null) ret=1 (Spoofed)" >> /tmp/wcp_board.log
        exit 1
    fi
done

logger -t board "caller=$(cat /proc/$PPID/comm 2>/dev/null) ret=2 (WCP Enabled)"
echo "$(date +%T) caller=$(cat /proc/$PPID/comm 2>/dev/null) ret=2 (WCP Enabled)" >> /tmp/wcp_board.log
exit 2
EOF
  if ! sh -n "${GBT}.new"; then
    fail "New get_board_type.sh has syntax errors"
  fi
  chmod 0755 "${GBT}.new"
  mv -f "${GBT}.new" "$GBT"
  echo "Updated get_board_type.sh (Process Spoofing)"
  rm -f /data_persist/wcp_force_off /data_persist/wcp_bootcnt /data_persist/ublox.txt 2>/dev/null
  echo "Cleaned up unnecessary files"

  sync
  echo "=== WCP Mod Installation Completed ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Installation successful!\nYou can now remove the USB.\nCMU will reboot in 5 seconds..." --no-cancel &

elif [ "$CHOICE" -eq 1 ]; then
  # ============================================================
  # UNINSTALL (reverse order: switch -> sm_WCP -> autostart)
  # ============================================================
  exec > "${MYDIR}/logs/uninstall_wcp.log" 2>&1
  echo "=== Starting WCP Mod Uninstallation ==="

  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Uninstalling WCP Mod...\nPlease DO NOT remove USB." --no-cancel &

  # --- 1. get_board_type.sh ---
  if [ -e "${GBT}${BAK}" ]; then
    cp -a "${GBT}${BAK}" "$GBT"
    rm -f "${GBT}${BAK}"
    echo "Restored get_board_type.sh from ${BAK}"
  else
    echo "Backup get_board_type.sh${BAK} not found, recreating stock script"
    cat << 'EOO' > "${GBT}.new"
#!/bin/sh

ret=1

DI_TP1056=/sys/class/gpio/DI_TP1056/value
DI_TP1029=/sys/class/gpio/DI_TP1029/value

if [ -e "$DI_TP1056" ] && [ -e "$DI_TP1029" ]; then
    for cnt in `seq 0 2`            # Retry 3 times
    do
        value1=$(cat $DI_TP1056)
        if [ $? = '0' ]; then
            if [ $value1 = '0' ] || [ $value1 = '1' ]; then
                value2=$(cat $DI_TP1029)
                if [ $? = '0' ]; then
                    if [ $value2 = '0' ] || [ $value2 = '1' ]; then
                        if [ $value1 = '1' ] || [ $value2 = '1' ]; then
                            ret=2                # For WCP, New Hardware.
                        fi
                        break
                    fi
                fi
            fi
        fi
        sleep 1                     # sleep before retry
    done
fi

exit $ret
EOO
    chmod 0755 "${GBT}.new"
    mv -f "${GBT}.new" "$GBT"
  fi

  # --- 2. sm_WCP.conf ---
  if [ -e "${SMW}${BAK}" ]; then
    cp -a "${SMW}${BAK}" "$SMW"
    rm -f "${SMW}${BAK}"
    echo "Restored sm_WCP.conf from ${BAK}"
  else
    echo "Backup sm_WCP.conf${BAK} not found, performing manual undo"
    sed -i '/name="jciLDS"/{/GPS=UBLOX/!s/\(args="[^"]*\)"/\1 GPS=UBLOX"/;s/reset_board="no"/reset_board="yes"/}' "$SMW"
    sed -i '/name="jcinavi"/{s/args=""/args="wcp"/;s/reset_board="no"/reset_board="yes"/}' "$SMW"
  fi

  # --- 3. autostart ---
  if [ -e "${AUTOSTART}${BAK}" ]; then
    cp -a "${AUTOSTART}${BAK}" "$AUTOSTART"
    rm -f "${AUTOSTART}${BAK}"
    echo "Restored autostart from ${BAK}"
  else
    echo "Backup autostart${BAK} not found, performing manual undo"
    sed -i '/WCP mod: do not create ublox.txt/s/.*/    test ! -e "$UBLOX_FILE" \&\& touch "$UBLOX_FILE"/' "$AUTOSTART"
  fi

  # --- 4. Cleanup ---
  rm -f /data_persist/wcp_force_off /tmp/wcp_board.log
  rm -f /data_persist/ublox.txt 2>/dev/null
  echo "Cleanup completed"

  sync
  echo "=== WCP Mod Uninstallation Completed ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Uninstallation completed!\nYou can now remove the USB.\nCMU will reboot in 5 seconds..." --no-cancel &

else
  # ============================================================
  # CANCEL
  # ============================================================
  sync
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Operation cancelled.\nSystem unchanged.\nYou can now remove the USB." \
    --ok-label="Close" --no-cancel
  exit 0
fi

sleep 5
killall -q jci-dialog
reboot
exit 0
