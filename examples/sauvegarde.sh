#!/bin/zsh
# Sauvegarde quotidienne du dossier Dropbox vers un disque externe
set -euo pipefail

SOURCE="$HOME/Library/CloudStorage/Dropbox"
DEST="/Volumes/Backup/dropbox-$(date +%Y-%m-%d)"
LOG=~/Library/Logs/sauvegarde.log

function journal() {
    local niveau=$1; shift
    echo "[$(date '+%H:%M:%S')] $niveau : $*" | tee -a "$LOG"
}

if [[ ! -d /Volumes/Backup ]]; then
    journal ERREUR "Disque externe absent"
    exit 1
fi

for dossier in Documents IA Photos; do
    rsync -a --delete --exclude '.DS_Store' "$SOURCE/$dossier" "$DEST/" && journal OK "$dossier copié"
done

cat <<FIN
Sauvegarde terminée : ${#} arguments, code $?
FIN
