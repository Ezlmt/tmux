#!/usr/bin/env bash
# tmux status capsule: remaining gcert (LOAS2 / corp cert) lifetime, color-coded.
#   > 8h  green | 4-8h yellow | 1-4h peach | < 1h red | expired: red "gcert!"
# Cached for 60s so the 15s status refresh doesn't hammer gcertstatus.
CACHE="/tmp/tmux-gcert-${USER}.cache"
TTL=60

now=$(date +%s)
# Invalidate on reconnect: the agent symlink points at a new sshd socket.
key=$(readlink -f "${SSH_AUTH_SOCK:-none}" 2>/dev/null)
if [ -f "$CACHE" ] && [ "$(cat "$CACHE.key" 2>/dev/null)" = "$key" ] \
   && [ $(( now - $(stat -c %Y "$CACHE") )) -lt "$TTL" ]; then
  cat "$CACHE"
  exit 0
fi

# simple format prints one "<cert>:<seconds>" line per *valid* cert. An expired
# cert is simply omitted (rc=90). Since the Mac-forwarded ssh-agent cert
# (corp/normal) is usually fresh, the absence of the LOAS2 line is exactly the
# "need to run gcert on this machine" case - judge each cert separately.
raw=$(timeout 5 gcertstatus --format=simple 2>/dev/null)
loas2=$(awk -F: '$1 == "LOAS2" && $2 ~ /^-?[0-9]+$/ { print $2 }' <<<"$raw")
agent=$(awk -F: '$1 == "corp/normal" && $2 ~ /^-?[0-9]+$/ { print $2 }' <<<"$raw")

# Catppuccin Mocha palette
crust="#11111b"; surface0="#313244"; text="#cdd6f4"
green="#a6e3a1"; yellow="#f9e2af"; peach="#fab387"; red="#f38ba8"

if [ -z "$loas2" ] || [ "$loas2" -le 0 ]; then
  color=$red; label="gcert!"           # local LOAS2 expired/missing -> run gcert
elif [ -z "$agent" ] || [ "$agent" -le 0 ]; then
  color=$red; label="agent✗"           # ssh-agent cert gone (dead forwarding)
else
  secs=$(( loas2 < agent ? loas2 : agent ))
  h=$(( secs / 3600 )); m=$(( secs % 3600 / 60 ))
  if   [ "$h" -ge 8 ]; then color=$green
  elif [ "$h" -ge 4 ]; then color=$yellow
  elif [ "$h" -ge 1 ]; then color=$peach
  else                      color=$red
  fi
  if [ "$h" -gt 0 ]; then label="${h}h$(printf '%02d' "$m")m"; else label="${m}m"; fi
fi

L=$'\ue0b6'; R=$'\ue0b4'; ICON=$'\U000f033e'   # rounded caps + nf-md-lock
out="#[fg=${color},bg=default]${L}#[fg=${crust},bg=${color}]${ICON} #[fg=${text},bg=${surface0}] ${label}#[fg=${surface0},bg=default]${R} "
printf "%s" "$out" > "$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE" && printf "%s" "$key" > "$CACHE.key"
printf '%s' "$out"
