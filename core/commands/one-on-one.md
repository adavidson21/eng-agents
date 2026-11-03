---
description: "Draft talking points for a 1:1 from a prep packet (written by Workshop's 1:1s app). Writes draft.md next to it; drafts only. Usage: /one-on-one <path to packet.md>"
agent: people-prep
---

Draft talking points from the 1:1 packet at **$ARGUMENTS**

You draft. The manager decides what to say. You never rate, rank or judge the person, and you never add facts that are not in the packet.

## Step 1: Check the argument

- The argument is the full path to a file named `packet.md`. Workshop's 1:1s app writes it in its own folder, never in the workspace.
- If the argument is empty, or does not end in `packet.md`, stop and reply: `Usage: /one-on-one <path to packet.md>`.
- If the file does not exist, stop and reply: "There is no packet at that path. Start the draft again from 1:1s in Workshop."

## Step 2: Read the packet

- Read `packet.md`. Do not open any other file.
- It has a date, a period, and these sections: Docket tasks (open, waiting on them, nudges due), Receipts (wins, feedback given, growth, notes, and concerns only when the manager chose to include them), Work items (in progress, stale, changed in the period, all open), and Last 1:1 (open follow-ups).
- Note which sections are empty or "Not available".

## Step 3: Write draft.md

- Start from `{{ENG_HOME}}/templates/one-on-one.md`. Write it as `draft.md` in the same folder as `packet.md`. Replace an existing `draft.md`.
- **Wins to recognize:** from Receipts wins and feedback given, and work items that moved forward. One line each: what happened and why it is worth saying out loud. At most 5.
- **Follow-ups from last time:** each open follow-up from Last 1:1, as written, plus Docket tasks waiting on them and nudges due. One line each. Say which source each came from.
- **Blockers to ask about:** stale work items and nudges due, as questions about what is in the way. Never as blame. At most 5.
- **Growth topics:** from Receipts growth lines (and concerns, only if the packet has them), as topics to explore together. At most 3.
- **3 questions to ask:** exactly 3 open questions that follow from the lines above. Not yes or no questions.
- Under each heading, if the packet has nothing for it, write "Nothing in the packet."
- Never add a rating, a ranking, a comparison with other people, or an opinion about the person. Never add a fact, date, number or name that is not in the packet.

## Step 4: Finish

- Reply with one line: "Draft written to `<path to draft.md>`. It is a draft: change anything before the 1:1."
- Do not print the draft again.
