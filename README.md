# Herdr config

Install the published config, `herdr-config` utility, and agent skill with one command. It downloads the installer first so a failed fetch cannot be mistaken for a successful piped `sh` invocation:

```sh
(tmp=$(mktemp) && curl -fsSL -o "$tmp" https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/install.sh && sh "$tmp"; status=$?; [ -z "${tmp:-}" ] || rm -f "$tmp"; exit "$status")
```

**Publication caveat:** The remote `main` branch must contain `install.sh`, `config.toml`, `bin/herdr-config`, and `skills/herdr-config/SKILL.md` for this to work. Until this change is published, `sh install.sh` without source overrides fetches the **published** files, not the current checkout. For a local-only installation from this trusted checkout, run:

```sh
HERDR_CONFIG_SOURCE="$PWD/config.toml" HERDR_UTILITY_SOURCE="$PWD/bin/herdr-config" HERDR_SKILL_SOURCE="$PWD/skills/herdr-config/SKILL.md" sh install.sh
```

Run that command from the repository root. Review remote scripts before executing them. Add `$HOME/.local/bin` to your `PATH` if necessary.

## Shortcuts

| Keys | Action |
| --- | --- |
| `prefix+d` | Detach from Herdr. |
| `prefix+f` | Open the port-forward popup (see [Port forwarding plugin](#port-forwarding-plugin)). |
| `Alt+1` through `Alt+9` | Select the corresponding **tab**, not a numbered pane. |

Your terminal or desktop may intercept Alt-number keys before Herdr sees them. Configure the terminal to send Alt/Meta to applications if the shortcut does not work.

## Port forwarding plugin

`plugins/port-forward` is a Herdr workflow plugin (`elvisgastelum.port-forward`) that manages SSH port forwards from a popup opened with `prefix+f`. The popup lists saved forwards with their status and offers:

- **Add** a remote→local forward (`ssh -L`, a remote port reachable on this host) or a local→remote forward (`ssh -R`, a local port reachable on the remote host). The target is a saved Herdr machine (`herdr machine list`) or a manually entered SSH target; ports are validated.
- **Start** a stopped forward, **stop** a running one, or **remove** one. Stop keeps the saved forward but disables its restore; remove stops a running tunnel and deletes the saved forward.

Enabled forwards are restored by the plugin's startup hook each time the Herdr server starts. Restore runs without prompting and records failures rather than waiting for input.

**Requirements:** `ssh`, `jq`, and `fzf` on the Herdr server host. Tunnels run `ssh -N` with `BatchMode=yes`, so each target needs non-interactive authentication (keys or an SSH agent); a forward that would need a password or host-key confirmation fails instead of prompting. `ExitOnForwardFailure=yes` makes a tunnel exit when its port cannot be bound.

**Where it runs:** plugin commands run on the Herdr server host, not necessarily the terminal you are typing in. With `--remote` or saved machines, forwards start wherever the plugin is installed, and "local" means that host. Saved forward specs live in the plugin config directory (`herdr plugin config-dir elvisgastelum.port-forward`); process IDs and logs live in `$HERDR_PLUGIN_STATE_DIR`. Neither is stored in the checkout, and neither is synchronized.

**Registration:** `herdr-config sync` links the plugin from its managed checkout (`${XDG_DATA_HOME:-$HOME/.local/share}/herdr-config/plugins/port-forward`) with `herdr plugin link --enabled` after deploying config. Sync needs `herdr` and `jq` on `PATH` for this step. It refuses a missing or symlinked plugin directory or manifest and a plugin directory that resolves outside the checkout. If the plugin is already linked from the same path, sync leaves it as is; if `elvisgastelum.port-forward` is registered from another path or installed from GitHub, sync prints where it is registered and leaves it unchanged. A failed link makes sync exit nonzero after config was already deployed; fix the reported cause and rerun sync. To use the plugin from a trusted local checkout instead, run `herdr plugin link "$PWD/plugins/port-forward" --enabled` from the repository root. The plugin executes code from that directory, so link only a checkout you trust.

**Limitations:** there is no supervision or automatic reconnect; after a dropped connection, use **Start** again. Start watches a new tunnel for about two seconds, so a forward reported as started can still fail afterwards (for example during authentication); its status in the popup reflects the process actually running.

## Update with the repository

To update the installed configuration, run `herdr-config sync` and, **only if it succeeds**, run `herdr-config reload`. Sync also links the port-forward plugin; see [Port forwarding plugin](#port-forwarding-plugin). Herdr itself has no `herdr sync` subcommand. The installed agent skill at `${HOME}/.agents/skills/herdr-config/SKILL.md` follows this sequence for requests such as “update my herdr config” or “sync herdr config”; it reports errors rather than automatically cleaning backups or pushing changes. Backup and restore remain user-invoked. Sync needs `git`, working GitHub SSH authentication for `git@github.com:elvisgastelum/herdr-config.git`, and access to the published `main` branch. It clones to `${XDG_DATA_HOME}/herdr-config` (or `${HOME}/.local/share/herdr-config`) if missing; otherwise it checks the checkout root, `origin` URL, and current `main` branch before `git pull --ff-only origin main`. A failed clone or pull does not deploy config. Sync refuses any tracked or untracked checkout changes both before and after pulling, including nonconflicting changes; resolve or preserve them yourself before retrying. Divergent branches are not forced. Git ignores ambient system/global config and disables hooks and filesystem monitors for its own commands. The fetched repository and any existing checkout (including its local `.git/config`, attributes, and scripts), the configured SSH transport, and executables on `PATH` must still be trusted; do not sync an untrusted repository.

For isolated offline tests only, `HERDR_CONFIG_REPOSITORY` accepts an existing absolute local directory instead of the SSH URL. The installer accepts `HERDR_CONFIG_SOURCE`, `HERDR_UTILITY_SOURCE`, and `HERDR_SKILL_SOURCE` together as regular, non-symlink files from a trusted checkout; without them it downloads all three published files. Do not set these overrides for a normal published install.

## Back up, restore, and reload

`herdr-config backup` captures the current config without syncing or reloading. `herdr-config backup restore` requires `fzf` and displays a selectable table of config backups (name, creation time, size); it snapshots the current config before restoring. Canceling the selector changes nothing. `herdr-config backup --clean` deletes older recognized backups in the backups directory, retaining the newest backup of each kind (config, utility, and skill); a tie for newest leaves the tied backups intact. Cleanup does not touch legacy adjacent backups or unknown files. `herdr-config reload` runs `herdr server reload-config`; it does not sync implicitly.

## Files and safety

The installer places `config.toml` at `${XDG_CONFIG_HOME}/herdr/config.toml` when set and nonempty, otherwise `${HOME}/.config/herdr/config.toml`; the executable is placed at `${HOME}/.local/bin/herdr-config`, and the agent skill at `${HOME}/.agents/skills/herdr-config/SKILL.md`. Runtime state such as `session.json` is not synchronized. Existing regular files get unique `.bak.XXXXXX` backups under `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/backups/` before replacement. Symlinked destination directories, their immediate caller-controlled parents (`HOME`, `XDG_CONFIG_HOME` when used, and `HOME/.local`), or destination files are refused; more distant ancestors and concurrent path replacement are not protected. Sync also checks its checkout, data-home directory, `HOME`, and `HOME/.local` for symlinks, not all ancestors. Failed downloads leave existing files unchanged. If utility or config deployment fails after replacing the skill, the installer rolls back replaced files using their preserved backups (or removes newly created files); if rollback fails, restore manually from the printed backup path. No input prompts are used.

The published install needs `sh`, `curl`, `mktemp`, `mkdir`, `cp`, `chmod`, and `mv`, plus network access to GitHub. The installer refuses symlinked skill destinations and caller-controlled skill directories, and saves replaced skills as `herdr-config-skill.bak.*` under the backups directory. Sync additionally needs `git` and SSH access. Test without network, live config writes, or real SSH hosts using `sh tests/install.sh`, `sh tests/sync.sh`, `sh tests/backup.sh`, and `sh tests/port-forward.sh`; the sync and port-forward tests use fake `herdr` and `ssh` executables.
