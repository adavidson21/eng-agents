# Shell API

A *shell* is another web page that shows the live dashboard and work item stages, such as [Workshop](https://github.com/adavidson21/workshop). This is the contract between the live dashboard and a shell. The live dashboard owns it; a change that breaks it bumps `api` and gets a Dashboard changelog entry.

Current version: **`api: 1`** (Dashboard 1.6.0 and later).

## Allowing a shell

Off by default. The live dashboard answers a shell only when its origin is listed:

```json
"dashboard": { "shellOrigins": ["https://adavidson21.github.io"] }
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

## Code review

Dispatch's review screen reads a branch's diff and sends the reviewer's verdict back. Same origin allowlist and CORS as the rest of the shell API. Added in Dashboard 1.8.0; additive, so `api` stays `1`.

There is one review per work item and repo, matching Push PR. `repo` is the repo folder name from the item's `pr.md` (the same value `/api/push` takes). A shell shows a repo switcher when an item has more than one. `<id>` is the work item number, or `L<number>` for a local item.

### Types

```ts
type ReviewSession = {
  workItemId: string;
  repo: string;              // repo folder from pr.md
  revision: number;          // 1, 2, 3...
  branch: string;
  baseBranch: string;        // origin/<target> if the clone has it, else <target>
  baseSha: string;           // merge-base of baseBranch and the branch head
  headSha: string;
  status: 'awaiting_review' | 'revising' | 'approved';
  files: ChangedFile[];
  previousFeedback?: ReviewFeedback;   // revision 2 and later
  previousResponses?: ReviewResponse[]; // the agent's answers to previousFeedback, when it wrote them
  sinceLastReview?: ChangedFile[];      // files changed from previousFeedback.headSha to headSha
  revisionRun?: RevisionRun;            // the latest revision the agent ran for this review
};

type RevisionRun = {
  status: 'running' | 'failed' | 'done';
  message: string | null;    // plain words; for 'failed', what the engineer should do
  session: string | null;    // the opencode session, for opening it in the dashboard
  revision: number;          // the revision whose feedback it is addressing
};

type ReviewResponse = {
  commentId: string;
  status: 'fixed' | 'declined' | 'answered';
  note: string;
};

type ChangedFile = {
  path: string;
  oldPath?: string;          // renames
  status: 'added' | 'modified' | 'deleted' | 'renamed';
  additions: number;
  deletions: number;
  binary: boolean;
};

type ReviewComment = {
  id: string;
  path: string;
  side: 'old' | 'new';
  startLine: number;
  endLine: number;
  quotedCode: string;        // the lines at baseSha (old) or headSha (new)
  type: 'must_fix' | 'suggestion' | 'question';
  body: string;
  suggestedCode?: string;
};

type ReviewFeedback = {
  workItemId: string;
  repo: string;
  revision: number;
  headSha: string;
  verdict: 'approve' | 'request_changes';
  summary?: string;
  comments: ReviewComment[];
  submittedAt: string;       // set by the server when it saves
};

type FileContent = {
  kind: 'text' | 'binary' | 'too_large' | 'absent';
  text?: string;             // kind 'text' only
  size?: number;             // bytes, for 'binary' and 'too_large'
};
```

### `GET /api/shell/code-review/<id>?repo=<repo>`

Returns the `ReviewSession`. A review is available once the item reaches the `pr` stage (the step before Push PR), and from then on whatever stage it shows.

- 409 `{ "error", "status": "not_ready", "stage" }`: the item is not at the `pr` stage yet, or `pr.md` has no section for `repo`.
- 409 `{ "error" }`: the branch, target, or merge-base cannot be found.

### `GET /api/shell/code-review/<id>/file?repo=<repo>&path=<path>&side=old|new|prev`

Returns `FileContent`. `old` reads the file at `baseSha`, `new` at `headSha`, and `prev` at the last reviewed head (`previousFeedback.headSha`, revision 2 and later; 400 on revision 1). For a renamed file, pass `oldPath` with `side=old`. Monaco computes the diff in the browser.

"Changes since last review" diffs `prev` against `new` for the files in `sinceLastReview`. Comments made in that view go on the `new` side, since `ReviewComment.side` only names `baseSha` or `headSha`.

- `absent`: the file does not exist on that side (the old side of an added file, the new side of a deleted one).
- `binary` or `too_large` (over 1 MB): no `text`, just `size`.

### `POST /api/shell/code-review/<id>/submit?repo=<repo>`

Body: `ReviewFeedback`. Returns `{ "ok": true, "status", "revision", "submittedAt" }`.

- `approve`: saves the verdict and sets the status to `approved`. Nothing is pushed.
- `request_changes`: saves the feedback, sets the status to `revising`, and starts the revision. Needs at least one comment or a summary.
- 503: request changes while the agent cannot start a revision (opencode not connected). Nothing is saved.

Errors:

- 400: the body does not match the types, or its `workItemId` or `repo` does not match the URL.
- 409 `{ "error", "status", "headSha" }`: the branch head moved since the review loaded. Nothing is saved. Reload the review.
- 409 `{ "error", "status", "revision" }`: wrong revision number.
- 409 `{ "error", "status" }`: the review is not awaiting a verdict (already `revising` or `approved`).

### Storage

Per work item and repo, in `.work/<folder>/code-review/<repo>/`:

| File | Contents |
| --- | --- |
| `state.json` | `{ revision, status, lastReviewedHeadSha }`. Missing means revision 1, awaiting review. |
| `rev-<n>.json` | The `ReviewFeedback` submitted for revision `n`. |
| `rev-<n>-response.json` | The agent's `ReviewResponse[]` for revision `n`. |
| `run.json` | The latest revision run: `{ revision, branch, session, status, message, startedAt, updatedAt }`. |

Inside the server, a request changes verdict emits `changes-requested` (and approve emits `approved`) on the code review module's `events`, with `{ workItemId, folder, repo, repoDir, branch, revision, feedback }`.

### Revision runner

`server/revision-runner.mjs` handles `changes-requested`:

1. Builds the revision prompt (the template in the spec, plus the repo folder) and sends it through the same opencode launcher the page uses: the item's current session when it is idle, so the agent keeps its context, else a new session linked to the item.
2. When that session's turn ends, it checks that `rev-<n>-response.json` exists and is valid, and that the branch still contains the reviewed commit (no rewritten history).
3. If both hold, it sets revision `n+1`, status `awaiting_review`, and emits `revision-ready`. If not, the review stays `revising` and `revisionRun` is `failed` with the reason. Replying to the agent in that session runs the checks again when its turn ends.

Unfinished runs are picked up again after a restart.
