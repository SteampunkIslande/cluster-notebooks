#!/bin/bash
#SBATCH --output=/OPT/notebooks/logs/notebook-%j.out
#SBATCH --error=/OPT/notebooks/logs/notebook-%j.err

SIF_FILE=${SIF_FILE:-"jupyter-notebook-base"}

SIF_FILE=/SINGULARITIES/${SIF_FILE}.sif

[[ ! -f "${SIF_FILE}" ]] && { echo "${SIF_FILE} n'existe pas, rien n'a été lancé!"; exit 1; }

# Lancer le conteneur
singularity exec -B "$PWD" -B /OPT/notebooks "${SIF_FILE}" entrypoint.sh

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
    } | sendmail -t
    
}
# Notification

if [[ -f $HOME/.usermail ]];then
    USER_MAIL="$(cat $HOME/.usermail | head -n1)"
    
    if [[ -n $USER_MAIL && -f "/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo" ]]; then
        mail_content=$(mktemp)
        echo "Votre notebook est disponible jusqu'à $(date -d @$SLURM_JOB_END_TIME)" > $mail_content
        
        notebook_url=$(cat "/OPT/notebooks/running/notebook-${SLURM_JOB_ID}.execinfo")
        echo "Vous pouvez y accéder à l'adresse suivante: <a href="${notebook_url}" />" >> $mail_content
        
        echo "Si vous voulez arrêter son exécution et ainsi économiser des ressources, vous pouvez l'arrêter avec la commande suivante:</br>"
        echo "<code>scancel $SLURM_JOB_ID</code>"
        
        send_email $USER_MAIL "Notebook prêt ($SLURM_JOB_NAME)" $mail_content
        rm $mail_content
    fi
fi

if [[ $(( $SLURM_JOB_END_TIME - $SLURM_JOB_START_TIME )) -ge 86400 ]];then
    mail_content=$(mktemp)
    echo "$USER a demandé un notebook pour une durée supérieure à 24 heures" > $mail_content
    send_email charles.monod-broca@aphp.fr "Notebook - Allocation longue" >$mail_content
    rm $mail_content
fi