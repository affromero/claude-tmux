#!/bin/bash
# tmux status bar: Codex usage limits
# Reads OAuth token from ~/.codex/auth.json, queries chatgpt.com/backend-api/wham/usage
# Caches for 60s to avoid hammering the API

CACHE_FILE="/tmp/.tmux-codex-limits"
CACHE_TTL=60  # seconds

# ── Check cache ────────────────────────────────────────────────
if [ -f "$CACHE_FILE" ]; then
  cache_age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# ── Colors ─────────────────────────────────────────────────────
L='#[fg=colour83]'    # green label (Codex/OpenAI brand)
V='#[fg=colour255]'   # value white
G='#[fg=colour76]'    # green (healthy)
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
# pct = used percent. Bar fills from left as usage grows.
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
AUTH_FILE="$HOME/.codex/auth.json"
if [ ! -f "$AUTH_FILE" ]; then
  echo "${L}Codex ${S}│ ${R}no auth" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

TOKEN=$(python3 -c "import json; print(json.load(open('$AUTH_FILE'))['tokens']['access_token'])" 2>/dev/null)
if [ -z "$TOKEN" ]; then
  echo "${L}Codex ${S}│ ${R}bad token" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

# ── Fetch usage ────────────────────────────────────────────────
USAGE=$(curl -s --max-time 5 -H "Authorization: Bearer $TOKEN" "https://chatgpt.com/backend-api/wham/usage" 2>/dev/null)

if [ -z "$USAGE" ]; then
  echo "${L}Codex ${S}│ ${Y}unreachable" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

# Parse usage
eval "$(echo "$USAGE" | python3 -c "
import json, sys, datetime

d = json.load(sys.stdin)

if 'error' in d or 'detail' in d:
    print('API_ERROR=1')
    sys.exit(0)

print('API_ERROR=0')

rl = d.get('rate_limit', {})
pw = rl.get('primary_window', {})
sw = rl.get('secondary_window', {})
cr = d.get('credits', {})

# Primary (5h) window
p_used = pw.get('used_percent', 0)
p_left = 100 - p_used
p_reset_sec = pw.get('reset_after_seconds', 0)
p_reset_h = p_reset_sec // 3600
p_reset_m = (p_reset_sec % 3600) // 60
p_reset = f'{p_reset_h}h{p_reset_m:02d}m' if p_reset_h > 0 else f'{p_reset_m}m'

# Secondary (weekly) window
s_used = sw.get('used_percent', 0) if sw else 0
s_left = 100 - s_used
s_reset_ts = sw.get('reset_at', 0) if sw else 0
if s_reset_ts:
    dt = datetime.datetime.fromtimestamp(s_reset_ts)
    remaining = max(0, s_reset_ts - datetime.datetime.now().timestamp())
    days = int(remaining // 86400)
    hours = int((remaining % 86400) // 3600)
    s_reset = f'{dt.strftime(\"%b %d\")} {days}d{hours:02d}h'
else:
    s_reset = 'N/A'

# Credits
balance = cr.get('balance', '0')
unlimited = cr.get('unlimited', False)

# Plan
plan = d.get('plan_type', 'unknown')
limited = rl.get('limit_reached', False)

print(f'P_USED={p_used}')
print(f'P_LEFT={p_left}')
print(f'P_RESET=\"{p_reset}\"')
print(f'S_USED={s_used}')
print(f'S_LEFT={s_left}')
print(f'S_RESET=\"{s_reset}\"')
print(f'BALANCE=\"{balance}\"')
print(f'UNLIMITED={1 if unlimited else 0}')
print(f'PLAN=\"{plan}\"')
print(f'LIMITED={1 if limited else 0}')
" 2>/dev/null)"

if [ "${API_ERROR:-1}" = "1" ]; then
  echo "${L}Codex ${S}│ ${Y}token expired — run codex to refresh" > "$CACHE_FILE"
  cat "$CACHE_FILE"
  exit 0
fi

p_color=$(color_for_pct "$P_LEFT")
s_color=$(color_for_pct "$S_LEFT")
p_bar=$(make_bar "$P_USED")
s_bar=$(make_bar "$S_USED")

# Plan type + Codex label
if [ -n "$PLAN" ] && [ "$PLAN" != "unknown" ]; then
  out="${L}$(echo "$PLAN" | awk '{print toupper(substr($0,1,1)) substr($0,2)}') Codex"
else
  out="${L}Codex"
fi

out="${out} ${S}│ ${L}5h ${p_color}${P_USED}% ${p_bar} ${S}(${P_RESET}) ${S}│ ${L}Wk ${s_color}${S_USED}% ${s_bar} ${S}(${S_RESET})"

# Credits
if [ "$UNLIMITED" = "1" ]; then
  out="${out} ${S}│ ${L}Credits ${G}∞"
elif [ -n "$BALANCE" ] && [ "$BALANCE" != "0" ]; then
  out="${out} ${S}│ ${L}Credits ${V}\$${BALANCE}"
fi

# Rate limited warning
if [ "$LIMITED" = "1" ]; then
  out="${R}⚠ RATE LIMITED ${out}"
fi

echo "$out" > "$CACHE_FILE"
cat "$CACHE_FILE"
