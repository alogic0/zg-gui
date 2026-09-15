# Providing reusable framework capabilities

Consumers submit requirements expressed as reusable behavior. The provider
maintains a neutral contract under `docs/requests/` and implements it through
public APIs, general examples and independently reproducible tests.

Consumer-specific motivation and product acceptance stay with the consumer.
Provider contracts must stand alone without access to a customer's repository,
backend, credentials or internal issue tracker.

## Request lifecycle

1. **Requested:** record the reusable problem and observable acceptance checks.
2. **Specified:** define the proposed API, ownership, admission limits, failure
   behavior and compatibility expectations. Record unresolved choices explicitly.
3. **Implemented:** commit a cohesive implementation with native checks and any
   relevant compiler, package or browser tests.
4. **Verified:** record actual commands, results, limits and measurements. Link
   framework evidence and public documentation. Leave unmet criteria unchecked.

Consumer integration is a separate process. A verified provider capability can
remain unadopted by a consumer; a consumer workaround is not a framework API.

## Design boundaries

The framework owns template compilation, typed projections, node identity,
admission checks, the DOM command protocol and the generic browser host.
Consumers own state derivation, domain actions, persistence, authentication,
effects, routing, layout, styles and application interaction policy.

Prefer a small reusable capability to a special case for one screen. Keep
JavaScript responsible for protocol validation and DOM application; state
comparison and mutation selection remain in Zig. Preserve the smallest stable
owner of a changed value and retain unrelated controls and focus.

## Evidence

Use synthetic, neutral fixtures and an independent consumer package for public
build APIs. Cover invalid input and allocation/capacity failure as well as the
normal path. Browser checks should assert DOM object identity and focus when
relevant, rather than relying only on serialized HTML or accessibility snapshots.

Measure artifact size and initial/peak memory separately. State the workload and
limits of measurements. Do not infer application performance from the demo or
tune to an unstated budget.

## Requests

- [001: reusable template components](requests/001-template-components.md)

- [002: description lists](requests/002-description-lists.md)

- [003: projection composition](requests/003-projection-composition.md)

- [005: table fragments](requests/005-table-fragments.md)

- [030: dynamic determinate progress bounds](requests/030-dynamic-progress-bounds.md)

- [031: fragment anchors and explicit HTTP links](requests/031-fragment-and-http-links.md)

Dynamic input kinds use the finite `template.InputType` contract (request 032).
Keep file and checked-input ownership separate from form-value controls.
