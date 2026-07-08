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
| 1 | `feature/capability-adapter-foundation` | §4A.0 | Complete (pending review) |
| 2 | `feature/local-risk-approval-engine` | §10, §11, §11.1A | Complete (pending review) |
| 3 | `feature/web-research-app-foundation` | §4A.2, §4A.3 | Complete (pending review) |
| 4 | `feature/provider-media-playback` | §4A.4 | Complete (pending review) |
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

### Branch: feature/capability-adapter-foundation
Status: complete
Date: 2026-07-04
Implementing agent: Codex
Reviewing agent: Claude

Spec sections covered: §4A.0 complete. Forward-compatible metadata placeholders for §10/§11/§11.1A are present, but no risk engine, approval gating, escalation UI, or policy logic was implemented on this branch.
Files changed:
- `Sources/MacAgentCore/AgentActionExecutor.swift`
- `Sources/MacAgentCore/CapabilityAdapter.swift`
- `Sources/MacAgentCore/CreateWorkspaceCapabilityAdapter.swift`
- `Sources/MacAgentCore/DefaultCapabilityAdapters.swift`
- `Sources/MacAgentCore/DocxConversionCapabilityAdapter.swift`
- `Sources/MacAgentCore/FinderSelectionCapabilityAdapter.swift`
- `Sources/MacAgentCore/FinderSelectionResolver.swift`
- `Sources/MacAgentCore/HackerNewsMarkdownCapabilityAdapter.swift`
- `Sources/MacAgentCore/LargestFilesZipCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenAllowlistedAppCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenMediaResultCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenSafeURLCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenWorkspaceCapabilityAdapter.swift`
- `Sources/MacAgentCore/PermissionReadinessCapabilityAdapter.swift`
- `Sources/MacAgentCore/RevealInFinderCapabilityAdapter.swift`
- `Sources/MacAgentCore/RunRoutineCapabilityAdapter.swift`
- `Sources/MacAgentCore/SaveRoutineCapabilityAdapter.swift`
- `Sources/MacAgentCore/ToolRegistry.swift`
- `Tests/MacAgentCoreTests/AgentActionExecutorTests.swift`
- `Tests/MacAgentCoreTests/CapabilityRegistryTests.swift`
- `Tests/MacAgentCoreTests/PlannerBoundaryTests.swift`
- `docs/sonny-v1-implementation-changelog.md`

Tests: `env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib` -> pass, 53 tests in 8 suites.

Behavior added:
- Added `CapabilityAdapter`, `CapabilityMetadata`, `CapabilityRegistry`, and adapter-backed default tool registration for local Mac capabilities.
- Added stable capability IDs, display names/descriptions, planner tool metadata, descriptive-only required permissions metadata, default risk-tier placeholders, dry-run behavior descriptions, and local executor location metadata.
- Added registry/protocol/metadata tests, planner prompt golden tests, tool-registry golden tests, response-format shape tests, and adapter routing coverage.

Behavior preserved (required, no blanket claims):
- Largest-files zip still scans whitelisted folders, selects the largest regular files, preserves stable default zip output paths between preview and execution, dry-runs without writing, creates zips through the injected archiver, and suggests revealing the generated zip.
- DOCX conversion still scans whitelisted folders, uses the injected document converter, supports mock destination behavior, skips existing PDF outputs, dry-runs without writing, and suggests revealing the PDF folder.
- Hacker News Markdown still opens `https://news.ycombinator.com`, fetches headlines via the existing `HackerNewsFetching` service, writes Markdown to the resolved whitelisted output path, dry-runs without writing, and suggests opening/revealing the Markdown file.
- Safe URL opening still validates through `SafeURL.validateWebURL`, allows only HTTP/HTTPS, rejects unsupported schemes, previews the URL, and executes through the injected browser opener.
- Allowlisted app opening still resolves apps through `MacAppCatalog`, rejects unknown apps, preserves the bundle-ID allowlist, previews the resolved display name/bundle ID, and executes through the injected app opener.
- Media result opening still validates provider/title, builds the same `MediaPlaybackRequest`, preserves Apple Music/Spotify behavior-description preview text, executes through the injected media opener, and returns the exact summary from `mediaOpener.open()`.
- Finder selection still reads selected Finder items through the existing Finder context reader, validates every path through the Desktop/Documents whitelist, previews selected paths, and reports the whitelisted item count on execution.
- Reveal in Finder still validates paths through the whitelist, allows preview of a future not-yet-created artifact, requires the path to exist during execution, and opens Finder with `NSWorkspace.activateFileViewerSelecting`.
- Permission readiness still uses `PermissionReadinessService.currentStatus`, previews the same status source used by execution, has no side effects, does not prompt for permissions, and reports required-action items in the existing summary format.
- Save routine still validates routine names and nested steps, rejects unsafe routine/workspace/clarify/unsupported/nested-routine steps, previews nested steps through normal plan preview, writes to `routineStore.fileURL`, and preserves saved step counts in the summary.
- Run routine still loads saved routines from `RoutineStore`, previews nested routine plans, executes nested plans through normal executor dispatch, preserves suggestions, and preserves the `Ran routine <name>. ...` summary prefix.
- Create workspace still validates workspace names, allowlisted apps, safe URLs, non-empty app/URL content, previews `workspaceStore.fileURL`, saves through `WorkspaceStore`, and preserves app/URL counts in the summary.
- Open workspace still loads from `WorkspaceStore`, validates allowlisted apps and safe URLs, opens apps before URLs, uses the injected app/browser openers, previews the combined opens list, and preserves app/URL counts in the summary.
- Chained execution still segments composite workflows, resolves reveal-in-Finder steps to the previous produced artifact, preserves the zip-plus-reveal future-artifact preview behavior, and executes each segment through the top-level adapter-backed dispatch.

Architectural decisions / pitfalls discovered (required, write "none" if true):
- `DefaultCapabilityAdapters.all()` now uses real adapters for every executable capability; only `clarify` remains `MetadataOnlyCapabilityAdapter` because clarification is intercepted by `clarificationQuestion()` / `prepare()` before executable dispatch and has no local side-effect executor.
- Routines need executor recursion because saved routine plans can contain any already-migrated capability or mixed chain. `CapabilityExecutionContext` now carries `previewNestedPlan` and `executeNestedPlan` closures back to the executor so `RunRoutineCapabilityAdapter` and `SaveRoutineCapabilityAdapter` can stay adapter-owned without leaving routine behavior in the switch.
- `FinderSelectionResolver` was extracted as the shared DRY helper for whitelisted Finder selection and selected-folder resolution; zip and DOCX adapters use it instead of duplicating Finder-selection code.
- The transitional `previews` closure in `AgentActionExecutor.execute()` was removed once all executable switch cases routed through adapters.
- Planner/schema behavior was protected with hard golden tests for `ToolRegistry.default.plannerDescription`, `OpenAIPlanner.systemPrompt(toolRegistry: .default)`, and `AgentPlanSchema.responseFormat()`.
- Required permissions metadata is descriptive-only on this branch. It does not enforce readiness, gate execution, request permissions, or implement branch #2 approval behavior.
- Chained execution is intentionally not an adapter because it is not tied to one `AgentOperation`; it remains runtime segmentation that calls top-level preview/execute, which now dispatches segment capabilities through the adapter registry.
- During checkpoint 7 review, a one-off uncaught `NSException` flake appeared in `asyncProcessRunnerCancelsRunningProcess` from an existing `AsyncProcessRunner`/`NSTask` cancellation race. It passed on rerun, `AsyncProcessRunner.swift` was not touched, and it is unrelated/non-blocking for this branch.
Known limitations / deferred scope:
- Real risk tiers, dynamic escalation, approval UI, and policy enforcement are deferred to `feature/local-risk-approval-engine`.
- `clarify` has metadata for planner/tool description purposes but remains pre-dispatch control flow rather than an executable adapter.
- The existing `AsyncProcessRunner`/`NSTask` cancellation flake described above remains unresolved and should not be treated as a new capability-adapter regression if it reappears.
Open questions for the next chat (required, write "none" if true): none.

Next branch: `feature/local-risk-approval-engine` (§10, §11, §11.1A), building real risk tiers and dynamic escalation on top of the fully migrated capability adapters.

--- Kickoff prompt for next chat (paste verbatim as the first message) ---
Repo: /Users/sauranshbhardwaj/Desktop/macos-agent
Spec: docs/sonny-major-release-spec.md
Changelog: docs/sonny-v1-implementation-changelog.md — read the latest entry before anything else. Do not trust memory or assumptions over it; verify against current git state.

Branch: feature/local-risk-approval-engine
Implementing agent: Codex  Reviewing agent: Claude
Primary target: §10, §11, §11.1A

Just completed: feature/capability-adapter-foundation — existing prototype capabilities now route through protocol-based local capability adapters with registry-backed metadata while preserving planner/schema boundaries.
Must preserve: largest-files zip default output stability and dry-run behavior; DOCX injected converter/mock/skip-existing-PDF behavior; Hacker News browser/fetch/Markdown write/reveal behavior; SafeURL HTTP/HTTPS-only validation; MacAppCatalog allowlist rejection; media provider/title validation and injected opener summaries; Finder selection whitelist validation; reveal-in-Finder preview-vs-execute existence distinction; permission readiness read-only semantics; save/run routine behavior; create/open workspace behavior and app-before-URL order; zip-plus-reveal chained execution.
Known pitfalls to avoid repeating: routines require `previewNestedPlan`/`executeNestedPlan` recursion hooks because saved routines can contain mixed adapter-backed chains; Finder selection should use `FinderSelectionResolver`; do not reintroduce the removed transitional previews closure; required permissions metadata is descriptive-only until this branch defines enforcement; an existing `AsyncProcessRunner`/`NSTask` cancellation flake may appear in tests and is unrelated to adapter work unless reproduced against touched code.

Start in plan mode. Confirm git status is clean on main, confirm the changelog's account of the prior branch still matches the current code, then produce an implementation plan before editing anything. Do not commit, push, merge, or open a PR without explicit approval.

### Branch: feature/local-risk-approval-engine
Status: complete
Date: 2026-07-08
Implementing agent: Codex
Reviewing agent: Claude

Spec sections covered: §10, §11, and §11.1A complete for the local runtime. §9.3 is covered only for the minimal local `.risk`/`risk.escalated` log marker needed by §11.1A; full hosted Agent Trace Event Types remain out of scope.
Files changed:
- `Sources/MacAgent/AgentViewModel.swift`
- `Sources/MacAgent/ContentView.swift`
- `Sources/MacAgentCore/AgentActionExecutor.swift`
- `Sources/MacAgentCore/AgentEvent.swift`
- `Sources/MacAgentCore/AgentRunner.swift`
- `Sources/MacAgentCore/CapabilityAdapter.swift`
- `Sources/MacAgentCore/CreateWorkspaceCapabilityAdapter.swift`
- `Sources/MacAgentCore/HackerNewsMarkdownCapabilityAdapter.swift`
- `Sources/MacAgentCore/LargestFilesZipCapabilityAdapter.swift`
- `Sources/MacAgentCore/RiskApproval.swift`
- `Sources/MacAgentCore/RunRoutineCapabilityAdapter.swift`
- `Sources/MacAgentCore/SaveRoutineCapabilityAdapter.swift`
- `Tests/MacAgentCoreTests/AgentRunnerTests.swift`
- `Tests/MacAgentCoreTests/RiskApprovalTests.swift`
- `docs/sonny-v1-implementation-changelog.md`

Tests: `env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib` -> pass, 78 tests in 10 suites.

Behavior added:
- Added the local risk-tier and approval-rule model: tier 0 auto-run, tier 1 auto-run unless policy tightens, tier 2 preview/lightweight-confirmation policy, tier 3 explicit approval, and tier 4 refusal.
- Added `CapabilityRiskAssessment`, `CapabilityRiskEscalation`, `RiskApprovalPolicy`, `RiskApprovalRequest`, `RiskApprovalDecision`, and text-only `RiskApprovalCopy` fields covering what Sonny will do, why it is risky, the app/file/domain involved, whether data leaves the device, and undoability.
- Added adapter-owned `assessRisk(plan:context:)` hooks to the `CapabilityAdapter` contract, defaulting to static `defaultRiskTier` so simple capabilities do not need custom risk code.
- Added read-only `AgentActionExecutor.assessRisk(plan:)` to resolve default outputs, collect unique capability adapters in a plan/chain, combine default/effective tiers, collect escalations, and generate approval copy without making an approval decision or executing anything.
- Added real tier gating in `AgentRunner`: it owns auto-run, lightweight-confirmation, explicit-approval, preview-only, and refusal decisions before calling `AgentActionExecutor.execute()`.
- Preserved `AgentActionExecutor.execute(plan:log:)` as an unchanged direct-execution primitive for already-approved plans; direct executor tests remain execution tests, not approval tests.
- Added dynamic validation-time escalation from tier 2 to tier 3 when a largest-files zip output path already exists.
- Added dynamic validation-time escalation from tier 2 to tier 3 when a Hacker News Markdown output file already exists.
- Added dynamic validation-time escalation from tier 2 to tier 3 when saving a routine would replace an existing routine with the same normalized name.
- Added dynamic validation-time escalation from tier 2 to tier 3 when creating a workspace would replace an existing workspace with the same normalized name.
- Added stale-approval protection: a stored `.approved(tier)` decision only authorizes execution if a fresh risk reassessment is still at or below that approved tier.
- Added visible local risk logging through `AgentPhase.risk`, including `risk.assessed` and `risk.escalated` messages; this is deliberately not the hosted trace spine.
- Added approval-pending UI state in `AgentViewModel`/`ContentView`: tier 2+ runs pause after preview with an approval panel, the primary button becomes `Approve`, cancel clears the pending run, approval re-runs risk assessment before execution, and tier 0/1 typed/voice runs continue without added friction.
- Added synchronous `isRunning = true` before spawning start/approval tasks, closing the pre-existing fast double-click race for both normal start and approval execution.
- Added `assessNestedPlan` to `CapabilityExecutionContext`, mirroring the existing nested preview/execute hooks so routine risk assessment recurses through the same executor dispatch path routine execution uses.
- Added runner-level tests for tier 0/1 auto-run, tier 2 confirmation, tier 3 escalation, tier 4 refusal scaffolding, stale approval protection, approval UI-facing state behavior, nested routine escalation, and cross-capability zip-plus-reveal chain gating.

Behavior preserved (required, no blanket claims):
- Largest-files zip still preserves stable default output paths between preview and execution, still dry-runs without writing, still creates archives through the injected archiver, still suggests reveal behavior, and is now tier 2 gated by `AgentRunner`; if its explicit or resolved zip output already exists, it escalates to tier 3 before execution.
- DOCX conversion still scans whitelisted folders, uses the injected converter/mock behavior, skips existing PDF outputs, dry-runs without writing, and remains tier 2 gated by `AgentRunner`; an existing destination PDF is still skip-existing behavior, not an overwrite escalation.
- Hacker News Markdown still opens the fixed HN URL, fetches headlines through `HackerNewsFetching`, writes Markdown to the whitelisted output, dry-runs without writing, and is now tier 2 gated by `AgentRunner`; if the Markdown output already exists, it escalates to tier 3 before execution.
- Safe URL opening still validates through `SafeURL.validateWebURL`, allows only HTTP/HTTPS, rejects unsupported schemes, opens through the injected browser opener, and stays tier 1 auto-run for typed and voice commands with no approval friction by default.
- Allowlisted app opening still resolves apps through `MacAppCatalog`, rejects unknown apps, preserves the bundle-ID allowlist, opens through the injected app opener, and stays tier 1 auto-run for typed commands with no approval friction by default.
- Media result opening still validates provider/title, builds the same `MediaPlaybackRequest`, preserves Apple Music/Spotify result-opening preview text, executes through the injected media opener, returns the opener summary, and stays tier 1 auto-run by default.
- Finder selection still uses the shared Finder selection reader/resolver path, validates every selected item through the whitelist, reports whitelisted item count, and stays tier 0 auto-run because it is read-only context gathering.
- Reveal in Finder still validates paths through the whitelist, allows preview of a future generated artifact, requires the path to exist at execution, opens Finder with `NSWorkspace.activateFileViewerSelecting`, and stays tier 1 auto-run by default.
- Permission readiness still uses `PermissionReadinessService.currentStatus`, remains read-only/no-prompt/no-side-effect, reports required-action items in the existing summary format, and stays tier 0 auto-run.
- Save routine still validates routine names and nested steps, rejects unsafe routine/workspace/clarify/unsupported/nested-routine steps, previews nested steps through normal plan preview, writes to `RoutineStore`, and is now tier 2 gated by `AgentRunner`; replacing an existing routine name escalates to tier 3 before execution.
- Run routine still loads saved routines from `RoutineStore`, previews nested routine plans, executes nested plans through normal executor dispatch, preserves suggestions and the `Ran routine <name>. ...` summary prefix, and is now tier 2 gated by `AgentRunner`; nested routine plans now surface their own escalations in the outer approval request.
- Create workspace still validates workspace names, allowlisted apps, safe URLs, non-empty app/URL content, previews `WorkspaceStore.fileURL`, saves through `WorkspaceStore`, and is now tier 2 gated by `AgentRunner`; replacing an existing workspace name escalates to tier 3 before execution.
- Open workspace still loads from `WorkspaceStore`, validates allowlisted apps and safe URLs, opens apps before URLs, uses the injected app/browser openers, preserves app/URL count summaries, and stays tier 1 auto-run by default.
- Zip-plus-reveal chained execution still segments the zip step and reveal step through top-level dispatch, resolves the reveal step to the produced zip artifact, preserves future-artifact preview behavior, and is now risk-assessed/gated once as a tier 2 chain before either segment executes.

Architectural decisions / pitfalls discovered (required, write "none" if true):
- `dryRun` and tier-based approval are orthogonal. Dry-run remains preview-only mode; non-dry-run execution now goes through tier-aware approval in `AgentRunner`.
- `AgentRunner` owns the approve/refuse decision. `AgentActionExecutor.assessRisk(plan:)` supplies read-only assessment because it has registry/context access, but `AgentActionExecutor.execute(plan:log:)` never gates by itself.
- Keeping `AgentActionExecutor.execute()` as the already-approved primitive meant all pre-existing direct executor execution tests stayed valid and required zero approval rewrites.
- `AgentPlan.requiresConfirmation` remains advisory. The authoritative local decision is the fresh `CapabilityRiskAssessment` plus `RiskApprovalPolicy`.
- Tier 0/1 actions must remain frictionless for typed and voice flows by default. Tests now assert this explicitly for permission readiness, Finder selection, open URL, open app, media opening, reveal in Finder, and open workspace coverage paths.
- Approval decisions carry the tier that was approved, not a Boolean. This is what lets a later reassessment reject stale tier 2 approval if the plan has escalated to tier 3.
- The approval/start double-click task race existed before this branch in `start()` and was more visible once approval was introduced. Both `start()` and `approvePendingRun()` now set `isRunning = true` synchronously before spawning their tasks.
- DOCX existing-PDF behavior is intentionally not an escalation because the adapter skips existing PDFs rather than overwriting or replacing them.
- `assessNestedPlan` mirrors `previewNestedPlan` and `executeNestedPlan`; routines need all three because saved routines can contain mixed adapter-backed chains and must not bypass risk behavior.
- Dynamic escalation belongs to the capability adapter contract, not ad hoc executor logic. The executor combines adapter assessments but does not invent capability-specific escalation rules.
- `AgentPhase.risk` was added as a minimal local marker for visible assessment/escalation logs. Full hosted trace event taxonomy remains deferred to the hosted trace workstream.
- Required-permissions metadata remains descriptive-only on this branch. The risk/approval system does not yet enforce macOS permission readiness or subscription/entitlement checks.
- Finder selection is tier 0, not tier 1, because it only reads whitelisted local context. This was re-verified at the runner gating layer during checkpoint 4.
Known limitations / deferred scope:
- No Power Mode, Accessibility action space, generated shell, generated AppleScript, hosted trace spine, hosted backend, subscription/entitlement validation, Keychain/encrypted storage, provider playback, generic web research, Shortcuts bridge, instant utilities, follow-up correction, or usage transparency was implemented on this branch.
- Tier 2 defaults to lightweight confirmation because there is still no settings UI for changing `RiskApprovalPolicy`.
- No current first-party capability has static tier 3 or tier 4 metadata; tier 3 is exercised through real dynamic escalation and tier 4 through refusal scaffolding in tests.
- Required permissions metadata remains descriptive-only until a later branch defines enforcement.
Open questions for the next chat (required, write "none" if true): none.

Next branch: `feature/web-research-app-foundation` (§4A.2, §4A.3), the first split local capability generalization branch. It is now unblocked because new web/app capabilities can plug into the real adapter risk hooks and `AgentRunner` approval gate instead of inventing their own confirmation path.

--- Kickoff prompt for next chat (paste verbatim as the first message) ---
Repo: /Users/sauranshbhardwaj/Desktop/macos-agent
Spec: docs/sonny-major-release-spec.md
Changelog: docs/sonny-v1-implementation-changelog.md — read the latest entry before anything else. Do not trust memory or assumptions over it; verify against current git state.

Branch: feature/web-research-app-foundation
Implementing agent: Codex  Reviewing agent: Claude
Primary target: §4A.2, §4A.3

Just completed: feature/local-risk-approval-engine — Sonny now has a local risk-tier/approval-rule model, adapter-owned dynamic escalation hooks, `AgentRunner`-owned approval gating, visible local risk logs, approval-pending UI state, stale-approval protection, and nested routine risk assessment.
Must preserve: largest-files zip tier 2 gating plus tier 3 overwrite escalation and stable dry-run/default-output behavior; DOCX tier 2 gating plus skip-existing-PDF behavior with no overwrite escalation; Hacker News Markdown tier 2 gating plus tier 3 output-collision escalation; Safe URL tier 1 auto-run with HTTP/HTTPS-only validation; allowlisted app tier 1 auto-run with `MacAppCatalog` rejection; media result tier 1 auto-run with provider/title validation and injected opener summaries; Finder selection tier 0 auto-run with whitelist validation; reveal-in-Finder tier 1 auto-run with preview-vs-execute existence distinction; permission readiness tier 0 auto-run/read-only semantics; save routine tier 2 gating plus tier 3 replacement escalation; run routine tier 2 gating with nested risk assessment and nested dispatch; create workspace tier 2 gating plus tier 3 replacement escalation; open workspace tier 1 auto-run with app-before-URL order; zip-plus-reveal chain assessed/gated once before either segment executes.
Known pitfalls to avoid repeating: `dryRun` is preview-only and orthogonal to approval; `AgentRunner` owns gating while `AgentActionExecutor.execute()` remains direct already-approved execution; new capability-specific escalation rules belong in adapter `assessRisk(plan:context:)`; approval decisions must carry the approved tier and be checked against fresh reassessment; routines need `assessNestedPlan`/`previewNestedPlan`/`executeNestedPlan` recursion hooks; DOCX skip-existing behavior is not an overwrite escalation; required-permissions metadata is still descriptive-only; `AgentPhase.risk` is only a minimal local log marker, not the hosted trace spine.

Start in plan mode. Confirm git status is clean on main, confirm the changelog's account of the prior branch still matches the current code, then produce an implementation plan before editing anything. Do not commit, push, merge, or open a PR without explicit approval.

### Branch: feature/web-research-app-foundation
Status: complete
Date: 2026-07-08
Implementing agent: Codex
Reviewing agent: Claude

Spec sections covered: §4A.2 complete for direct public URL web-to-Markdown, comparison notes from multiple sources, Hacker News as a provider preset, output save/open/reveal behavior, robots/login/CAPTCHA/paywall refusal, and the required untrusted-content boundary/red-team fixture. §4A.2 remains partial for production topic/search because this branch shipped the `WebSearchProviding` protocol seam and fixture-backed tests only; no real provider is configured. §4A.3 complete for the scoped local app/website action foundation: declarative descriptors, app search URLs, local draft artifacts, generated artifact opening, and existing reveal reuse. Active browser page import, logged-in/private browser content, unrestricted multi-URL user input parsing, hosted search, and UI control of apps are intentionally deferred.
Files changed:
- `Package.swift`
- `Package.resolved`
- `Sources/MacAgent/ContentView.swift`
- `Sources/MacAgentCore/AgentActionExecutor.swift`
- `Sources/MacAgentCore/AgentPlan.swift`
- `Sources/MacAgentCore/AppWebsiteActionDescriptors.swift`
- `Sources/MacAgentCore/CapabilityAdapter.swift`
- `Sources/MacAgentCore/CreateLocalDraftCapabilityAdapter.swift`
- `Sources/MacAgentCore/DefaultCapabilityAdapters.swift`
- `Sources/MacAgentCore/HackerNewsMarkdownCapabilityAdapter.swift` (deleted; behavior moved into `WebResearchMarkdownCapabilityAdapter`)
- `Sources/MacAgentCore/OpenAIPlanner.swift`
- `Sources/MacAgentCore/OpenAllowlistedAppCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenAppSearchURLCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenGeneratedArtifactCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenSafeURLCapabilityAdapter.swift`
- `Sources/MacAgentCore/OpenWorkspaceCapabilityAdapter.swift`
- `Sources/MacAgentCore/WebResearchMarkdownCapabilityAdapter.swift`
- `Sources/MacAgentCore/WebResearchService.swift`
- `Sources/MacAgentCore/WebResearchSynthesizer.swift`
- `Tests/MacAgentCoreTests/AgentActionExecutorTests.swift`
- `Tests/MacAgentCoreTests/AgentRunnerTests.swift`
- `Tests/MacAgentCoreTests/CapabilityRegistryTests.swift`
- `Tests/MacAgentCoreTests/PlannerBoundaryTests.swift`
- `Tests/MacAgentCoreTests/RiskApprovalTests.swift`
- `Tests/MacAgentCoreTests/ToolRegistryTests.swift`
- `Tests/MacAgentCoreTests/WebResearchServiceTests.swift`
- `Tests/MacAgentCoreTests/WebResearchSynthesizerTests.swift`
- `docs/sonny-v1-implementation-changelog.md`

Tests: `env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib` -> pass, 100 tests in 12 suites.

Behavior added:
- Added `web_to_markdown` direct URL support: validates public `http`/`https` URLs, checks robots.txt, fetches public HTML without browser cookies or logged-in context, rejects login/CAPTCHA/paywall-like pages, extracts readable page content through SwiftSoup-backed parsing, synthesizes a structured note, and writes source-linked Markdown with retrieval/generated timestamps.
- Added `web_to_markdown` comparison-note support: multiple resolved source pages can be fetched, wrapped separately as untrusted observed content, synthesized into one comparison note, and saved to a whitelisted Markdown path.
- Added `web_to_markdown` topic/search support at the adapter seam: `AgentStep.searchQuery` routes through `WebSearchProviding` with the same tier 2 risk path, output-collision escalation, synthesis, and Markdown save flow as direct URLs; production intentionally uses `UnavailableWebSearchProvider` and fails clearly with `Web search provider not configured.`
- Added `source=hacker_news` preset behavior inside `WebResearchMarkdownCapabilityAdapter`: the existing `open_hacker_news`, `fetch_hn_headlines`, and `write_markdown` operation sequence now routes through the generic web research adapter instead of a separate HN adapter.
- Added `open_app_search_url`: tier 1 action that opens only fixed allowlisted search URL templates for Google, GitHub, YouTube, Apple Music, and Spotify; it does not click, type, scroll, or otherwise control apps.
- Added `open_generated_artifact`: tier 1 action that opens an existing whitelisted generated file through the injected file opener and supports chained null-output resolution from the previous produced artifact.
- Added `create_local_draft`: tier 2 action that creates only a local whitelisted Markdown draft artifact, suggests opening/revealing it, and escalates to tier 3 before overwriting an existing draft path.

Behavior preserved (required, no blanket claims):
- Hacker News Markdown still opens the fixed `https://news.ycombinator.com` URL, fetches headlines through `HackerNewsFetching`, writes the same `MarkdownWriter.hackerNewsMarkdown(...)` structure to the whitelisted output, dry-runs without writing, suggests opening/revealing the Markdown file, stays tier 2 by default, and escalates to tier 3 with the exact reason `Markdown output already exists at <path>.`
- The existing HN operation sequence `open_hacker_news -> fetch_hn_headlines -> write_markdown` still routes correctly; the old adapter file was removed so there is one implementation path rather than parallel HN code.
- Safe URL opening still validates through `SafeURL.validateWebURL`, permits only HTTP/HTTPS, rejects unsupported schemes, opens through the injected browser opener, and now reads its metadata from the shared app/website action descriptor.
- Allowlisted app opening still resolves apps through `MacAppCatalog`, rejects unknown apps, preserves the bundle-ID allowlist, opens through the injected app opener, and now reads its metadata from the shared app/website action descriptor.
- Open workspace still loads saved workspaces from `WorkspaceStore`, validates allowlisted apps and safe URLs, opens apps before URLs, uses injected openers, preserves app/URL count summaries, and now reads its metadata from the shared app/website action descriptor.
- Reveal in Finder remains the generic reveal file/folder action; it still validates paths through the whitelist, supports future-artifact preview, requires the path to exist during execution, and opens Finder through `NSWorkspace.activateFileViewerSelecting`.
- Tier gating from `feature/local-risk-approval-engine` remains owned by `AgentRunner`; the new web/draft overwrite escalations live in adapter-owned `assessRisk(plan:context:)`, and stale approval protection still requires a fresh reassessment before execution.
- `AgentActionExecutor.execute(plan:log:)` remains the already-approved execution primitive; no new capability introduced a parallel confirmation or approval mechanism.
- Existing zip-plus-reveal chained execution still resolves reveal steps to the previous produced artifact, and the same shared chain resolution now also supports `open_generated_artifact`.

Architectural decisions / pitfalls discovered (required, write "none" if true):
- SwiftSoup `2.13.5` is the repo's first third-party dependency and is pinned deliberately in `Package.swift`/`Package.resolved`. It was added because §4A.2 requires real HTML parsing/readability-style extraction rather than ad hoc string slicing; Sonny-owned extraction still does the product-specific scoring and metadata shaping.
- Fetched web content never enters `OpenAIPlanner.plan(command:)`. The executable `AgentPlan` is decided from the trusted user command first; only after that does `WebResearchMarkdownCapabilityAdapter.execute(...)` fetch pages and call the separate `OpenAIWebResearchSynthesizer`.
- The web synthesis prompt uses strict `WebResearchNote` structured output, not executable `AgentPlan` JSON. The trusted instruction is wrapped with `TRUSTED_USER_INSTRUCTION_BEGIN/END`; each fetched page is sent as a separate observed-content message wrapped with `UNTRUSTED_OBSERVED_CONTENT_BEGIN id=... source_url=... retrieved_at=...` and `UNTRUSTED_OBSERVED_CONTENT_END id=...`.
- The permanent red-team fixture in `WebResearchSynthesizerTests` includes observed HTML text that says to ignore prior instructions and emit fake plan/tool directives. Tests assert the trusted plan/instruction remain unchanged, the malicious text appears only inside the delimited untrusted segment, and execution writes only the expected Markdown artifact with fixed suggestions.
- The app/website action foundation now uses `LocalActionDescriptor` / `AppWebsiteActionDescriptors` for supported actions, required permissions, default risk tier, and fallback behavior. This keeps app/URL/workspace/draft/open-artifact metadata declarative without loosening app bundle allowlists or website URL validation.
- `open_app_search_url` intentionally uses fixed URL templates instead of arbitrary user-provided URL templates, AppleScript, Accessibility, or app UI control. Provider media playback remains branch #4; Power Mode remains branch #14.
- `open_generated_artifact` extends the existing chained null-output artifact resolution used by `reveal_in_finder`; future artifact-opening actions should share this runtime helper rather than reimplement previous-step path lookup.
- `WebSearchProviding` was added as a protocol seam so a real provider can be wired into the existing `web_to_markdown` adapter later without changing risk tiering, output escalation, Markdown writing, or synthesis boundaries.

Known limitations / deferred scope:
- Production topic/search is not fully wired. This branch shipped the protocol-only `WebSearchProviding` seam plus fixture-backed search tests, while production uses `UnavailableWebSearchProvider` and returns `Web search provider not configured.` A real search-provider decision, credentials/runtime boundary, and provider implementation must be resolved before the v1 major release is announced.
- The §21.0A Workstream 0 topic/search exit criterion is therefore only partially satisfied: the adapter path and tests exist, but a configured production search provider does not.
- Active-browser-page input and logged-in/private browser content are not implemented. Sonny does not use browser cookies or private session state for web research in this branch.
- Explicit arbitrary multi-URL user parsing is not implemented; comparison support exists for multiple source URLs once the planner/provider supplies them.
- Paywall, CAPTCHA, robots.txt denial, and login-wall bypass are not implemented; those cases are refused rather than worked around.
- No unrestricted app UI control, Accessibility clicking/typing/scrolling, real provider media playback, hosted backend/search, Keychain/encrypted storage, instant utilities, Shortcuts bridge, follow-up correction, or usage transparency was implemented on this branch.
Open questions for the next chat (required, write "none" if true):
- Which production web search provider to use for `WebSearchProviding` remains open and must be resolved before announcing v1; it does not block `feature/provider-media-playback`.

Next branch: `feature/provider-media-playback` (§4A.4), converting the existing media-result-opening fallback into provider-aware Spotify/Apple Music playback where first-party provider APIs allow it.

--- Kickoff prompt for next chat (paste verbatim as the first message) ---
Repo: /Users/sauranshbhardwaj/Desktop/macos-agent
Spec: docs/sonny-major-release-spec.md
Changelog: docs/sonny-v1-implementation-changelog.md — read the latest entry before anything else. Do not trust memory or assumptions over it; verify against current git state.

Branch: feature/provider-media-playback
Implementing agent: Codex  Reviewing agent: Claude
Primary target: §4A.4

Just completed: feature/web-research-app-foundation — Sonny now has a generic web-to-Markdown capability with SwiftSoup-backed extraction, strict untrusted-content separation, Markdown save/open/reveal behavior, HN as a preset inside the generic adapter, a protocol-only search seam, and descriptor-backed app/website actions including app search URLs, generated-artifact opening, and local draft creation.
Must preserve: web-to-Markdown direct URL tier 2 behavior with robots/login/CAPTCHA/paywall refusal, source links, timestamps, open/reveal suggestions, and tier 3 output-collision escalation; comparison-note support from multiple resolved sources; production topic/search must continue to fail clearly with `Web search provider not configured.` until a real provider is explicitly selected; Hacker News must keep the fixed HN URL, `HackerNewsFetching`, exact Markdown output structure, dry-run behavior, open/reveal suggestions, tier 2 gating, and exact tier 3 collision reason; `open_app_search_url` must remain fixed-template tier 1 URL opening only; `open_generated_artifact` must remain tier 1 whitelisted file opening with chained null-output resolution; `create_local_draft` must remain tier 2 local Markdown only with tier 3 overwrite escalation; app bundle allowlists and safe URL validation must not loosen; `AgentRunner` must continue to own approval gating and `AgentActionExecutor.execute()` must remain already-approved execution.
Known pitfalls to avoid repeating: fetched or observed external content must not enter executable `AgentPlan` generation; use the separate strict-schema untrusted-content prompt path for summarization; new capability-specific escalation belongs in adapter `assessRisk(plan:context:)`; do not add a parallel confirmation path; use the shared previous-artifact chain resolver for generated artifact follow-ups; do not introduce app UI clicking/typing/scrolling for media playback because Power Mode is branch #14; production web search remains intentionally unavailable until a provider is chosen.

Start in plan mode. Confirm git status is clean on main, confirm the changelog's account of the prior branch still matches the current code, then produce an implementation plan before editing anything. Do not commit, push, merge, or open a PR without explicit approval.

### Branch: feature/provider-media-playback
Status: complete
Date: 2026-07-08
Implementing agent: Codex
Reviewing agent: Claude

Spec sections covered: §4A.4 complete for provider-aware media playback seams, fixed-order playback failure diagnosis, fixture-tested Spotify and Apple Music match/resolution, route-aware dry-run previews, preserved provider result/search fallback, and risk/runner integration. Production Spotify OAuth/Web API calls and Apple Music MusicKit calls remain intentionally deferred before the v1 major release announcement, per the branch decision.
Files changed:
- `Sources/MacAgentCore/AgentActionExecutor.swift`
- `Sources/MacAgentCore/CapabilityAdapter.swift`
- `Sources/MacAgentCore/MediaPlaybackService.swift`
- `Sources/MacAgentCore/OpenAIPlanner.swift`
- `Sources/MacAgentCore/OpenMediaResultCapabilityAdapter.swift`
- `Tests/MacAgentCoreTests/AgentActionExecutorTests.swift`
- `Tests/MacAgentCoreTests/AgentRunnerTests.swift`
- `Tests/MacAgentCoreTests/MediaPlaybackServiceTests.swift`
- `Tests/MacAgentCoreTests/PlannerBoundaryTests.swift`
- `Tests/MacAgentCoreTests/ToolRegistryTests.swift`
- `docs/sonny-v1-implementation-changelog.md`

Tests: `env CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" swift test --disable-sandbox -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib` -> pass, 122 tests in 12 suites.

Behavior added:
- Added the dedicated `MediaPlaybackFailureDiagnosis.diagnose(_:)` function over `MediaPlaybackBlockers`, returning exactly one `MediaPlaybackFailureReason` in the required precedence order: authorization, subscription/Premium, active device, catalog match, then provider outage.
- Generalized the existing `MediaSearchMatcher` instead of adding a parallel scorer, keeping the title/artist normalization path used by iTunes fallback while adding optional album, duration, market/storefront scoring, and stable tie-breaking for provider resolvers.
- Added the Spotify playback seam and resolver: `SpotifyPlaybackProviding`, `UnavailableSpotifyPlaybackProvider`, `SpotifyPlaybackResolver`, and typed Spotify status/device/candidate/result models. Fixture tests cover success, transfer playback, missing auth, missing Premium, missing active device, catalog mismatch, outage/rate-limit, and multi-blocker precedence.
- Added the Apple Music playback seam and resolver: `AppleMusicPlaybackProviding`, `UnavailableAppleMusicPlaybackProvider`, `AppleMusicPlaybackResolver`, and typed Apple Music status/candidate/result models. Fixture tests cover authorized playback, missing authorization, missing subscription, catalog mismatch, provider outage, and multi-blocker precedence.
- Wired provider playback into `OpenMediaResultCapabilityAdapter` and `AgentActionExecutor`: dry-run previews now explicitly show `search`, `play`, `transfer-playback`, or `fallback-open`; execution tries the provider seam first and, when blocked, reports the diagnosed blocker plus the result from `context.mediaOpener.open(request)`.

Behavior preserved (required, no blanket claims):
- Existing `play_media` planner-facing schema is unchanged: it still uses `mediaProvider`, `mediaTitle`, optional `mediaArtist`, and optional exact `targetURL`; the strict planner schema and golden metadata tests cover this boundary.
- Existing provider/title validation and `MediaPlaybackRequest` construction are preserved for Apple Music and Spotify, including exact target URI handling when the user supplies one.
- Existing result-opening/search-fallback behavior is unchanged for real users today because both production providers remain unconfigured by default. Apple Music still opens supplied Apple Music URLs, best matching iTunes/Apple Music catalog album results, or Apple Music search; Spotify still opens supplied Spotify URIs or Spotify search.
- Existing iTunes-based Apple Music fallback lookup through `ITunesSearchAPIClient.bestTrack(...)` remains in place and continues to use the generalized `MediaSearchMatcher`; the provider resolver did not replace or bypass that fallback path.
- Existing `MediaOpening` injection behavior is preserved: tests prove blocked provider playback still falls through to the injected `context.mediaOpener.open(request)` fallback, while provider-success execution does not call the opener.
- `play_media` remains tier 1 auto-run with `dataLeavesDevice == true` and no new escalation; runner tests assert it still auto-runs through the existing `AgentRunner` risk contract.

Architectural decisions / pitfalls discovered (required, write "none" if true):
- The branch reused and generalized `MediaSearchMatcher` instead of duplicating normalization/scoring logic. Spotify, Apple Music, and the iTunes fallback now share the same core title/artist matching behavior, with album/duration/market/storefront as optional scoring dimensions.
- Provider `preview(_:)` is deliberately synchronous and non-throwing because `CapabilityAdapter.preview(...)` is synchronous and dry-run must never make live OAuth, MusicKit, or network calls. Previews can only report static/known route information from the injected seam; unavailable production providers therefore preview `fallback-open`.
- `UnavailableSpotifyPlaybackProvider` and `UnavailableAppleMusicPlaybackProvider` intentionally map "not configured" to the authorization blocker, so the fixed diagnosis precedence does not need a separate seam-state exception.
- The adapter reports one diagnosed blocker plus the fallback result when playback is blocked. It does not enumerate every possible failure, because §4A.4 requires exactly one surfaced reason in fixed precedence order.
- Route-aware preview belongs at the adapter/provider seam boundary; real playback and transfer decisions remain provider concerns, while fallback opening remains the existing `MediaOpening` concern.

Known limitations / deferred scope:
- Spotify production playback is deferred before the v1 major release announcement, not permanently stubbed. The user has an existing Spotify Developer account, but real OAuth/PKCE credentials, scopes, token handling, device discovery, catalog search, and playback API calls still need to be wired before release.
- Apple Music production playback is deferred before the v1 major release announcement, not permanently stubbed. Real MusicKit playback requires Apple Developer Program membership that the user does not currently have, plus the corresponding developer capabilities/credentials before release.
- No live Spotify OAuth/Web API calls, Apple Music MusicKit calls, provider network traffic, Keychain token persistence, secure token storage, or provider app UI clicking/typing/scrolling were added on this branch.
- Candidate resolution is real and fixture-tested, but production catalog candidates still need to come from future real provider implementations.
Open questions for the next chat (required, write "none" if true): none.

Next branch: `feature/instant-utilities-shortcuts` (§4A.6, §4A.7), adding instant utility actions and a scoped Shortcuts bridge on top of the adapter/risk foundations.

--- Kickoff prompt for next chat (paste verbatim as the first message) ---
Repo: /Users/sauranshbhardwaj/Desktop/macos-agent
Spec: docs/sonny-major-release-spec.md
Changelog: docs/sonny-v1-implementation-changelog.md — read the latest entry before anything else. Do not trust memory or assumptions over it; verify against current git state.

Branch: feature/instant-utilities-shortcuts
Implementing agent: Codex  Reviewing agent: Claude
Primary target: §4A.6, §4A.7

Just completed: feature/provider-media-playback — Sonny now has provider-aware Spotify and Apple Music playback seams, fixture-tested match resolution, fixed single-blocker diagnosis precedence, route-aware dry-run previews, and universal fallback to existing result opening while production providers remain intentionally unavailable.
Must preserve: fixed playback failure precedence through `MediaPlaybackFailureDiagnosis.diagnose(_:)`; generalized `MediaSearchMatcher` reuse; Spotify and Apple Music unavailable defaults with fallback-open behavior; existing Apple Music iTunes result/search fallback and Spotify URI/search fallback; `play_media` tier 1 auto-run/no escalation behavior; unchanged `play_media` planner-facing schema; no live OAuth/MusicKit/provider network calls until credentials and developer access are explicitly wired.
Known pitfalls to avoid repeating: provider `preview(_:)` is synchronous/non-throwing by design and must never make live calls; do not duplicate media scoring logic instead of reusing `MediaSearchMatcher`; do not introduce UI clicking/typing/scrolling app control for provider media; new capability-specific risk behavior must go through adapter `assessRisk(plan:context:)` and `AgentRunner`; production Spotify and Apple Music wiring remain deferred-before-v1 known limitations, not permanent stubs.

Start in plan mode. Confirm git status is clean on main, confirm the changelog's account of the prior branch still matches the current code, then produce an implementation plan before editing anything. Do not commit, push, merge, or open a PR without explicit approval.
