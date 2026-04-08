#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_PATH="${SCRIPT_DIR}/.venv"

echo ""
echo ""
echo "================================================================================"
echo "============================  PREPARAR ENTORNO  ================================"
echo "================================================================================"
echo ""

chmod +x "${SCRIPT_DIR}"/*.sh

python3 -m venv "${VENV_PATH}"
source "${VENV_PATH}/bin/activate"
pip install -r "${PROJECT_ROOT}/direct/rest/service/requirements.txt"
pip install -r "${SCRIPT_DIR}/requirements_indirect.txt"
pip install -r "${SCRIPT_DIR}/requirements_report.txt"

echo ""
echo "================================================================================"
echo "========================  LEVANTAR DEPENDENCIAS BASE  =========================="
echo "================================================================================"
echo ""

sudo systemctl enable --now redis-server
sudo systemctl enable --now rabbitmq-server
sudo systemctl status redis-server --no-pager
sudo systemctl status rabbitmq-server --no-pager

echo "Servicios levantados correctamente"