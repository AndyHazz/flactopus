#!/usr/bin/env bash
# flactopus.sh — Convert all .flac files recursively to high-quality .opus and delete originals.
# Usage: ./flactopus.sh [directory] [--yes|-y] [--jobs|-j N] [--dry-run] [--keep] [--bitrate|-b RATE]

set -o pipefail

# --- Color support (respects NO_COLOR standard and TTY detection) ---
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    BOLD=$'\033[1m'  DIM=$'\033[2m'
    RED=$'\033[31m'  GREEN=$'\033[32m'  YELLOW=$'\033[33m'  CYAN=$'\033[36m'
    RESET=$'\033[0m'
    IS_TTY=true
else
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" RESET=""
    IS_TTY=false
fi

# --- Argument parsing ---
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
    echo "${RED}Error:${RESET} '$SOURCE_DIR' is not a directory or does not exist." >&2
    exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "${RED}Error:${RESET} ffmpeg not found. Please install it." >&2; exit 1; }

# --- Banner ---
echo ""
echo "  ${BOLD}${CYAN}+---------------------------------------+${RESET}"
echo "  ${BOLD}${CYAN}|${RESET}   ${BOLD}FLACTOPUS${RESET} ${DIM}--${RESET} FLAC ${DIM}->${RESET} Opus Converter  ${BOLD}${CYAN}|${RESET}"
echo "  ${BOLD}${CYAN}+---------------------------------------+${RESET}"
echo ""
echo "  ${DIM}Directory${RESET}   $SOURCE_DIR"
echo "  ${DIM}Bitrate${RESET}     $BITRATE"
if [[ "$DRY_RUN" == true ]]; then
    echo "  ${DIM}Mode${RESET}        ${YELLOW}Dry run (no changes)${RESET}"
elif [[ "$KEEP_FLAC" == true ]]; then
    echo "  ${DIM}Mode${RESET}        Keep originals"
fi
echo "  ${DIM}Jobs${RESET}        $JOBS"
echo ""

# --- Log session header ---
if [[ "$DRY_RUN" != true ]]; then
    {
        echo ""
        echo "=== flactopus session: $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "Source: $SOURCE_DIR"
    } >> "$LOG_FILE"
fi

# --- Scanning phase ---
printf "  Scanning for .flac files..."
mapfile -d '' FLAC_FILES < <(find "$SOURCE_DIR" -type f -iname "*.flac" -print0)
echo " ${BOLD}${#FLAC_FILES[@]}${RESET} found."

if [[ ${#FLAC_FILES[@]} -eq 0 ]]; then
    echo "  No .flac files found. Nothing to do!"
    echo ""
    exit 0
fi

# Calculate total FLAC size using find to avoid ARG_MAX limits
printf "  Calculating total size..."
TOTAL_FLAC_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.flac" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')
TOTAL_FLAC_HR=$(numfmt --to=iec --suffix=B "$TOTAL_FLAC_SIZE" 2>/dev/null)
echo " ${BOLD}${TOTAL_FLAC_HR}${RESET}"

# --- Dry-run mode ---
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    dr_skip=0
    dr_convert=0
    for f in "${FLAC_FILES[@]}"; do
        dr_basename="${f##*/}"
        dr_dirpath="${f%/*}"
        dr_stem="${dr_basename%.[fF][lL][aA][cC]}"
        dr_opus="${dr_dirpath}/${dr_stem}.opus"
        if [[ -f "$dr_opus" ]]; then
            echo "  ${YELLOW}~${RESET} ${DIM}$f${RESET} ${DIM}(opus exists)${RESET}"
            ((dr_skip++))
        else
            echo "  ${CYAN}>${RESET} $f"
            ((dr_convert++))
        fi
    done
    echo ""
    echo "  ${BOLD}$dr_convert${RESET} file(s) to convert, ${BOLD}$dr_skip${RESET} to skip."
    echo "  ${DIM}Dry run complete. No files were modified.${RESET}"
    echo ""
    exit 0
fi

# --- Confirmation ---
if [[ "$AUTO_YES" != true ]]; then
    echo ""
    if [[ "$KEEP_FLAC" == true ]]; then
        read -rp "  Proceed with conversion? (originals kept) [y/N] " proceed_choice
    else
        read -rp "  Proceed with conversion and delete originals? [y/N] " proceed_choice
    fi
    if [[ ! "$proceed_choice" =~ ^[Yy]$ ]]; then
        echo "  Aborted. No changes made."
        echo ""
        exit 0
    fi
fi

# --- Signal handling ---
CURRENT_OPUS=""

cleanup() {
    if [[ "$IS_TTY" == true ]]; then
        printf "\r\033[K"
    fi
    echo ""
    echo "  ${RED}Interrupted!${RESET} Cleaning up..." | tee -a "$LOG_FILE"
    if [[ -n "$CURRENT_OPUS" && -f "$CURRENT_OPUS" ]]; then
        rm -f "$CURRENT_OPUS"
        echo "  Removed partial file: $CURRENT_OPUS" | tee -a "$LOG_FILE"
    fi
    exit 130
}

trap cleanup SIGINT SIGTERM

# Snapshot pre-existing opus size so the summary only counts new files
PRE_OPUS_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.opus" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# --- Progress bar (TTY only) ---
draw_progress() {
    [[ "$IS_TTY" != true ]] && return
    local current=$1 total=$2 filename=$3
    local bar_width=25
    local pct=$((current * 100 / total))
    local filled=$((current * bar_width / total))

    local bar_fill="" bar_empty=""
    printf -v bar_fill '%*s' "$filled" ''
    printf -v bar_empty '%*s' "$((bar_width - filled))" ''
    bar_fill="${bar_fill// /=}"
    bar_empty="${bar_empty// /.}"

    # Truncate long filenames
    if [[ ${#filename} -gt 35 ]]; then
        filename="${filename:0:34}~"
    fi

    printf "\r  ${GREEN}[%s${DIM}%s${GREEN}]${RESET} %3d%% ${DIM}(%d/%d)${RESET} %s\033[K" \
        "$bar_fill" "$bar_empty" "$pct" "$current" "$total" "$filename"
}

# --- Conversion function (writes to log only; caller handles display) ---
convert_flac() {
    local flac_file="$1"

    # Case-insensitive extension replacement
    local basename="${flac_file##*/}"
    local dirpath="${flac_file%/*}"
    local stem="${basename%.[fF][lL][aA][cC]}"
    local opus_file="${dirpath}/${stem}.opus"

    if [[ -f "$opus_file" ]]; then
        echo "[SKIP] $opus_file already exists" >> "$LOG_FILE"
        return 2
    fi

    CURRENT_OPUS="$opus_file"
    echo "[CONVERT] $basename" >> "$LOG_FILE"

    if ffmpeg -nostdin -hide_banner -loglevel error -y -i "$flac_file" \
        -c:a libopus -b:a "$BITRATE" -vbr on -compression_level 10 \
        -application audio -map_metadata 0 "$opus_file" < /dev/null; then
        if [[ "$KEEP_FLAC" != true ]]; then
            rm -f "$flac_file"
            echo "[DONE] Converted and deleted $basename" >> "$LOG_FILE"
        else
            echo "[DONE] Converted $basename (original kept)" >> "$LOG_FILE"
        fi
        CURRENT_OPUS=""
        return 0
    else
        echo "[ERROR] Conversion failed for $flac_file" >> "$LOG_FILE"
        rm -f "$opus_file"
        CURRENT_OPUS=""
        return 1
    fi
}

# --- Conversion phase ---
echo ""
echo "  Converting ${BOLD}${#FLAC_FILES[@]}${RESET} files..."
echo ""

START_TIME=$(date +%s)
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
    # Sequential mode
    count=0
    for f in "${FLAC_FILES[@]}"; do
        ((count++))
        fname="${f##*/}"

        if [[ "$IS_TTY" == true ]]; then
            draw_progress "$count" "${#FLAC_FILES[@]}" "$fname"
        else
            printf "[%3d/%3d] " "$count" "${#FLAC_FILES[@]}"
        fi

        convert_flac "$f"
        rc=$?

        case $rc in
            0)
                ((SUCCESS_COUNT++))
                if [[ "$IS_TTY" != true ]]; then
                    echo "Converted: $fname"
                fi
                ;;
            1)
                ((FAIL_COUNT++))
                if [[ "$IS_TTY" == true ]]; then
                    printf "\r\033[K"
                    echo "  ${RED}x Failed:${RESET} $fname"
                else
                    echo "FAILED: $fname"
                fi
                ;;
            2)
                ((SKIP_COUNT++))
                if [[ "$IS_TTY" == true ]]; then
                    printf "\r\033[K"
                    echo "  ${YELLOW}~ Skipped:${RESET} $fname ${DIM}(opus exists)${RESET}"
                else
                    echo "Skipped: $fname"
                fi
                ;;
        esac
    done

    # Clear progress bar
    if [[ "$IS_TTY" == true ]]; then
        printf "\r\033[K"
    fi
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# Format elapsed time
if [[ $ELAPSED -ge 3600 ]]; then
    ELAPSED_FMT=$(printf '%dh%02dm%02ds' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))
elif [[ $ELAPSED -ge 60 ]]; then
    ELAPSED_FMT=$(printf '%dm%02ds' $((ELAPSED/60)) $((ELAPSED%60)))
else
    ELAPSED_FMT="${ELAPSED}s"
fi

# --- Post-conversion summary ---
REMAINING_FLAC_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.flac" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')
POST_OPUS_SIZE=$(find "$SOURCE_DIR" -type f -iname "*.opus" -printf "%s\n" | awk '{sum+=$1} END {print sum+0}')

# Only count opus files created during this run
NEW_OPUS_SIZE=$((POST_OPUS_SIZE - PRE_OPUS_SIZE))
CONVERTED_FLAC_SIZE=$((TOTAL_FLAC_SIZE - REMAINING_FLAC_SIZE))

echo ""
echo "  ${BOLD}Results${RESET}"
echo "  ${DIM}-----------------------------------${RESET}"

if [[ "$JOBS" -eq 1 ]]; then
    echo "  ${GREEN}+${RESET} Converted      ${BOLD}$SUCCESS_COUNT${RESET} files"
    if [[ $SKIP_COUNT -gt 0 ]]; then
        echo "  ${YELLOW}~${RESET} Skipped        $SKIP_COUNT files"
    fi
    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo "  ${RED}x${RESET} Failed         $FAIL_COUNT files"
    fi
    echo "  ${DIM}-----------------------------------${RESET}"
fi

NEW_OPUS_HR=$(numfmt --to=iec --suffix=B "$NEW_OPUS_SIZE" 2>/dev/null)
echo "  ${DIM}Opus size${RESET}      $NEW_OPUS_HR"

if [[ "$KEEP_FLAC" == true ]]; then
    echo "  ${DIM}Originals${RESET}      Kept"
else
    SAVED=$((CONVERTED_FLAC_SIZE - NEW_OPUS_SIZE))
    if [[ "$SAVED" -lt 0 ]]; then
        SAVED=0
    fi
    SAVED_HR=$(numfmt --to=iec --suffix=B "$SAVED" 2>/dev/null)
    echo "  ${DIM}Space saved${RESET}    ${GREEN}$SAVED_HR${RESET}"
fi

if [[ "$KEEP_FLAC" != true && "$REMAINING_FLAC_SIZE" -gt 0 ]]; then
    REMAINING_HR=$(numfmt --to=iec --suffix=B "$REMAINING_FLAC_SIZE" 2>/dev/null)
    REMAINING_COUNT=$(find "$SOURCE_DIR" -type f -iname "*.flac" | wc -l)
    echo "  ${YELLOW}!${RESET} ${DIM}Remaining${RESET}      $REMAINING_HR ($REMAINING_COUNT files)"
fi

echo "  ${DIM}Elapsed${RESET}        $ELAPSED_FMT"
echo "  ${DIM}Log${RESET}            $LOG_FILE"
echo ""
