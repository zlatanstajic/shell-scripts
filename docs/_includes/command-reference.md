<details markdown="1">
<summary><strong>Backup</strong> — <code>src/scripts/backup.sh</code></summary>

```text
Running backup.sh
Description: Backup documents on Linux machine

Show this help  : backup.sh -h
Run this script : backup.sh
Preview only    : backup.sh -n

  -h, --help     Show this help and exit
  -n, --dry-run  Print intended changes; make no filesystem change
  -y, --yes      Skip the confirmation prompt before mutating

Configuration is read from <repo-root>/.env (see .env.example).
BACKUP_LOCATION is required; per-section variables are optional.
```

</details>

<details markdown="1">
<summary><strong>Dev Setup</strong> — <code>src/scripts/dev-setup.sh</code></summary>

```text
Running dev-setup.sh
Description: Development setup for git

Show this help  : dev-setup.sh -h
Run this script : dev-setup.sh -nu 1 -na "Example issue name"

  -nu, --number   Issue number (required)
  -na, --name     Issue name (required)
```

</details>

<details markdown="1">
<summary><strong>Generate Password</strong> — <code>src/scripts/generate-password.sh</code></summary>

```text
Running generate-password.sh
Description: Generate strong and secure password
Minimum length is 8 and must be divisible by 4.

Show this help    : generate-password.sh -h
Generate password : generate-password.sh -l 20
```

</details>

<details markdown="1">
<summary><strong>Git Copy</strong> — <code>src/scripts/git-copy.sh</code></summary>

```text
Running git-copy.sh
Description: Copy all differences between two git commits

Show this help  : git-copy.sh -h
Run this script : git-copy.sh

  -s, --start_commit_hash      Start commit hash (optional)
  -e, --end_commit_hash        End commit hash (optional)
  -t, --target_directory_path  Target directory path (optional)

Defaults are computed at runtime: start is the penultimate commit,
end is the last commit. When -t is omitted the target defaults to
$GIT_COPY_TARGET_DIRECTORY_PATH/<repo-basename> (see .env.example);
when -t is given its value is used verbatim.
```

</details>

<details markdown="1">
<summary><strong>Hash Filenames</strong> — <code>src/scripts/hash-filenames.sh</code></summary>

```text
Running hash-filenames.sh
Description: Renames files in a directory to random hash names

Show this help   : hash-filenames.sh -h
Hash a directory : hash-filenames.sh -d /path/to/dir
Verbose output   : hash-filenames.sh -d /path/to/dir -v
Move into batches: hash-filenames.sh -d /path/to/dir -m
Preview only     : hash-filenames.sh -d /path/to/dir -n

  -h, --help       Show this help and exit
  -d, --directory  Directory to process (defaults to current directory)
  -v, --verbose    Enable verbose output
  -m, --move       Move hashed files into hashed_00X folders
  -n, --dry-run    Print intended changes; make no filesystem change
  -y, --yes        Skip the confirmation prompt before mutating

Target extensions are read from HASH_FILENAMES_FILE_EXTENSIONS in
<repo-root>/.env (see .env.example).
```

</details>

<details markdown="1">
<summary><strong>PHP Switch</strong> — <code>src/scripts/php-switch.sh</code></summary>

```text
Running php-switch.sh
Description: Switch main version of PHP on OS

Show this help : php-switch.sh -h
Switch version : php-switch.sh -v 8.1
Interactive    : php-switch.sh
```

</details>

<details markdown="1">
<summary><strong>Restore VSCode Folder</strong> — <code>src/scripts/restore-vscode-folder.sh</code></summary>

```text
Running restore-vscode-folder.sh
Description: Restore the .vscode folder from backup into the current
directory (only when it has no .vscode yet).

Show this help  : restore-vscode-folder.sh -h
Run this script : restore-vscode-folder.sh

Configuration is read from <repo-root>/.env (see .env.example).
Reuses BACKUP_LOCATION and PROJECTS_DESTINATION_FOLDER_NAME; both are
required. Restores from <BACKUP_LOCATION>/
<PROJECTS_DESTINATION_FOLDER_NAME>/<current-dir-basename>/.vscode.
```

</details>

<details markdown="1">
<summary><strong>Splice Images</strong> — <code>src/scripts/splice-images.sh</code></summary>

```text
Running splice-images.sh
Description: Splices images horizontally using ffmpeg

Show this help    : splice-images.sh -h
Splice given imgs : splice-images.sh -i a.jpg b.jpg
Splice 3 images   : splice-images.sh -i a.jpg b.jpg c.jpg -n 3
Random 2 from cwd : splice-images.sh
Fixed scale height: splice-images.sh -i a.jpg b.jpg --height 200

  -h, --help     Show this help and exit
  -i, --images   One or more input image files
  -o, --output   Output filename (only its extension is used)
      --height   Target scale height (default: auto from first image)
  -n, --number   Number of images to splice (default: 2)
      --dry-run  Print intended changes; make no filesystem change
                 (long form only; -n stays bound to --number)

Valid extensions are read from SPLICE_IMAGES_FILE_EXTENSIONS in
<repo-root>/.env (see .env.example).
```

</details>

<details markdown="1">
<summary><strong>Splice Videos</strong> — <code>src/scripts/splice-videos.sh</code></summary>

```text
Running splice-videos.sh
Description: Splices random clips of a video into one output video

Show this help    : splice-videos.sh -h
Splice 12s output : splice-videos.sh -i clip.mp4 -d 12
Custom segment    : splice-videos.sh -i clip.mp4 -d 12 -s 4
Preview only      : splice-videos.sh -i clip.mp4 -d 12 -n

  -h, --help       Show this help and exit
  -i, --input      Input video file (Required)
  -d, --duration   Output video duration in seconds (Required)
  -s, --segment    Random clip duration in seconds (default: 3)
  -n, --dry-run    Print intended changes; make no filesystem change
  -y, --yes        Skip the confirmation prompt before mutating

Valid extensions are read from SPLICE_VIDEOS_FILE_EXTENSIONS in
<repo-root>/.env (see .env.example).
```

</details>
