# Shell Scripts

> Custom Unix shell scripts for file manipulation, program execution, and printing text.

## Table of Contents

- [How to Use](#how-to-use)
- [List of Available Scripts](#list-of-available-scripts)
  - [Dev Setup](#dev-setup)
  - [PHP Switch](#php-switch)
  - [Generate Password](#generate-password)
  - [Git](#git)
    - [Git Copy](#git-copy)
    - [Git Sync](#git-sync)
    - [Git Pull](#git-pull)
- [Recommendations](#recommendations)
- [Contributing](#contributing)
- [License](#license)

---

## How to Use

Clone this repository to your local machine and navigate to the `src` directory. Mirror the `src` directory to a new folder named `deploy/versions/[current-version]`, where `[current-version]` is the version of the scripts you are using (e.g., `1.0.0`).

```bash
cp -R src/ deploy/versions/[current-version]
```

It is recommended to keep the name `deploy` for this copy, as it is ignored by [.gitignore](.gitignore).
This allows you to `git pull` the latest version of this repository without overwriting your custom script updates.

Navigate to the mirrored folder and edit scripts as needed:

```bash
cd deploy/versions/[current-version]
ls -al *.sh
nano [script-name].sh
```

After editing, save the script and run it:

```bash
bash [script-name].sh
```

[⬆ back to top](#table-of-contents)

---

## List of Available Scripts

This is a list of available scripts you may use on any Unix-like system.

### Dev Setup

- **File:** [`dev-setup.sh`](src/dev-setup.sh)
- **Parameters:** `issue-number` `issue-name`
- **Description:** Development setup for git repositories.

If you're using this shell script to set up development for a git repository, you're ready to go by default. You can change several parameters based on personal or team preferences.

1. Each branch will have a prefix, which is, by default, *issues*. To change this prefix, update the `BRANCH_PREFIX` variable.
2. Upon completion, the script will offer helper text to copy/paste into your issue tracking software. The `REQUEST_PREFIX` is used as a prefix for pull request titles, and `ISSUE_BASE_PATH` can be set for pull request descriptions. These helper texts do not affect script execution.

```bash
# Show help
bash dev-setup.sh -h

# Set up development for issue #1 "Example issue name"
bash dev-setup.sh 1 "Example issue name"
```

[⬆ back to top](#table-of-contents)

### PHP Switch

- **File:** [`php-switch.sh`](src/php-switch.sh)
- **Parameters:** `php-version`
- **Description:** Switch the main version of PHP on your OS.

Update the `PHP_VERSIONS_INSTALLED` array in the script to match the PHP versions installed on your system.

```bash
# Show help
bash php-switch.sh -h

# Switch to PHP version 8.1
bash php-switch.sh 8.1
```

[⬆ back to top](#table-of-contents)

### Generate Password

- **File:** [`generate-password.sh`](src/generate-password.sh)
- **Parameters:** None
- **Description:** Generate strong and secure password

```bash
# Show help
bash generate-password.sh -h

# How to generate password
bash generate-password.sh
```

[⬆ back to top](#table-of-contents)

### Git

#### Git Copy

- **File:** [`git-copy.sh`](src/git-copy.sh)
- **Parameters:** `start-commit` `end-commit` `target-directory`
- **Description:** Copy all differences between two git commits

```bash
# Show help
bash git-copy.sh -h

# Copy all differences between start and end git commit to target directory
bash git-copy.sh [start-commit] [end-commit] [target-directory]
```

[⬆ back to top](#table-of-contents)

#### Git Sync

- **File:** [`git-sync.sh`](src/git-sync.sh)
- **Parameters:** `[branch-name]` `[folder-location]` `[remote-upstream]`
- **Description:** Synchronize forked git repository

```bash
# Show help
bash git-sync.sh -h

# Sync with remote repo (doing this only once per forked repo)
bash git-sync.sh [branch-name] [full-forked-repo-folder-path] [full-remote-repo-path]

# Sync with remote repo (when branch is master, remote upstream has been added and current directory chosen)
bash [path-to-the-shell-script]/git-sync.sh
```

[⬆ back to top](#table-of-contents)

#### Git Pull

- **File:** [`git-pull.sh`](src/git-pull.sh)
- **Parameters:** None
- **Description:** Run git pull on all repos from directory

```bash
# Show help
bash [path-to-the-shell-script]/git-pull.sh -h

# When navigated to the root folder where all repos are located
bash [path-to-the-shell-script]/git-pull.sh
```

[⬆ back to top](#table-of-contents)

---

## Recommendations

You can create an alias for a script:

```bash
alias [alias-name]="[command]"
[alias-name] -h
```

Replace `[alias-name]` with your chosen alias and `[command]` with the full path to your script (e.g., `[installation-path]/shell-scripts/deploy/versions/[current-version]/[script-name].sh`).

[⬆ back to top](#table-of-contents)

---

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

[⬆ back to top](#table-of-contents)

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

[⬆ back to top](#table-of-contents)
