# Light Software Factory — Agent Operational Manifesto

## 1. Core Principles
1. **Never weaken tests or skip checks** to force a passing PR. Fix root causes.
2. **One atomic Sub-Issue per PR.** Target \`staging\`, never \`master\`.
3. **Clean-room resets:** Builders run \`.factory/prep-branch.sh\` to wipe the local \`public\` schema and dependencies before building.
4. **Zero personal keys:** Use live 1-hour GitHub tokens via \`.factory/enter-role.sh\`.

## 2. Model Roles
- **🧠 Architect (\`herdr-hub\`):** Plans Epics, reviews PR diffs with Vision, approves & squash-merges routine PRs to \`staging\`.
- **🛠️ Primary Builder (\`worker-gemini\`):** High-volume backend, DB migrations, unit tests, and Final-Wave Playwright E2E verification.
- **💻 Parallel Builder (\`worker-qwen\`):** Local GPU inference for UI, styles, unit tests, and overflow.
- **🔥 Specialist (\`specialist-fable\`):** Capped at 1 pass per PR for merge conflicts and 3-strike CI loops.

## 3. Human Approval Gates
- Any PR touching migrations (\`migrations/\`, \`*.sql\`), auth (\`auth/\`, \`security/\`), or factory config requires human approval.
- Human approves via GitHub Reviews UI -> merges using **"Create a merge commit"** for the rolling \`staging -> master\` Release PR.
