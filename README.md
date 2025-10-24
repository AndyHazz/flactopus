Script to find all .flac files nested in a given folder, show the total filesize, ask for confirmation, then convert all .flac files to .opus at a high quality (192kb VBR, equal or better quality to 320kbps .mp3)


💡 Example Run

```
🐙  FLACTOPUS — FLAC → Opus Converter
Source directory: /mnt/media/music
Log file: /tmp/flactopus.log
============================================

🔍 Scanning for .flac files... 128 found.
📦 Calculating total size... 5.7GiB
Proceed with conversion and deletion of .flac files? [y/N] y

🚀 Starting conversion of 128 files...

[  1/128] [CONVERT] Track01.flac
[  2/128] [CONVERT] Track02.flac
...

🧮 Calculating space usage...
💿 Total Opus size:    1.8GiB
💾 Space saved:        3.9GiB

✅ All conversions complete.
🪶 Log saved to: /tmp/flactopus.log
```
