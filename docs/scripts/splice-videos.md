---
layout: default
title: Splice Videos
parent: Scripts
nav_order: 9
---

# Splice Videos

**File:** `src/scripts/splice-videos.sh` · Splice random fixed-length clips of
one input video into a single output video of a target duration using ffmpeg.

Cuts random fixed-length clips out of one input video and concatenates them into
a single output of a target duration. `-i/--input` (relative to the current
directory) and `-d/--duration` (output length in seconds) are required;
`-s/--segment` sets each random clip's length in seconds (default 3).

The script skips the first and last 10% of the source, caps the output at ~1 GB
(1.5 Mbps estimate), and reuses an existing `./random_clips` directory on a
rerun (resume path). Concatenation uses `ffmpeg -c copy`; output goes to
`./spliced_videos/output_from_<input>`. Valid extensions are read from
`SPLICE_VIDEOS_FILE_EXTENSIONS` in the project root `.env` (copy `.env.example`
to `.env`). Extension matching uses true file extensions (text after the last
dot), so dotless names are rejected. Both `ffmpeg` and `ffprobe` are required —
the script exits with an error if either is missing (`ffprobe` reads
source/clip durations).

Pass `-n/--dry-run` to preview the run: it prints the would-be clips-folder
removal, the would-be clip-extraction and concat `ffmpeg` commands, and the
would-be output path, then exits without removing/creating/writing anything.
Before it wipes an existing `./random_clips` folder the script prompts for
confirmation; pass `-y/--yes` (or `-n/--dry-run`) to bypass the prompt.

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-i`, `--input` | yes | — | Input video (relative to cwd) |
| `-d`, `--duration` | yes | — | Output length in seconds |
| `-s`, `--segment` | no | 3 | Each random clip's length in seconds |
| `-n`, `--dry-run` | no | off | Print intended changes; make no filesystem change |
| `-y`, `--yes` | no | off | Skip the confirmation prompt before mutating |
| `-h`, `--help` | — | — | Print usage and exit |

## `.env` keys

`SPLICE_VIDEOS_FILE_EXTENSIONS` — comma-separated, case-insensitive, leading dot
optional.

## Usage

```bash
# Show help
bash splice-videos.sh -h

# Splice a 12-second output from clip.mp4
bash splice-videos.sh -i clip.mp4 -d 12

# Use a custom 4-second segment length
bash splice-videos.sh -i clip.mp4 -d 12 -s 4
```
