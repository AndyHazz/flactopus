#!/usr/bin/env bash
# flactopus.sh — Convert all .flac files recursively to high-quality .opus and delete originals.
# Usage: ./flactopus.sh [directory] [--yes|-y]

SOURCE_DIR="${1:-.}"
FLAG="$2"
LOG_FILE="/tmp/flactopus.log"

command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not found. Please install it."; exit 1; }

echo "============================================"
echo "🐙  FLACTOPUS — FLAC → Opus Converter"
echo "Source directory: $SOURCE_DIR"
echo "Log file: $LOG_FILE"
echo "============================================"
echo

# --- Scanning phase ---
echo -n "🔍 Scanning for .flac files..."
mapfile -d '' FLAC_FILES < <(find "$SOURCE_DIR" -type f -iname "*.flac" -print0)
echo " ${#FLAC_FILES[@]} found."

if [[ ${#FLAC_FILES[@]} -eq 0 ]]; then
    echo "No .flac files found. Nothing to do!"
    exit 0
fi

# Calculate total FLAC size (in bytes)
echo -n "📦 Calculating total size..."
TOTAL_FLAC_SIZE=$(du -cb "${FLAC_FILES[@]}" 2>/dev/null | tail -n 1 | awk '{print $1}')
TOTAL_FLAC_HR=$(numfmt --to=iec --suffix=B "$TOTAL_FLAC_SIZE" 2>/dev/null)
echo " $TOTAL_FLAC_HR"

# If no --yes flag, offer to show summary and confirm
if [[ "$FLAG" != "--yes" && "$FLAG" != "-y" ]]; then
    read -p "Proceed with conversion and deletion of .flac files? [y/N] " proceed_choice
    if [[ ! "$proceed_choice" =~ ^[Yy]$ ]]; then
        echo "Aborted. No changes made."
        exit 0
    fi
fi

# --- Conversion function ---
convert_flac() {
    local flac_file="$1"
    local opus_file="${flac_file%.flac}.opus"

    if [[ -f "$opus_file" ]]; then
        echo "[SKIP] $opus_file already exists" | tee -a "$LOG_FILE"
        return
    fi

    echo "[CONVERT] $(basename "$flac_file")" | tee -a "$LOG_FILE"

    if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$flac_file" \
        -c:a libopus -b:a 192k -vbr on -compression_level 10 \
        -application audio -map_metadata 0 "$opus_file" < /dev/null; then
        rm -f "$flac_file"
        echo "[DONE] Converted and deleted $(basename "$flac_file")" | tee -a "$LOG_FILE"
    else
        echo "[ERROR] Conversion failed for $flac_file" | tee -a "$LOG_FILE"
    fi
}

export -f convert_flac
export LOG_FILE

# --- Conversion phase ---
echo
echo "🚀 Starting conversion of ${#FLAC_FILES[@]} files..."
echo

count=0
for f in "${FLAC_FILES[@]}"; do
    ((count++))
    printf "[%3d/%3d] " "$count" "${#FLAC_FILES[@]}"
    convert_flac "$f"
done

# --- Post-conversion summary ---
echo
echo "🧮 Calculating space usage..."

# Total remaining FLAC size (should be zero if all deleted)
REMAINING_FLAC_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.flac" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# Total OPUS size
TOTAL_OPUS_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.opus" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# Calculate space saved
SAVED=$((TOTAL_FLAC_SIZE - TOTAL_OPUS_SIZE))
SAVED_HR=$(numfmt --to=iec --suffix=B "$SAVED" 2>/dev/null)
TOTAL_OPUS_HR=$(numfmt --to=iec --suffix=B "$TOTAL_OPUS_SIZE" 2>/dev/null)

echo "💿 Total Opus size:    $TOTAL_OPUS_HR"
echo "💾 Space saved:        $SAVED_HR"
echo
echo "✅ All conversions complete."
echo "🪶 Log saved to: $LOG_FILE"
