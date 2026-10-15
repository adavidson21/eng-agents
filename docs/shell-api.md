# Shell API

A *shell* is another web page that shows the live dashboard and work item stages, such as the [EM Hub](https://github.com/adavidson21/prioritizer). This is the contract between the live dashboard and a shell. The live dashboard owns it; a change that breaks it bumps `api` and gets a Dashboard changelog entry.

Current version: **`api: 1`** (Dashboard 1.6.0).

## Allowing a shell

Off by default. The live dashboard answers a shell only when its origin is listed:

```json
"dashboard": { "shellOrigins": ["https://em.alexisdavidson.org"] }
```

in `~/.config/eng-agents/config.json`, or with `--shell-origin <url>` (repeatable). Origins must be `https://`, or `http://localhost` / `http://127.0.0.1` for testing. Restart the live dashboard after a change.

The server checks the `Origin` header on every `/api/shell/*` request (browsers cannot fake it) and only lets listed origins put the page in a frame (`frame-ancestors`). It listens on `127.0.0.1` only and rejects other `Host` headers.

## HTTP

Base: `http://127.0.0.1:<port>` (default port 4300). Send `targetAddressSpace: "loopback"` with `fetch` so Chrome's local network access prompt works. Errors are `{ "error": "<plain words>" }` with a 4xx or 5xx status.

### `GET /api/shell/status`

```json
{
  "app": "eng-agents-dashboard",
  "api": 1,
  "version": "1.6.0",
  "workspace": "work",
  "opencode": { "connected": true, "error": null },
  "error": null,
  "items": [
    {
      "id": "123",
      "title": "Fix login",
      "lane": "bug",
      "stage": "build",
      "bucket": "active",
      "next": { "command": "/do-task 123 3", "action": null, "text": "Task 3: Add test", "needsYou": false },
      "tasks": { "done": 2, "total": 5 },
      "paused": false,
      "blocked": false,
      "agent": "busy",
      "waiting": false,
      "autopilot": null
    }
  ],
  "starting": [ { "id": "456", "agent": "busy", "waiting": false, "error": null } ]
}
```

- `app` is always `eng-agents-dashboard`; check it to be sure the right thing answered.
- `items` has one row per numbered work item in `.work`. `stage` is one of `start`, `spec`, `plan`, `bug`, `tasks`, `build`, `review`, `pr`, `ship`.
- `next.text` is the next step in plain words. Show it instead of the command. The wording comes from `New-Dashboard.ps1` (`stepWords`), the one place it is defined.
- `next.needsYou`: the engineer has to act (approve, answer review findings).
- `agent`: `busy`, `idle`, or `null` (no session yet). `waiting`: an agent is asking a question or for permission.
- `autopilot`: `null`, or `{ "status": "running" | "waiting", "message" }`.
- `starting`: work items started from a shell whose `.work` folder does not exist yet.

### `POST /api/shell/start`

Body: `{ "id": "456", "lane": "feature" }` (`lane` is `feature` or `bug`). Runs `/start <id> <lane>` in a new opencode session. Returns `{ "session": "<id>" }`. Fails with 409 if the item is already started or starting, 503 if opencode is not connected.

## Frame messages

A shell shows the dashboard page in a frame at `/?embed=1`. All messages use `postMessage` with an explicit target origin; both sides ignore messages from any other window or origin.

| Direction | Message | Meaning |
| --- | --- | --- |
| dashboard to shell | `{ "type": "eng-ready" }` | The page loaded and listens. Send theme and focus after this. |
| shell to dashboard | `{ "type": "eng-theme", "theme": "<key>" }` | Use this theme (a key from the shared `themes.css`, such as `slate` or `nord`). Unknown keys fall back to the system theme. |
| shell to dashboard | `{ "type": "eng-focus", "id": "<work item id>" }` | Scroll to that item and highlight it. |

Embedded, the page hides its own theme menu.
