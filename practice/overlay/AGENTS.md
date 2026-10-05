<!--
PRACTICE COMPANY OVERLAY. Used only for the practice run, to test that a third layer installs and wins over the others.
Install with: pwsh ./install.ps1 -Company ./practice/overlay
-->

## Company-wide engineering rules (practice)

- Never log personal or payment data. Log order IDs, not customer details.
- New public API fields use camelCase in JSON. Do not rename existing fields.
- Every pricing rule change needs a unit test that pins the exact amounts.
