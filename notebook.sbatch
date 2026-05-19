#!/bin/bash
#SBATCH --output=/OPT/notebooks/logs/notebook-%j.out
#SBATCH --error=/OPT/notebooks/logs/notebook-%j.err

SIF_FILE=${SIF_FILE:-"jupyter-notebook-base"}

SIF_FILE=/SINGULARITIES/${SIF_FILE}.sif

INSTANCE_NAME="notebook-${SLURM_JOB_ID}"

[[ ! -f "${SIF_FILE}" ]] && { echo "${SIF_FILE} n'existe pas, rien n'a été lancé!"; exit 1; }

cleanup() {
    singularity instance stop "${INSTANCE_NAME}"
    rm -f "$execinfo"
}
trap cleanup EXIT INT TERM

send_email(){
    
    TO_EMAIL="$1"
    MAIL_SUBJECT=$2
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

# Lancer le conteneur
singularity instance start -B "$PWD" -B /OPT/notebooks "${SIF_FILE}" "${INSTANCE_NAME}"

# Attendre 5 secondes que le point d'entrée ait démarré le notebook (soit le temps de trouver un port disponible)
# Nous sommes dans le contexte d'un script sbatch donc déjà alloué, pas besoin d'attendre l'allocation des ressources.
sleep 5

# Notification (si une adresse mail a été définie pour cet utilisateur)
if [[ -f $HOME/.usermail ]];then
    USER_MAIL="$(cat $HOME/.usermail | head -n1)"
    
    if [[ -n $USER_MAIL && -f "/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo" ]]; then
        mail_content=$(mktemp)
        echo "Votre notebook est disponible jusqu'à $(squeue -j $SLURM_JOB_ID -o '%e' -h)</br>" > $mail_content
        
        notebook_url=$(cat "/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo")
        echo "Vous pouvez y accéder à l'adresse suivante: <a href="${notebook_url}" />" >> $mail_content
        
        echo "Si vous voulez arrêter son exécution et ainsi économiser des ressources, vous pouvez l'arrêter avec la commande suivante (assurez-vous d'avoir sauvegardé avant):</br>"
        echo "<code>scancel $SLURM_JOB_ID</code>"
        
        send_email $USER_MAIL "Notebook prêt ($SLURM_JOB_NAME)" $mail_content
        rm $mail_content
    fi
fi
