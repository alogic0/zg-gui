# SVG filters

GUI templates support local SVG filter definitions. Consumers own IDs and must
make them unique across independently mounted drawings. Core rendering remains
allocation-free; effects use the browser's SVG renderer.

```html
<svg viewBox="0 0 100 50">
  <defs>
    <filter id="$effect_id" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="$blur"/>
    </filter>
  </defs>
  <circle cx="50" cy="25" r="10" filter="$effect"/>
</svg>
```

Use the public `addTemplate` build helper and ordinary typed view fields.
`blur` is a finite nonnegative integer or float. `effect` is `none`,
`url(#identifier)`, or an optional null to remove the attribute. Identifiers
contain ASCII letters, digits, underscores and hyphens. External URLs, quoted
URLs, fallback lists, nonfinite numbers and negative deviations are rejected.
The first deviation API admits one scalar rather than an anisotropic pair.

`filter` belongs under `defs`. It contains only `feGaussianBlur`, `feOffset`,
`feColorMatrix`, `feBlend`, `feComposite`, `feMorphology`, and
`feComponentTransfer`. Only the last accepts children: `feFuncR`, `feFuncG`,
`feFuncB`, and `feFuncA`. Other primitives are leaves. Names are case-sensitive.

| Element | Static attributes in addition to id/class/role/aria/data |
| --- | --- |
| filter | x, y, width, height, filterUnits, primitiveUnits, color-interpolation-filters |
| All primitives | in, result, x, y, width, height, color-interpolation-filters |
| feGaussianBlur | stdDeviation, edgeMode |
| feOffset | dx, dy |
| feColorMatrix | type, values |
| feBlend | in2, mode |
| feComposite | in2, operator, k1, k2, k3, k4 |
| feMorphology | operator, radius |
| Channel functions | type, tableValues, slope, intercept, amplitude, exponent, offset |

Units admit `userSpaceOnUse` and `objectBoundingBox`. Interpolation admits
`sRGB` and `linearRGB`. Blend modes are `normal`, `multiply`, `screen`, `darken`
and `lighten`. Composite operators are `over`, `in`, `out`, `atop`, `xor`, and
`arithmetic`; morphology uses `erode`/`dilate`. Matrix types are `matrix`,
`saturate`, `hueRotate`, `luminanceToAlpha`; channel types are `identity`,
`table`, `discrete`, `linear`, `gamma`. Blur edge modes are `duplicate`, `wrap`,
`none`. Numeric values use finite decimal/exponent notation. Regions accept percentages; width/height,
blur deviation and morphology radii are nonnegative. Matrix values are bounded
to twenty scalars, radii to two, channel tables to 256. Browser SVG semantics
still determine matrix arity, channel defaults and named input resolution.

Only deviation and ordinary ID/class/role/aria/data metadata on filter elements
are dynamic. Other filter parameters are static. A shape's `filter` reference
is dynamic. Changes emit attribute patches and retain their SVG owners, filter
definitions, shapes and unrelated focus. A rejected projection or exhausted
output buffer must not be committed by the caller. The DOM host independently
validates dynamic references and blur values.

Verification: `zig build test-templates test` and
`zig build test-browser -Dbrowser-filter='SVG filters'`. The browser fixture
checks real SVG animated values, computed filter references, isolated IDs,
object identity and sibling focus in Chromium. This does not establish visual
acceptance for any consumer or support for external filter resources.
