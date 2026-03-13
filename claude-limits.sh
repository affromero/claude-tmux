#!/bin/bash
# tmux status bar: Claude Code usage limits
# Sends a minimal Haiku request to read rate-limit headers (the /api/oauth/usage endpoint is disabled).
# Costs essentially nothing (~1 input token + 1 output token of Haiku).
# Caches for 300s to stay well under any rate limits.

CACHE_FILE="/tmp/.tmux-claude-limits"
CACHE_TTL=300  # seconds (5 min — each call is a real API request)

# ── Check cache ────────────────────────────────────────────────
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# ── Colors ─────────────────────────────────────────────────────
L='#[fg=colour135]'   # purple label (Claude brand)
V='#[fg=colour255]'   # value white
G='#[fg=colour135]'   # purple (healthy — Claude brand)
Y='#[fg=colour214]'   # amber (caution)
R='#[fg=colour196]'   # red (low)
S='#[fg=colour238]'   # separator

color_for_pct() {
  local left=$1
  if [ "$left" -ge 50 ]; then echo "$G"
  elif [ "$left" -ge 20 ]; then echo "$Y"
  else echo "$R"
  fi
}

# ── Bar (8-char, shows consumed) ──────────────────────────────
make_bar() {
  local used="${1:-0}" width=8
  local filled=$(( used * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local left=$(( 100 - used ))
  local color
  color=$(color_for_pct "$left")
  local bar="${color}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+='#[fg=colour238]'
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

# ── Fetch token ────────────────────────────────────────────────
get_token() {
  if command -v security &>/dev/null; then
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
      python3 -c "import json,sys; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null
  elif [ -f "$HOME/.claude/.credentials.json" ]; then
    python3 -c "import json; print(json.load(open('$HOME/.claude/.credentials.json'))['claudeAiOauth']['accessToken'])" 2>/dev/null
  fi
}

get_sub_type() {
  if command -v security &>/dev/null; then
    security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | \
      python3 -c "import json,sys; print(json.load(sys.stdin)['claudeAiOauth'].get('subscriptionType',''))" 2>/dev/null
  fi
}

# ── Fetch usage via Messages API headers ──────────────────────
TOKEN=$(get_token)
if [ -z "$TOKEN" ]; then
  echo "${L}Claude ${S}│ ${R}no auth" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

# Send minimal Haiku request to get rate-limit headers
HEADER_FILE="/tmp/.tmux-claude-headers"
RESP_FILE="/tmp/.tmux-claude-resp"
HTTP_CODE=$(curl -s --max-time 10 \
  -w "%{http_code}" \
  -o "$RESP_FILE" \
  -D "$HEADER_FILE" \
  -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "User-Agent: claude-code/2.1.5" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
  "https://api.anthropic.com/v1/messages" 2>/dev/null)

if [ "$HTTP_CODE" != "200" ]; then
  SUB_TYPE=$(get_sub_type)
  SUB_LABEL=""
  if [ -n "$SUB_TYPE" ]; then
    SUB_LABEL="${L}$(echo "$SUB_TYPE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') "
  fi
  echo "${SUB_LABEL}${L}Claude ${S}│ ${Y}usage unavailable" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

# Parse rate-limit headers
eval "$(python3 -c "
import sys, datetime

headers = {}
with open('$HEADER_FILE') as f:
    for line in f:
        if ':' in line:
            k, v = line.split(':', 1)
            headers[k.strip().lower()] = v.strip()

# 5-hour window
fh_util = float(headers.get('anthropic-ratelimit-unified-5h-utilization', '0'))
fh_used = int(round(fh_util * 100))
fh_left = 100 - fh_used
fh_reset_ts = float(headers.get('anthropic-ratelimit-unified-5h-reset', '0'))
if fh_reset_ts > 0:
    now = datetime.datetime.now().timestamp()
    remaining = max(0, fh_reset_ts - now)
    h = int(remaining // 3600)
    m = int((remaining % 3600) // 60)
    fh_reset = f'{h}h{m:02d}m' if h > 0 else f'{m}m'
else:
    fh_reset = 'N/A'

# If 5h window already expired, usage is 0
import time
if fh_reset_ts > 0 and fh_reset_ts < time.time():
    fh_used = 0
    fh_left = 100

# 7-day window
sd_util = float(headers.get('anthropic-ratelimit-unified-7d-utilization', '0'))
sd_used = int(round(sd_util * 100))
sd_left = 100 - sd_used
sd_reset_ts = float(headers.get('anthropic-ratelimit-unified-7d-reset', '0'))
if sd_reset_ts > 0:
    dt = datetime.datetime.fromtimestamp(sd_reset_ts)
    remaining = max(0, sd_reset_ts - datetime.datetime.now().timestamp())
    days = int(remaining // 86400)
    hours = int((remaining % 86400) // 3600)
    sd_reset = f'{dt.strftime(\"%b %d\")} {days}d{hours:02d}h'
else:
    sd_reset = 'N/A'

print(f'FH_USED={fh_used}')
print(f'FH_LEFT={fh_left}')
print(f'FH_RESET=\"{fh_reset}\"')
print(f'SD_USED={sd_used}')
print(f'SD_LEFT={sd_left}')
print(f'SD_RESET=\"{sd_reset}\"')
" 2>/dev/null)"

fh_color=$(color_for_pct "$FH_LEFT")
sd_color=$(color_for_pct "$SD_LEFT")
fh_bar=$(make_bar "$FH_USED")
sd_bar=$(make_bar "$SD_USED")

# Subscription type label
SUB_TYPE=$(get_sub_type)
SUB_LABEL=""
if [ -n "$SUB_TYPE" ]; then
  SUB_LABEL="${L}$(echo "$SUB_TYPE" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') "
fi

out="${SUB_LABEL}${L}Claude ${S}│ ${L}5h ${fh_color}${FH_USED}% ${fh_bar} ${S}(${FH_RESET}) ${S}│ ${L}Wk ${sd_color}${SD_USED}% ${sd_bar} ${S}(${SD_RESET})"

echo "$out" > "$CACHE_FILE"
cat "$CACHE_FILE"
