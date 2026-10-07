---
description: "Draft a technical spec document (TSD) with Mermaid diagrams for a product or repos. Usage: /tsd <product or repo folder> [repo folder ...]"
agent: writer
---

Draft a technical spec for: **$ARGUMENTS**

The diagrams carry the design: context, containers, database schema, key flows, business processes, deployment. Text only explains what a diagram cannot show. Do not change any code.

## Step 1: Pick the scope

- Read the repo map (the workspace root `AGENTS.md`).
- **Product:** if the arguments match a product heading or an "Also called" name in the repo map's **Products** section, the scope is every repo in that product's repo table. The name is the product name.
- **Repos:** otherwise, every argument must be a repo folder in the workspace root. If one is not, stop and reply with the usage line and the product names from the repo map.
  - Find every product whose repo table lists one of these repos. If that product lists other repos, ask: "`<repo>` belongs to `<product>`, which also uses `<other repos>`. Include them? (Recommended: yes, so cross-repo links are drawn.)" Wait.
  - The name is the product name if exactly one product matched, otherwise the first repo folder.
- Show the engineer the final list: each repo folder with its one-line role from the repo map. Ask: "Is this the right scope?" Wait and apply changes.
- The work folder is `.work/tsd-<short-name>/`. `<short-name>` is the name in lowercase, spaces replaced by hyphens, at most 40 characters.
- If `.work/tsd-<short-name>/tsd.md` already exists, read its `Status:` line:
  - `Status: APPROVED`: stop. Tell the engineer it is approved and suggest `/publish tsd-<short-name>`. To revise it, they change the line back to `Status: DRAFT` and run `/tsd` again.
  - `Status: PUBLISHED`: the line names where it was published. Read that published file. It is the base for this update, because the engineer may have edited it there.
  - `Status: DRAFT`: read it.
- If a TSD exists, ask: "A TSD already exists here. Update it (keeps your edits, refreshes facts from the code) or start over? (Recommended: update.)" Wait. To update, read `inventory.md` too, and keep any text the engineer wrote unless the code now contradicts it.

## Step 2: Read the guides

- For each repo in scope, read its repo guide (`AGENTS.local.md` or `AGENTS.md`). If a repo has neither, stop and tell the engineer to run `/onboard-repo <repo>` first.
- From the product block in the repo map, note "Entry points", "External systems", "Business processes", and "Product docs". If a product docs folder is listed, read its `overview.md`, or its first markdown file if there is no overview.
- Read `{{ENG_HOME}}/templates/tsd-diagrams.md` completely. Every diagram you draw must follow it.

## Step 3: Build the inventory

Copy `{{ENG_HOME}}/templates/tsd-inventory.md` into the work folder as `inventory.md`. Fill in one section at a time and save after each one.

Rules for this step:
- Every row needs a source file path. If you cannot point to a file, do not write the row.
- **Never open** `appsettings*.json`, `*.config` files (including `web.config`), `*.pubxml`, `secrets.json`, or `.env` files. They can hold secrets. Find configuration **key names** in code instead (`GetConnectionString("...")`, `GetSection("...")`, options classes).
- Read about 40 files in total for this step. If you reach that, write "Inventory stopped at <section>" under Notes and continue with what you have.

Where to look, section by section. Use `Select-String` or `rg` to search, then read only the files that match.

| Section | Search for |
|---|---|
| Deployables | `*.csproj` files containing `Microsoft.NET.Sdk.Web` or `Microsoft.NET.Sdk.Worker`, `host.json` (Azure Functions), `angular.json` projects |
| Data stores | Classes that inherit `DbContext`, `UseSqlServer`, `UseNpgsql`, `UseSqlite`, `UseCosmos`, `GetConnectionString(` |
| Entities | First choice: the migrations `*ModelSnapshot.cs` for each DbContext (`b.Entity`, `ToTable`, `HasKey`, `HasOne`, `WithMany`, `IsRequired`). Otherwise the `DbSet<>` properties, `IEntityTypeConfiguration<>` classes, and the entity classes. At most 12 entities per DbContext in the diagram; if there are more, ask the engineer which area matters most. |
| External systems | `AddHttpClient`, `HttpClient`, `BaseAddress`, `ServiceBus`, `MassTransit`, `RabbitMQ`, `Kafka`, `SmtpClient`, `SendGrid`, `BlobServiceClient`, `SftpClient`, `ServiceReference`. In Angular: services that inject `HttpClient`, and `environment` key names. Also the product block's "External systems" line. |
| Entry points | `[ApiController]`, `[Route(`, `MapGet`, `MapPost`, `MapPut`, `MapDelete`, Angular `Routes`. Also the product block's "Entry points" line. |
| Background work | `BackgroundService`, `IHostedService`, `Hangfire`, `Quartz`, `[Function(`, `[FunctionName(`, `TimerTrigger` |
| Links between repos | The repo map's dependency table, `ProjectReference` paths that start with `..`, and UI code that calls an API |
| Auth | `AddAuthentication`, `AddJwtBearer`, `AddOpenIdConnect`, `[Authorize`, Angular `HttpInterceptor` and route guards |
| Status fields | Enum properties named `Status` or `State` on entities, their values, and the code that sets them |
| Deployment files | `azure-pipelines*.yml`, other `*.yml` under a `pipelines` or `.azuredevops` folder, `Dockerfile`, `docker-compose*.yml`, `*.bicep`, `*.tf`, Helm `Chart.yaml`. Read stage names, job names, and task names only. Ignore variable values. For `web.config`, only check that it exists (`Test-Path`): it means IIS hosting. |

## Step 4: Pick the flows and processes

- Under "Candidates" in `inventory.md`, list up to 8 **flows** (a request or job worth a sequence diagram, with its entry point) and up to 5 **business processes** (a lifecycle across people and systems, usually a status field plus the product block's "Business processes"). Number them.
- Ask: "Which flows should get a sequence diagram? Pick 3 to 5 numbers. (Recommended: <your picks and one reason>.)" Wait.
- Ask: "Which business processes should get a BPMN-style diagram? Pick 1 to 3 numbers, or none. (Recommended: <your picks>.)" Wait.
- Write the picks into `inventory.md`.
- For each pick, trace the code path from the entry point to the database or external call. Read at most 8 files per pick. Write each step into "Traced flows" with its source file.

## Step 5: Write tsd.md

- Start from `{{ENG_HOME}}/templates/tsd.md`. Write it to the work folder as `tsd.md`.
- Keep `Status: DRAFT`. Never set it to `APPROVED`. When updating a published TSD, set it back to `Status: DRAFT`.
- Write one section at a time, in template order, and save after each one.
- Replace each `<Diagram: ...>` placeholder with a Mermaid block drawn from that section of `tsd-diagrams.md`. Copy the example's structure, shapes, and `classDef` lines. Change only names and labels.
- Draw only what is in `inventory.md`. If something seems to be missing, do not draw it. Add it to "Open questions".
- Delete sections that do not apply:
  - No DbContext: delete "Data model".
  - No business process picked: delete "Business processes".
  - No deployment files: keep the heading, write the one sentence from the template, and add an open question.
- Fill the table under every diagram. Every element in the diagram has a row or appears in the inventory.

## Step 6: Check the diagrams

Run exactly this command:

```
{{PS}} -NoProfile -ExecutionPolicy Bypass -File "{{ENG_HOME}}/scripts/diagrams/Test-Mermaid.ps1" -Path ".work/tsd-<short-name>/tsd.md"
```

Read the last line of the output:

- `RESULT: PASS`: go to Step 7.
- `RESULT: FAIL`: for each `FAIL` block, read the error and the file line it points to. Find the error in the "Common errors" table in `tsd-diagrams.md` and fix **only that block**. Run the command again. After 3 failed runs, stop fixing: list the failing blocks under "Open questions" and tell the engineer.
- `RESULT: SKIPPED`: mermaid-cli is not installed, so nothing was rendered. Go through "Check before you finish" in `tsd-diagrams.md` for every block and fix what you find. Tell the engineer in Step 8 that the diagrams were not render-tested.

## Step 7: Save sources for the fact check

- Write `sources.md` in the work folder as a table: claim, source file. Add one row per diagram listing every file its elements came from, and one row per factual sentence outside the diagrams.

## Step 8: Hand off

Tell the engineer:
- The path to `tsd.md` and the result line from Step 6.
- If it passed: "SVG copies of every diagram are in `.work/tsd-<short-name>/render/`. Use them if your doc editor does not render Mermaid."
- Every open question, one line each.
- The next steps, exactly:
  1. "Start a new session and run `/check-docs .work/tsd-<short-name>/tsd.md` to fact-check every diagram against the code."
  2. "Fix what it finds: edit `tsd.md` yourself, or run `/tsd` again and choose update."
  3. "When it is correct, run `/publish tsd-<short-name>`. That approves it and moves it into the product docs folder."
