# Changelog

Core and the dashboard have their own versions (`core/VERSION`, `core/scripts/dashboard/VERSION`), so the dashboard can be updated on its own. `update.ps1` and the live dashboard read this file to show what is new.

Format: one `## Core <version> (<date>)` or `## Dashboard <version> (<date>)` heading per release, newest first, with one `- ` line per change. Bump the version in the same pull request.

## Dashboard 1.5.1 (2026-10-15)

- The shell API (`/api/shell/status`) also sends each item's next step in plain words (`next.text`) and whether autopilot is running or needs you (`autopilot`), so Prioritizer can show them.

## Dashboard 1.5.0 (2026-10-15)

- `Start-LiveDashboard.ps1 -Detach`: starts the live dashboard in its own minimized window and returns once it answers, or opens it if it is already running.
- The live dashboard keeps `.work/dashboard.html` current, so after a restart that file shows where everything stood.
- The static page shows whether the live dashboard is running, with **Open live dashboard** or how to start it.

## Core 2.1.0 (2026-10-15)

- `/dashboard` opens the live dashboard, starting it if needed, and falls back to the static page. `/dashboard static` builds the static page.

## Dashboard 1.4.0 (2026-10-15)

- One main button per step. The Next line says the step in plain words ("Task 3: Update invoice totals") and offers **Approve and build** or **Build with autopilot** when autopilot can take over, otherwise **Run**, **Approve**, or **Resume**. The command is in the tooltip.
- The autopilot box only shows while autopilot is running or needs you.
- No terminal hints in the live dashboard ("then /approve", "After approval: /tasks", Copy buttons). The static page keeps them.
- Simpler header: one status pill, Update available only when there is one, and a More menu for Refresh, alerts, the TUI, the terminal command, and Check for updates.
- The group count chips only show when there are more than 8 items.

## Dashboard 1.3.0 (2026-10-15)

- Push button on PR cards in the live dashboard: runs `git -C <repo> push -u origin <branch>` for the branch named in `pr.md`. The click is the approval, so there is no separate prompt. It never pushes `main`, `master`, `develop`, `dev`, or the PR's target branch, and never force pushes. Git errors (for example, a sign-in failure) show in the toast and the server log.

## Dashboard 1.2.1 (2026-10-14)

- The item in Pick up here is no longer shown again as a full card in its group. The group shows a one-line pointer to it instead.
- Pick up here has its own Abandon button.

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
