# Performance notes

This file started as a list of recommendations produced by
`test/arcade/Benchmarks.hx`. All of them have now been applied. It records what
was changed, what it bought, and the trade-offs that came with it.

Measurements are from `./run-benchmarks.sh` (JavaScript target, node 22),
milliseconds per frame, best of several runs. "Before" numbers were re-measured
against the pre-optimisation library using the *same* benchmark harness, so the
comparison is like for like. Absolute values depend on target and machine; the
ratios held on the Haxe interpreter too.

## Results

| Scenario | Before | After | |
|---|---|---|---|
| 400 bodies self-colliding | 2.262 ms | 0.067 ms | **33.7x** |
| 200 bodies self-colliding | 0.551 ms | 0.024 ms | **23.3x** |
| 150 bodies self-colliding (rectangles) | 0.322 ms | 0.017 ms | **19.5x** |
| 200 bodies, detect and resolve | 0.701 ms | 0.042 ms | **16.8x** |
| Platformer frame (1 player, 60 enemies, 200 platforms, 120 bullets) | 1.936 ms | 0.159 ms | **12.1x** |
| Bullet hell (1500 projectiles vs 20 targets) | 7.904 ms | 0.690 ms | **11.5x** |
| 200 vs 200 bodies, two groups | 0.562 ms | 0.053 ms | **10.6x** |
| 1000 bodies clustered in 5% of the world | 0.856 ms | 0.117 ms | **7.3x** |
| 200 bodies piling up on the ground | 0.632 ms | 0.138 ms | **4.6x** |
| 1 body vs a group of 2000 | 0.988 ms | 0.276 ms | **3.6x** |
| 1000 bodies, integration only | 0.066 ms | 0.044 ms | **1.5x** |

Every scenario in the suite improved except four, listed under
[What got slower](#what-got-slower).

---

## 1. The QuadTree is built once per frame, and only when it will be reused

**Was.** `collideBodyVsGroup` and `overlapBodyVsGroup` built a complete tree over
the group on every call and threw it away after a single query. Building a tree
over N bodies is more work than the linear scan it replaces, so the QuadTree
path measured 2.8-3.7x *slower* than `skipQuadTree = true` at every size tested.

**Now.** Each `Group` owns its tree (`Group.getQuadTree`) and rebuilds it only
when its bodies have moved, so every query in a frame shares one build. On top
of that, `Group.useQuadTreeForNextQuery` means the first query after the bodies
move is answered by scanning, and the tree is only built from the second query
onward — building it for a single query can never pay off.

**Result.** The single-query case now costs exactly what the brute force scan
costs, because no tree is built (1 vs 2000 bodies: 0.988 ms → 0.276 ms, and
within noise of the `skipQuadTree` path). The many-query case is where the tree
now earns its keep: 60 body-vs-group calls against one 200-body group went from
2.12 ms to 0.19 ms, and with sorting off the tree beats the scan roughly 2:1
(0.12 ms vs 0.22 ms), which it never did before.

**Cache invalidation.** `Body.preUpdate` compares the body's position against
where it was at the end of the previous `preUpdate` and only invalidates the
groups holding it if it has actually moved. `Body.reset`, `Body.setCircle`, a
size change and `Group.add`/`remove` invalidate directly. Retrieve queries are
padded by `overlapBias` so that a body nudged by separation after the tree was
built is still found within the frame.

Comparing positions rather than asking "did this body move under its own power"
matters: separation, world bounds clamping and direct assignment to `body.x` all
move a body without it having any velocity, and all three are caught. It also
has to be a comparison against the *previous frame*, not against the start of
this `preUpdate` — separation happens after `preUpdate` has run, so a body can
sit still all of the next frame in a place the caches know nothing about.

Doing this from `World.separate` instead, so that `Body` needs no extra fields,
was tried and is much worse: separation runs *during* the collision phase, so
invalidating there tears the caches down mid-frame and they get rebuilt several
times a frame instead of once. The platformer scenario measured 3.3x slower.

**Result.** A group of static level geometry now keeps its tree and its sort
order for as long as nothing in it moves. Measured on 200 static platforms with
60 bodies colliding against them, 0.0668 ms -> 0.0462 ms a frame, **1.45x**, with
every paired run favouring it. The same probe on 1200 bodies that all move every
frame — where there is nothing to cache and the comparison is pure overhead —
measures identically to before (0.2496 ms vs 0.2498 ms).

## 2. Sorting happens once per frame, not once per call

**Was.** Every `collide`/`overlap` against a group re-sorted it. A frame
colliding 60 enemies against one platform group sorted that group 60 times,
with nothing changing in between.

**Now.** `Group` records the direction it is currently sorted in, and
`World.sort` returns immediately when the cached ordering is still valid.

**Result.** A sort call that hits the cache costs 0.0045 ms against 0.19 ms for
a real sort of 1000 bodies — about 42x cheaper. In the 1-vs-2000 scenario the
sorting overhead in a collide call dropped from 0.907 ms to 0.257 ms.

## 3. Group collisions use the sort order as a sweep and prune

**Was.** `collideGroupVsGroup`, `collideGroupVsItself` and their `overlap`
counterparts were plain nested loops, measuring n^2.0 growth — despite the
groups having just been sorted on an axis. The sort was paid for and then
ignored. `collideGroupVsItself` also ran the full n² rather than n²/2.

**Now.** When a group is sorted `LEFT_RIGHT` or `TOP_BOTTOM`, the inner loop
stops at the first body that starts beyond the current body's far edge: nothing
after it can overlap either. Group vs group also advances a start index past
bodies that finish before the current one begins. Self-collision iterates
`j` from `i + 1`.

The descending orders (`RIGHT_LEFT`, `BOTTOM_TOP`) keep the full loop. They are
sorted by the near edge but would need to break on the far edge, which is not
monotonic when bodies have different sizes — the early exit would be unsound.

The break is padded by `overlapBias`, which covers bodies that separation has
nudged out of order since the sort, and circle bodies whose `halfWidth` was
floored.

**Result.** 400 bodies self-colliding: 2.26 ms → 0.067 ms (33.7x). 200 vs 200 in
two groups: 0.562 ms → 0.053 ms (10.6x).

**Behaviour change.** Group self-collision now reports each pair once rather
than twice. This is a breaking change for code that counts callbacks, and it is
documented in the README.

**Correctness.** `UnitTests.broadphase()` cross-checks the swept path against a
brute force reference on randomised scenes with deliberately mixed body sizes,
for group vs itself, group vs group and body vs group, across every sort
direction. Deliberately breaking the sweep (breaking on the near edge instead of
the far edge) fails 8 tests, so the check has teeth.

## 4. `angle` and `speed` are computed on read

**Was.** `Body.preUpdate` computed an `atan2` and a `sqrt` for every body every
frame to maintain two derived fields.

**Now.** Both are properties backed by a dirty flag that `preUpdate` sets. They
remain assignable, so the public API is unchanged.

**Result.** Integration of 1000 bodies: 0.066 ms → 0.044 ms (1.5x). About a
third of the entire integration cost was maintaining two values most games never
read.

## 5. Smaller changes

- **`unsafeGet` on the group loops.** `collideGroupVsGroup`,
  `collideGroupVsItself` and `collideBodyVsGroup` now use
  `Extensions.unsafeGet` like the rest of the library. Free on JS, real on
  cpp/cs.
- **`Body.skipQuadTree` is now honoured.** The field existed and was documented
  but nothing ever read it.
- **`maxLevels` default raised from 4 to 6.** Now that a tree is built once and
  reused, a deeper tree amortises. Measured on a 400 body group taking 80
  queries a frame: about 6% faster spread out, 4% clustered, with no further
  gain past 6. `maxObjects = 10` was already optimal (4 and 20 are both worse).
- **The benchmark harness is adaptive.** Scenarios that finish faster than 15 ms
  are re-run with more frames. Without this, the optimised scenarios became fast
  enough that timer noise made a 50-body scene measure slower than a 400-body
  one.

## What was deliberately not changed

- **`SortBodies.hx` is still four copies of the same merge sort.** The four
  classes are byte-identical apart from their `cmp` function, which exists so
  each comparison inlines into the sort. Replacing them with one implementation
  taking a comparator would either lose that inlining or require a build macro,
  adding complexity to a library that has no dependencies — for no measured
  speedup, since sorting is now cached and rarely on the hot path. A comment at
  the top of the file records that a fix has to be applied to all four.
- **`separate` calling `intersects` twice** is not redundant: the second call
  happens after the first axis has moved the bodies, and its answer decides
  whether the second axis needs separating.

## What got slower

| Scenario | Before | After | Why |
|---|---|---|---|
| create 5000 bodies | 1.559 ms | 1.783 ms | Six extra fields per `Body`: four for the lazy `angle`/`speed`, two for the position the group caches were last built from. Construction is not a per-frame cost, and it buys 1.5x on integration and 1.45x on static groups. |
| sort 1000 shuffled bodies | 0.195 ms | 0.210 ms | The cache check, plus the benchmark now calling `invalidate()` each frame to keep measuring a real sort. Pays for itself the first time a second call in the same frame hits the cache. |
| sort 5000 shuffled bodies | 1.016 ms | 1.089 ms | Same. |
| 50 retrieves against one reused tree | 0.503 ms | 0.556 ms | Within run-to-run noise. |

## A note on measuring this

The scenarios in the suite became fast enough that run-to-run variance on a
shared machine is +/-20%, which is larger than several of the effects above. A
single before/after run of the suite will happily show a 1.3x "win" on a
scenario the change cannot possibly have touched.

What the numbers here are based on:

- Baselines re-measured against the previous library using the *same* harness,
  not compared against numbers captured earlier in the session.
- Builds run alternately rather than all of one then all of the other, so drift
  in machine state affects both.
- The global minimum across many rounds, not a mean.
- A control scenario the change cannot affect, checked to be flat before
  believing anything else.
- For effects under about 20%, a dedicated probe that runs one scene for long
  enough to swamp the noise, rather than the full suite.

The last point is what settled the static group change: the full suite put it
anywhere between 1.17x faster and 3.3x slower depending on the run, while a
focused probe gave 1.45x consistently across every paired run.

## What is still true

- **Separation is cheap.** Dense contact costs about 4x sparse contact, and
  `collide` costs about the same as `overlap`. The narrowphase is not the
  bottleneck.
- **Circles cost about the same as rectangles.**
- **Clustering still hurts.** A group packed into a small part of the world
  cannot subdivide usefully, so it leans on the linear scan. It is now 7.3x
  faster than it was, but still the worst case for a spatial index.
