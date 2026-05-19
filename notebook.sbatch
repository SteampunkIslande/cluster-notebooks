#!/bin/bash
#SBATCH --output=/OPT/notebooks/logs/notebook-%j.out
#SBATCH --error=/OPT/notebooks/logs/notebook-%j.err

set -euo pipefail

#
# Configuration
#

SIF_FILE="${SIF_FILE:-jupyter-notebook-base}"
SIF_FILE="/SINGULARITIES/${SIF_FILE}.sif"

EXECINFO="/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo"

#
# Vérifications
#

if [[ ! -f "${SIF_FILE}" ]]; then
    echo "Image Singularity absente: ${SIF_FILE}"
    exit 1
fi

#
# Variables globales
#

WATCHER_PID=""
CHILD_PID=""

#
# Cleanup
#

cleanup() {
    
    trap - EXIT INT TERM
    
    echo "[CLEANUP] Début du nettoyage"
    
    #
    # Arrêt du watcher
    #
    
    if [[ -n "${WATCHER_PID}" ]]; then
        if kill -0 "${WATCHER_PID}" 2>/dev/null; then
            echo "[CLEANUP] Arrêt du watcher (${WATCHER_PID})"
            kill "${WATCHER_PID}" 2>/dev/null || true
        fi
    fi
    
    #
    # Arrêt du conteneur si encore vivant
    #
    
    if [[ -n "${CHILD_PID}" ]]; then
        if kill -0 "${CHILD_PID}" 2>/dev/null; then
            echo "[CLEANUP] Arrêt du notebook (${CHILD_PID})"
            kill "${CHILD_PID}" 2>/dev/null || true
        fi
    fi
    
    #
    # Suppression du fichier execinfo
    #
    
    if [[ -f "${EXECINFO}" ]]; then
        echo "[CLEANUP] Suppression ${EXECINFO}"
        rm -f "${EXECINFO}"
    fi
    
    echo "[CLEANUP] Fin"
}

on_term() {
    cleanup
    exit 143
}

trap cleanup EXIT
trap on_term INT TERM

#
# Envoi mail
#

send_email() {
    
    local TO_EMAIL="$1"
    local MAIL_SUBJECT="$2"
    local CONTENT_FILE="$3"
    
    if [[ -z "${TO_EMAIL}" ]]; then
        echo "[MAIL] Adresse mail vide"
        return 1
    fi
    
    if [[ ! -f "${CONTENT_FILE}" ]]; then
        echo "[MAIL] Contenu introuvable"
        return 1
    fi
    
    local ENCODED_SUBJECT
    ENCODED_SUBJECT=$(printf "%s" "${MAIL_SUBJECT}" | base64)
    
    echo "[MAIL] Envoi vers ${TO_EMAIL}"
    
    {
        echo "To: ${TO_EMAIL}"
        echo "Subject: =?UTF-8?B?${ENCODED_SUBJECT}?="
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo "Content-Transfer-Encoding: 8bit"
        echo
        cat "${CONTENT_FILE}"
        echo
    } | ssh p01 /usr/sbin/sendmail -t
    
    echo "[MAIL] sendmail terminé"
}

#
# Watcher notebook
#

watcher() {
    
    local timeout=60
    
    echo "[WATCHER] Attente du notebook..."
    
    while [[ ${timeout} -gt 0 ]]; do
        #
        # Notebook prêt
        #
        
        if [[ -f "${EXECINFO}" ]]; then
            
            echo "[WATCHER] Notebook détecté"
            
            #
            # Adresse mail utilisateur
            #
            
            if [[ -f "${HOME}/.usermail" ]]; then
                
                USER_MAIL="$(head -n1 "${HOME}/.usermail")"
                
                if [[ -n "${USER_MAIL}" ]]; then
                    
                    echo "[WATCHER] Destinataire: ${USER_MAIL}"
                    
                    NOTEBOOK_URL="$(cat "${EXECINFO}")"
                    
                    MAIL_CONTENT="$(mktemp)"
                    
                    {
                        echo "<html><body>"
                        
                        echo "Votre notebook est disponible jusqu'à :"
                        echo "<br><br>"
                        
                        squeue -j "${SLURM_JOB_ID}" -o '%e' -h
                        
                        echo "<br><br>"
                        
                        echo "Accès :"
                        echo "<br>"
                        
                        echo "<a href=\"${NOTEBOOK_URL}\">${NOTEBOOK_URL}</a>"
                        
                        echo "<br><br>"
                        
                        echo "Pour arrêter le notebook :"
                        echo "<br>"
                        
                        echo "<code>scancel ${SLURM_JOB_ID}</code>"
                        
                        echo "</body></html>"
                        
                    } > "${MAIL_CONTENT}"
                    
                    if send_email "${USER_MAIL}" "Notebook prêt (${SLURM_JOB_NAME})" "${MAIL_CONTENT}"; then
                        echo "[WATCHER] Mail envoyé"
                        
                    else
                        echo "[WATCHER] ECHEC ENVOI MAIL"
                    fi
                    
                    rm -f "${MAIL_CONTENT}"
                    
                else
                    echo "[WATCHER] .usermail vide"
                fi
                
            else
                echo "[WATCHER] Pas de fichier .usermail"
            fi
            
            return 0
        fi
        
        #
        # Notebook non prêt
        #
        
        sleep 1
        timeout=$((timeout - 1))
    done
    
    echo "[WATCHER] Timeout notebook"
    
    return 1
}

#
# Lancement watcher
#

watcher &
WATCHER_PID=$!

echo "[MAIN] Watcher lancé (${WATCHER_PID})"

#
# Lancement notebook
#

echo "[MAIN] Lancement Singularity"

singularity exec -B "$PWD" -B /OPT/notebooks "${SIF_FILE}" entrypoint.sh &

CHILD_PID=$!

echo "[MAIN] Notebook PID=${CHILD_PID}"

#
# Attente notebook
#

wait "${CHILD_PID}"
RET=$?

echo "[MAIN] Notebook terminé code=${RET}"

exit "${RET}"