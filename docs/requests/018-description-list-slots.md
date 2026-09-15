# Description-list child slots

Allow an empty `dl` to delegate its children to a typed slot without an extra
wrapper. Consumers supply valid term/value pairs or grouped pairs and own child
membership and capacity. Retain the list and unrelated controls during leaf
updates. Existing slot rejection rules apply to nonempty containers and competing
child owners. No host, allocation or protocol change is required.

Verification: `npm test` passed native/generated/compiler checks and 17 Node
tests, including description identity/focus regression coverage. The generated
list fixture verifies escaping, leaf-only output and short-output retry.
Consumer adoption is separate.
