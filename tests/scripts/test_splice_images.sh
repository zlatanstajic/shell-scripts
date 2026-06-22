################################################################################
# Test file   : tests/scripts/test_splice_images.sh
# Description : Dry-run behaviour test for src/scripts/splice-images.sh. Uses a
#               PATH-shimmed ffmpeg/ffprobe stub so the test is hermetic, and a
#               copied-tree fixture (own .env) so PROJECT_ROOT resolves to the
#               fixture rather than the developer's repo .env. Asserts a
#               --dry-run run prints the would-be ffmpeg command, creates none
#               of spliced_images/standalone_images, and does not abort on a
#               fake input. Also asserts the documented hard-dep End 1 when
#               ffmpeg/ffprobe are absent. Sourced by tests/run.sh.
# Author      : Zlatan Stajic <contact@zlatanstajic.com>
# License     : MIT
################################################################################

# Hermetic fixture: script + lib + own .env in a temp tree.
SI_TMP="$(mktemp -d)"
mkdir -p "$SI_TMP/src/scripts" "$SI_TMP/src/lib" "$SI_TMP/work" "$SI_TMP/bin"
cp "$REPO_ROOT/src/scripts/splice-images.sh" "$SI_TMP/src/scripts/"
cp "$REPO_ROOT/src/lib/common.sh" "$SI_TMP/src/lib/"
printf 'SPLICE_IMAGES_FILE_EXTENSIONS=jpg,png\n' > "$SI_TMP/.env"

# PATH-shim stubs. ffprobe echoes a valid integer height; ffmpeg exits 0 (and
# in a real run would create output, but dry-run never invokes it).
cat > "$SI_TMP/bin/ffprobe" <<'STUB'
#!/bin/bash
echo 100
STUB
cat > "$SI_TMP/bin/ffmpeg" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$SI_TMP/bin/ffprobe" "$SI_TMP/bin/ffmpeg"

# Fake (zero-byte) input images. Dry-run must not abort despite unreadable
# images because GetHeight skips ffprobe in dry-run.
: > "$SI_TMP/work/a.jpg"
: > "$SI_TMP/work/b.jpg"

SI_SCRIPT="$SI_TMP/src/scripts/splice-images.sh"

# Output folders are relative to the cwd, so run from $SI_TMP/work; in dry-run
# nothing is created, which the assertions below confirm.
if command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1
then
  # With the stub on PATH first, EnsureTools passes; dry-run prints the would-be
  # command and touches nothing.
  assert_exit 0 "splice-images --dry-run exits 0" -- \
    bash -c "cd '$SI_TMP/work'; export PATH='$SI_TMP/bin:'\"\$PATH\"; \
      bash '$SI_SCRIPT' -i a.jpg b.jpg --dry-run"
  assert_contains "$ASSERT_OUTPUT" "would: ffmpeg" \
    "splice-images dry-run prints the would-be ffmpeg command"
  assert_contains "$ASSERT_OUTPUT" "would move" \
    "splice-images dry-run prints would move lines"
  assert_eq "0" \
    "$([ -d "$SI_TMP/work/spliced_images" ] && echo 1 || echo 0)" \
    "splice-images dry-run creates no spliced_images folder"
  assert_eq "0" \
    "$([ -d "$SI_TMP/work/standalone_images" ] && echo 1 || echo 0)" \
    "splice-images dry-run creates no standalone_images folder"
  # Inputs untouched.
  assert_eq "1" "$([ -f "$SI_TMP/work/a.jpg" ] && echo 1 || echo 0)" \
    "splice-images dry-run leaves input a.jpg in place"
else
  # No ffmpeg/ffprobe on PATH: the documented hard-dep behaviour is End 1.
  assert_exit 1 "splice-images End 1 without ffmpeg/ffprobe" -- \
    bash "$SI_SCRIPT" -i "$SI_TMP/work/a.jpg" "$SI_TMP/work/b.jpg" --dry-run
fi

rm -rf "$SI_TMP"

################################################################################
