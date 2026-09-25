# Request 054: large-list snapshot measurements and exact identity tradeoffs

Status: implemented and provider verified; consumer acceptance is separate.

## Reusable problem

High-throughput industrial dashboards, streaming log viewers, and tabular applications
frequently render large lists of 500 to 1,000 items (2,500 to 5,000 DOM property leaves)
updated at high frequencies.

In UI frameworks with virtual DOMs or tree diffing, large lists often introduce:
- Dynamic heap allocations and garbage collection pauses during reconciliation.
- Significant memory consumption from retaining tree copies and allocated string copies.
- Frame-rate drops during reverse sorting or partial row updates.

`zg-gui` uses an intrusive hash-bucket property snapshot (`Snapshot(capacity)`) combined with
64-bit Wyhash hashing (`Entry: { node: u32, link: u32, property: u64, value: u64 }`). This
request establishes the empirical throughput, memory bounds, and architectural tradeoffs
between 64-bit Wyhash property identity versus storing exact strings across frames.

## Empirical benchmark results

Hardware: x86_64 Linux, Zig 0.17 Fast mode. Benchmark suite: `tests/snapshot_benchmark.zig`.

### 1. Memory footprint

| Scale | Properties / Item | Total Snapshot Entries | Total Memory | Memory / Entry |
| :--- | :--- | :--- | :--- | :--- |
| **500 items** | 5 | 2,500 entries | 64,104 bytes (**62.6 KB**) | **25.64 bytes** |
| **1,000 items** | 5 | 5,000 entries | 128,200 bytes (**125.2 KB**) | **25.64 bytes** |

- An `Entry` is exactly **24 bytes** (`node: u32`, `link: u32`, `property: u64`, `value: u64`).
- Intrusive hash index buckets consume only **1.64 bytes** per entry on average (load factor $\approx 4$).
- Entire snapshot storage is statically bounded and embeddable in WASM linear memory or application BSS with zero runtime allocations.

### 2. Reconciliation latency across scenarios

| Scenario | 500 items (2,500 entries) | 1,000 items (5,000 entries) | Per-Entry Latency |
| :--- | :--- | :--- | :--- |
| **Cold Capture** (first frame) | 36.63 $\mu$s | 56.55 $\mu$s | 11.31 – 14.65 ns |
| **Unchanged (100% hits, 0 diffs)** | 40.49 $\mu$s | 117.70 $\mu$s | 16.20 – 23.54 ns |
| **Single Edit (1 row updated)** | 39.89 $\mu$s | 83.89 $\mu$s | 15.96 – 16.78 ns |
| **Reverse Permutation** (reordered) | 60.13 $\mu$s | 92.21 $\mu$s | 18.44 – 24.05 ns |
| **Total Replacement** (100% diffs) | 40.67 $\mu$s | 116.41 $\mu$s | 16.27 – 23.28 ns |

- Reconciling 5,000 properties takes **less than 0.12 milliseconds** (~118 $\mu$s).
- This is **over 130x faster** than a standard 60 FPS browser budget (16.6 ms), leaving ample headroom for rendering, network, and DOM updates.

### 3. Exact string identity vs 64-bit Wyhash tradeoff analysis

#### Wyhash 64-bit scalar digest (Adopted by `zg-gui`)
- **Microbenchmark latency**: 1.60 ns per hash.
- **Zero-heap lifetime**: Arbitrary ephemeral strings (e.g. `bufPrint` stack integers, computed labels, formatted timestamps) are digested immediately into a 64-bit scalar. The underlying string bytes need not be retained across animation frames.
- **Collision probability**:
  For $N = 5,000$ values, the collision probability is:
  $$P(\text{collision}) \approx \frac{N^2}{2 \times 2^{64}} \approx \frac{25 \times 10^6}{3.68 \times 10^{19}} \approx 6.77 \times 10^{-13}$$
  (Less than one in a trillion chance of a single collision across the lifetime of the application).

#### Exact string comparison (Alternative evaluated)
- **Memory hazard**: Storing `[]const u8` requires retaining the underlying string bytes in memory until the *next* frame. In a zero-allocation architecture, this would require either double-buffered string arenas (e.g., 200–500 KB per frame) or fixed inline byte buffers in every entry.
- **Inline buffer explosion**: Even a modest 48-byte inline buffer per entry would increase `Entry` size from 24 bytes to 72 bytes, ballooning the 5,000-entry snapshot from 125 KB to over 400 KB, while still risking truncation or failure on strings longer than 48 bytes.
- **Performance**: While `std.mem.eql` on pre-interned strings can be fast, pointer dereferences to non-contiguous string data incur L1/L2 cache misses that exceed the 1.6 ns required to hash with Wyhash in-register.

## Conclusion

Wyhash 64-bit hashing inside `zg-gui`'s `Snapshot` is the optimal design choice for embedded,
WASM, and high-frequency UI rendering:
1. It guarantees bounded memory (25.64 bytes per property leaf).
2. It allows transient stack-allocated string generation without lifetime or allocation leaks.
3. It achieves sub-millisecond (80–120 $\mu$s) patch computation at scales of 1,000 items (5,000 entries).
