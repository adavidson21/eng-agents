# Triage: item-count Show item count before paying

## Summary

Customers want the number of items in their order on the summary before they pay.

## Products and repos

- sample-api: `OrderTotals` would gain an item count.

## Related items

None found.

## What is clear

Count means the sum of quantities across lines.

## Questions for the requester

- Should an empty order show 0?

## Message to the requester

Thanks, this looks small: we can add an item count to the order summary. One question: should an empty order show 0?

## Suggested route

Quick lane, one engineer, sample-api only.

## Next step

`/quick` once the question is answered.
