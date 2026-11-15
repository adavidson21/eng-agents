# Progress: <id> <title>

Append a new entry at the bottom after every command. Never edit or delete old entries.

---

## <yyyy-mm-dd> | /<command> | <agent>

- Did: <one or two lines>
- Files changed: <list, or "none">
- Verify: `<command>` -> <PASS | FAIL | not run>
- Output (last lines):
  ```
  <paste the last 10 to 20 lines of real output>
  ```
- Red run (`/do-task` on .NET code only: the verify run BEFORE the code change, showing the new test failing):
  ```
  <last 10 to 20 lines, including the failing test name and the assertion or exception>
  ```
- Green run (`/do-task` on .NET code only: the same verify command AFTER the change; can be the Output block above):
  ```
  <last 10 to 20 lines>
  ```
- Manual validation (`/do-task` only, skip if blocked):
  1. Open <exact URL or file path>
  2. <exact physical action: click 'X', type 'Y', or run 'Z'>
  3. Verify <exact visual or terminal result>
- Stats: <key=value pairs the command asks for, for example `questions=1 assumptions=2` or `verify=PASS full=PASS attempts=1`. Leave the line out if the command asks for none.>
- Notes: <problems, things found out of scope, or "none">
- Next: `<exact next command>`
