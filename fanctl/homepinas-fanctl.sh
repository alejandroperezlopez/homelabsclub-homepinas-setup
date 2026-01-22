#!/usr/bin/env bash
set -euo pipefail

# =========================
# Default configuration
# (used if no user config)
# =========================

# PWM1 (HDD / SSD)
PWM1_T30=65
PWM1_T35=90
PWM1_T40=130
PWM1_T45=180
PWM1_TMAX=230

# PWM2 (NVMe + CPU)
PWM2_T40=80
PWM2_T50=120
PWM2_T60=170
PWM2_TMAX=255

# Safety limits
MIN_PWM1=65
MIN_PWM2=80
MAX_PWM=255

CPU_FAILSAFE_C=80
FAST_FAILSAFE_C=70

HYST_PWM=10

# =========================
# Optional user config
# =========================

CONFIG_FILE="/usr/local/bin/homepinas-fanctl.conf"

log() { echo "[$(date '+%F %T')] $*" >&2; }

if [[ -r "$CONFIG_FILE" ]]; then
  log "Cargando configuración de usuario: $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  log "No hay configuración de usuario, usando valores por defecto"
fi

# =========================
# Runtime config
# =========================

STATE_FILE="/run/homepinas-fanctl.state"
DRYRUN="${DRYRUN:-0}"

# =========================
# Helpers
# =========================

need_root() {
  if (( EUID != 0 )); then
    echo "ERROR: Ejecuta como root (sudo)." >&2
    exit 1
  fi
}

find_emc_hwmon() {
  local hw
  hw="$(grep -l '^emc2305$' /sys/class/hwmon/hwmon*/name 2>/dev/null | head -n1 || true)"
  [[ -n "$hw" ]] && echo "${hw%/name}"
}

read_cpu_temp_c() {
  local f="/sys/class/thermal/thermal_zone0/temp"
  [[ -r "$f" ]] && echo $(( $(cat "$f") / 1000 )) || echo 0
}

read_sata_temp_c() {
  local dev="$1" t=""
  t="$(smartctl -A "$dev" 2>/dev/null | awk '$1==194 {print $10; exit}')"
  [[ -z "$t" ]] && t="$(smartctl -A "$dev" 2>/dev/null | awk '$1==190 {print $10; exit}')"
  t="$(echo "$t" | sed 's/[^0-9].*$//')"
  [[ "$t" =~ ^[0-9]+$ ]] && echo "$t"
}

read_nvme_usb_temp_c() {
  local dev="$1" t=""
  t="$(smartctl -a -d sntasmedia "$dev" 2>/dev/null | awk '/^Temperature:/ {print $2; exit}')"
  [[ "$t" =~ ^[0-9]+$ ]] && echo "$t"
}

# =========================
# PWM curves
# =========================

pwm_hdd_from_temp() {
  local t="$1"
  if   (( t <= 30 )); then echo "$PWM1_T30"
  elif (( t <= 35 )); then echo "$PWM1_T35"
  elif (( t <= 40 )); then echo "$PWM1_T40"
  elif (( t <= 45 )); then echo "$PWM1_T45"
  else                    echo "$PWM1_TMAX"
  fi
}

pwm_fast_from_temp() {
  local t="$1"
  if   (( t <= 40 )); then echo "$PWM2_T40"
  elif (( t <= 50 )); then echo "$PWM2_T50"
  elif (( t <= 60 )); then echo "$PWM2_T60"
  else                    echo "$PWM2_TMAX"
  fi
}

# =========================
# PWM apply with hysteresis
# =========================

apply_pwm() {
  local path="$1" new="$2" last="$3" label="$4"

  (( new < 0 )) && new=0
  (( new > MAX_PWM )) && new=$MAX_PWM

  if [[ "$last" =~ ^[0-9]+$ ]]; then
    local diff=$(( new > last ? new-last : last-new ))
    if (( diff < HYST_PWM )); then
      log "$label: mantiene PWM=$last (nuevo $new, diff $diff < $HYST_PWM)"
      echo "$last"
      return
    fi
  fi

  if (( DRYRUN == 1 )); then
    log "$label: (DRYRUN) pondría PWM=$new"
  else
    echo "$new" > "$path"
    log "$label: PWM aplicado $new → $path"
  fi

  echo "$new"
}

load_last_state() {
  [[ -r "$STATE_FILE" ]] && source "$STATE_FILE" || true
  PWM1_LAST="${PWM1_LAST:-}"
  PWM2_LAST="${PWM2_LAST:-}"
}

save_state() {
  umask 077
  cat > "$STATE_FILE" <<EOF
PWM1_LAST=$1
PWM2_LAST=$2
EOF
}

# =========================
# Main
# =========================

need_root

command -v smartctl >/dev/null || {
  echo "ERROR: smartctl no encontrado (instala smartmontools)" >&2
  exit 1
}

HWMON="$(find_emc_hwmon)"
[[ -z "$HWMON" ]] && {
  echo "ERROR: hwmon emc2305 no encontrado" >&2
  exit 1
}

PWM1_PATH="$HWMON/pwm1"
PWM2_PATH="$HWMON/pwm2"

[[ -w "$PWM1_PATH" && -w "$PWM2_PATH" ]] || {
  echo "ERROR: No se puede escribir en pwm1/pwm2" >&2
  exit 1
}

load_last_state

SCAN="$(smartctl --scan 2>/dev/null || true)"

MAX_HDD=0
MAX_NVME=0

log "Controlador: $HWMON"
log "Leyendo temperaturas…"

for d in /dev/sd?; do
  [[ -b "$d" ]] || continue

  if echo "$SCAN" | grep -q "^$d .*sntasmedia"; then
    t="$(read_nvme_usb_temp_c "$d")"
    [[ -n "$t" ]] && log "  NVMe USB  $d → ${t}°C" && (( t > MAX_NVME )) && MAX_NVME=$t
  else
    t="$(read_sata_temp_c "$d")"
    [[ -n "$t" ]] && log "  HDD/SSD   $d → ${t}°C" && (( t > MAX_HDD )) && MAX_HDD=$t
  fi
done

CPU_TEMP="$(read_cpu_temp_c)"
log "  CPU       → ${CPU_TEMP}°C"

FAST_TEMP=$(( MAX_NVME > CPU_TEMP ? MAX_NVME : CPU_TEMP ))

PWM1_TARGET="$(pwm_hdd_from_temp "$MAX_HDD")"
PWM2_TARGET="$(pwm_fast_from_temp "$FAST_TEMP")"

(( PWM1_TARGET < MIN_PWM1 )) && PWM1_TARGET=$MIN_PWM1
(( PWM2_TARGET < MIN_PWM2 )) && PWM2_TARGET=$MIN_PWM2

if (( CPU_TEMP >= CPU_FAILSAFE_C )); then
  log "FAILSAFE CPU ${CPU_TEMP}°C → PWM1=255 PWM2=255"
  PWM1_TARGET=255
  PWM2_TARGET=255
elif (( FAST_TEMP >= FAST_FAILSAFE_C )); then
  log "FAILSAFE FAST ${FAST_TEMP}°C → PWM2=255"
  PWM2_TARGET=255
fi

log "Resumen:"
log "  Max HDD/SSD: ${MAX_HDD}°C → PWM1 $PWM1_TARGET"
log "  Max NVMe:    ${MAX_NVME}°C"
log "  FAST:        ${FAST_TEMP}°C → PWM2 $PWM2_TARGET"

NEW_PWM1="$(apply_pwm "$PWM1_PATH" "$PWM1_TARGET" "$PWM1_LAST" "PWM1 (HDD/SSD)")"
NEW_PWM2="$(apply_pwm "$PWM2_PATH" "$PWM2_TARGET" "$PWM2_LAST" "PWM2 (NVMe+CPU)")"

save_state "$NEW_PWM1" "$NEW_PWM2"

log "OK."
