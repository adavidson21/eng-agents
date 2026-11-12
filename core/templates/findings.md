# Spike findings: <topic>

Date: <yyyy-mm-dd>
Asked by: <who asked, in their role: "CEO", "Product", "me">
Size: <S | M | L | XL | n/a>
Effort: <a range, for example "2 to 4 weeks", or "n/a">
Confidence: <High | Medium | Low>
Lenses: business, engineering, leadership
Default lens: <business | engineering | leadership>

<!--
One investigation, three ways to read it. A "### For <lens>" block shows only in that lens; anything outside
those blocks shows in every lens. A section can have all three blocks, some, or none. Leave a lens out of a
section when it has nothing to say there. Plain language for business and leadership: no file paths, class
names or jargon. Export to a shareable page: Export-Brief.ps1 (see /spike).
-->

## The ask

> <The request in the asker's own words, as given.>

<What we understood it to mean, in one or two sentences, and the decision this supports.>

## Short answer

### For business

<What customers or the business get, roughly how long, and what it costs in team time. Two or three sentences.>

### For engineering

<Lead with the answer: the approach, size, and the riskiest part. Two or three sentences.>

### For leadership

<The recommendation and the decision needed, in two sentences. Include size, effort range and confidence.>

## Questions for the requester

- <Something only the asker can answer that changes the size or the approach. At least one.>

## Current state

### For business

<What exists today, in plain words. One or two sentences.>

### For engineering

- **Confirmed:** <fact> (`<file:line>` or command output)
- **Suspected:** <belief> (<why>)

## Options

### For business

- **<Option A name>:** <what the customer gets, and roughly how long>
- **<Option B name>:** <what the customer gets, and roughly how long>

### For engineering

| Option | How it works | Pros | Cons | Effort (S/M/L) |
|---|---|---|---|---|
| A | | | | |
| B | | | | |

### For leadership

- **<Option A>:** <the tradeoff in one line>
- **<Option B>:** <the tradeoff in one line>

## Risks and dependencies

- <A risk, other team, vendor or unknown that could move the estimate.>

## Recommendation

### For business

<Which option and what it means for customers and timing.>

### For engineering

<Which option and why. Confidence: High / Medium / Low, and what would raise it.>

### For leadership

<Which option, the tradeoff accepted, and the one decision or approval needed.>

## Next step

<For example: answer the questions above, then `/start 12345 feature` and `/spec 12345` using this file as input.>

## Sources

- `<repo>/<path>`: <what it showed>
- <work item, PR, doc or page>: <what it showed>
