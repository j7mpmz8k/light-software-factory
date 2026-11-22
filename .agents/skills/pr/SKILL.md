---
name: pr
description: Author comprehensive pull requests with test results, evidence, and clear summaries.
---

# Pull Request Authoring Standards

When opening a Pull Request from a feature branch to `staging`, follow this standard format.

## PR Structure

Every PR must conform to `.github/PULL_REQUEST_TEMPLATE.md`:

```markdown
## Summary
Closes #<sub_issue_number>
Brief 2-3 sentence overview of the vertical slice implemented.

## Changes
- Concise bullet points of what files were added/modified.
- Notation of any schema migrations or domain types added.

## Verification & Test Plan
- [x] Automated tests pass (Red -> Green verified)
- [x] Clean DB migration verified (if applicable)
- [x] Visual evidence attached (if UI or user flow affected)

### Test Run Output
```text
<paste passing test suite output summary>
```

### Visual Evidence
![Evidence Description](<screenshot_or_trace_link>)
```

## Guidelines
- Keep PRs scoped strictly to the single Sub-Issue.
- Never bundle unrelated formatting or renames in the same PR.
- Link the parent Sub-Issue using `Closes #<id>` so GitHub tracks closure automatically.
