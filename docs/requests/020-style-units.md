# Typed dimensional style variables

Floating and resizable containers need integer pixel coordinates and percentage
opacity without raw CSS strings. Extend `:style-vars` to accept public typed
values with a closed unit enum (unitless, pixels, percentage), alongside existing
integers. Preserve fixed property names, 1–16 fields, i64 admission and atomic
serialization. Optional/partial schemas, arbitrary strings, floats and runtime
property names remain unsupported.

Consumers own geometry and value ranges. The existing host accepts these units;
no host or protocol extension is requested. Test generated initial serialization,
leaf updates, signed boundaries, overflow and short-output retry, retaining
container/input identity. Provider verification and consumer acceptance are separate.

Provider verification: `npm test` passed native/generated/compiler checks and
18 Node tests, including retained DOM/focus with pixel and percentage leaves.
Consumer adoption remains separate.
