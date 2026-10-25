#!/bin/sh
# ==============================================================================
# Native Wireless CarPlay (WCP) Mod Installer / Uninstaller for Mazda CMU150
# Target Firmware: V74.00.324
# Cai dat: sao luu -> autostart (khong tao ublox.txt) -> sm_WCP.conf -> get_board_type.sh
# Go cai dat: khoi phuc tu .bak, neu khong co thi hoan tac thu cong
# Backup extension: .bak
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

# Hien thong bao, doi 5 giay roi thoat (khong reboot)
abort_msg()
{
  /jci/tools/jci-dialog --info --title="WCP Mod" --text="$1" --no-cancel &
  sleep 5
  killall -q jci-dialog
  exit "$2"
}

# --- 1. Kiem tra phien ban Firmware V74.00.324 ---
CMU_VER=$(grep '^JCI_SW_VER=' /jci/version.ini 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
if [ "${CMU_VER}" != "74.00.324" ]; then
  abort_msg "Chi ho tro CMU firmware V74.00.324.\nPhien ban hien tai: V${CMU_VER}\nDa huy thao tac.\nVui long rut USB." 1
fi

# --- 2. Kiem tra phan cung qua GPIO: chi cai tren CMU doi cu (0/0) ---
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
    abort_msg "Phat hien CMU doi moi ho tro san WCP (GPIO=${v1}/${v2}).\nKhong can cai dat ban mod nay.\nVui long rut USB." 0
  fi

  if [ "$v1" != "0" ] || [ "$v2" != "0" ]; then
    abort_msg "Khong xac dinh duoc phan cung (GPIO=${v1}/${v2}).\nDa huy thao tac de an toan.\nVui long rut USB." 1
  fi
fi

mkdir -p "${MYDIR}/logs" 2>/dev/null

# --- 3. Trang thai hien tai ---
if grep -q "vim_app" "$GBT" 2>/dev/null; then
  MOD_STATUS="DA CAI DAT"
else
  MOD_STATUS="CHUA CAI DAT"
fi

# --- 4. Menu ---
/jci/tools/jci-dialog --3-button-dialog \
  --title="Wireless CarPlay Mod (V${CMU_VER})" \
  --text="Trang thai hien tai: ${MOD_STATUS}\nBan muon thuc hien thao tac nao?" \
  --ok-label="Install" \
  --cancel-label="Uninstall" \
  --button3-label="Cancel"
CHOICE=$?

# Cai dat loi: khoi phuc cac tep tu .bak roi thoat (khong reboot)
fail()
{
  echo "LOI: $1"
  for f in "$GBT" "$SMW" "$AUTOSTART"; do
    if [ -e "${f}${BAK}" ]; then
      cp -a "${f}${BAK}" "$f"
      echo "Da khoi phuc $f tu ${BAK}"
    fi
  done
  rm -f "${GBT}.new" "${AUTOSTART}.new"
  sync
  killall -q jci-dialog
  abort_msg "Cai dat that bai: $1\nDa khoi phuc cac tep goc.\nXem logs tren USB.\nVui long rut USB." 1
}

if [ "$CHOICE" -eq 0 ]; then
  # ============================================================
  # INSTALL
  # ============================================================
  exec > "${MYDIR}/logs/install_wcp.log" 2>&1
  echo "=== Bat dau cai dat WCP Mod (FW: ${CMU_VER}, GPIO=${v1}/${v2}) ==="

  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Dang cai dat WCP Mod...\nVui long KHONG rut USB." --no-cancel &

  # --- 1. Sao luu (chi lan dau) ---
  for f in "$GBT" "$SMW" "$AUTOSTART"; do
    if [ ! -e "${f}${BAK}" ]; then
      cp -a "$f" "${f}${BAK}"
      echo "Da sao luu ${f}${BAK}"
    else
      echo "Ban sao luu ${f}${BAK} da ton tai"
    fi
  done

  # --- 2. autostart: thay dong tao ublox.txt bang lenh xoa ublox.txt ---
  if grep -qF 'WCP mod: khong tao ublox.txt' "$AUTOSTART"; then
    echo "autostart da duoc sua, bo qua"
  else
    if [ "$(grep -cF 'touch "$UBLOX_FILE"' "$AUTOSTART")" != "1" ]; then
      fail "khong tim thay dung 1 dong touch ublox.txt trong autostart"
    fi
    cp -a "$AUTOSTART" "${AUTOSTART}.new"
    sed '/touch "\$UBLOX_FILE"/s/.*/    test -e "$UBLOX_FILE" \&\& rm -f "$UBLOX_FILE" # WCP mod: khong tao ublox.txt/' "$AUTOSTART" > "${AUTOSTART}.new"
    if grep -qF 'touch "$UBLOX_FILE"' "${AUTOSTART}.new" \
       || [ "$(wc -l < "${AUTOSTART}.new")" != "$(wc -l < "$AUTOSTART")" ] \
       || ! sh -n "${AUTOSTART}.new"; then
      fail "autostart moi khong hop le"
    fi
    mv -f "${AUTOSTART}.new" "$AUTOSTART"
    echo "Da cap nhat autostart"
  fi

  # --- 3. sm_WCP.conf: bo GPS=UBLOX, reset_board=no, jcinavi args rong ---
  sed -i '/name="jciLDS"/{s/ GPS=UBLOX//;s/reset_board="yes"/reset_board="no"/}' "$SMW"
  sed -i '/name="jcinavi"/{s/args="wcp"/args=""/;s/reset_board="yes"/reset_board="no"/}' "$SMW"
  if grep 'name="jciLDS"' "$SMW" | grep -q 'GPS=UBLOX' \
     || ! grep 'name="jciLDS"' "$SMW" | grep -q 'reset_board="no"' \
     || ! grep 'name="jcinavi"' "$SMW" | grep -q 'args=""'; then
    fail "sm_WCP.conf sau khi sua khong dung nhu mong doi"
  fi
  echo "Da cap nhat sm_WCP.conf"

  # --- 4. get_board_type.sh (cong tac kich hoat, ghi cuoi cung) ---
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
    fail "get_board_type.sh moi co loi cu phap"
  fi
  chmod 0755 "${GBT}.new"
  mv -f "${GBT}.new" "$GBT"
  echo "Da cap nhat get_board_type.sh (Process Spoofing)"
  rm -f /data_persist/wcp_force_off /data_persist/wcp_bootcnt /data_persist/ublox.txt 2>/dev/null
  echo "Da xoa cac tep khong can thiet"

  sync
  echo "=== Cai dat WCP Mod hoan tat ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Cai dat thanh cong!\nBan co the rut USB ra.\nCMU se khoi dong lai sau 5 giay..." --no-cancel &

elif [ "$CHOICE" -eq 1 ]; then
  # ============================================================
  # UNINSTALL (theo thu tu nguoc: cong tac -> sm_WCP -> autostart)
  # ============================================================
  exec > "${MYDIR}/logs/uninstall_wcp.log" 2>&1
  echo "=== Bat dau go cai dat WCP Mod ==="

  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Dang go cai dat WCP Mod...\nVui long KHONG rut USB." --no-cancel &

  # --- 1. get_board_type.sh ---
  if [ -e "${GBT}${BAK}" ]; then
    cp -a "${GBT}${BAK}" "$GBT"
    rm -f "${GBT}${BAK}"
    echo "Da khoi phuc get_board_type.sh tu ${BAK}"
  else
    echo "Khong tim thay get_board_type.sh${BAK}, tao lai tap lenh goc"
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
                            ret=2                # For WCP, New Hadware.
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
    echo "Da khoi phuc sm_WCP.conf tu ${BAK}"
  else
    echo "Khong tim thay sm_WCP.conf${BAK}, hoan tac thu cong"
    sed -i '/name="jciLDS"/{/GPS=UBLOX/!s/\(args="[^"]*\)"/\1 GPS=UBLOX"/;s/reset_board="no"/reset_board="yes"/}' "$SMW"
    sed -i '/name="jcinavi"/{s/args=""/args="wcp"/;s/reset_board="no"/reset_board="yes"/}' "$SMW"
  fi

  # --- 3. autostart ---
  if [ -e "${AUTOSTART}${BAK}" ]; then
    cp -a "${AUTOSTART}${BAK}" "$AUTOSTART"
    rm -f "${AUTOSTART}${BAK}"
    echo "Da khoi phuc autostart tu ${BAK}"
  else
    echo "Khong tim thay autostart${BAK}, hoan tac thu cong"
    sed -i '/WCP mod: khong tao ublox.txt/s/.*/    test ! -e "$UBLOX_FILE" \&\& touch "$UBLOX_FILE"/' "$AUTOSTART"
  fi

  # --- 4. Don dep ---
  rm -f /data_persist/wcp_force_off /tmp/wcp_board.log
  rm -f /data_persist/ublox.txt 2>/dev/null
  echo "Da don dep"

  sync
  echo "=== Go cai dat WCP Mod hoan tat ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Go cai dat hoan tat!\nBan co the rut USB ra.\nCMU se khoi dong lai sau 5 giay..." --no-cancel &

else
  # ============================================================
  # CANCEL
  # ============================================================
  sync
  /jci/tools/jci-dialog --info --title="WCP Mod" \
    --text="Da huy thao tac.\nHe thong khong thay doi.\nBan co the rut USB ra." \
    --ok-label="Dong" --no-cancel
  exit 0
fi

sleep 5
killall -q jci-dialog
reboot
exit 0
