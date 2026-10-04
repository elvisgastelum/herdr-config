# Herdr config

Install the published config and `herdr-config` utility with one command. It downloads the installer first so a failed fetch cannot be mistaken for a successful piped `sh` invocation:

```sh
(tmp=$(mktemp) && curl -fsSL -o "$tmp" https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/install.sh && sh "$tmp"; status=$?; [ -z "${tmp:-}" ] || rm -f "$tmp"; exit "$status")
```

**Publication caveat:** The remote `main` branch must contain `install.sh`, `config.toml`, and `bin/herdr-config` for this to work. Until T2 is published, `sh install.sh` from this checkout still fetches the **published** config and utility; it cannot provision an unpublished utility. For a local-only installation from this trusted checkout, run:

```sh
HERDR_CONFIG_SOURCE="$PWD/config.toml" HERDR_UTILITY_SOURCE="$PWD/bin/herdr-config" sh install.sh
```

Run that command from the repository root. Review remote scripts before executing them. Add `$HOME/.local/bin` to your `PATH` if necessary.

## Shortcuts

| Keys | Action |
| --- | --- |
| `prefix+d` | Detach from Herdr. |
| `Alt+1` through `Alt+9` | Select the corresponding **tab**, not a numbered pane. |

Your terminal or desktop may intercept Alt-number keys before Herdr sees them. Configure the terminal to send Alt/Meta to applications if the shortcut does not work.

## Update with the repository

Run `herdr-config sync` after installation. It needs `git`, working GitHub SSH authentication for `git@github.com:elvisgastelum/herdr-config.git`, and access to the published `main` branch. It clones to `${XDG_DATA_HOME}/herdr-config` (or `${HOME}/.local/share/herdr-config`) if missing; otherwise it checks the checkout root, `origin` URL, and current `main` branch before `git pull --ff-only origin main`. A failed clone or pull does not deploy config. Sync refuses any tracked or untracked checkout changes both before and after pulling, including nonconflicting changes; resolve or preserve them yourself before retrying. Divergent branches are not forced. Git ignores ambient system/global config and disables hooks and filesystem monitors for its own commands. The fetched repository and any existing checkout (including its local `.git/config`, attributes, and scripts), the configured SSH transport, and executables on `PATH` must still be trusted; do not sync an untrusted repository.

For isolated offline tests only, `HERDR_CONFIG_REPOSITORY` accepts an existing absolute local directory instead of the SSH URL. The installer accepts `HERDR_CONFIG_SOURCE` and `HERDR_UTILITY_SOURCE` together as regular, non-symlink files from a trusted checkout; without them it downloads both published files. Do not set these overrides for a normal published install.

## Back up, restore, and reload

`herdr-config backup` captures the current config without syncing or reloading. `herdr-config backup restore` requires `fzf` and displays a selectable table of config backups (name, creation time, size); it snapshots the current config before restoring. Canceling the selector changes nothing. `herdr-config backup --clean` deletes older recognized backups in the backups directory, retaining the newest config backup and newest utility backup; a tie for newest leaves the tied backups intact. Cleanup does not touch legacy adjacent backups or unknown files. `herdr-config reload` runs `herdr server reload-config`; it does not sync implicitly.

## Files and safety

The installer places `config.toml` at `${XDG_CONFIG_HOME}/herdr/config.toml` when set and nonempty, otherwise `${HOME}/.config/herdr/config.toml`; the executable is placed at `${HOME}/.local/bin/herdr-config`. Runtime state such as `session.json` is not synchronized. Existing regular files get unique `.bak.XXXXXX` backups under `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/backups/` before replacement. Symlinked destination directories, their immediate caller-controlled parents (`HOME`, `XDG_CONFIG_HOME` when used, and `HOME/.local`), or destination files are refused; more distant ancestors and concurrent path replacement are not protected. Sync also checks its checkout, data-home directory, `HOME`, and `HOME/.local` for symlinks, not all ancestors. Failed downloads leave existing files unchanged. If the config move fails after utility replacement, the installer restores the old utility from its preserved backup (or removes the new utility if none existed); if that rollback also fails, restore manually from the printed backup path. No input prompts are used.

The published install needs `sh`, `curl`, `mktemp`, `mkdir`, `cp`, `chmod`, and `mv`, plus network access to GitHub. Sync additionally needs `git` and SSH access. Test without network or live config writes using `sh tests/install.sh`, `sh tests/sync.sh`, and `sh tests/backup.sh`.
