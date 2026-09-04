# Performance notes

Everything below was measured with `./run-benchmarks.sh` (JavaScript target,
node 22) on the commit that added `test/arcade/Benchmarks.hx`. Numbers are
milliseconds per frame, best of several runs. Absolute values depend on target
and machine — the ratios are the point, and they held on the Haxe interpreter
too.

The recommendations are ordered by measured payoff. None of them are applied to
the library: this file records what the benchmarks found and what to do about
it.

---

## 1. Stop rebuilding the QuadTree for a single query

**The problem.** `collideBodyVsGroup` and `overlapBodyVsGroup` are the only
paths that use the QuadTree. Each call does:

```haxe
quadTree = getQuadTree();
quadTree.populate(objects);                                  // N inserts
objects = quadTree.retrieve(body.left, body.top, ...);       // 1 query
releaseQuadTree(quadTree);
```

Building a tree over N bodies is strictly more work than the linear scan it is
meant to replace, and the tree is thrown away after one query. A spatial index
pays for itself over many queries; here it never gets the chance.

**Evidence.** The QuadTree path against a brute-force scan of the same group:

| Group size | QuadTree | `skipQuadTree = true` | |
|---|---|---|---|
| 100 | 0.040 ms | 0.011 ms | **3.7x slower** |
| 500 | 0.158 ms | 0.057 ms | **2.8x slower** |
| 2000 | 0.935 ms | 0.302 ms | **3.1x slower** |

It is never faster, at any size tested. Clustering makes it worse still: 1000
bodies packed into 5% of the world measure 2.3x slower than the same bodies
spread out, because `maxLevels = 4` caps subdivision and every query then
returns nearly the whole group anyway.

**What to do.** Either of:

- **Cheap:** raise `maxObjectsWithoutQuadTree` to effectively disable the tree,
  or delete the tree from these two methods. The broadphase becomes a linear
  scan, which is what it effectively already is, minus the build cost.
- **Better:** make the tree persist. Give `Group` an optional tree that is
  rebuilt at most once per frame (invalidated when bodies are added, removed or
  moved) and shared by every query against that group in that frame. This is
  the only version where a QuadTree can win, and the benchmarks show the shape
  of the win: 50 queries against one reused tree cost 0.53 ms, while 50
  build-and-query cycles over the same bodies cost 22.9 ms — **43x**.

**Risk.** Low for the cheap option (it only removes work). The persistent tree
needs careful invalidation; get it wrong and collisions are silently missed.

---

## 2. Sort at most once per frame, not once per call

**The problem.** Every `collide`/`overlap` against a group re-sorts that group
when `sortDirection` is set:

```haxe
if (group.sortDirection != NONE && ...) {
    sort(group);
}
```

A frame that collides 60 enemies against one platform group sorts that group 60
times. Nothing between those calls changes the group's membership.

**Evidence.** A realistic frame — 60 enemies each colliding against a
200-platform group, 60 `collide` calls per frame:

| Configuration | ms/frame | |
|---|---|---|
| QuadTree on, sort `LEFT_RIGHT` (library defaults) | 2.121 | baseline |
| QuadTree off, sort `LEFT_RIGHT` | 0.493 | 4.3x faster |
| QuadTree on, sort `NONE` | 1.384 | 1.5x faster |
| QuadTree off, sort `NONE` | 0.240 | **8.8x faster** |

The two per-call overheads together account for almost 90% of that frame.

**What to do.** Add a dirty flag to `Group`, set it in `add`/`remove` and when a
body moves, and have `World.sort` return immediately when the group is already
sorted for the requested direction. Clear the flag at the start of each frame.
Sorting an already sorted array is measurably cheaper than a shuffled one
(0.028 ms vs 0.192 ms for 1000 bodies) but it is not free, and skipping it
entirely is better.

**Risk.** Low. Worst case the group is sorted more often than strictly needed,
which is the current behaviour.

---

## 3. Sweep and prune in the group loops

**The problem.** `collideGroupVsGroup`, `collideGroupVsItself` and their
`overlap` counterparts are plain nested loops with no broadphase at all:

```haxe
for (i in 0...objects.length) {
    for (j in 0...objects.length) {
        if (body1 != body2) separate(body1, body2, ...);
    }
}
```

Measured growth is n^2.0. `collideGroupVsItself` also runs the full n² rather
than n²/2, so every unordered pair is visited twice.

This is the part that stings, because the groups have *already been sorted* on
the axis immediately before the loop. The sort is paid for and then not used.

**What to do.** When the group is sorted `LEFT_RIGHT`, the inner loop can stop
as soon as `body2.x >= body1.right`: no later body can overlap `body1` on x, so
`separate` would have returned false anyway. Combined with starting the inner
loop at `i + 1` for the self-collision case:

```haxe
for (i in 0...objects.length) {
    final body1 = objects.unsafeGet(i);
    final limit = body1.x + body1.width;
    for (j in (i + 1)...objects.length) {
        final body2 = objects.unsafeGet(j);
        if (sorted && body2.x >= limit) break;
        ...
    }
}
```

**Evidence.** Prototyped both variants against the full test suite (which
stayed green, including the stack-stability regression test):

| Bodies self-colliding | current | break only | break + `i + 1` |
|---|---|---|---|
| 100 | 0.170 ms | 0.102 ms | 0.089 ms |
| 200 | 0.592 ms | 0.328 ms | 0.038 ms (**15x**) |
| 400 | 2.365 ms | 1.446 ms | 0.103 ms (**23x**) |

**Risk.** Two things to be careful about.

- The `i + 1` half changes observable behaviour: each pair is currently reported
  to the collide callback twice, and would be reported once. That is arguably
  the fix, but it is a breaking change for anyone counting callbacks.
- The `break` is only valid when the group really is sorted on x, so it must be
  gated on `sortDirection`. Separation moves bodies during iteration, which can
  degrade the ordering slightly within a frame; adding `overlapBias` to the
  limit covers that. Circle bodies whose radius exceeds `halfWidth` (odd
  diameters, because `halfWidth` is floored) need the same margin.

---

## 4. Make `angle` and `speed` lazy

**The problem.** `Body.preUpdate` computes both on every body on every frame:

```haxe
if (this.x != this.prevX || this.y != this.prevY) {
    this.angle = Math.atan2(this.velocityY, this.velocityX);
}
this.speed = Math.sqrt(this.velocityX * this.velocityX + this.velocityY * this.velocityY);
```

An `atan2` and a `sqrt` per body per frame, for two fields most games never
read.

**Evidence.** Removing both from `preUpdate` (integration only, no collisions):

| Scenario | current | without atan2/sqrt | |
|---|---|---|---|
| 1000 bodies | 0.064 ms | 0.043 ms | **1.47x faster** |
| 5000 bodies | 0.548 ms | 0.382 ms | **1.43x faster** |

About 30% of the entire integration cost is spent maintaining two derived
values.

**What to do.** Turn `angle` and `speed` into computed properties
(`public var speed(get, never)`), or keep the fields with a dirty flag set in
`preUpdate` and resolved on first read. Three internal call sites read or write
them and need to go through the accessor: `Body.moveFrom` (reads both),
`Body.moveTo` (reads `angle`) and `Body.stop` (writes `speed = 0`).

**Risk.** Low, but `angle` and `speed` are currently public writable fields, so
making them read-only properties is a breaking API change. The dirty-flag
variant avoids that.

---

## 5. Smaller items

- **Use `unsafeGet` consistently in the group loops.** `QuadTree` uses
  `Extensions.unsafeGet` throughout, but `collideGroupVsGroup`,
  `collideGroupVsItself` and `collideBodyVsGroup` use plain `objects[i]`
  indexing on their hottest loops. Free on JS, real on cpp/cs.
- **Prefer the typed collide methods in hot code.** `World.collide` resolves its
  arguments through `getCollidableType`, which is a `Type.getClass` switch (or
  an `untyped __class__` read on JS) on every call. Code making many small
  calls can call `collideBodyVsBody` / `collideBodyVsGroup` / `collideGroupVsGroup`
  directly — they are already public — and skip the dispatch entirely. Worth a
  note in the README rather than a code change.
- **`separate` calls `intersects` twice** in the common case: once on entry, then
  again between the two axis passes. The second call is needed (the first axis
  may have resolved the overlap), but the entry check could be folded into the
  caller's loop, which already knows whether the pair is a candidate. Minor.
- **`SortBodies.hx` is one merge sort copy-pasted four times** (571 lines) so the
  comparator inlines. That is a legitimate trade, but a build macro or a
  comparator passed as an inlined type parameter would give the same codegen
  from one source. Maintenance, not speed: today a fix has to land in four
  places.
- **`maxLevels = 4` is low** for a large world. If the persistent-tree option in
  §1 is taken, this default should be revisited alongside it — a deeper tree is
  only worth building when the build cost is amortised over many queries.

---

## What is already fast

Worth stating so effort goes to the right place:

- **Separation is cheap.** Dense contact costs ~1.3x sparse, and `collide` costs
  about the same as `overlap`. The narrowphase is not the bottleneck.
- **Circles are not meaningfully more expensive than rectangles** (within noise
  of each other at 150 bodies self-colliding).
- **The QuadTree pool works.** 1000 acquire/release pairs cost 0.100 ms, about
  0.1 µs each. The pooling is not where the tree cost comes from — the
  `populate` that follows it is.
- **World bounds and drag are nearly free** relative to the base integration
  cost.

Broadphase strategy and per-call overhead dominate everything else.
