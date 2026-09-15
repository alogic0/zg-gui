# Explicit external link bindings

Status: provider verified; consumer adoption is separate.

Links to caller-approved HTTPS destinations need typed, optional href bindings.
Require a static data-external-link="true" marker on an anchor to select this
capability. Preserve existing rooted local-link validation. Reject credentials,
protocol-relative paths, control characters and non-HTTPS schemes. Null removes
the destination. Caller policy still decides which destinations are allowed.
Verify escaping, removal, rejected sources and retained link/sibling identity.

Verification: `npm test` passed, including escaped hrefs, destination rejection,
attribute removal, failed-output retry and 23 Node/browser tests. Browser coverage preserves link
identity and sibling focus. Destination availability was not tested.
