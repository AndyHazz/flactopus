#!/usr/bin/env bash
# flactopus.sh — Convert all .flac files recursively to high-quality .opus and delete originals.
# Usage: ./flactopus.sh [directory] [--yes|-y] [--jobs|-j N] [--dry-run] [--keep] [--bitrate|-b RATE]

set -o pipefail

# --- Argument parsing (flags in any order) ---
SOURCE_DIR=""
AUTO_YES=false
DRY_RUN=false
KEEP_FLAC=false
JOBS=1
BITRATE="192k"

show_help() {
    cat <<'HELP'
Usage: flactopus.sh [OPTIONS] [DIRECTORY]

Convert all .flac files in DIRECTORY (default: current dir) to high-quality
Opus format and delete the originals.

Options:
  -y, --yes          Skip confirmation prompt
  -j, --jobs N       Run N conversions in parallel (default: 1)
  -b, --bitrate RATE Set Opus bitrate (default: 192k)
  -n, --dry-run      Show what would be converted without making changes
  --keep             Convert but don't delete original .flac files
  -h, --help         Show this help message

Examples:
  flactopus.sh /mnt/media/music
  flactopus.sh --yes --jobs 4 /mnt/media/music
  flactopus.sh --dry-run .
  flactopus.sh --keep --bitrate 128k /mnt/media/music
HELP
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)      AUTO_YES=true; shift ;;
        -n|--dry-run)  DRY_RUN=true; shift ;;
        --keep)        KEEP_FLAC=true; shift ;;
        -b|--bitrate)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --bitrate requires an argument (e.g. 192k, 128k)." >&2
                exit 1
            fi
            BITRATE="$2"; shift 2 ;;
        -j|--jobs)
            if [[ -z "${2:-}" || ! "$2" =~ ^[0-9]+$ || "$2" -lt 1 ]]; then
                echo "Error: --jobs requires a positive integer argument." >&2
                exit 1
            fi
            JOBS="$2"; shift 2 ;;
        -h|--help)  show_help ;;
        -*)         echo "Error: Unknown option '$1'. Use --help for usage." >&2; exit 1 ;;
        *)
            if [[ -n "$SOURCE_DIR" ]]; then
                echo "Error: Multiple directories specified." >&2; exit 1
            fi
            SOURCE_DIR="$1"; shift ;;
    esac
done

SOURCE_DIR="${SOURCE_DIR:-.}"
LOG_FILE="/tmp/flactopus.log"

# --- Validation ---
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: '$SOURCE_DIR' is not a directory or does not exist." >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "Error: ffmpeg not found. Please install it." >&2; exit 1; }

echo "============================================"
echo "FLACTOPUS — FLAC -> Opus Converter"
echo "Source directory: $SOURCE_DIR"
echo "Bitrate:         $BITRATE"
if [[ "$DRY_RUN" == true ]]; then
    echo "Mode:            DRY RUN (no changes)"
elif [[ "$KEEP_FLAC" == true ]]; then
    echo "Mode:            Keep originals"
fi
echo "Parallel jobs:   $JOBS"
echo "Log file:        $LOG_FILE"
echo "============================================"
echo

# --- Log session header ---
if [[ "$DRY_RUN" != true ]]; then
    {
        echo ""
        echo "=== flactopus session: $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "Source: $SOURCE_DIR"
    } >> "$LOG_FILE"
fi

# --- Scanning phase ---
echo -n "Scanning for .flac files..."
mapfile -d '' FLAC_FILES < <(find "$SOURCE_DIR" -type f -iname "*.flac" -print0)
echo " ${#FLAC_FILES[@]} found."

if [[ ${#FLAC_FILES[@]} -eq 0 ]]; then
    echo "No .flac files found. Nothing to do!"
    exit 0
fi

# Calculate total FLAC size using find to avoid ARG_MAX limits
echo -n "Calculating total size..."
TOTAL_FLAC_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.flac" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')
TOTAL_FLAC_HR=$(numfmt --to=iec --suffix=B "$TOTAL_FLAC_SIZE" 2>/dev/null)
echo " $TOTAL_FLAC_HR"

# --- Dry-run mode ---
if [[ "$DRY_RUN" == true ]]; then
    echo
    echo "Files that would be converted:"
    dr_skip=0
    dr_convert=0
    for f in "${FLAC_FILES[@]}"; do
        dr_basename="${f##*/}"
        dr_dirpath="${f%/*}"
        dr_stem="${dr_basename%.[fF][lL][aA][cC]}"
        dr_opus="${dr_dirpath}/${dr_stem}.opus"
        if [[ -f "$dr_opus" ]]; then
            echo "  [SKIP]    $f (opus already exists)"
            ((dr_skip++))
        else
            echo "  [CONVERT] $f"
            ((dr_convert++))
        fi
    done
    echo
    echo "$dr_convert file(s) to convert, $dr_skip to skip."
    echo "Dry run complete. No files were modified."
    exit 0
fi

if [[ "$AUTO_YES" != true ]]; then
    if [[ "$KEEP_FLAC" == true ]]; then
        read -rp "Proceed with conversion? (originals will be kept) [y/N] " proceed_choice
    else
        read -rp "Proceed with conversion and deletion of .flac files? [y/N] " proceed_choice
    fi
    if [[ ! "$proceed_choice" =~ ^[Yy]$ ]]; then
        echo "Aborted. No changes made."
        exit 0
    fi
fi

# --- Signal handling ---
CURRENT_OPUS=""

cleanup() {
    echo ""
    echo "Interrupted! Cleaning up..." | tee -a "$LOG_FILE"
    if [[ -n "$CURRENT_OPUS" && -f "$CURRENT_OPUS" ]]; then
        rm -f "$CURRENT_OPUS"
        echo "[CLEANUP] Removed partial file: $CURRENT_OPUS" | tee -a "$LOG_FILE"
    fi
    exit 130
}

trap cleanup SIGINT SIGTERM

# Snapshot pre-existing opus size so the summary only counts new files
PRE_OPUS_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.opus" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# --- Conversion function ---
convert_flac() {
    local flac_file="$1"

    # Case-insensitive extension replacement
    local basename="${flac_file##*/}"
    local dirpath="${flac_file%/*}"
    local stem="${basename%.[fF][lL][aA][cC]}"
    local opus_file="${dirpath}/${stem}.opus"

    if [[ -f "$opus_file" ]]; then
        echo "[SKIP] $opus_file already exists" | tee -a "$LOG_FILE"
        return 0
    fi

    CURRENT_OPUS="$opus_file"
    echo "[CONVERT] $(basename "$flac_file")" | tee -a "$LOG_FILE"

    if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$flac_file" \
        -c:a libopus -b:a "$BITRATE" -vbr on -compression_level 10 \
        -application audio -map_metadata 0 "$opus_file" < /dev/null; then
        if [[ "$KEEP_FLAC" != true ]]; then
            rm -f "$flac_file"
            echo "[DONE] Converted and deleted $(basename "$flac_file")" | tee -a "$LOG_FILE"
        else
            echo "[DONE] Converted $(basename "$flac_file") (original kept)" | tee -a "$LOG_FILE"
        fi
        CURRENT_OPUS=""
        return 0
    else
        echo "[ERROR] Conversion failed for $flac_file" | tee -a "$LOG_FILE"
        rm -f "$opus_file"  # Remove failed output
        CURRENT_OPUS=""
        return 1
    fi
}

# --- Conversion phase ---
echo
echo "Starting conversion of ${#FLAC_FILES[@]} files..."
echo

FAIL_COUNT=0
SKIP_COUNT=0
SUCCESS_COUNT=0

if [[ "$JOBS" -gt 1 ]]; then
    # Parallel mode using xargs
    export -f convert_flac
    export LOG_FILE CURRENT_OPUS BITRATE KEEP_FLAC

    printf '%s\0' "${FLAC_FILES[@]}" | xargs -0 -P "$JOBS" -I{} bash -c '
        convert_flac "$@"
    ' _ {}
    # In parallel mode we cannot easily track per-file counts from the parent,
    # so recount from the filesystem after completion.
else
    # Sequential mode with progress counter
    count=0
    for f in "${FLAC_FILES[@]}"; do
        ((count++))
        printf "[%3d/%3d] " "$count" "${#FLAC_FILES[@]}"
        convert_flac "$f"
        case $? in
            0)
                if [[ "$(tail -1 "$LOG_FILE")" == *"[SKIP]"* ]]; then
                    ((SKIP_COUNT++))
                else
                    ((SUCCESS_COUNT++))
                fi
                ;;
            *) ((FAIL_COUNT++)) ;;
        esac
    done
fi

# --- Post-conversion summary ---
echo
echo "Calculating space usage..."

REMAINING_FLAC_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.flac" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')
POST_OPUS_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.opus" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# Only count opus files created during this run
NEW_OPUS_SIZE=$((POST_OPUS_SIZE - PRE_OPUS_SIZE))
CONVERTED_FLAC_SIZE=$((TOTAL_FLAC_SIZE - REMAINING_FLAC_SIZE))

NEW_OPUS_HR=$(numfmt --to=iec --suffix=B "$NEW_OPUS_SIZE" 2>/dev/null)
echo "New Opus files:     $NEW_OPUS_HR"

if [[ "$KEEP_FLAC" == true ]]; then
    echo "Originals:          Kept (no disk space freed)"
else
    SAVED=$((CONVERTED_FLAC_SIZE - NEW_OPUS_SIZE))
    if [[ "$SAVED" -lt 0 ]]; then
        SAVED=0
    fi
    SAVED_HR=$(numfmt --to=iec --suffix=B "$SAVED" 2>/dev/null)
    echo "Space saved:        $SAVED_HR"
fi

if [[ "$KEEP_FLAC" != true && "$REMAINING_FLAC_SIZE" -gt 0 ]]; then
    REMAINING_HR=$(numfmt --to=iec --suffix=B "$REMAINING_FLAC_SIZE" 2>/dev/null)
    REMAINING_COUNT=$(find "$SOURCE_DIR" -type f -iname "*.flac" | wc -l)
    echo "Remaining FLAC:     $REMAINING_HR ($REMAINING_COUNT files — check log for errors)"
fi

if [[ "$JOBS" -eq 1 && "$FAIL_COUNT" -gt 0 ]]; then
    echo "Failed conversions: $FAIL_COUNT"
fi

echo
echo "All done."
echo "Log saved to: $LOG_FILE"
