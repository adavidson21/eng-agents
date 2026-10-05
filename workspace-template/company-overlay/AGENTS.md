<!--
COMPANY OVERLAY. Copy the whole company-overlay folder to %USERPROFILE%\.config\eng-agents\overlay\
This is COMPANY content. It lives on the work PC only. Never commit it to eng-agents.

Use this file for rules that apply to EVERY repo at work. Repo-specific rules go in each repo's AGENTS.md.
install.ps1 appends this as the last section, so it overrides Core and Personal.

Lines marked SAMPLE are starting points. TODO(you) lines need your input. Delete this comment when done.
-->

## Company-wide engineering rules

- SAMPLE: Never log personal, health, or financial data. Log IDs, not values.
- SAMPLE: Every new API endpoint requires an authorization attribute. Copy the attribute style from existing endpoints in the same controller.
- SAMPLE: Configuration values come from the existing options classes. Never hard-code URLs, keys, or environment names.
- TODO(you): Add your team's coding standards, or point to them: "Read `<repo>/docs/standards.md` before writing code." (or delete this line)

## Team conventions that differ from Core

- SAMPLE: (Delete this section if Core conventions already match your team.)
