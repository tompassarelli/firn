---
name: rust-development
description: >-
  Write, edit, review, debug, test, optimize, or otherwise work on Rust code
  or Cargo projects. Use whenever a task touches .rs files, Cargo manifests or
  workspaces, Rust APIs, ownership, errors, async or unsafe code, tests,
  clippy, rustfmt, compiler profiles, build feedback loops, or concurrent Rust
  worktrees.
---

# Rust Development

## Contract

- Repository policy is authoritative: inspect `Cargo.toml`, `rust-toolchain*`, `.cargo/config.toml`, formatting/lint configuration, CI, `CONTRIBUTING`, and nearby code/tests. Preserve the declared edition, MSRV (`rust-version`), targets, feature matrix, unsafe policy, and async runtime.
- Before changing behavior or signatures, identify the affected packages, callers, tests, public boundaries, enabled configurations, and the commands CI runs. Do not hand-edit generated code.
- Make the smallest coherent change that satisfies the task. Do not silently alter public APIs, serialized/wire/on-disk formats, CLI behavior, feature defaults, dependencies, MSRV, or unrelated behavior.
- Reuse existing abstractions and dependencies. Add a dependency, generic abstraction, macro, async boundary, or synchronization primitive only when it materially reduces complexity or risk and fits project policy.

## Implementation

- Borrow when the callee only observes or temporarily mutates; take ownership when it must retain or consume. Do not accept a borrow merely to clone it internally.
- Do not add `clone`, `Arc`, or `Mutex` just to appease the compiler. Make ownership and sharing explicit; clone when an independent owned value is intended.
- Prefer concrete borrowed views such as `&str`, `&[T]`, and `&Path` internally. Use bounds such as `AsRef<Path>` or `IntoIterator` only when they serve real callers without obscuring the API.
- Keep items private by default and public APIs small. Use enums/newtypes for domain distinctions and to exclude invalid states; avoid ambiguous booleans.
- Implement `From` for infallible, lossless, value-preserving, obvious conversions and `TryFrom` for fallible ones. Derive traits only when their semantics are honest. Avoid speculative traits, builders, and generics.
- Use `Path`/`PathBuf` and `OsStr`/`OsString` for filesystem and process values; do not assume platform data is UTF-8 or build paths by string concatenation.
- Use `?` for propagation; `let ... else` for required bindings with early exit; `if let` for one interesting pattern; and `match` when alternatives or exhaustiveness matter.
- Use `for` for straightforward iteration. Use iterator adapters when they clarify a transformation or collect directly; use an explicit loop when state, early exit, mutation, or borrowing is clearer. Do not collect merely to iterate again.

```rust
let Some(path) = request.path() else {
    return Ok(Response::not_found());
};

let records = lines
    .map(parse_record)
    .collect::<Result<Vec<_>, ParseError>>()?;
```

## Errors and Panics

- Use `Option` for ordinary absence, `Result` for expected failure, and panic only for programmer errors or broken invariants.
- Follow the project’s error stack. Reusable boundaries expose meaningful typed errors—often with `thiserror`; application orchestration may use contextual erased errors such as `anyhow`. Do not add either dependency reflexively.
- Use `?` when `From` supplies conversion. Add `map_err` or context only when it adds actionable information or deliberately changes semantics; preserve the source.
- Do not use `unwrap`/`expect` on ordinary fallible production paths. Tests and locally proven invariants may use `expect` with a message explaining why failure is impossible.
- Handle or propagate errors; document intentional best-effort suppression.

## Async and Unsafe

- Do not introduce async or change runtimes unless required. Never block an executor or hold a blocking lock guard across `.await`; use the project’s blocking bridge. Bound growing concurrency, track spawned tasks unless deliberately detached, and preserve valid state across cancellation.
- Respect `forbid(unsafe_code)`. When unsafe is necessary, keep it in the smallest practical block behind a safe abstraction, state the invariant in `// SAFETY:`, document caller obligations under `# Safety`, test boundaries, and run Miri when supported.

## Tests and Documentation

- Test observable behavior, important edges, and every bug fix; prefer a regression test that fails before the fix. Follow existing test organization/helpers and keep tests deterministic and isolated.
- Document changed public APIs. Include `# Errors`, `# Panics`, and `# Safety` when applicable; add examples when they clarify non-obvious use. Comments explain invariants and why, not the code itself.

## Feedback Loop and Concurrent Lanes

- Measure before changing build structure or toolchain settings. Record the exact package/workspace scope, target, features, profile, effective flags/wrappers, target directory, warm/cold state, and wall time. Compare only like-for-like runs; a cold cache, changed flags/profile, contention, or a different target directory invalidates the comparison.
- Keep a recurring hot loop stable: package selection, profile, features, target triple, compiler flags, and target directory. Change one reversible variable at a time; keep it only when comparable measurements improve feedback without weakening required verification.
- Every concurrently written Rust worktree gets its own `CARGO_TARGET_DIR`. A shared target directory can execute another lane's artifacts and is a correctness failure, not merely a performance issue. Shared download/source caches are separate from build artifacts.
- Prefer the narrowest check that covers the change during iteration; run the full required suite before handoff. Use Cargo timings or compiler output to locate a persistent bottleneck before restructuring.
- Modules are ownership/reasoning boundaries; crates are compilation and cache boundaries. Do not split a crate for line count. Propose a crate boundary only after repeated comparable evidence identifies an invalidation edge it would remove; otherwise split private modules to preserve locality.
- Treat custom profiles, `RUSTFLAGS`, wrappers, codegen settings, and cache changes as measured opt-ins, not global defaults. Changing flags can invalidate or repartition artifacts; define a named profile only for a recurring measured workflow.

## Completion

Use repository scripts and CI as authority. Otherwise adapt these to the affected package/workspace, target, and feature matrix:

```bash
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
```

- Run targeted checks first, then the required full suite. Use `--all-features` only when simultaneous enablement is valid; test touched or CI-required non-default/target-specific configurations.
- Run docs checks for public API changes, Miri for relevant unsafe changes, and a representative benchmark/profile before performance claims. Review all automated fixes and the final diff for unrelated churn, debug code, generated files, suppressed warnings, and accidental API/dependency/MSRV changes.
- Report exact commands and outcomes. Separate failures caused by the change from pre-existing or environment failures; never claim a check passed if it did not run.
