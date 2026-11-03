# Coding standards

These rules guide change review and code-health audits across Nix, configuration
and scripts. Read them at the working revision. Each finding needs a rule ID,
source location and concrete consequence. A preference, file size or suspected
shallow module alone is not a defect. Formatter and lint configuration own syntax;
[AGENTS.md](AGENTS.md) owns workflow and verification policy.

Rule IDs are stable. Retire an ID rather than reuse it for a different rule.

## Design

- **CS1. Deep modules.** Put cohesive behavior behind a small interface that owns
  its invariants and failure handling. In a command such as `bin/keepawake`, callers
  should not need to repeat configuration validation or runtime-state rules. Justify
  refactors by caller complexity removed or knowledge concentrated, not line counts.
- **CS2. Real seams.** Introduce an adapter where behavior varies, such as macOS
  `pmset` and Linux systemd in `bin/remote-mode`. Keep platform-specific commands
  behind the operation they implement. Add shared abstractions only when actual
  callers benefit; keep module-internal seams private.
- **CS3. Locality.** Give each rule one authoritative implementation. Reuse the
  owning Nix module or library instead of copying host settings or policy into
  scripts. Before removing a wrapper, inspect its callers and preserve any useful
  validation, platform selection or lifecycle contract. Keep pure transformations
  separate from subprocess calls and state writes when that reduces caller burden
  or makes consequential logic directly verifiable.

## Configuration and scripts

- **CS4. Source ownership.** Change the source that produces the installed file.
  Follow [source-to-target guidance](AGENTS.md#source--target),
  [example/live settings](AGENTS.md#examplelive-settings-pairs) and
  [Nix guidance](nix/AGENTS.md) for generation, package and host ownership.
  Distinguish source edits, builds and activation in verification reports.
- **CS5. Platform and failure behavior.** Keep shell and Python commands compatible
  with their declared interpreter and supported hosts. Check the affected platform
  branches and tool dependencies before moving code into shared configuration.
  Quote shell paths and arguments, preserve argument boundaries in subprocess
  calls, and validate external input before consequential writes or commands.
  Report a failed operation as a failure; preserve state needed to diagnose or
  recover from a partial update. A Linux-only tool in shared macOS configuration
  or a failed command reported as success has a concrete consequence.
- **CS6. Existing contracts.** Follow the root [repository guide](AGENTS.md) for
  runtime versus development scripts and public-repository privacy, and its
  [theme contract](AGENTS.md#theme) for themed consumers. Read component instructions
  before changing their files. Keyboard changes also follow
  [keyboard rules](docs/keyboard-rules.md). These sources own their detailed rules.

## Verification and documentation

- **CS7. Observable verification.** Follow [the test policy](AGENTS.md#tests),
  including its criteria for adding tests. Verify the affected behavior through
  the command, app or existing suite as appropriate. When tests are warranted,
  assert outcomes and state, not implementation structure or prose. Preserve
  useful behavioral coverage through refactors. Report blocked checks and untested
  platforms explicitly; a build alone does not prove installed behavior.
- **CS8. Documentation.** Keep each rule in one authoritative place, with pointers
  that say when to read it. Keep human setup in `README.md` and agent workflow in
  `AGENTS.md`. Explain hidden constraints and reasons; read settings from their
  configuration. Give procedures checkable completion criteria.

## Code-health application

The existing software-factory `dotfiles-weekly-health` job owns scheduled maintenance.
Its repository owns scheduling and the review/merge policy. This procedure also
applies to code-health findings and tickets created through other workflows.

1. Read this file at the working revision and inspect open PRs and active work.
   Select an uncovered issue with a rule ID, source location and concrete consequence
   or design benefit. Include that evidence in a finding or ticket so its implementer
   can verify it. Resolve ambiguous architectural decisions with Jonas.
2. Spend at most 60 minutes on investigation and implementation. Make at most one
   cohesive improvement, including a small behavior-preserving refactor when the
   evidence justifies it. Keep unrelated cleanup, features and dependency upgrades
   outside the change. Larger refactors become discussion items.
3. Verify affected behavior under the existing repository checks and test policy.
   Inspect formatter and lint autofixes. Document blocked checks and leave work
   open when required verification cannot finish.
4. Explain the rule ID, source evidence, before/after behavior or design benefit,
   checks and remaining limitations in the ticket or change report and any PR.
   Require reviewers to read this file at the working revision. The factory health
   job explicitly requests a GitHub PR, so it follows that exception to the root
   direct-main default and its existing convergence-gated merge policy. It does not
   authorize deployment or activation. Other work follows its existing delivery
   instructions.

A run may finish without a change when its inspected scope contains no justified,
uncovered fix. Report the inspected scope and findings without an empty commit or
PR. Standards changes require Jonas's agreement; do not weaken a rule or bundle a
standards change into a health fix to make it qualify.
