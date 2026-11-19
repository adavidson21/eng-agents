---
description: "Work with your Cloudflare account through Workshop: look things up, find out why a build failed, or propose changes (DNS, Worker custom domains, Pages projects, variables, rollbacks) for you to approve in Workshop. Never applies anything. Usage: /cloudflare <what you want>, /cloudflare why <worker or Pages project>, /cloudflare cf-<name> check"
agent: investigator
---

Cloudflare request: **$ARGUMENTS**

You work with Cloudflare only through Workshop's tools for agents. Workshop holds the token; you never see it, never ask for it, and never call Cloudflare (or `wrangler`) yourself. You can read everything and **propose** a change set. Only the engineer approves it, in Workshop's Approvals (or an always-allow rule they made there covers it). Read `{{ENG_HOME}}/guides/pipeline.md` first (work folders).

Every call below is one command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/workshop/Invoke-WorkshopTool.ps1" -Connector cloudflare -Action <action> -Arg <name>=<value>
```

Join several arguments with commas (`-Arg zone=example.org,type=CNAME`); leave `-Arg` out when there are none. For change sets, write the JSON to a file and pass `-ArgsFile <path>` instead. The output is JSON, or one line starting with a code:

- `NOWORKSHOP:` Workshop is not running or not installed here. Tell the engineer the line and stop.
- `NOTOOL:` the Cloudflare connector is off, not set up, or off in work mode. Tell the engineer: "Turn on Cloudflare in Workshop's Settings (see its README for the token)." Stop.
- `REFUSED:` Workshop said no and why (a zone not allowed, a bad field, Tandem not allowed). Fix your input if the message says how; otherwise report it and stop.
- `FAILED:` report it and stop.

Read actions: `token.verify`, `zones.list`, `dns.list` (`zone`), `workers.list`, `workers.domains` (`service`), `workers.versions` (`script`), `workers.deployments` (`script`), `workers.builds` (`script`), `workers.buildLog` (`buildId`), `pages.projects`, `pages.project` (`project`), `pages.deployments` (`project`), `pages.deploymentLog` (`project`, `deployment`), `changes.list`, `changes.get` (`id`). Change sets: `changes.check` and `changes.propose`. The kinds of change and their fields are in Step 3.

## Step 1: Pick the mode and the folder

- `why <name>`: **diagnose** mode (Step 5).
- `$1` is a `cf-` folder in `.work/` and `$2` is `check`: **check** mode (Step 6).
- Anything else: **propose** mode (Steps 2 to 4), unless the request is only a question ("which domains does rally use?"): then answer it from reads in Step 2, write `answer.md`, and stop.
- Make `.work/cf-<short-name>/` (3 to 5 lowercase words from the request), unless `$1` names one.

## Step 2: Read what is there now

- Run `zones.list` once. `mayChange: true` marks the zones Workshop allows changes in. A change outside them will be refused: if the request needs one, say so and stop (the engineer adds the zone in Settings, Cloudflare).
- Read only what the request touches: `dns.list` for the zone (with `name` when you know it), `workers.list` and `workers.domains` for a Worker, `pages.projects` or `pages.project` for Pages.
- Note in `plan.md` under **Now** the exact records, domains and settings that matter, with ids.

## Step 3: Write the change set

Write `plan.md` (Request, Now, Changes in plain words, Why, Risk: what breaks if it is wrong and how to undo it) and `propose.json`:

```json
{"title": "<one line, what the engineer will see>", "why": "<one or two sentences>", "item": "<work item id if this came from one, else leave out>", "changes": [ ... ]}
```

Each change is an object with `op`:

| op | Fields |
| --- | --- |
| `dns.create` | `zone`, `type` (A, AAAA, CNAME, TXT, MX), `name` (`@`, `app` or a full name), `content`, optional `proxied`, `ttl` (1 is auto), `comment`, `priority` (MX) |
| `dns.update` | `zone`, `id` (from `dns.list`), any of `name`, `content`, `proxied`, `ttl`, `comment` |
| `dns.delete` | `zone`, `id` |
| `workers.domain.attach` | `hostname`, `service` (the Worker name) |
| `workers.domain.detach` | `hostname` |
| `workers.rollback` | `script`, `versionId` (from `workers.versions`), optional `message` |
| `workers.build.retry` | `script`, `buildId` |
| `pages.create` | `name`, `productionBranch`, optional `repo: {owner, name}`, `buildCommand`, `outputDir`, `rootDir` |
| `pages.domain.add` | `project`, `domain` |
| `pages.env.set` | `project`, `environment` (production or preview), `vars: {NAME: "value" or null to remove}` |
| `pages.rollback`, `pages.retry` | `project`, `deployment` |

Rules:

- The fewest changes that do what was asked. Prefer an update over delete-then-create.
- A Worker on a custom domain needs only `workers.domain.attach`: Cloudflare adds the DNS record. Do not also add one; if a record already uses that name, plan its removal first and say so under Risk.
- Never put a secret in a change (tokens, keys, passwords). Workshop refuses variable names that look like one. If the work needs a secret, write under **For you** in `plan.md`: "Set `<NAME>` yourself in the Cloudflare dashboard as an encrypted variable on `<project>`."
- Nothing deletes a zone, a Worker or a Pages project, and nothing can. If the request needs that, say it is for the engineer to do in the dashboard.

## Step 4: Check, then propose

1. Run `changes.check` with `-ArgsFile` on `check.json`, a file holding `{"changes": [...]}` (the `changes` part of `propose.json`). Every problem comes back at once. Fix `propose.json` and check again, at most 3 times (Core rule 6).
2. Run `changes.propose` with `-ArgsFile ".work/cf-<name>/propose.json"`. Write the `id` it returns at the top of `plan.md` as `Change set: <id>`, with `Approval: <approval.id>` and `Status: WAITING`. If it returns `status: applied`, an always-allow rule applied it: write `Status: APPLIED` and go to Step 6, item 3.
3. Reply with the steps it returned (they are what the engineer will see), then: "Approve it in Workshop: Settings, Manager, Approvals (Needs you links there). Then run `/cloudflare cf-<name> check`." Stop. Do not wait or poll.

## Step 5: Diagnose (`why <name>`)

1. Find it: `workers.list`, else `pages.projects`. If neither has it, say so and stop.
2. Worker: `workers.builds` (`script`), take the newest failed build, then `workers.buildLog` (`buildId`). Pages: `pages.deployments` (`project`), the newest with status `failure`, then `pages.deploymentLog`.
3. Write `findings.md`: what failed (quote at most 10 log lines), **Probable cause** labeled Confirmed or Suspected (core investigator rules), and **Fix**:
   - Fixed by a change in the repo (build command, a missing file, config): say exactly what and where, with the repo guide read first. Do not change code. End with the command to start it, for example `/start new bug <one line>`.
   - Fixed on Cloudflare (a retry after a flaky failure, a rollback while the fix is made, a variable): propose it with Steps 3 and 4 in the same folder.
4. Reply with the probable cause and the next command. Stop.

## Step 6: Check (`cf-<name> check`)

1. Read `plan.md` for the change set id. Run `changes.get` with it.
2. `waiting`: say "Still waiting for you to approve it in Workshop's Approvals." Stop. `rejected`: write `Status: REJECTED` (with the note, if any) in `plan.md` and stop.
3. `applied` or `failed`: for each result, read back what it changed (`dns.list`, `workers.domains`, `pages.project`) and confirm it is there. Write `result.md`: each step as Done, Failed (with the error) or Skipped, and what you saw. Set `Status: APPLIED` or `Status: FAILED` in `plan.md`.
4. If it failed, say why in one line and offer a new change set for what is left (Steps 3 and 4). New domains can take a few minutes for their certificate: say so rather than calling it a failure.
