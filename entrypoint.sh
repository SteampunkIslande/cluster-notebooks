#!/bin/bash

set -euo pipefail

if [[ -z "${SLURM_JOB_ID:-}" ]]; then
    echo "Erreur: ce script doit être lancé par SLURM"
    exit 1
fi

execinfo="/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo"

find_free_port() {
    for _ in {1..50}; do
        port=$(shuf -i 8000-9000 -n 1)
        if ! ss -ltn | awk '{print $4}' | grep -q ":${port}$"; then
            echo "$port"
            return 0
        fi
    done
    echo "Impossible de trouver un port libre" >&2
    exit 1
}

HOST=$(hostname -f)
PORT=$(find_free_port)
TOKEN=$(openssl rand -hex 16)

URL="http://${HOST}:${PORT}/tree?token=${TOKEN}"

echo "$URL" > "$execinfo"

echo "Notebook lancé sur : $URL"

jupyter notebook -y --ip="${HOST}" --port="${PORT}" --no-browser --ServerApp.token="${TOKEN}"