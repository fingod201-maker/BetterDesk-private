#!/bin/bash
set -euo pipefail
AUTO_REBOOT=no
REBOOT=no
ERROR=0
for FILE in "$@"; do
  if [ -r "$FILE" ]; then
    EXT="${FILE##*.}"
    if [ "$EXT" = "pkg" ] || [ "$EXT" = "mpkg" ]; then
      LOG="/tmp/zoom-vip-install-$(basename "$FILE").log"
      echo "Installing $FILE on /"
      installer -allowUntrusted -verboseR -pkg "$FILE" -target / -lang en 2>&1 | tee -a "$LOG"
      INSTALL_EXIT="${PIPESTATUS[0]}"
      if [ "$INSTALL_EXIT" = 0 ]; then
        echo "$FILE installed successfully."
        if grep -q 'installer: The install recommends restarting now.' "$LOG"; then REBOOT=should; fi
        if grep -q 'installer: The install requires restarting now.' "$LOG"; then REBOOT=must; fi
      else
        echo "failed ($INSTALL_EXIT). See $LOG for details"
        ERROR=1
      fi
    else
      ERROR=1
    fi
  else
    ERROR=1
  fi
done
if [ "$REBOOT" = no ]; then
  exit $ERROR
fi
exit $ERROR
