#!/bin/bash
# Rotate journal export log file
# Runs hourly via systemd timer

LOG_DIR="/mnt/btrfs-pool/subvol7-containers/journal-export"
LOG_FILE="$LOG_DIR/journal.log"
MAX_SIZE=104857600  # 100 MB

# Check if log file exists and is larger than MAX_SIZE
if [ -f "$LOG_FILE" ]; then
    SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null)

    if [ "$SIZE" -gt "$MAX_SIZE" ]; then
        echo "Log file is ${SIZE} bytes, rotating..."

        # Rotate the file
        mv "$LOG_FILE" "${LOG_FILE}.1"

        # Compress old log
        gzip "${LOG_FILE}.1" 2>/dev/null

        # Create new empty file
        touch "$LOG_FILE"

        # Signal journal-export to continue writing
        systemctl --user restart journal-export.service

        # Clean up old compressed logs (keep last 3)
        cd "$LOG_DIR" || exit 1
        ls -t journal.log.*.gz 2>/dev/null | tail -n +4 | xargs -r rm

        echo "Rotation complete. Kept last 3 compressed logs."
    else
        echo "Log file is ${SIZE} bytes, below threshold. No rotation needed."
    fi
else
    echo "Log file not found: $LOG_FILE"
fi
