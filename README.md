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
| `-h`, `--help` | Show help message |

If no directory is given, the current directory is used.

### Examples

```bash
# Convert all FLACs under a music library
./flactopus.sh /mnt/media/music

# Skip confirmation and use 4 parallel workers
./flactopus.sh --yes --jobs 4 /mnt/media/music

# Convert FLACs in current directory
./flactopus.sh
```

## Example Output

```
============================================
FLACTOPUS — FLAC -> Opus Converter
Source directory: /mnt/media/music
Log file: /tmp/flactopus.log
Parallel jobs: 1
============================================

Scanning for .flac files... 128 found.
Calculating total size... 5.7GiB
Proceed with conversion and deletion of .flac files? [y/N] y

Starting conversion of 128 files...

[  1/128] [CONVERT] Track01.flac
[  1/128] [DONE] Converted and deleted Track01.flac
[  2/128] [CONVERT] Track02.flac
...

Calculating space usage...
Total Opus size:    1.8GiB
Space saved:        3.9GiB

All done.
Log saved to: /tmp/flactopus.log
```

## Log

All actions are logged to `/tmp/flactopus.log` with session timestamps, so you can review what happened across multiple runs.
