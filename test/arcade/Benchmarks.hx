package arcade;

import arcade.Bench.BenchResult;

/**
 * Performance stress tests for the arcade physics library.
 *
 * Each section isolates one cost so that a slow frame can be attributed to a
 * specific part of the engine: raw integration, the broadphase, the narrowphase,
 * separation, or the pre-collision sort.
 *
 * Run on the interpreter with:  `haxe build-benchmarks.hxml`
 * Run on JS (much faster) with: `./run-benchmarks.sh`
 *
 * Absolute numbers depend entirely on the target and machine. What matters is
 * the ratio between scenarios, which is what the summary at the end reports.
 */
class Benchmarks {

    // The interpreter is orders of magnitude slower than a compiled target, so
    // the same scenarios run with proportionally fewer frames there.
    #if (interp || eval)
    static inline var FRAME_SCALE:Float = 0.06;
    static inline var TARGET:String = 'eval (Haxe interpreter)';
    #else
    static inline var FRAME_SCALE:Float = 1.0;
    static inline var TARGET:String = 'compiled target';
    #end

    public static function main():Void {

        Bench.println('');
        Bench.println('═════════════════════════════════════════════════════════════════════════════════');
        Bench.println('  arcade physics — performance stress tests');
        Bench.println('  target: $TARGET');
        Bench.println('  "budget" is the frame rate this workload alone would sustain');
        Bench.println('═════════════════════════════════════════════════════════════════════════════════');

        integration();
        bodyVsGroup();
        groupVsGroup();
        groupVsItself();
        spatialDistribution();
        shapeCost();
        sortingCost();
        quadTreeInternals();
        separationLoad();
        overlapVsCollide();
        realisticFrame();
        allocation();

        summary();

    }

/// Scene building helpers

    static function frames(count:Int):Int {

        final scaled = Std.int(count * FRAME_SCALE);
        return scaled < 3 ? 3 : scaled;

    }

    static function newWorld():World {

        final world = new World(0, 0, 2000, 2000);
        world.elapsed = 1 / 60;
        return world;

    }

    /**
     * Builds `count` bodies scattered over `spread` fraction of the world,
     * each with a small random velocity. Deterministic for a given seed.
     */
    static function scatter(count:Int, size:Float = 16, spread:Float = 1.0, seed:Int = 7):Array<Body> {

        Bench.reseed(seed);
        final bodies = [];
        final extent = 2000 * spread;

        for (_ in 0...count) {
            final body = new Body(Bench.range(0, extent - size), Bench.range(0, extent - size), size, size);
            body.velocityX = Bench.range(-60, 60);
            body.velocityY = Bench.range(-60, 60);
            bodies.push(body);
        }

        return bodies;

    }

    static function toGroup(bodies:Array<Body>):Group {

        final group = new Group();
        for (body in bodies) group.add(body);
        return group;

    }

    static inline function pre(world:World, bodies:Array<Body>):Void {

        for (body in bodies) {
            body.preUpdate(world, body.x, body.y, body.width, body.height, body.rotation);
        }

    }

    static inline function post(world:World, bodies:Array<Body>):Void {

        for (body in bodies) {
            body.postUpdate(world);
        }

    }

/// Scenarios

    static function integration():Void {

        Bench.section('1. Motion integration only (no collision checks)');
        Bench.header();

        for (count in [100, 1000, 5000]) {
            final world = newWorld();
            var bodies = scatter(count);

            Bench.measure('$count bodies, plain velocity', count, frames(200), () -> {
                pre(world, bodies);
                post(world, bodies);
            }, () -> bodies = scatter(count));
        }

        final world = newWorld();
        world.gravityY = 800;
        var bodies = scatter(1000);
        Bench.measure('1000 bodies, world gravity', 1000, frames(200), () -> {
            pre(world, bodies);
            post(world, bodies);
        }, () -> bodies = scatter(1000));

        final boundsWorld = newWorld();
        boundsWorld.gravityY = 800;
        var boundsBodies = scatter(1000);
        Bench.measure('1000 bodies, gravity + world bounds', 1000, frames(200), () -> {
            pre(boundsWorld, boundsBodies);
            post(boundsWorld, boundsBodies);
        }, () -> {
            boundsBodies = scatter(1000);
            for (body in boundsBodies) {
                body.collideWorldBounds = true;
                body.bounceX = 0.8;
                body.bounceY = 0.8;
            }
        });

        final fullWorld = newWorld();
        fullWorld.gravityY = 800;
        var fullBodies = scatter(1000);
        Bench.measure('1000 bodies, gravity + drag + rotation', 1000, frames(200), () -> {
            pre(fullWorld, fullBodies);
            post(fullWorld, fullBodies);
        }, () -> {
            fullBodies = scatter(1000);
            for (body in fullBodies) {
                body.dragX = 50;
                body.dragY = 50;
                body.accelerationX = 20;
                body.angularVelocity = 45;
                body.angularDrag = 10;
            }
        });

    }

    static function bodyVsGroup():Void {

        Bench.section('2. One body vs a group (the QuadTree path)');
        Bench.header();

        for (count in [100, 500, 2000]) {
            for (skip in [false, true]) {
                final world = newWorld();
                world.skipQuadTree = skip;
                var bodies = scatter(count);
                var group = toGroup(bodies);
                final player = new Body(1000, 1000, 24, 24);
                player.velocityX = 30;
                final all = [player].concat(bodies);
                final label = skip ? 'brute force' : 'quadtree   ';

                Bench.measure('$label, 1 vs $count bodies', count, frames(120), () -> {
                    pre(world, all);
                    world.collide(player, group);
                    post(world, all);
                }, () -> {
                    bodies = scatter(count);
                    group = toGroup(bodies);
                    while (all.length > 1) all.pop();
                    for (body in bodies) all.push(body);
                });
            }
        }

    }

    static function groupVsGroup():Void {

        Bench.section('3. Group vs group (sweep and prune when the groups are sorted)');
        Bench.header();

        for (count in [50, 100, 200]) {
            final world = newWorld();
            var a = scatter(count, 16, 1.0, 11);
            var b = scatter(count, 16, 1.0, 29);
            var groupA = toGroup(a);
            var groupB = toGroup(b);
            var all = a.concat(b);

            Bench.measure('$count vs $count bodies', count * count, frames(60), () -> {
                pre(world, all);
                world.collide(groupA, groupB);
                post(world, all);
            }, () -> {
                a = scatter(count, 16, 1.0, 11);
                b = scatter(count, 16, 1.0, 29);
                groupA = toGroup(a);
                groupB = toGroup(b);
                all = a.concat(b);
            }, '${count * count} pair tests');
        }

    }

    static function groupVsItself():Void {

        Bench.section('4. Group vs itself (each pair visited once)');
        Bench.header();

        for (count in [50, 100, 200, 400]) {
            final world = newWorld();
            var bodies = scatter(count);
            var group = toGroup(bodies);

            Bench.measure('$count bodies self-colliding', count * count, frames(60), () -> {
                pre(world, bodies);
                world.collide(group);
                post(world, bodies);
            }, () -> {
                bodies = scatter(count);
                group = toGroup(bodies);
            }, '${count * count} pair tests');
        }

    }

    static function spatialDistribution():Void {

        Bench.section('5. Spatial distribution (how much the QuadTree actually helps)');
        Bench.header();

        for (spread in [1.0, 0.3, 0.05]) {
            final percent = Math.round(spread * 100);
            final world = newWorld();
            var bodies = scatter(1000, 16, spread);
            var group = toGroup(bodies);
            final player = new Body(50, 50, 24, 24);
            player.velocityX = 30;
            final all = [player].concat(bodies);

            Bench.measure('1000 bodies spread over $percent% of the world', 1000, frames(60), () -> {
                pre(world, all);
                world.collide(player, group);
                post(world, all);
            }, () -> {
                bodies = scatter(1000, 16, spread);
                group = toGroup(bodies);
                while (all.length > 1) all.pop();
                for (body in bodies) all.push(body);
            });
        }

    }

    static function shapeCost():Void {

        Bench.section('6. Collision shape cost (rectangle vs circle narrowphase)');
        Bench.header();

        for (circle in [false, true]) {
            final world = newWorld();
            var bodies = scatter(150, 20);
            var group = toGroup(bodies);
            final label = circle ? 'circle bodies' : 'rect bodies  ';

            Bench.measure('$label, 150 self-colliding', 150 * 150, frames(60), () -> {
                pre(world, bodies);
                world.collide(group);
                post(world, bodies);
            }, () -> {
                bodies = scatter(150, 20);
                if (circle) for (body in bodies) body.setCircle(10);
                group = toGroup(bodies);
            });
        }

    }

    static function sortingCost():Void {

        Bench.section('7. Pre-collision sorting');
        Bench.header();

        for (count in [200, 1000, 5000]) {
            final world = newWorld();
            var bodies = scatter(count);
            var group = toGroup(bodies);
            group.sortDirection = SortDirection.LEFT_RIGHT;

            Bench.measure('sort $count shuffled bodies', count, frames(60), () -> {
                // Moving bodies directly does not go through preUpdate, so the
                // group's cached ordering has to be invalidated by hand
                group.invalidate();
                world.sort(group);
                // Re-shuffle by nudging positions, otherwise every run after the
                // first sorts an already sorted array (the easy case)
                for (i in 0...bodies.length) {
                    bodies[i].x = (bodies[i].x * 7 + 13) % 2000;
                }
            }, () -> {
                bodies = scatter(count);
                group = toGroup(bodies);
                group.sortDirection = SortDirection.LEFT_RIGHT;
            });
        }

        final world = newWorld();
        var sortedBodies = scatter(1000);
        var sortedGroup = toGroup(sortedBodies);
        sortedGroup.sortDirection = SortDirection.LEFT_RIGHT;
        Bench.measure('sort 1000 already sorted bodies', 1000, frames(60), () -> {
            sortedGroup.invalidate();
            world.sort(sortedGroup);
        }, () -> {
            sortedBodies = scatter(1000);
            sortedGroup = toGroup(sortedBodies);
            sortedGroup.sortDirection = SortDirection.LEFT_RIGHT;
        });

        var cachedBodies = scatter(1000);
        var cachedGroup = toGroup(cachedBodies);
        cachedGroup.sortDirection = SortDirection.LEFT_RIGHT;
        Bench.measure('sort 1000 bodies, cache already valid', 1000, frames(60), () -> {
            world.sort(cachedGroup);
        }, () -> {
            cachedBodies = scatter(1000);
            cachedGroup = toGroup(cachedBodies);
            cachedGroup.sortDirection = SortDirection.LEFT_RIGHT;
        });

        // How much of a body-vs-group frame is the sort?
        for (direction in [SortDirection.NONE, SortDirection.LEFT_RIGHT]) {
            final label = direction == SortDirection.NONE ? 'sortDirection NONE       ' : 'sortDirection LEFT_RIGHT';
            final world = newWorld();
            var bodies = scatter(2000);
            var group = toGroup(bodies);
            group.sortDirection = direction;
            final player = new Body(1000, 1000, 24, 24);
            player.velocityX = 30;
            final all = [player].concat(bodies);

            Bench.measure('$label, 1 vs 2000', 2000, frames(60), () -> {
                pre(world, all);
                world.collide(player, group);
                post(world, all);
            }, () -> {
                bodies = scatter(2000);
                group = toGroup(bodies);
                group.sortDirection = direction;
                while (all.length > 1) all.pop();
                for (body in bodies) all.push(body);
            });
        }

    }

    static function quadTreeInternals():Void {

        Bench.section('8. QuadTree internals');
        Bench.header();

        for (count in [500, 2000]) {
            var bodies = scatter(count);
            final tree = new QuadTree(null, 0, 0, 2000, 2000, 10, 4);

            Bench.measure('build a tree of $count bodies', count, frames(60), () -> {
                tree.clear();
                tree.reset(0, 0, 2000, 2000, 10, 4);
                tree.populate(bodies);
            }, () -> bodies = scatter(count));
        }

        var bodies = scatter(2000);
        final tree = new QuadTree(null, 0, 0, 2000, 2000, 10, 4);
        tree.populate(bodies);
        // What 50 body-vs-group calls would cost if every call built its own
        // tree, which is what the library used to do.
        Bench.measure('50 build+retrieve cycles over 2000 bodies', 50, frames(30), () -> {
            for (i in 0...50) {
                tree.clear();
                tree.reset(0, 0, 2000, 2000, 10, 4);
                tree.populate(bodies);
                tree.retrieve(i * 19 % 2000, i * 37 % 2000, i * 19 % 2000 + 24, i * 37 % 2000 + 24);
            }
        }, () -> bodies = scatter(2000));

        // The same 50 queries against a tree built once, which is what a group
        // now does for every query after the first in a frame.
        var sharedBodies = scatter(2000);
        Bench.measure('50 retrieves against one reused tree', 50, frames(30), () -> {
            final shared = new QuadTree(null, 0, 0, 2000, 2000, 10, 4);
            shared.populate(sharedBodies);
            for (i in 0...50) {
                shared.retrieve(i * 19 % 2000, i * 37 % 2000, i * 19 % 2000 + 24, i * 37 % 2000 + 24);
            }
        }, () -> sharedBodies = scatter(2000));

        // The threshold below which the world skips the tree entirely
        for (threshold in [10, 200]) {
            final world = newWorld();
            world.maxObjectsWithoutQuadTree = threshold;
            var thresholdBodies = scatter(150);
            var group = toGroup(thresholdBodies);
            final player = new Body(1000, 1000, 24, 24);
            player.velocityX = 30;
            final all = [player].concat(thresholdBodies);
            final label = threshold == 10 ? 'tree used   ' : 'tree skipped';

            Bench.measure('$label (maxObjectsWithoutQuadTree=$threshold), 1 vs 150', 150, frames(60), () -> {
                pre(world, all);
                world.collide(player, group);
                post(world, all);
            }, () -> {
                thresholdBodies = scatter(150);
                group = toGroup(thresholdBodies);
                while (all.length > 1) all.pop();
                for (body in thresholdBodies) all.push(body);
            });
        }

    }

    static function separationLoad():Void {

        Bench.section('9. Separation load (how much overlapping actually costs)');
        Bench.header();

        // Same body count, different amounts of real contact
        for (spread in [1.0, 0.08]) {
            final label = spread == 1.0 ? 'sparse (few real overlaps) ' : 'dense (constant overlaps)  ';
            final world = newWorld();
            var bodies = scatter(200, 20, spread);
            var group = toGroup(bodies);

            Bench.measure('$label, 200 self-colliding', 200 * 200, frames(60), () -> {
                pre(world, bodies);
                world.collide(group);
                post(world, bodies);
            }, () -> {
                bodies = scatter(200, 20, spread);
                group = toGroup(bodies);
            });
        }

        // A pile of bodies resting on the ground: worst case for separation
        final world = newWorld();
        world.gravityY = 1000;
        var pile = scatter(200, 20, 0.15);
        var group = toGroup(pile);
        final ground = new Body(0, 1900, 2000, 100);
        ground.immovable = true;
        ground.allowGravity = false;
        var all = [ground].concat(pile);

        Bench.measure('200 bodies piling up on the ground', 200 * 200, frames(60), () -> {
            pre(world, all);
            world.collide(group);
            for (body in pile) world.collide(body, ground);
            post(world, all);
        }, () -> {
            pile = scatter(200, 20, 0.15);
            for (body in pile) body.y += 1500;
            group = toGroup(pile);
            all = [ground].concat(pile);
        });

    }

    static function overlapVsCollide():Void {

        Bench.section('10. overlap() vs collide()');
        Bench.header();

        for (useOverlap in [true, false]) {
            final label = useOverlap ? 'overlap (detect only) ' : 'collide (detect+resolve)';
            final world = newWorld();
            var bodies = scatter(200, 20, 0.3);
            var group = toGroup(bodies);

            Bench.measure('$label, 200 self-colliding', 200 * 200, frames(60), () -> {
                pre(world, bodies);
                if (useOverlap) world.overlap(group) else world.collide(group);
                post(world, bodies);
            }, () -> {
                bodies = scatter(200, 20, 0.3);
                group = toGroup(bodies);
            });
        }

    }

    static function realisticFrame():Void {

        Bench.section('11. Realistic game frames');
        Bench.header();

        // A platformer: a player, some enemies, a lot of static platforms
        final world = newWorld();
        world.gravityY = 1200;

        var platforms = scatter(200, 80, 1.0, 3);
        var enemies = scatter(60, 24, 1.0, 5);
        var bullets = scatter(120, 6, 1.0, 9);
        final player = new Body(1000, 1000, 24, 32);

        var platformGroup = toGroup(platforms);
        var enemyGroup = toGroup(enemies);
        var bulletGroup = toGroup(bullets);
        var all = [player].concat(platforms).concat(enemies).concat(bullets);

        function build() {
            platforms = scatter(200, 80, 1.0, 3);
            for (platform in platforms) {
                platform.immovable = true;
                platform.allowGravity = false;
                platform.velocityX = 0;
                platform.velocityY = 0;
            }
            enemies = scatter(60, 24, 1.0, 5);
            bullets = scatter(120, 6, 1.0, 9);
            for (bullet in bullets) bullet.allowGravity = false;
            platformGroup = toGroup(platforms);
            enemyGroup = toGroup(enemies);
            bulletGroup = toGroup(bullets);
            all = [player].concat(platforms).concat(enemies).concat(bullets);
        }

        Bench.measure('platformer: 1 player, 60 enemies, 200 platforms, 120 bullets', 381, frames(60), () -> {
            pre(world, all);
            world.collide(player, platformGroup);
            for (enemy in enemies) world.collide(enemy, platformGroup);
            world.overlap(player, enemyGroup);
            world.overlap(bulletGroup, enemyGroup);
            post(world, all);
        }, build);

        // The same scene, but colliding the enemies as a group instead of
        // looping body by body.
        Bench.measure('same scene, enemies as group vs platform group', 381, frames(60), () -> {
            pre(world, all);
            world.collide(player, platformGroup);
            world.collide(enemyGroup, platformGroup);
            world.overlap(player, enemyGroup);
            world.overlap(bulletGroup, enemyGroup);
            post(world, all);
        }, build);

        // A bullet-hell style scene: many small fast bodies, few targets
        final hellWorld = newWorld();
        var projectiles = scatter(1500, 6, 1.0, 21);
        var targets = scatter(20, 40, 1.0, 33);
        var projectileGroup = toGroup(projectiles);
        var targetGroup = toGroup(targets);
        var hellAll = projectiles.concat(targets);

        Bench.measure('bullet hell: 1500 projectiles vs 20 targets', 1500, frames(60), () -> {
            pre(hellWorld, hellAll);
            for (target in targets) hellWorld.overlap(target, projectileGroup);
            post(hellWorld, hellAll);
        }, () -> {
            projectiles = scatter(1500, 6, 1.0, 21);
            targets = scatter(20, 40, 1.0, 33);
            projectileGroup = toGroup(projectiles);
            targetGroup = toGroup(targets);
            hellAll = projectiles.concat(targets);
        });

    }

    static function allocation():Void {

        Bench.section('12. Allocation');
        Bench.header();

        Bench.measure('create 5000 bodies', 5000, frames(20), () -> {
            final bodies = [];
            for (i in 0...5000) {
                bodies.push(new Body(i % 2000, i % 2000, 16, 16));
            }
        });

        final world = newWorld();
        Bench.measure('acquire and release a pooled QuadTree 1000x', 1000, frames(20), () -> {
            for (_ in 0...1000) {
                final tree = world.getQuadTree();
                world.releaseQuadTree(tree);
            }
        });

    }

/// Summary

    static function summary():Void {

        Bench.println('');
        Bench.println('═════════════════════════════════════════════════════════════════════════════════');
        Bench.println('  Where the time goes');
        Bench.println('═════════════════════════════════════════════════════════════════════════════════');
        Bench.println('');

        Bench.println('  BROADPHASE — is the QuadTree earning its keep?');
        Bench.println('  (baseline = brute force scan, candidate = the QuadTree path)');
        Bench.compare('    body vs group, 100 bodies', 'brute force, 1 vs 100 bodies', 'quadtree   , 1 vs 100 bodies');
        Bench.compare('    body vs group, 500 bodies', 'brute force, 1 vs 500 bodies', 'quadtree   , 1 vs 500 bodies');
        Bench.compare('    body vs group, 2000 bodies', 'brute force, 1 vs 2000 bodies', 'quadtree   , 1 vs 2000 bodies');
        Bench.compare('    150 bodies, threshold flipped', 'tree skipped (maxObjectsWithoutQuadTree=200), 1 vs 150', 'tree used    (maxObjectsWithoutQuadTree=10), 1 vs 150');
        Bench.println('');
        Bench.compare('    rebuild per query vs reuse one tree', '50 retrieves against one reused tree', '50 build+retrieve cycles over 2000 bodies');
        Bench.println('');

        Bench.println('  CLUSTERING — a QuadTree only helps when bodies are spread out:');
        Bench.compare('    1000 bodies in 30% of the world', '1000 bodies spread over 100% of the world', '1000 bodies spread over 30% of the world');
        Bench.compare('    1000 bodies in 5% of the world', '1000 bodies spread over 100% of the world', '1000 bodies spread over 5% of the world');
        Bench.println('');

        Bench.println('  QUADRATIC GROWTH — group vs itself (n=1 would be linear, n=2 quadratic):');
        scaling(['50 bodies self-colliding', '100 bodies self-colliding', '200 bodies self-colliding', '400 bodies self-colliding'], [50, 100, 200, 400]);
        Bench.println('');
        Bench.println('  Group vs group grows the same way:');
        scaling(['50 vs 50 bodies', '100 vs 100 bodies', '200 vs 200 bodies'], [50, 100, 200]);
        Bench.println('');

        Bench.println('  NARROWPHASE AND SEPARATION:');
        Bench.compare('    circle bodies vs rectangles', 'rect bodies  , 150 self-colliding', 'circle bodies, 150 self-colliding');
        Bench.compare('    dense contacts vs sparse', 'sparse (few real overlaps) , 200 self-colliding', 'dense (constant overlaps)  , 200 self-colliding');
        Bench.compare('    collide() vs overlap()', 'overlap (detect only) , 200 self-colliding', 'collide (detect+resolve), 200 self-colliding');
        Bench.println('');

        Bench.println('  SORTING — cached per frame, so only the first call in a frame pays:');
        Bench.compare('    LEFT_RIGHT vs NONE, 1 vs 2000', 'sortDirection NONE       , 1 vs 2000', 'sortDirection LEFT_RIGHT, 1 vs 2000');
        Bench.compare('    shuffled vs already sorted, 1000', 'sort 1000 already sorted bodies', 'sort 1000 shuffled bodies');
        Bench.println('');

        Bench.println('  CALL SHAPE — same scene, same bodies, different API calls:');
        Bench.compare('    per-body loop vs one group call', 'same scene, enemies as group vs platform group', 'platformer: 1 player, 60 enemies, 200 platforms, 120 bullets');
        Bench.println('');

        Bench.println('  BASELINE COST — integration with no collision at all:');
        final integration = Bench.find('1000 bodies, plain velocity');
        if (integration != null) {
            Bench.println('    ${Bench.format(integration.usPerUnit, 3)} µs per body per frame');
        }
        Bench.compare('    gravity + bounds vs plain velocity', '1000 bodies, plain velocity', '1000 bodies, gravity + world bounds');
        Bench.println('');

        final worst = worstScenario();
        if (worst != null) {
            Bench.println('  Slowest single scenario: "${worst.name}"');
            Bench.println('    ${Bench.format(worst.msPerFrame, 3)} ms per frame (${Bench.format(worst.fps, 0)} fps budget)');
        }

        var overBudget = 0;
        for (result in Bench.results) {
            if (result.msPerFrame > 16.67) overBudget++;
        }
        Bench.println('');
        Bench.println('  $overBudget of ${Bench.results.length} scenarios exceed a 16.67 ms (60 fps) frame budget on this target.');
        Bench.println('');

    }

    /**
     * Prints how the measured cost grows against the body count, and the
     * implied exponent (1 = linear, 2 = quadratic).
     */
    static function scaling(names:Array<String>, counts:Array<Int>):Void {

        var previous:BenchResult = null;
        var previousCount = 0;

        for (i in 0...names.length) {
            final result = Bench.find(names[i]);
            if (result == null) continue;

            if (previous != null && previous.msPerFrame > 0) {
                final timeRatio = result.msPerFrame / previous.msPerFrame;
                final countRatio = counts[i] / previousCount;
                final exponent = Math.log(timeRatio) / Math.log(countRatio);
                Bench.println('    $previousCount -> ${counts[i]} bodies: ${Bench.format(timeRatio, 2)}x slower  (n^${Bench.format(exponent, 2)})');
            }

            previous = result;
            previousCount = counts[i];
        }

    }

    static function worstScenario():BenchResult {

        var worst:BenchResult = null;
        for (result in Bench.results) {
            if (worst == null || result.msPerFrame > worst.msPerFrame) worst = result;
        }
        return worst;

    }

}
