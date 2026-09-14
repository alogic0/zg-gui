# Framework provider

This repository provides a general-purpose Zig/WASM GUI framework.

## Requests and ownership

- Work from neutral capability contracts in `docs/requests/`. Describe the
  reusable problem, public API expectations, ownership, failure behavior,
  acceptance checks and limits before implementation.
- Keep customer names, repository paths, product screens, business controllers,
  upstream comparisons and application acceptance evidence in consumer
  repositories. Do not add them to framework documentation, examples, tests,
  source comments or commit messages.
- Use general-purpose examples and synthetic fixtures. Consumers own business
  logic, routing, authentication, provider effects, styling and product policy.
- Track provider delivery separately from consumer adoption. Framework test
  success does not establish application acceptance.
- Document supported public APIs so consumers do not depend on internal files.
- Record size, initial and peak memory, and patch work when relevant. Measurement
  alone does not authorize optimization work or changes to consumer budgets.

See [contributing](docs/contributing.md) and the [roadmap](docs/roadmap.md).

## Verification and commits

Create a commit for each cohesive, working implementation slice. Before committing:

1. Format touched Zig files with `zig fmt`.
2. Run the smallest relevant checks; broaden coverage for public API, compiler or
   host changes. Verify DOM identity and focus for interactive rendering changes.
3. Require `git diff --check` and review the staged diff for unrelated changes.
4. Write the complete message to a temporary file and use `git commit -F`.
   Keep its subject within 80 columns and body paragraphs wrapped at 80 columns.
   Remove the temporary file after the commit succeeds.

Use named input structs for ambiguous primitive argument groups. Define allocation
and release ownership and reject overflow before publishing output. Preserve
smallest-owner DOM updates and test that unaffected ancestors are retained.

Remove temporary files when finished. When deleting files, use plain `rm -- path`
without force flags.
