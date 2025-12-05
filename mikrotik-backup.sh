#!/bin/bash
# -------------------------------------------------------------------
#   MikroTik Backup Server – RouterOS + SwOS
#   Backups, configuraties en logs volledig op NAS
#   Daily / Weekly / Monthly retentie per apparaat
#   NAS-mountcheck met automatische remount
#   Versie: 2025-02
# -------------------------------------------------------------------

set -euo pipefail

# ===================================================================
# PADEN OP NAS
# ===================================================================
NAS_BASE="/mnt/mikrotik-backups"
CONFIG_DIR="$NAS_BASE/devices"
BACKUP_ROOT="$NAS_BASE/backups"
LOG_FILE="$NAS_BASE/logs/backup.log"

mkdir -p "$CONFIG_DIR" "$BACKUP_ROOT" "$(dirname "$LOG_FILE")"

# ===================================================================
# LOGGING
# ===================================================================
TS=$(date +"%Y-%m-%d_%H-%M-%S")

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$LOG_FILE"
}

log "==== Start backup run: $TS ===="

# ===================================================================
# NAS MOUNT CHECK
# ===================================================================
if ! mountpoint -q "$NAS_BASE"; then
    log "NAS niet gemount — poging tot remount..."
    mount -a

    if ! mountpoint -q "$NAS_BASE"; then
        log "FOUT: NAS blijft onbereikbaar. Backup-runde afgebroken."
        exit 1
    fi

    log "NAS succesvol opnieuw gemount."
fi

# ===================================================================
# LOOP: alle device-configbestanden verwerken
# ===================================================================
shopt -s nullglob
for cfg in "$CONFIG_DIR"/*.conf; do
    
    log "Verwerk configuratiebestand: $cfg"

    # Reset variabelen
    unset DEVICE_NAME DEVICE_TYPE DEVICE_IP DEVICE_USER DEVICE_PASS
    unset RETENTION_DAILY RETENTION_WEEKLY RETENTION_MONTHLY

    # shellcheck disable=SC1090
    . "$cfg"

    if [[ -z "${DEVICE_NAME:-}" || -z "${DEVICE_TYPE:-}" || -z "${DEVICE_IP:-}" ]]; then
        log "  -> Ongeldige configuratie. Verplichte velden ontbreken. Overslaan."
        continue
    fi

    DEVICE_DIR="$BACKUP_ROOT/$DEVICE_NAME"
    mkdir -p "$DEVICE_DIR"

    log "  -> Apparaat: $DEVICE_NAME ($DEVICE_IP) – type: $DEVICE_TYPE"

    # -------------------------------------------------------------------
    # Reachability check
    # -------------------------------------------------------------------
    if ! ping -c 1 -W 1 "$DEVICE_IP" >/dev/null 2>&1; then
        log "  -> Apparaat niet bereikbaar. Overslaan."
        continue
    fi

    # ===================================================================
    # ROUTEROS BACKUP
    # ===================================================================
    if [[ "$DEVICE_TYPE" == "routeros" ]]; then
        
        ROS_BACKUP="${DEVICE_NAME}-${TS}.backup"
        ROS_EXPORT="${DEVICE_NAME}-${TS}.rsc"

        log "  -> RouterOS backup starten…"

        # 1) Backup & export aanmaken op RouterOS
        sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no \
            "$DEVICE_USER@$DEVICE_IP" \
            "/system backup save name=$ROS_BACKUP dont-encrypt=yes; /export file=$ROS_EXPORT" \
            >/dev/null 2>&1 || log "  !! Fout tijdens backup-opdracht op RouterOS."

        # 2) Downloaden naar NAS
        sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no \
            "$DEVICE_USER@$DEVICE_IP:$ROS_BACKUP" "$DEVICE_DIR/" \
            >/dev/null 2>&1 || log "  !! Download van .backup mislukt."

        sshpass -p "$DEVICE_PASS" scp -o StrictHostKeyChecking=no \
            "$DEVICE_USER@$DEVICE_IP:$ROS_EXPORT" "$DEVICE_DIR/" \
            >/dev/null 2>&1 || log "  !! Download van .rsc mislukt."

        # 3) Verwijderen op RouterOS
        sshpass -p "$DEVICE_PASS" ssh -o StrictHostKeyChecking=no \
            "$DEVICE_USER@$DEVICE_IP" \
            "/file remove \"$ROS_BACKUP\"; /file remove \"$ROS_EXPORT\"" \
            >/dev/null 2>&1 || log "  !! Kon remote bestanden niet verwijderen."

        log "  -> RouterOS backup voltooid."
    fi


    # ===================================================================
    # SWOS BACKUP
    # ===================================================================
    if [[ "$DEVICE_TYPE" == "swos" ]]; then

        SW_BACKUP="${DEVICE_NAME}-${TS}.swb"
        SW_PATH="$DEVICE_DIR/$SW_BACKUP"

        log "  -> SwOS backup starten…"

        wget --auth-no-challenge \
             --user="$DEVICE_USER" --password="$DEVICE_PASS" \
             "http://$DEVICE_IP/backup.swb" \
             -O "$SW_PATH" >/dev/null 2>&1 \
        && log "  -> SwOS backup opgeslagen op NAS." \
        || log "  !! SwOS backup mislukt!"
    fi



    # ===================================================================
    # RETENTIE (DAILY / WEEKLY / MONTHLY)
    # ===================================================================

    DAILY_KEEP=${RETENTION_DAILY:-7}
    WEEKLY_KEEP=${RETENTION_WEEKLY:-4}
    MONTHLY_KEEP=${RETENTION_MONTHLY:-12}

    log "  -> Retentie toegepast: Daily=${DAILY_KEEP}d, Weekly=${WEEKLY_KEEP}w, Monthly=${MONTHLY_KEEP}m"

    mapfile -t FILES < <(ls -1 "$DEVICE_DIR")

    # ------------------ DAILY ------------------
    DAILY_CAND=()
    for f in "${FILES[@]}"; do
        FP="$DEVICE_DIR/$f"
        DATE=$(echo "$f" | grep -oP '\d{4}-\d{2}-\d{2}')
        [[ -z "$DATE" ]] && continue

        AGE=$(( ( $(date +%s) - $(date -d "$DATE" +%s) ) / 86400 ))

        (( AGE > DAILY_KEEP )) && DAILY_CAND+=("$FP")
    done

    # ------------------ WEEKLY ------------------
    WEEKLY_CAND=()
    for f in "${DAILY_CAND[@]}"; do
        DATE=$(echo "$f" | grep -oP '\d{4}-\d{2}-\d{2}')
        [[ -z "$DATE" ]] && continue

        WD=$(date -d "$DATE" +%w)
        AGE=$(( ( $(date +%s) - $(date -d "$DATE" +%s) ) / 86400 ))

        # zondag = weekly snapshot
        if [[ "$WD" -eq 0 ]] && (( AGE <= WEEKLY_KEEP * 7 )); then
            continue
        fi

        WEEKLY_CAND+=("$f")
    done

    # ------------------ MONTHLY ------------------
    for f in "${WEEKLY_CAND[@]}"; do
        DATE=$(echo "$f" | grep -oP '\d{4}-\d{2}-\d{2}')
        [[ -z "$DATE" ]] && continue

        DAY=$(date -d "$DATE" +%d)
        MONTHS=$(( ( $(date +%s) - $(date -d "$DATE" +%s) ) / (86400 * 30) ))

        if (( DAY <= 7 )) && (( MONTHS <= MONTHLY_KEEP )); then
            continue
        fi

        log "  -> Oude backup verwijderd: $f"
        rm -f "$f"
    done

done
# ===================================================================

log "==== Backup run voltooid: $TS ===="
exit 0
