# Upstream

This directory is a vendored fork of [qu8n/herdr-automatic-rename](https://github.com/qu8n/herdr-automatic-rename), copied at commit `1db6c41b208b2b28b8e8784b79425e3f7177efa2` (plugin version 0.13.0) under its MIT license (see `LICENSE`).

Only the runtime files, shell hooks, license, and docs were copied. Upstream's installer, tests, CI, and tooling were left out. The plugin id is changed to `elvisgastelum.automatic-rename` in `herdr-plugin.toml` (action ids such as `elvisgastelum.automatic-rename.reset` follow it). The config path (`~/.config/herdr-automatic-rename/config.sh`) and state directory (`~/.local/state/herdr-automatic-rename/`) keep upstream's names.

Make local changes here directly. To pick up upstream changes, diff against a newer upstream commit, apply what you want, and update the commit above.
