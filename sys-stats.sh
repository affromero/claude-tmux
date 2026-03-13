#!/bin/bash
# tmux status bar: hostname, OS, CPU, RAM, disk, GPU — cross-platform
# Refreshed every tmux status-interval (default 5s)
# Disk uses df (kernel VFS call — sub-millisecond, safe at 5s intervals)

OS="$(uname -s)"

# ── Hostname ────────────────────────────────────────────────────
get_host() {
  case "$OS" in
    Darwin) scutil --get ComputerName 2>/dev/null || hostname -s ;;
    *)      hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "unknown" ;;
  esac
}

# ── OS version ──────────────────────────────────────────────────
get_os() {
  case "$OS" in
    Darwin)
      echo "macOS $(sw_vers -productVersion 2>/dev/null)"
      ;;
    Linux)
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${PRETTY_NAME:-Linux}"
      else
        echo "Linux $(uname -r | cut -d- -f1)"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Windows"
      ;;
    *)
      echo "$OS"
      ;;
  esac
}

# ── CPU usage ───────────────────────────────────────────────────
get_cpu() {
  case "$OS" in
    Darwin)
      # Second sample is accurate (first is since-boot average)
      top -l 2 -n 0 -s 0 2>/dev/null | grep "CPU usage" | tail -1 | awk '{printf "%2d", 100-$7}'
      ;;
    Linux)
      # Two 1-second samples from /proc/stat
      read -r _ u1 n1 s1 i1 _ < /proc/stat
      sleep 1
      read -r _ u2 n2 s2 i2 _ < /proc/stat
      total=$(( (u2+n2+s2+i2) - (u1+n1+s1+i1) ))
      idle=$(( i2 - i1 ))
      if [ "$total" -gt 0 ]; then
        printf "%2d" $(( 100 * (total - idle) / total ))
      else
        echo "0"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      wmic cpu get loadpercentage 2>/dev/null | awk 'NR==2{printf "%d", $1}'
      ;;
  esac
}

# ── RAM usage ───────────────────────────────────────────────────
get_ram() {
  case "$OS" in
    Darwin)
      total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
      total_gb=$((total_bytes / 1073741824))
      used_gb=$(vm_stat 2>/dev/null | awk '
        /page size of/                 {psize=$8}
        /Pages active/                 {a=int($3)}
        /Pages wired down/             {w=int($4)}
        /Pages occupied by compressor/ {c=int($5)}
        END {printf "%.1f", (a+w+c)*psize/1073741824}
      ')
      printf "%.1f/%.1fG" "$used_gb" "$total_gb"
      ;;
    Linux)
      awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f/%.1fG", (t-a)/1048576, t/1048576}' /proc/meminfo
      ;;
    MINGW*|MSYS*|CYGWIN*)
      # PowerShell fallback
      powershell.exe -NoProfile -Command '
        $os = Get-CimInstance Win32_OperatingSystem
        $used = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB, 1)
        $total = [math]::Round($os.TotalVisibleMemorySize/1MB)
        Write-Output "${used}/${total}G"
      ' 2>/dev/null
      ;;
  esac
}

# ── Disk usage (root filesystem) ────────────────────────────────
# df reads the kernel VFS table — no disk I/O, runs in <1ms
# Output: "1.2/4.0T" or "234.5/931.5G"
get_disk() {
  case "$OS" in
    Darwin)
      # APFS: all volumes share one container — used = total - available
      # df / shows only the small system volume; total-avail is container-wide truth
      df -k / 2>/dev/null | awk 'NR==2{
        total=$2; avail=$4; used=total-avail
        if (total >= 1073741824)
          printf "%.1f/%.1fT", used/1073741824, total/1073741824
        else
          printf "%.1f/%.1fG", used/1048576, total/1048576
      }'
      ;;
    Linux)
      df -k / 2>/dev/null | awk 'NR==2{
        total=$2; used=$3
        if (total >= 1073741824)
          printf "%.1f/%.1fT", used/1073741824, total/1073741824
        else
          printf "%.1f/%.1fG", used/1048576, total/1048576
      }'
      ;;
    MINGW*|MSYS*|CYGWIN*)
      powershell.exe -NoProfile -Command '
        $d = Get-PSDrive C
        $used = [math]::Round($d.Used/1GB, 1)
        $total = [math]::Round(($d.Used + $d.Free)/1GB, 1)
        Write-Output "${used}/${total}G"
      ' 2>/dev/null
      ;;
  esac
}

# ── GPU name ────────────────────────────────────────────────────
get_gpu_name() {
  case "$OS" in
    Darwin)
      # Apple Silicon: chip name is the GPU name
      sysctl -n machdep.cpu.brand_string 2>/dev/null | awk '{print $1, $2, $3}'
      ;;
    Linux)
      if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
      elif [ -f /sys/class/drm/card0/device/product_name ]; then
        cat /sys/class/drm/card0/device/product_name 2>/dev/null
      else
        lspci 2>/dev/null | awk -F': ' '/VGA|3D/{print $2; exit}' | sed 's/\[//;s/\]//'
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v nvidia-smi.exe &>/dev/null; then
        nvidia-smi.exe --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
      fi
      ;;
  esac
}

# ── GPU memory cur/max (mirrors RAM's used/total format) ─────────
# Sets GPU_BAR_PCT as side effect for the visual bar
GPU_BAR_PCT=""
get_gpu_stats() {
  GPU_BAR_PCT=""
  case "$OS" in
    Darwin)
      # Apple Silicon: unified memory — GPU allocation from IOKit
      local gpu_mem_bytes total_bytes
      gpu_mem_bytes=$(ioreg -r -c AGXAccelerator -l 2>/dev/null | grep -o '"In use system memory"=[0-9]*' | awk -F= '{print $2}')
      total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
      if [ -n "$gpu_mem_bytes" ] && [ -n "$total_bytes" ]; then
        local used_gb total_gb
        used_gb=$(awk "BEGIN{printf \"%.1f\", ${gpu_mem_bytes}/1073741824}")
        total_gb=$(awk "BEGIN{printf \"%.1f\", ${total_bytes}/1073741824}")
        printf "%s/%sG" "$used_gb" "$total_gb"
        GPU_BAR_PCT=$(awk "BEGIN{printf \"%d\", (${gpu_mem_bytes}/${total_bytes})*100}")
      fi
      ;;
    Linux)
      if command -v nvidia-smi &>/dev/null; then
        local data mem_used mem_total
        data=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        mem_used=$(echo "$data" | awk -F', ' '{printf "%.1f", $1/1024}')
        mem_total=$(echo "$data" | awk -F', ' '{printf "%.1f", $2/1024}')
        if [ -n "$mem_used" ] && [ -n "$mem_total" ]; then
          printf "%s/%sG" "$mem_used" "$mem_total"
          GPU_BAR_PCT=$(echo "$data" | awk -F', ' '{printf "%d", ($1/$2)*100}')
        fi
      elif [ -f /sys/class/drm/card0/device/mem_info_vram_used ]; then
        local vram_used vram_total
        vram_used=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null)
        vram_total=$(cat /sys/class/drm/card0/device/mem_info_vram_total 2>/dev/null)
        if [ -n "$vram_used" ] && [ -n "$vram_total" ]; then
          printf "%.1f/%.1fG" "$(awk "BEGIN{print ${vram_used}/1073741824}")" "$(awk "BEGIN{print ${vram_total}/1073741824}")"
          GPU_BAR_PCT=$(awk "BEGIN{printf \"%d\", (${vram_used}/${vram_total})*100}")
        fi
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if command -v nvidia-smi.exe &>/dev/null; then
        local data mem_used mem_total
        data=$(nvidia-smi.exe --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
        mem_used=$(echo "$data" | awk -F', ' '{printf "%.1f", $1/1024}')
        mem_total=$(echo "$data" | awk -F', ' '{printf "%.1f", $2/1024}')
        if [ -n "$mem_used" ] && [ -n "$mem_total" ]; then
          printf "%s/%sG" "$mem_used" "$mem_total"
          GPU_BAR_PCT=$(echo "$data" | awk -F', ' '{printf "%d", ($1/$2)*100}')
        fi
      fi
      ;;
  esac
}

# ── Top process by resource ────────────────────────────────────
# Returns "name(PID)" of the top consumer
get_top_cpu_proc() {
  case "$OS" in
    Darwin) ps -Arco pid,comm,%cpu 2>/dev/null | awk 'NR==2{printf "%s(%s)", $2, $1}' ;;
    Linux)  ps -eo pid,comm --sort=-%cpu 2>/dev/null | awk 'NR==2{printf "%s(%s)", $2, $1}' ;;
  esac
}

get_top_ram_proc() {
  case "$OS" in
    Darwin) ps -Amco pid,comm,rss 2>/dev/null | awk 'NR==2{printf "%s(%s)", $2, $1}' ;;
    Linux)  ps -eo pid,comm --sort=-rss 2>/dev/null | awk 'NR==2{printf "%s(%s)", $2, $1}' ;;
  esac
}

# ── Visual bar ─────────────────────────────────────────────────
# 8-char bar using █ (filled) and ░ (empty), colored by threshold
make_bar() {
  local pct="${1:-0}" width=8
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  local empty=$(( width - filled ))
  local color
  if [ "$pct" -ge 80 ]; then
    color='#[fg=colour196]'   # red
  elif [ "$pct" -ge 60 ]; then
    color='#[fg=colour214]'   # amber
  else
    color='#[fg=colour76]'    # green
  fi
  local bar="${color}"
  local i
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+='#[fg=colour238]'
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo "$bar"
}

# ── Assemble output (with tmux color codes) ───────────────────
# Labels: colour214 (gold/amber)  Values: colour255 (white)
# Critical: colour196 (red)       Separators: colour238 (dim grey)
L='#[fg=colour214]'   # label
V='#[fg=colour255]'   # value
C='#[fg=colour196]'   # critical (red)
S='#[fg=colour245]'   # separator

# Thresholds
CPU_CRIT=80   # percent
RAM_CRIT=85   # percent used
DISK_CRIT=85  # percent used

host=$(get_host)
os_ver=$(get_os)
cpu=$(get_cpu)
ram=$(get_ram)
disk=$(get_disk)

# Parse RAM used/total for threshold check
ram_used=$(echo "$ram" | sed 's|/.*||')
ram_total=$(echo "$ram" | sed 's|.*/||; s|[GT]||')
ram_pct=$(awk "BEGIN{printf \"%d\", ($ram_used/$ram_total)*100}" 2>/dev/null)

# Parse disk used/total for threshold check
disk_used=$(echo "$disk" | sed 's|/.*||')
disk_total=$(echo "$disk" | sed 's|.*/||; s|[GT]||')
disk_pct=$(awk "BEGIN{printf \"%d\", ($disk_used/$disk_total)*100}" 2>/dev/null)

# CPU: check critical
cpu_val=${cpu// /}  # strip padding
if [ "${cpu_val:-0}" -ge "$CPU_CRIT" ] 2>/dev/null; then
  cpu_color="$C"
  cpu_extra=" $(get_top_cpu_proc)"
else
  cpu_color="$V"
  cpu_extra=""
fi

# RAM: check critical
if [ "${ram_pct:-0}" -ge "$RAM_CRIT" ] 2>/dev/null; then
  ram_color="$C"
  ram_extra=" $(get_top_ram_proc)"
else
  ram_color="$V"
  ram_extra=""
fi

# Disk: check critical
if [ "${disk_pct:-0}" -ge "$DISK_CRIT" ] 2>/dev/null; then
  disk_color="$C"
else
  disk_color="$V"
fi

ram_bar=$(make_bar "${ram_pct:-0}")
disk_bar=$(make_bar "${disk_pct:-0}")

out="${V}${host} ${S}│ ${V}${os_ver} ${S}│ ${L}CPU ${cpu_color}${cpu}%${cpu_extra} ${S}│ ${L}RAM ${ram_color}${ram}${ram_extra} ${ram_bar} ${S}│ ${L}Disk ${disk_color}${disk} ${disk_bar}"

gpu_name=$(get_gpu_name)
gpu_stats=$(get_gpu_stats)
if [ -n "$gpu_name" ] || [ -n "$gpu_stats" ]; then
  gpu_bar=$(make_bar "${GPU_BAR_PCT:-0}")
  out="${out} ${S}│ ${L}GPU ${V}"
  [ -n "$gpu_name" ] && out="${out}${gpu_name}"
  [ -n "$gpu_name" ] && [ -n "$gpu_stats" ] && out="${out} "
  [ -n "$gpu_stats" ] && out="${out}${gpu_stats}"
  out="${out} ${gpu_bar}"
fi

echo "$out"
