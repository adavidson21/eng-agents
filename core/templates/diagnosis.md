# Spike findings: <the error in a few words, for example "Timeout calling the eligibility API">

Date: <yyyy-mm-dd>
Asked by: <who pasted the log: "me", or their role>
Kind: Error log
Fix type: <Configuration | Data | Infrastructure | Code>
Confidence: <High | Medium | Low>

<!--
Written by /spike in log mode from log.md in this folder. Loom reads the "# Spike findings:" title,
the Fix type line, and the Short answer, Recommendation and Next step sections, so keep their shapes.
Never copy a secret, token, password, connection string or personal data from the log into this file: name it
("the connection string in appsettings.Production.json") instead.
-->

## Short answer

<One or two sentences: what broke, the probable root cause, and the fix in plain words.>

## The error

- **Message:** <the exception type and message, as logged>
- **Where:** <service, environment, and the first frame in our code, `repo/path/File.cs:line`>
- **When:** <timestamps or frequency from the log, or "one occurrence">
- **Correlation:** <request id, user-facing operation, or "none in the log">

## Probable root cause

<The cause in two or three sentences.> **Confidence:** <High | Medium | Low>

## Why

<!-- The chain from the log line to the cause. Each step is Confirmed (file:line, config value, commit, or command output) or Suspected (why you think so). -->

1. **Confirmed:** <the log line, and the code that throws it, `file:line`>
2. **Confirmed:** <what that code reads or calls: a setting, a dependency, a data shape>
3. **Suspected:** <what is wrong with it, and why you think so>

## Solution

**Fix type:** <Configuration | Data | Infrastructure | Code>

<!-- Prefer a fix that changes no code: a setting, a feature flag, an environment variable, a connection or timeout value, data, or infrastructure. Give a code fix only when nothing else fixes the cause, and say why. -->

- **Change:** <the setting or thing to change, by name>
- **Where:** <the file (`repo/path/appsettings.Production.json`), the environment variable, the pipeline or release variable, the portal or service>
- **From → to:** <the current value, if you could read it, and the value to set; never a secret>
- **Roll out:** <restart, redeploy, cache flush, or nothing>
- **Verify:** <the log line that should stop, or the check that should pass>

## If this is not it

- <The next most likely cause, and the one check that tells them apart.>

## Recommendation

<What to do now, in one or two sentences. For a configuration fix: who applies it and where. For a code fix: start Fix a bug from these findings.>

## Next step

<For example: "Set Eligibility:TimeoutSeconds to 30 in the production App Service settings, then close this in Loom." or "Fix a bug from these findings: `/start new bug` with this folder.">

## Sources

- <Every file, commit, config file and doc you used.>
