# Sonny V1 Implementation Changelog

Canonical progress/handoff record for Sonny v1 implementation. This file is the source of truth between chats — future implementation chats should read this before trusting memory or assumptions about current state. See `docs/sonny-major-release-spec.md` §21.0A (build sequence) and §24 (future-chat operating procedure, cross-agent review protocol) for the workflow this file supports.

Branch naming: plain `feature/<name>` (no per-agent prefix). Agent identity is tracked per-entry below, not in the branch name.

## Feature Branch Checkpoint Workflow

Each roadmap row below is one feature branch, but a feature branch should be implemented as a sequence of small, reviewable checkpoints on that same branch. A checkpoint should map to one migrated capability, subfeature, or similarly coherent leg of the branch.

Checkpoint workflow:

1. Plan the full branch scope before editing.
2. Implement one checkpoint on the feature branch.
3. Run the relevant tests for that checkpoint.
4. Report the diff and test results to the user.
5. Wait for the user's manual review/testing and explicit approval before committing or pushing that checkpoint.
6. Continue on the same feature branch for the next checkpoint.
7. When all checkpoints for the branch are complete, run the full required test pass, fill this changelog entry, append the next-chat kickoff prompt, and send the branch for cross-agent review before merge to `main`.

Do not batch an entire feature branch into one large unreviewed implementation. Do not create extra branches for every checkpoint unless this roadmap is explicitly updated. Never commit, push, merge, or open/modify a PR without explicit user approval.

## Locked Branch Roadmap (2026-07-04)

Dependency-ordered. Do not start a branch before the ones above it are merged, unless a later chat explicitly re-justifies reordering here.

| # | Branch | Spec sections | Status |
|---|---|---|---|
| 1 | `feature/capability-adapter-foundation` | §4A.0 | Not started |
| 2 | `feature/local-risk-approval-engine` | §10, §11, §11.1A | Not started |
| 3 | `feature/web-research-app-foundation` | §4A.2, §4A.3 | Not started |
| 4 | `feature/provider-media-playback` | §4A.4 | Not started |
| 5 | `feature/instant-utilities-shortcuts` | §4A.6, §4A.7 | Not started |
| 6 | `feature/followup-usage-transparency` | §4A.8, §4A.9 | Not started |
| 7 | `feature/local-storage-privacy-foundation` | §15.4 | Not started |
| 8 | `feature/product-shell-shared-state` | §4A.1 (shell only), §6.2, §6.3, §17.3 | Not started |
| 9 | `feature/hosted-agent-runtime-backend` | §6.1, §8, §9, §16, §21.2, §21.3, §6.19 | Not started |
| 10 | `feature/billing-command-center-memory` | §6.14, §16.3, §16.4, §6.3A (full), §6.10 | Not started |
| 11 | `feature/screen-intelligence` | §6.4, §12, §20.3, §21.5, §6.13, §14.4A, §14.5 | Not started |
| 12 | `feature/privacy-security-hardening` | remaining §6.12, §14, §15, §20.5, §20.6, §21.7 | Not started |
| 13 | `feature/workflow-library-polish` | §18.1, §18.2, §18.5, §18.6 | Not started |
| 14 | `feature/power-mode` | §6.5, §13, §20.4, §21.6, §20.9 | Not started |
| 15 | `feature/enterprise-foundations` | §6.15, §15.6, §21.9 | Not started |
| 16 | `feature/release-ops-evals-hardening` | §19, remaining §20, §21.10, §22, §23, §24, §26 | Not started |

Notes on sequencing decisions behind this table:

- Branches 1-2 are split (adapter contract alone, then risk/approval on top of it) so each proves one thing in isolation: "existing tools run through adapters without regression," then "risk/approval works on top of adapters."
- Branches 3-6 split the §4A.2-§4A.9 generalization pass into four smaller reviewable branches rather than one large one, per user decision on 2026-07-04.
- Branch 7 (local storage/Keychain hardening) is pulled out as its own branch, done before backend/auth work per §21.0A step 4.
- Branch 8 is scoped to the shared-state shell only (§4A.1) — the full Command Center UI (account/subscription/stats screens) is deferred to branch 10, once billing exists to gate it.
- Memory (§6.10) is bundled into branch 10 rather than given its own branch, since it needs the full Command Center UI to be viewable/editable.
- §6.16-§6.18 and §18.7-§18.8 are not separate branches — they are explicitly cross-references to §4A.6-§4A.8 ("formal v1 requirement version of...", "listed here for completeness") with no independent scope, fully covered by branches 3-6.
- The kill switch (§20.9) is folded into branch 14 (Power Mode) rather than given its own branch, since it's tightly coupled to Power Mode's emergency-stop work (§13.5).

## Entry Template

Copy this for each completed branch. Fill every field — "none" is a valid answer, a blank field is not. Product context, constraints, and non-negotiables already live permanently in the spec (§1-§26); do not restate them here, only reference section numbers. The two fields marked **(required, no blanket claims)** exist because a vague answer there is exactly how a later chat regresses something silently.

```
### Branch: feature/<name>
Status: in progress | complete | blocked
Date: YYYY-MM-DD
Implementing agent: Claude | Codex
Reviewing agent: Claude | Codex | pending

Spec sections covered: (list; flag any left partial and why)
Files changed: (actual list — not "see diff")
Tests: (exact command run, from README) -> (pass/fail, counts)

Behavior added: (one bullet per new capability)
Behavior preserved (required, no blanket claims): (one bullet per EXISTING flow this branch touched, confirming it still works — "everything else still works" is not acceptable, name them)

Architectural decisions / pitfalls discovered (required, write "none" if true): (anything a future chat would get wrong if it only read the spec and not this entry)
Known limitations / deferred scope: 
Open questions for the next chat (required, write "none" if true): 

Next branch: feature/<name> (per roadmap above, or state the reordering and why)
```

Then append this ready-to-paste block so the next chat can start cold without re-deriving context:

```
--- Kickoff prompt for next chat (paste verbatim as the first message) ---
Repo: /Users/sauranshbhardwaj/Desktop/macos-agent
Spec: docs/sonny-major-release-spec.md
Changelog: docs/sonny-v1-implementation-changelog.md — read the latest entry before anything else. Do not trust memory or assumptions over it; verify against current git state.

Branch: feature/<next-name>
Implementing agent: <X>  Reviewing agent: <Y>
Primary target: §<sections>

Just completed: feature/<prev-name> — <one-line summary>
Must preserve: <the specific existing flows this branch must not break, pulled from "Behavior preserved" above>
Known pitfalls to avoid repeating: <from "Architectural decisions / pitfalls discovered" above, or "none">

Start in plan mode. Confirm git status is clean on main, confirm the changelog's account of the prior branch still matches the current code, then produce an implementation plan before editing anything. Do not commit, push, merge, or open a PR without explicit approval.
```

## Entries

_(none yet — branch 1, `feature/capability-adapter-foundation`, has not started)_
