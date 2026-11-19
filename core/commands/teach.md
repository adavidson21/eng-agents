---
description: "Answer a knowledge gap an agent logged, so it is written where it belongs and never asked again. Usage: /teach G<n> <answer>"
agent: writer
---

Answer knowledge gap **$1** with: **$ARGUMENTS**

The answer is everything after the first word. Workshop runs this when the engineer answers a Teach card; nobody else is watching. Ask nothing. Do not change any code.

## Step 1: Find the gap

- Read `.work/gaps.md`. Find the line that starts with `- $1 |`. Its cells are: id, date, kind, product, source, question, assumed, status.
- If there is no such line, reply `Not found: $1.` and stop. If its status is not `open`, reply `Already answered: $1.` and stop.
- If the answer is empty, reply `Give the answer after the id.` and stop.
- Never save secrets, tokens, passwords, connection strings or personal data. If the answer holds any, reply `Not saved: the answer looks like a secret or personal data.` and stop.

## Step 2: Write the answer where it belongs

Write it as one short line in the engineer's words: the question's subject plus the answer (for example `Refunds are capped at the order total.`). Pick the home with the split rule in `AGENTS.md` (Product notes) and the gap's kind:

| Kind | Home |
|---|---|
| `fact` about one product | Its product note, section `Business rules` (or `Gotchas` when it is a trap) |
| `term` | The product note's `Remembered` section as `<business word> means <what the code calls it>`. Mention in your reply that the engineer can add it to Settings, Knowledge, Glossary. With no product: the handbook |
| `process`, or a fact about how the team works | The team handbook, the matching section |
| `repo`, or a fact about one codebase | That repo guide's `## Remembered`, the way `/memory <repo>` does it, then log it in `tandem/changes.md` |

- For a product note or the handbook, read `{{ENG_HOME}}/guides/product-notes.md` and follow it exactly: `Set-ProductNote.ps1` only, `-Source "$1"`. If the product is `-` and the fact is about one product, use the product the gap's source work item belongs to (its `repos.md` and the repo map).
- If product notes are not available, write it to the repo guide (repo kind) or, failing that, keep it only in `gaps.md` (Step 3, where `.work/gaps.md only`).

## Step 3: Close the gap

Run exactly:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/work/Close-Gap.ps1" -WorkRoot ".work" -Id "$1" -Where "<where you wrote it, for example products/sample-portal.md, Business rules>"
```

## Step 4: Reply

In two lines: where the answer now lives, and the line you wrote. If the gap's assumption (`assumed` cell) differs from the answer, add a third line: `The build for <source> assumed "<assumed>". Send it back from Workshop if that changes what it built.`
