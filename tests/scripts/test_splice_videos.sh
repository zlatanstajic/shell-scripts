################################################################################
# Test file   : tests/scripts/test_splice_videos.sh
# Description : Dry-run behaviour test for src/scripts/splice-videos.sh. Uses a
#               PATH-shimmed ffmpeg/ffprobe stub and a copied-tree fixture (own
#               .env). Asserts a -n dry-run prints the would-be removal and
#               ffmpeg commands, reaches a clean exit 0 without reaching
#               PrintReport, and creates none of random_clips/spliced_videos.
#               Also asserts the documented hard-dep End 1 when ffmpeg/ffprobe
#               are absent. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Hermetic fixture: script + lib + own .env in a temp tree.
SV_TMP="$(mktemp -d)"
mkdir -p "$SV_TMP/src/scripts" "$SV_TMP/src/lib" "$SV_TMP/work" "$SV_TMP/bin"
cp "$REPO_ROOT/src/scripts/splice-videos.sh" "$SV_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$SV_TMP/src/lib/"
printf 'SPLICE_VIDEOS_FILE_EXTENSIONS=mp4\n' > "$SV_TMP/.env"

# PATH-shim stubs. ffprobe echoes a numeric duration; ffmpeg exits 0 (never
# invoked in dry-run because Main short-circuits before the mutating block).
cat > "$SV_TMP/bin/ffprobe" <<'STUB'
#!/bin/bash
echo 60
STUB
cat > "$SV_TMP/bin/ffmpeg" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$SV_TMP/bin/ffprobe" "$SV_TMP/bin/ffmpeg"

# Fake (zero-byte) input video; ResolveInput only checks existence + extension.
: > "$SV_TMP/work/clip.mp4"

SV_SCRIPT="$SV_TMP/src/scripts/splice-videos.sh"

# Output folders are relative to the cwd, so run from $SV_TMP/work.
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1
then
  assert_exit 0 "splice-videos -n dry-run exits 0" -- \
    bash -c "cd '$SV_TMP/work'; export PATH='$SV_TMP/bin:'\"\$PATH\"; \
      bash '$SV_SCRIPT' -i clip.mp4 -d 12 -n"
  assert_contains "$ASSERT_OUTPUT" "would remove" \
    "splice-videos dry-run prints would remove for the clips folder"
  assert_contains "$ASSERT_OUTPUT" "would: ffmpeg" \
    "splice-videos dry-run prints would-be ffmpeg commands"
  assert_contains "$ASSERT_OUTPUT" "would write output" \
    "splice-videos dry-run prints the would-be output path"
  # PrintReport emits "Splice Report"; the dry-run short-circuit must not reach
  # it.
  if [[ "$ASSERT_OUTPUT" == *"Splice Report"* ]]
  then
    _fail "splice-videos dry-run does not reach PrintReport" \
      "found Splice Report banner in dry-run output"
  else
    _pass "splice-videos dry-run does not reach PrintReport"
  fi
  assert_eq "0" \
    "$([ -d "$SV_TMP/work/random_clips" ] && echo 1 || echo 0)" \
    "splice-videos dry-run creates no random_clips folder"
  assert_eq "0" \
    "$([ -d "$SV_TMP/work/spliced_videos" ] && echo 1 || echo 0)" \
    "splice-videos dry-run creates no spliced_videos folder"
else
  assert_exit 1 "splice-videos End 1 without ffmpeg/ffprobe" -- \
    bash "$SV_SCRIPT" -i "$SV_TMP/work/clip.mp4" -d 12 -n
fi

rm -rf "$SV_TMP"

################################################################################
