---
name: herdr-config
description: "Trigger: update my herdr config, sync herdr config, back up Herdr config, restore Herdr backup. Manage config sync, reload, and backups safely."
license: Apache-2.0
metadata:
  author: elvisgastelum
  version: "1.0"
---

## Activation Contract

Use this skill when asked to update, sync, refresh, back up, restore, or clean up the installed Herdr configuration.

## Hard Rules

- Herdr itself has no `herdr sync` command. Use `herdr-config sync` instead.
- Run `herdr-config reload` only after sync succeeds; do not reload after an error.
- Never automatically run destructive cleanup (`backup --clean`), restore, or push changes. Backup and restore operations are user-invoked.
- Report command failures and stop rather than hiding them or forcing a checkout update.
- `herdr-config sync` also links every repo plugin (`elvisgastelum.port-forward`, `herdr-automatic-rename`) from its checkout. A sync that deployed config but failed to link any plugin is still a failure: report it and do not reload. If sync reports a plugin is registered elsewhere, relay that and its migration hint; do not uninstall, unlink, or relink it unless the user explicitly asks.
- Never start, stop, add, or remove port forwards, or connect to any host, unless the user explicitly asks.

## Decision Gates

| Request | Action |
| --- | --- |
| Update/sync config | Sync, then reload on success. |
| Backup or restore | Run only the requested `herdr-config backup` or `herdr-config backup restore`; restore needs `fzf`. |
| Cleanup | Run `herdr-config backup --clean` only on explicit request. |

## Execution Steps

1. For an update or sync request, run `herdr-config sync` and inspect its exit status. Only if successful, run `herdr-config reload` and inspect its exit status.
2. For a backup, restore, or explicit cleanup request, run only the requested command from the decision table; never sync or reload implicitly.
3. Report which commands succeeded or failed; do not claim a reload if it failed.

## Output Contract

State the sync and reload results, or the result of the explicitly requested backup operation. Include actionable errors without retrying destructively.
