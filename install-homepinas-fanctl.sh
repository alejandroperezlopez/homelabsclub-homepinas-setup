#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIGURACIÓN
# =========================

SERVICE_NAME="homepinas-fanctl"

# Repo GitHub
GITHUB_REPO="alejandroperezlopez/homelabsclub-homepinas-setup"
GITHUB_BRANCH="main"

# Ruta DENTRO del repo donde está el script de control
REMOTE_SCRIPT_PATH="fanctl/homepinas-fanctl.sh"

# Dónde se instalará en el sistema
INSTALL_PATH="/usr/local/bin/homepinas-fanctl.sh"

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_FILE="/etc/systemd/system/${SERVICE_NAME}.timer"

RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"

# =========================
# COMPROBACIONES
# =========================

echo "=== HomePinas Fan Control installer ==="
echo ""

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Ejecuta este instalador como root (sudo)." >&2
  exit 1
fi

for cmd in curl systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Comando requerido no encontrado: $cmd" >&2
    exit 1
  fi
done

echo "✔ Ejecutando como root"
echo "✔ Dependencias básicas OK"
echo ""

# =========================
# DESCARGAR SCRIPT
# =========================

echo "→ Descargando script de control desde GitHub…"
echo "  Repo: ${GITHUB_REPO}"
echo "  Path: ${REMOTE_SCRIPT_PATH}"

curl -fsSL \
  "${RAW_BASE}/${REMOTE_SCRIPT_PATH}" \
  -o "$INSTALL_PATH"

chmod +x "$INSTALL_PATH"

echo "✔ Script instalado en $INSTALL_PATH"
echo ""

# =========================
# CREAR SERVICE
# =========================

echo "→ Creando service systemd…"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=HomePinas Fan Control (HDD/SSD + NVMe/CPU)
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=${INSTALL_PATH}

Restart=on-failure
RestartSec=5s

User=root
Group=root

StandardOutput=journal
StandardError=journal
EOF

echo "✔ Service creado: $SERVICE_FILE"
echo ""

# =========================
# CREAR TIMER
# =========================

echo "→ Creando timer systemd…"

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run HomePinas Fan Control periodically

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "✔ Timer creado: $TIMER_FILE"
echo ""

# =========================
# ACTIVAR
# =========================

echo "→ Recargando systemd…"
systemctl daemon-reexec
systemctl daemon-reload

echo "→ Activando timer…"
systemctl enable --now "${SERVICE_NAME}.timer"

echo ""
echo "✔ Instalación completada correctamente"
echo ""

# =========================
# INFO FINAL
# =========================

cat <<EOF

Comprobaciones útiles:

  Ver timers activos:
    systemctl list-timers | grep ${SERVICE_NAME}

  Ver último estado:
    systemctl status ${SERVICE_NAME}.service

  Ver logs en tiempo real:
    journalctl -u ${SERVICE_NAME}.service -f

  Forzar ejecución ahora:
    systemctl start ${SERVICE_NAME}.service

Si actualizas el script en GitHub:
  → vuelve a ejecutar este instalador
  → se descargará la nueva versión automáticamente

EOF
