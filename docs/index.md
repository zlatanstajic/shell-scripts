---
layout: default
title: Home
nav_order: 1
---

# shell-scripts

Custom Unix shell scripts for git development setup, PHP version switching,
password generation, machine backups, decrypting the `.env` files a backup
encrypted, restoring a project's `.vscode` folder, hashing filenames, copying a
git diff between commits, splicing images and videos, installing Tampermonkey
userscripts from a GitHub repository, gating shell-initiated shutdowns and
restarts behind configurable guards, and listing every custom command you have
— from this repository and from the sibling `python_scripts` repository — with
a marker showing whether it currently resolves on `PATH`.

A collection of standalone Bash utility scripts for a Unix dev workflow. No
build step, no test framework dependency, no package manager — each script in
`src/scripts/` is run directly with `bash <script>.sh`.

[Browse the scripts]({{ site.baseurl }}/scripts/){: .btn .btn-primary }
[View on GitHub](https://github.com/zlatanstajic/shell-scripts){: .btn }

## More

- [Scripts]({{ site.baseurl }}/scripts/) — one page per script
- [Install]({{ site.baseurl }}/install/) — put the scripts on your `PATH`
- [Testing]({{ site.baseurl }}/testing/) — the pure-bash test harness
- [Contributing]({{ site.baseurl }}/contributing/) — how to propose a change
- [Security](https://github.com/zlatanstajic/shell-scripts/blob/master/SECURITY.md) — how to report a vulnerability privately
- [Releases](https://github.com/zlatanstajic/shell-scripts/releases) — the canonical changelog

Licensed under the MIT License.
