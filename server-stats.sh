#!/usr/bin/env bash
# server-stats.sh
# Print basic server performance stats: CPU, Memory, Disk, Top processes

set -u

# Ensure running on Linux
if [ ! -r /proc/stat ] || [ ! -r /proc/meminfo ]; then
  echo "This script must be run on a Linux system with /proc available." >&2
  exit 1
fi

# CPU: calculate total CPU usage over a short interval
get_cpu_usage() {
  # read first sample
  read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  prev_idle=$((idle + iowait))
  prev_non_idle=$((user + nice + system + irq + softirq + steal))
  prev_total=$((prev_idle + prev_non_idle))

  sleep 1

  read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle2=$((idle + iowait))
  non_idle2=$((user + nice + system + irq + softirq + steal))
  total2=$((idle2 + non_idle2))

  totald=$((total2 - prev_total))
  idled=$((idle2 - prev_idle))

  if [ "$totald" -eq 0 ]; then
    printf "0.0"
  else
    awk "BEGIN {printf \"%.1f\", (($totald - $idled)/$totald)*100}"
  fi
}

# Memory: calculate total, available, used and percent
get_memory() {
  total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  avail_kb=0
  # Prefer MemAvailable if present
  if awk '/MemAvailable:/ {exit 0} END {exit 1}' /proc/meminfo; then
    avail_kb=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  else
    # Fallback: estimate available as (MemFree + Buffers + Cached)
    memfree=$(awk '/MemFree:/ {print $2}' /proc/meminfo)
    buffers=$(awk '/Buffers:/ {print $2}' /proc/meminfo)
    cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
    avail_kb=$((memfree + buffers + cached))
  fi
  used_kb=$((total_kb - avail_kb))
  percent=$(awk "BEGIN {printf \"%.1f\", ($used_kb / $total_kb) * 100}")

  # human-readable helper (kB -> human)
  hr_kb() {
    awk -v k="$1" 'BEGIN{units="K M G T"; split(units,u," "); s=0; v=k; while(v>=1024 && s<3){v/=1024; s++} printf "%.1f %sB", v, u[s+1]}'
  }

  printf "%s used / %s total (%.1f%%)\n" "$(hr_kb $used_kb)" "$(hr_kb $total_kb)" "$percent"
}

# Disk: try to print a total across filesystems; fallback to root filesystem
get_disk() {
  if df --total -h >/dev/null 2>&1; then
    df --total -h | awk '/^total/ {printf "%s used / %s total (%s)\n", $3, $2, $5}'
  else
    # Fallback: report root filesystem only
    df -h / | awk 'NR==2{printf "%s used / %s total (%s)\n", $3, $2, $5}'
  fi
}

# Top processes by CPU and Memory
get_top_procs() {
  echo "Top 5 processes by CPU usage:" 
  # Use ps with no headers for portability
  ps -eo pid,user,comm,%cpu,%mem --no-headers --sort=-%cpu | head -n 5 | awk '{printf "PID:%s %-16s %6s%% CPU %5s%% MEM %s\n", $1, $2, $4, $5, $3}'

  echo
  echo "Top 5 processes by Memory usage:" 
  ps -eo pid,user,comm,%cpu,%mem --no-headers --sort=-%mem | head -n 5 | awk '{printf "PID:%s %-16s %6s%% CPU %5s%% MEM %s\n", $1, $2, $4, $5, $3}'
}

# Print report
echo "=== Server performance summary ($(date)) ==="

cpu=$(get_cpu_usage)
printf "Total CPU usage: %s%%\n" "$cpu"

printf "Total memory usage: "; get_memory

printf "Total disk usage: "; get_disk

echo
get_top_procs

exit 0
