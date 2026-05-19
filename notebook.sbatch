#!/bin/bash
#SBATCH --output=/OPT/notebooks/logs/notebook-%j.out
#SBATCH --error=/OPT/notebooks/logs/notebook-%j.err

SIF_FILE=${SIF_FILE:-"jupyter-notebook-base"}

SIF_FILE=/SINGULARITIES/${SIF_FILE}.sif

[[ ! -f "${SIF_FILE}" ]] && { echo "${SIF_FILE} n'existe pas, rien n'a été lancé!"; exit 1; }

cleanup() {
    rm -f "$execinfo"
}
trap cleanup EXIT INT TERM

send_email(){
    
    TO_EMAIL="$1"
    MAIL_SUBJECT="$2"
    CONTENT="$3"
    
    [ -z "$TO_EMAIL" ] && { echo "Pas d'adresse mail de destinataire définie"; exit 0; }
    [ -z "$MAIL_SUBJECT" ] && { echo "Pas de sujet défini"; exit 0; }
    [ ! -f "$CONTENT" ] && { echo "Pas de contenu";exit 0; }
    
    ENCODED_SUBJECT=$(printf "%s" "$MAIL_SUBJECT" | base64)
    {
        echo "To: $TO_EMAIL"
        echo "Subject: =?UTF-8?B?$ENCODED_SUBJECT?="
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"
        echo
        cat "$CONTENT"
        echo
    } | /usr/sbin/sendmail -t
    
}

(
    timeout=60
    while [[ $timeout -gt 0 ]]; do
        if [[ -f "$execinfo" ]]; then
            if [[ -f "$HOME/.usermail" ]]; then
                USER_MAIL="$(head -n1 "$HOME/.usermail")"
                if [[ -n "$USER_MAIL" ]]; then
                    notebook_url=$(cat "$execinfo")
                    mail_content=$(mktemp)
                    {
                        echo "Votre notebook est disponible jusqu'à $(squeue -j $SLURM_JOB_ID -o '%e' -h)<br><br>"
                        echo "Accès :<br>"
                        echo "<a href=\"$notebook_url\">$notebook_url</a><br><br>"
                        echo "Pour arrêter le notebook :<br>"
                        echo "<code>scancel $SLURM_JOB_ID</code>"
                    } > "$mail_content"
                    send_email "$USER_MAIL" "Notebook prêt ($SLURM_JOB_NAME)" "$mail_content"
                    rm -f "$mail_content"
                fi
            fi
            exit 0
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    echo "Le notebook ne s'est pas lancé dans les 60 secondes imparties ou a été interrompu de manière inattendue."
) &


# Lancer le conteneur
singularity exec -B "$PWD" -B /OPT/notebooks "${SIF_FILE}" entrypoint.sh
