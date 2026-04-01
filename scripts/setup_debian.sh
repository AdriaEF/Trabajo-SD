#!/usr/bin/env bash
set -euo pipefail

# Debian bootstrap for this project.
# What it does:
# 1) Checks and installs required system packages.
# 2) Enables/starts Redis, RabbitMQ, and NGINX services.
# 3) Creates Python virtual environments and installs requirements by component.
#
# Usage:
#   bash scripts/setup_debian.sh
#
# Optional env toggles:
#   INSTALL_SYSTEM=1        (default: 1)
#   INSTALL_PYTHON_ENVS=1   (default: 1)
#   ENABLE_SERVICES=1       (default: 1)

INSTALL_SYSTEM="${INSTALL_SYSTEM:-1}"
INSTALL_PYTHON_ENVS="${INSTALL_PYTHON_ENVS:-1}"
ENABLE_SERVICES="${ENABLE_SERVICES:-1}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APT_UPDATED=0

log() {
    echo "[setup] $*"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd"
        exit 1
    fi
}

ensure_apt_updated() {
    if [[ "$APT_UPDATED" -eq 0 ]]; then
        log "Running apt-get update"
        sudo apt-get update -y
        APT_UPDATED=1
    fi
}

is_debian_like() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]
        return
    fi
    return 1
}

install_pkg_if_missing() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        log "Package already installed: $pkg"
    else
        ensure_apt_updated
        log "Installing package: $pkg"
        sudo apt-get install -y "$pkg"
    fi
}

enable_service_if_present() {
    local service_name="$1"
    if systemctl list-unit-files | grep -q "^${service_name}"; then
        log "Enabling and starting service: $service_name"
        sudo systemctl enable --now "$service_name"
    else
        log "Service not found, skipping: $service_name"
    fi
}

install_python_requirements() {
    local req_path="$1"
    local venv_path="$2"

    if [[ ! -f "$req_path" ]]; then
        log "Requirements file not found, skipping: $req_path"
        return
    fi

    if [[ ! -d "$venv_path" ]]; then
        log "Creating virtualenv: $venv_path"
        python3 -m venv "$venv_path"
    fi

    log "Installing Python deps from: $req_path"
    # shellcheck disable=SC1091
    source "$venv_path/bin/activate"
    python -m pip install --upgrade pip
    python -m pip install -r "$req_path"
    deactivate
}

main() {
    require_cmd sudo
    require_cmd dpkg
    require_cmd apt-get
    require_cmd python3

    if ! is_debian_like; then
        echo "This script is intended for Debian or Debian-like distributions."
        exit 1
    fi

    log "Project root: $PROJECT_ROOT"

    if [[ "$INSTALL_SYSTEM" == "1" ]]; then
        log "Installing/checking system packages"
        install_pkg_if_missing python3
        install_pkg_if_missing python3-venv
        install_pkg_if_missing python3-pip
        install_pkg_if_missing redis-server
        install_pkg_if_missing rabbitmq-server
        install_pkg_if_missing nginx
        install_pkg_if_missing curl
        install_pkg_if_missing redis-tools
        install_pkg_if_missing git
    else
        log "Skipping system package installation"
    fi

    if [[ "$ENABLE_SERVICES" == "1" ]]; then
        log "Enabling/starting services"
        enable_service_if_present redis-server.service
        enable_service_if_present rabbitmq-server.service
        enable_service_if_present nginx.service
    else
        log "Skipping service enable/start"
    fi

    if [[ "$INSTALL_PYTHON_ENVS" == "1" ]]; then
        log "Preparing Python virtual environments"
        install_python_requirements \
            "$PROJECT_ROOT/direct/rest/service/requirements.txt" \
            "$PROJECT_ROOT/direct/rest/service/.venv"

        install_python_requirements \
            "$PROJECT_ROOT/indirect/rabbitmq/worker/requirements.txt" \
            "$PROJECT_ROOT/indirect/rabbitmq/worker/.venv"

        install_python_requirements \
            "$PROJECT_ROOT/scripts/requirements_indirect.txt" \
            "$PROJECT_ROOT/scripts/.venv-indirect"

        install_python_requirements \
            "$PROJECT_ROOT/scripts/requirements_report.txt" \
            "$PROJECT_ROOT/scripts/.venv-report"
    else
        log "Skipping Python virtualenv setup"
    fi

    log "Setup completed successfully"
}

main "$@"
