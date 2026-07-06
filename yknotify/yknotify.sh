#!/bin/bash

YKNTFY_BIN="$HOME/go/bin/yknotify"
TERM_NTFY_BIN="/opt/homebrew/bin/terminal-notifier"

LAST_NTFY=0
while IFS= read -r line; do

    # Skip FIDO2 touch events (browser/webauthn) — only notify for OpenPGP (GPG/SSH/sudo)
    if [[ "$(echo "$line" | jq -r '.type')" == 'FIDO2' ]]; then
        continue
    fi

    # 10-second cooldown between notifications
    NOW="$(date +%s)"
    if [[ "$NOW" -le "$((LAST_NTFY + 10))" ]]; then
        continue
    fi
    LAST_NTFY="$NOW"

    message="$(echo "$line" | jq -r '.type')"
    "$TERM_NTFY_BIN" -title "YubiKey" -message "Touch required ($message)" -sound Morse -ignoreDnD

done < <("$YKNTFY_BIN")
