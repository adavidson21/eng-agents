# Stacks

One file per tech stack: its testing rules and its review checklist items. A repo guide names its stacks on a `Stack:` line (for example `Stack: dotnet, angular`); `/plan`, `/tasks`, `/do-task` and `/review` read the matching files from `{{ENG_HOME}}/stacks/`.

Core ships `dotnet`, `angular` and `playwright`. Add a stack in the Personal or Company layer as `stacks/<name>.md` with the same two sections, `## Testing` and `## Review checklist`; a file with the same name replaces Core's. Use lower-case names with no spaces.

A repo guide without a `Stack:` line (written before Core 3.0.0) reads every stack file, and agents say so once, so no rules are silently lost. Run `/onboard-repo <repo>` to add the line.
