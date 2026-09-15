# Fragment anchors and explicit HTTP links

Status: provider verified; consumer acceptance is separate.

Allow dynamic same-document fragment anchors through the existing local link
binding. Keep its restricted ASCII syntax and reject empty fragments, protocol
relative URLs and executable schemes. Let a template explicitly opt into HTTP
and HTTPS destinations with `data-external-link="http"`; existing `true` retains
HTTPS-only behavior. Consumers own destination authorization and user navigation.

Validate before emitting attributes. Preserve failed output and retries and patch
only href when the destination changes. Verify generated links, rejected schemes,
compiler diagnostics and retained anchor/sibling focus. No browser policy or
allocation changes are required.

Verification: `npm test` passed native/compiler/generated checks and 26 Node
checks. Generated cases cover optional destinations, fragment anchors,
rejected schemes and credentials, escaped query strings, output failure/retry
and leaf-only patches. Browser coverage retains the anchor and focused input
across HTTPS, HTTP, fragment and href removal. The public admission predicate
uses the same policy as the attribute binding. No host changes were needed.
