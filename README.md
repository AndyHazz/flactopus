# Flactopus

Batch convert all `.flac` files in a directory tree to high-quality `.opus` (192 kbps VBR) and delete the originals.

Opus at 192 kbps VBR is transparent quality — perceptually equal to or better than 320 kbps MP3 — at roughly a third of the file size of FLAC.

## Dependencies

- **ffmpeg** (with libopus support)
- Standard GNU/Linux tools: `find`, `awk`, `numfmt`

### Install ffmpeg

```bash
# Debian/Ubuntu
sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# Arch
sudo pacman -S ffmpeg

# macOS (Homebrew)
brew install ffmpeg
```

## Usage

```
flactopus.sh [OPTIONS] [DIRECTORY]
```

| Option | Description |
|--------|-------------|
| `-y`, `--yes` | Skip confirmation prompt |
| `-j N`, `--jobs N` | Run N conversions in parallel (default: 1) |
| `-b`, `--bitrate RATE` | Set Opus bitrate (default: 192k) |
| `-n`, `--dry-run` | Show what would be converted without making changes |
| `--keep` | Convert but don't delete original .flac files |
| `-h`, `--help` | Show help message |

If no directory is given, the current directory is used.

### Examples

```bash
# Convert all FLACs under a music library
./flactopus.sh /mnt/media/music

# Skip confirmation and use 4 parallel workers
./flactopus.sh --yes --jobs 4 /mnt/media/music

# Preview what would happen without changing anything
./flactopus.sh --dry-run /mnt/media/music

# Convert at a lower bitrate, keeping originals
./flactopus.sh --keep --bitrate 128k /mnt/media/music
```

## Example Output

In a terminal, output is colorized with a live progress bar:

```
  +---------------------------------------+
  |   FLACTOPUS -- FLAC -> Opus Converter  |
  +---------------------------------------+

  Directory   /mnt/media/music
  Bitrate     192k
  Jobs        1

  Scanning for .flac files... 128 found.
  Calculating total size... 5.7GiB

  Proceed with conversion and delete originals? [y/N] y

  Converting 128 files...

  [=====================....] 84% (108/128) Track08.flac

  Results
  -----------------------------------
  + Converted      126 files
  ~ Skipped        2 files
  -----------------------------------
  Opus size      1.8GiB
  Space saved    3.9GiB
  Elapsed        4m12s
  Log            /tmp/flactopus.log
```

When piped or in non-TTY environments, output falls back to plain text with per-file status lines and no ANSI codes.

## Log

All actions are logged to `/tmp/flactopus.log` with session timestamps, so you can review what happened across multiple runs.
