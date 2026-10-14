# Changelog

Core and the dashboard have their own versions (`core/VERSION`, `core/scripts/dashboard/VERSION`), so the dashboard can be updated on its own. `update.ps1` and the live dashboard read this file to show what is new.

Format: one `## Core <version> (<date>)` or `## Dashboard <version> (<date>)` heading per release, newest first, with one `- ` line per change. Bump the version in the same pull request.

## Dashboard 1.2.0 (2026-10-14)

- Abandon or remove an item from the live dashboard: type the item id to confirm, and its `.work` folder, sessions, and autopilot state are deleted. Repos and branches are left alone; the dialog lists work still in them and the commands to delete the branches.
- Ready to ship items show the PR text from `pr.md` per repo, with copy buttons for the title and description, a Create PR in ADO button, and the push command when a branch is not pushed yet.
- Recent activity is one line per item per day ("Did 3 tasks, reviewed, wrote PR text") instead of every log entry.
- Clearer track: finished stages are checked, the current stage is a filled label with what is happening under it, later stages are faint.

## Dashboard 1.1.0 (2026-10-13)

- Shows inside a shell app: sites listed in `config.json` under `dashboard.shellOrigins` can embed the live dashboard and read each work item's stage. Prioritizer uses this for its Dashboard view and task badges.
- `/api/shell/start` starts a work item (`/start <id> <lane>`) from a listed shell, in a new opencode session.
- The page can only be framed by itself and listed shells.
- Themes now come from Prioritizer's `themes.css` (`sync-themes.mjs`). Adds Solarized Light, Nord, and Dracula, and a warn color for each theme.
- `Start-LiveDashboard.ps1 -ShellOrigin <url>` for a one-off shell without editing `config.json`.

## Dashboard 1.0.0 (2026-10-13)

- First versioned release of the live dashboard.
- New look: Slate, Graphite, Ivory, and Rosé themes, or follow the system setting. Pick one from the theme button in the header.
- Update notice: the live dashboard checks for updates and shows "Update available" in the header. Update the dashboard from the page; it restarts itself.
- Shows the installed dashboard version in the header.

## Core 2.0.0 (2026-10-13)

- Versioned installs. `install.ps1` records the version, source repo, commit, and overridden files in the manifest.
- `update.ps1`: pulls, shows what is new, warns (with diffs) when Core changed a file you override, then reinstalls.
- `install.ps1 -Component dashboard` and `update.ps1 -Component dashboard` update only the dashboard.
