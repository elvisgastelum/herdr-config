# Herdr config

Install the published `config.toml` on another machine with one command that verifies the installer download succeeded before running it:

```sh
(tmp=$(mktemp) && curl -fsSL -o "$tmp" https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/install.sh && sh "$tmp"; status=$?; [ -z "${tmp:-}" ] || rm -f "$tmp"; exit "$status")
```

**Publication caveat:** This URL works only after this repository and its `main` branch are published at `elvisgastelum/herdr-config`. Until then, run the local installer with `sh install.sh` from this checkout. Review remote scripts before executing them.

The shorter `curl -fsSL https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/install.sh | sh` also runs the installer, but POSIX `sh` reports the status of `sh` rather than `curl`: a failed installer download can appear successful. Prefer the command above.

## What it installs

Only `config.toml` is downloaded, from the same `main` branch as the installer. It goes to `${XDG_CONFIG_HOME}/herdr/config.toml` when `XDG_CONFIG_HOME` is set and nonempty, otherwise `${HOME}/.config/herdr/config.toml`. Runtime state such as `session.json` is not synchronized. The `odd/` task notes remain local and ignored by Git.

The installer needs `sh`, `curl`, `mktemp`, `mkdir`, `cp`, and `mv`, plus network access to GitHub for the published install. It reads no arguments or prompts from piped stdin. Tests replace `curl` with an offline fixture.

## Update safely

1. Review the published `config.toml` and installer before running the command again.
2. Run the same install command. A successful download is staged in the destination directory; a failed download leaves the current config unchanged.
3. If a regular config already exists, the installer first saves it alongside the destination as `config.toml.bak.XXXXXX` (a unique name on each update). Symlinked `herdr` directories and `config.toml` files are refused before a backup or download is staged. Keep the backup until the updated configuration works. To roll back, copy the desired backup over `config.toml` at the same location.

Run the isolated tests locally with `sh tests/install.sh`. They do not access the network or your live Herdr configuration.
