---
layout: default
title: Splice Images
parent: Scripts
nav_order: 8
---

# Splice Images

**File:** `src/scripts/splice-images.sh` · Splice images horizontally using
ffmpeg.

Splices two or more images side by side. Pass explicit inputs with
`-i/--images`, or run with no arguments to pick random images from the current
directory. `-o/--output` sets the output filename (only its extension is used),
`--height` sets a fixed scale height (default auto from the first image), and
`-n/--number` sets how many images to splice (default 2, must be ≥ 2).

Output goes to `./spliced_images`; consumed inputs are moved into
`./standalone_images`. Valid extensions are read from
`SPLICE_IMAGES_FILE_EXTENSIONS` in the project root `.env` (copy `.env.example`
to `.env`). Extension matching uses true file extensions (text after the last
dot), so dotless names are rejected. Both `ffmpeg` and `ffprobe` are required —
the script exits with an error if either is missing (`ffprobe` reads image
height).

Pass `--dry-run` to preview the run: it prints the would-be `ffmpeg` splice
command and `would move <img> -> <dest>` for each input, and creates/moves
nothing (height resolution skips `ffprobe`, so a missing input does not abort).
This is the **long form only** — `-n` stays bound to `--number`. There is no
confirmation gate on this script (output goes to fresh folders and inputs are
moved with non-clobbering `mv -n`).

## Parameters

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `-i`, `--images` | no | random from cwd | Input images |
| `-o`, `--output` | no | — | Output filename (extension only is used) |
| `--height` | no | auto (first image) | Fixed scale height |
| `-n`, `--number` | no | 2 | Number of images to splice (≥ 2) |
| `--dry-run` | no | off | Print intended changes; make no filesystem change (long form only; `-n` is `--number`) |
| `-h`, `--help` | — | — | Print usage and exit |

## `.env` keys

`SPLICE_IMAGES_FILE_EXTENSIONS` — comma-separated, case-insensitive, leading dot
optional.

## Usage

```bash
# Show help
bash splice-images.sh -h

# Splice two given images
bash splice-images.sh -i a.jpg b.jpg

# Splice three images at a fixed height
bash splice-images.sh -i a.jpg b.jpg c.jpg -n 3 --height 200

# Splice two random images from the current directory
bash splice-images.sh
```
