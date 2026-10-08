# Herdr config

Install the published config, `herdr-config` utility, agent skill, and repo plugins with one command:

```sh
curl -fsSL https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/install.sh | bash
```

The installer is one brace group, so bash parses all of it before running anything: a failed or truncated download installs nothing.

**Publication caveat:** The remote `main` branch must contain `install.sh`, `config.toml`, `bin/herdr-config`, and `skills/herdr-config/SKILL.md` for this to work. Until this change is published, `sh install.sh` without source overrides fetches the **published** files, not the current checkout. For a local-only installation from this trusted checkout, run:

```sh
HERDR_CONFIG_SOURCE="$PWD/config.toml" HERDR_UTILITY_SOURCE="$PWD/bin/herdr-config" HERDR_SKILL_SOURCE="$PWD/skills/herdr-config/SKILL.md" sh install.sh
```

Run that command from the repository root. Review remote scripts before executing them. Add `$HOME/.local/bin` to your `PATH` if necessary.

After installing the files, the published install runs `herdr-config sync`, which clones the managed checkout and links the repo plugins (see [Plugin registration](#plugin-registration)); it therefore needs the same `git`, `herdr`, and `jq` access as sync. No GitHub account or SSH key is needed. Rerunning the one-liner is safe: it fast-forwards the existing checkout and redeploys the latest config instead of cloning again. If that sync fails, the installer reports that config was installed but sync failed and exits nonzero; fix the cause and rerun `herdr-config sync`. The local-only install above skips sync, so it does not link plugins.

## Shortcuts

| Keys | Action |
| --- | --- |
| `prefix+d` | Detach from Herdr. |
| `prefix+f` | Open the port-forward popup (see [Port forwarding plugin](#port-forwarding-plugin)). |
| `prefix+t` | Open the port-kill popup (see [Port kill plugin](#port-kill-plugin)). Herdr's default `prefix+k` focuses the pane above, so this uses `t` (terminate). |
| `Alt+1` through `Alt+9` | Select the corresponding **tab**, not a numbered pane. |

Your terminal or desktop may intercept Alt-number keys before Herdr sees them. Configure the terminal to send Alt/Meta to applications if the shortcut does not work.

## Port forwarding plugin

`plugins/port-forward` is a Herdr workflow plugin (`elvisgastelum.port-forward`) that manages SSH port forwards from a popup opened with `prefix+f`. The popup lists saved forwards with their status and offers:

- **Add** a remote→local forward (`ssh -L`, a remote port reachable on this host) or a local→remote forward (`ssh -R`, a local port reachable on the remote host). The target is a saved Herdr machine (`herdr machine list`) or a manually entered SSH target; ports are validated.
- **Start** a stopped forward, **stop** a running one, or **remove** one. Stop keeps the saved forward but disables its restore; remove stops a running tunnel and deletes the saved forward.
- **Edit** a forward's target, direction, bind port, or destination; each prompt defaults to the current value. Edit keeps the forward's ID and stopped/started state: a running tunnel is stopped, the new settings are saved, and the tunnel starts again with them. A stopped forward stays stopped. From a shell: `port-forward edit <id> <target> <L|R> <bind_port> <dest_host:dest_port>`.

Enabled forwards are restored by the plugin's startup hook each time the Herdr server starts. Restore runs without prompting and records failures rather than waiting for input.

**Requirements:** `ssh`, `jq`, and `fzf` on the Herdr server host. Tunnels run `ssh -N` with `BatchMode=yes`, so each target needs non-interactive authentication (keys or an SSH agent); a forward that would need a password or host-key confirmation fails instead of prompting. `ExitOnForwardFailure=yes` makes a tunnel exit when its port cannot be bound.

**Where it runs:** plugin commands run on the Herdr server host, not necessarily the terminal you are typing in. With `--remote` or saved machines, forwards start wherever the plugin is installed, and "local" means that host. Saved forward specs live in the plugin config directory (`herdr plugin config-dir elvisgastelum.port-forward`); process IDs and logs live in `$HERDR_PLUGIN_STATE_DIR`. Neither is stored in the checkout, and neither is synchronized.

**Registration:** `herdr-config sync` links this plugin with the other repo plugins; see [Plugin registration](#plugin-registration).

**Limitations:** there is no supervision or automatic reconnect; after a dropped connection, use **Start** again. Start watches a new tunnel for about two seconds, so a forward reported as started can still fail afterwards (for example during authentication); its status in the popup reflects the process actually running.

## Port kill plugin

`plugins/port-kill` is a Herdr workflow plugin (`elvisgastelum.port-kill`) that kills processes listening on network ports from a popup opened with `prefix+t`. The popup lists every listening TCP socket and bound UDP socket with its port, protocol, PID, user, and full command line, sorted by port, with IPv4/IPv6 duplicates shown once. Typing filters by port; `Tab` selects several rows, `Enter` asks for confirmation, `ctrl-r` refreshes the list, and `Esc` closes the popup.

At the prompt, `y` sends `TERM` to each selected process, waits up to three seconds, and reports which exited and which are still alive; `f` does the same and then sends `KILL` to survivors. Anything else cancels. Only the selected PIDs are signalled, and PID 1, PID 0, and the plugin's own process are refused. The same commands work outside the popup: `sh port-kill list [port]` and `sh port-kill kill [--force] <pid>...`.

**Requirements:** `lsof` and `fzf` on the Herdr server host.

**Where it runs:** like every plugin command, on the Herdr server host, so it lists and kills that host's processes. Without root, `lsof` may not show sockets owned by other users, and signalling them fails with a reported error.

**Registration:** `herdr-config sync` links this plugin with the other repo plugins; see [Plugin registration](#plugin-registration).

## Automatic rename plugin

`plugins/automatic-rename` is a vendored fork of [qu8n/herdr-automatic-rename](https://github.com/qu8n/herdr-automatic-rename) at commit `1db6c41` (see `plugins/automatic-rename/UPSTREAM.md`). It names tabs after their directory, branch, SSH host, or running program, and prefixes workspaces and tabs with their jump-key number. Its plugin id is `elvisgastelum.automatic-rename`, so its actions are `elvisgastelum.automatic-rename.reset`, `.doctor`, and `.clear`; the config and state paths keep upstream's `herdr-automatic-rename` directory names. It needs `bash` and `jq`.

**Configuration (optional):** every setting has a default. To toggle features such as `NAME_TABS` or `AUTO_INDEX`, copy `config.example.sh` to `${XDG_CONFIG_HOME:-$HOME/.config}/herdr-automatic-rename/config.sh` (or point `HERDR_AUTOMATIC_RENAME_CONFIG` at another file) and uncomment what you want to change:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-automatic-rename"
cp "${XDG_DATA_HOME:-$HOME/.local/share}/herdr-config/plugins/automatic-rename/config.example.sh" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/herdr-automatic-rename/config.sh"
```

**Shell hooks (optional):** Herdr has no event for a new foreground command, so real-time renaming as each command starts comes from a shell hook. The plugin's own events still handle tab switches, new tabs, agents, and numbering without it. Source the hook for your shell from the managed checkout, which is where sync links the plugin from:

```sh
# ~/.zshrc (use shell/hook.bash in ~/.bashrc, or shell/hook.fish in ~/.config/fish/config.fish)
source "${XDG_DATA_HOME:-$HOME/.local/share}/herdr-config/plugins/automatic-rename/shell/hook.zsh"
```

The hooks do nothing outside a Herdr pane. Upstream's README in `plugins/automatic-rename/README.md` describes the actions, caveats, and uninstall steps; its install and hook paths refer to upstream's GitHub install, not this checkout.

## Plugin registration

`herdr-config sync` links each repo plugin from its managed checkout (`${XDG_DATA_HOME:-$HOME/.local/share}/herdr-config/plugins/<dir>`) with `herdr plugin link --enabled` after deploying config:

| Plugin id | Directory |
| --- | --- |
| `elvisgastelum.port-forward` | `plugins/port-forward` |
| `elvisgastelum.automatic-rename` | `plugins/automatic-rename` |
| `elvisgastelum.port-kill` | `plugins/port-kill` |

Sync needs `herdr` and `jq` on `PATH` for this step. For each plugin it refuses a missing or symlinked plugin directory or manifest and a plugin directory that resolves outside the checkout. If a plugin is already linked from the same path, sync leaves it as is, and prints an enable hint if it is disabled. If its id is registered from another path or installed from GitHub, sync prints where it is registered and leaves it unchanged; to switch to this checkout, run `herdr plugin uninstall <id>` and rerun `herdr-config sync`. If the upstream plugin `herdr-automatic-rename` is still registered, sync warns that it renames the same tabs and prints the command to remove it, but does not remove it. Sync processes every plugin and exits nonzero if any link failed, after config was already deployed; fix the reported cause and rerun sync. To use a plugin from a trusted local checkout instead, run `herdr plugin link "$PWD/plugins/<dir>" --enabled` from the repository root. Plugins execute code from that directory, so link only a checkout you trust.

## Update with the repository

To update the installed configuration, run `herdr-config sync` and, **only if it succeeds**, run `herdr-config reload`. Sync also links the repo plugins; see [Plugin registration](#plugin-registration). Herdr itself has no `herdr sync` subcommand. The installed agent skill at `${HOME}/.agents/skills/herdr-config/SKILL.md` follows this sequence for requests such as “update my herdr config” or “sync herdr config”; it reports errors rather than automatically cleaning backups or pushing changes. Backup and restore remain user-invoked. Sync needs `git` and access to the published `main` branch. When it clones, it first tries `git@github.com:elvisgastelum/herdr-config.git` over SSH without prompting (`BatchMode=yes`). If that fails, for example because no GitHub SSH key or known host is set up, it clones the public `https://github.com/elvisgastelum/herdr-config.git` instead. Git credential prompts are disabled. It clones to `${XDG_DATA_HOME}/herdr-config` (or `${HOME}/.local/share/herdr-config`) if missing; otherwise it checks the checkout root, the `origin` URL (either the SSH or the HTTPS URL above), and the current `main` branch before `git pull --ff-only origin main`. A failed clone or pull does not deploy config. Sync refuses any tracked or untracked checkout changes both before and after pulling, including nonconflicting changes; resolve or preserve them yourself before retrying. Divergent branches are not forced. Git ignores ambient system/global config and disables hooks and filesystem monitors for its own commands. The fetched repository and any existing checkout (including its local `.git/config`, attributes, and scripts), the configured SSH transport, and executables on `PATH` must still be trusted; do not sync an untrusted repository.

For isolated offline tests only, `HERDR_CONFIG_REPOSITORY` accepts an existing absolute local directory instead of the SSH URL. The installer accepts `HERDR_CONFIG_SOURCE`, `HERDR_UTILITY_SOURCE`, and `HERDR_SKILL_SOURCE` together as regular, non-symlink files from a trusted checkout; without them it downloads all three published files. Do not set these overrides for a normal published install.

## Back up, restore, and reload

`herdr-config backup` captures the current config without syncing or reloading. `herdr-config backup restore` requires `fzf` and displays a selectable table of config backups (name, creation time, size); it snapshots the current config before restoring. Canceling the selector changes nothing. `herdr-config backup --clean` deletes older recognized backups in the backups directory, retaining the newest backup of each kind (config, utility, and skill); a tie for newest leaves the tied backups intact. Cleanup does not touch legacy adjacent backups or unknown files. `herdr-config reload` runs `herdr server reload-config`; it does not sync implicitly.

## Files and safety

The installer places `config.toml` at `${XDG_CONFIG_HOME}/herdr/config.toml` when set and nonempty, otherwise `${HOME}/.config/herdr/config.toml`; the executable is placed at `${HOME}/.local/bin/herdr-config`, and the agent skill at `${HOME}/.agents/skills/herdr-config/SKILL.md`. Runtime state such as `session.json` is not synchronized. Existing regular files get unique `.bak.XXXXXX` backups under `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/backups/` before replacement. Symlinked destination directories, their immediate caller-controlled parents (`HOME`, `XDG_CONFIG_HOME` when used, and `HOME/.local`), or destination files are refused; more distant ancestors and concurrent path replacement are not protected. Sync also checks its checkout, data-home directory, `HOME`, and `HOME/.local` for symlinks, not all ancestors. Failed downloads leave existing files unchanged. If utility or config deployment fails after replacing the skill, the installer rolls back replaced files using their preserved backups (or removes newly created files); if rollback fails, restore manually from the printed backup path. No input prompts are used.

The published install needs `bash` (or `sh`), `curl`, `mktemp`, `mkdir`, `cp`, `chmod`, and `mv`, plus network access to GitHub. The installer refuses symlinked skill destinations and caller-controlled skill directories, and saves replaced skills as `herdr-config-skill.bak.*` under the backups directory. Sync additionally needs `git`; GitHub SSH access is optional. Test without network, live config writes, or real SSH hosts using `sh tests/install.sh`, `sh tests/sync.sh`, `sh tests/backup.sh`, `sh tests/port-forward.sh`, and `sh tests/port-kill.sh`; the install test uses a fake `herdr-config sync`, the sync and port-forward tests use fake `herdr` and `ssh` executables, and the port-kill test uses a fake `lsof` that reports only processes it spawns.
