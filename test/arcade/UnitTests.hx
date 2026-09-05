package arcade;


using arcade.Extensions;

/**
 * Assertion-based test suite for the arcade physics library.
 *
 * Unlike `arcade.Test` (which renders interactive demos in a browser and needs
 * a human to look at them), this suite is headless and self-checking, so it can
 * run on any Haxe target and gate CI.
 *
 * Run it with: `haxe build.hxml`
 */
class UnitTests {

    static var world:World;

    public static function main():Void {

        Assert.verbose = true;

        bodyBasics();
        motionIntegration();
        worldBounds();
        bodyVsBody();
        massAndBounce();
        touchingAndBlockedFlags();
        overlapVsCollide();
        callbacks();
        circleBodies();
        groups();
        sorting();
        quadTree();
        worldHelpers();
        geometry();
        extensions();
        broadphase();
        regressions();

        final code = Assert.report();
        #if sys
        Sys.exit(code);
        #elseif js
        // Surface the result to CI when running under node
        js.Syntax.code("if (typeof process !== 'undefined') process.exitCode = {0}", code);
        #end

    }

/// Helpers

    /** A fresh 800x600 world with no gravity and a fixed 60fps timestep. */
    static function newWorld():World {

        final w = new World(0, 0, 800, 600);
        w.elapsed = 1 / 60;
        return w;

    }

    /**
     * Runs one full physics frame in the order the library requires:
     * preUpdate all bodies, then collisions, then postUpdate all bodies.
     */
    static function step(world:World, bodies:Array<Body>, ?collisions:Void->Void):Void {

        for (body in bodies) {
            body.preUpdate(world, body.x, body.y, body.width, body.height, body.rotation);
        }

        if (collisions != null) {
            collisions();
        }

        for (body in bodies) {
            body.postUpdate(world);
        }

    }

    /** Runs `count` frames. */
    static function steps(world:World, bodies:Array<Body>, count:Int, ?collisions:Void->Void):Void {

        for (_ in 0...count) {
            step(world, bodies, collisions);
        }

    }

/// Tests

    static function bodyBasics():Void {

        Assert.suite('Body basics');

        Assert.test('constructor stores position and size', () -> {
            final body = new Body(10, 20, 30, 40);
            Assert.equals(10.0, body.x);
            Assert.equals(20.0, body.y);
            Assert.equals(30.0, body.width);
            Assert.equals(40.0, body.height);
            Assert.equals(10.0, body.prevX);
            Assert.equals(20.0, body.prevY);
        });

        Assert.test('position is the top-left corner, not the center', () -> {
            final body = new Body(100, 100, 20, 20);
            Assert.equals(100.0, body.left);
            Assert.equals(100.0, body.top);
            Assert.equals(120.0, body.right);
            Assert.equals(120.0, body.bottom);
            Assert.equals(110.0, body.centerX);
            Assert.equals(110.0, body.centerY);
        });

        Assert.test('half size is floored, so odd sizes lose half a pixel', () -> {
            final body = new Body(0, 0, 31, 41);
            Assert.equals(15.0, body.halfWidth);
            Assert.equals(20.0, body.halfHeight);
            // Center is derived from the floored half size
            Assert.equals(15.0, body.centerX);
            Assert.equals(20.0, body.centerY);
        });

        Assert.test('updateSize recomputes half size', () -> {
            final body = new Body(0, 0, 10, 10);
            body.updateSize(40, 60);
            Assert.equals(40.0, body.width);
            Assert.equals(20.0, body.halfWidth);
            Assert.equals(30.0, body.halfHeight);
        });

        Assert.test('reset clears motion and moves the body', () -> {
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 100;
            body.velocityY = 50;
            body.accelerationX = 10;
            body.angularVelocity = 5;
            body.reset(200, 300, 20, 20);
            Assert.equals(200.0, body.x);
            Assert.equals(300.0, body.y);
            Assert.equals(0.0, body.velocityX);
            Assert.equals(0.0, body.velocityY);
            Assert.equals(0.0, body.accelerationX);
            Assert.equals(0.0, body.angularVelocity);
            Assert.equals(200.0, body.prevX);
        });

        Assert.test('stop zeroes velocity and acceleration but not position', () -> {
            final body = new Body(50, 50, 10, 10);
            body.velocityX = 100;
            body.accelerationY = 20;
            body.stop();
            Assert.equals(0.0, body.velocityX);
            Assert.equals(0.0, body.accelerationY);
            Assert.equals(50.0, body.x);
        });

        Assert.test('hitTest detects points inside a rectangular body', () -> {
            final body = new Body(10, 10, 20, 20);
            Assert.isTrue(body.hitTest(15, 15));
            Assert.isTrue(body.hitTest(10, 10));
            Assert.isFalse(body.hitTest(5, 15));
            Assert.isFalse(body.hitTest(15, 35));
        });

        Assert.test('hitTest uses the center and radius for circular bodies', () -> {
            final body = new Body(0, 0, 20, 20);
            body.setCircle(10);
            // The circle is centered on (10,10) with radius 10, matching what
            // World.intersects and separateCircle use
            Assert.isTrue(body.hitTest(10, 10), 'the center is inside the circle');
            Assert.isTrue(body.hitTest(18, 10));
            Assert.isTrue(body.hitTest(10, 18));
            // A rectangle would contain these corners, a circle does not
            Assert.isFalse(body.hitTest(1, 1), 'the top left corner is outside the circle');
            Assert.isFalse(body.hitTest(19, 19));
            // Outside the bounding box entirely
            Assert.isFalse(body.hitTest(-5, 10));
            Assert.isFalse(body.hitTest(10, 25));
        });

        Assert.test('circle hitTest agrees with circle collision', () -> {
            final world = newWorld();
            final circle = new Body(100, 100, 20, 20);
            circle.setCircle(10);
            // A one pixel probe centered where hitTest reports a hit must also
            // be reported as intersecting, and vice versa
            for (offset in [1, 5, 10, 15, 19]) {
                final probe = new Body(100 + offset, 110, 1, 1);
                final hit = circle.hitTest(probe.x, probe.y);
                final intersecting = world.intersects(circle, probe);
                Assert.equals(hit, intersecting, 'hitTest and intersects disagree at offset $offset');
            }
        });

        Assert.test('deltaX/deltaY report movement during the collision phase', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 120;
            body.velocityY = -60;
            step(world, [body], () -> {
                // Deltas are only meaningful between preUpdate and postUpdate
                Assert.near(2, body.deltaX());
                Assert.near(-1, body.deltaY());
                Assert.near(2, body.deltaAbsX());
                Assert.near(1, body.deltaAbsY());
            });
        });

        Assert.test('deltaX/deltaY are zero again once the frame is finished', () -> {
            // postUpdate copies x into prevX, so the live delta collapses to
            // zero; the cached `dx`/`dy` still hold the frame's movement.
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 120;
            step(world, [body]);
            Assert.near(0, body.deltaX());
            Assert.near(2, body.dx, 0.0001, 'dx caches the movement of the frame');
        });

        Assert.test('facing is derived from movement direction', () -> {
            final world = newWorld();
            final body = new Body(100, 100, 10, 10);
            body.velocityX = 120;
            step(world, [body]);
            Assert.equals(Direction.RIGHT, body.facing);
            body.velocityX = -120;
            step(world, [body]);
            Assert.equals(Direction.LEFT, body.facing);
        });

        Assert.test('a disabled body does not move', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 600;
            body.enable = false;
            steps(world, [body], 10);
            Assert.equals(0.0, body.x);
        });

        Assert.test('a body with moves=false keeps its velocity but stays put', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 600;
            body.moves = false;
            steps(world, [body], 10);
            Assert.equals(0.0, body.x);
            Assert.equals(600.0, body.velocityX);
        });

    }

    static function motionIntegration():Void {

        Assert.suite('Motion integration');

        Assert.test('velocity moves the body by velocity * elapsed each frame', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 60;
            step(world, [body]);
            Assert.near(1, body.x);
            step(world, [body]);
            Assert.near(2, body.x);
        });

        Assert.test('world gravity accelerates the body', () -> {
            final world = newWorld();
            world.gravityY = 600;
            final body = new Body(0, 0, 10, 10);
            step(world, [body]);
            // Velocity is integrated before position
            Assert.near(10, body.velocityY);
            Assert.near(10.0 / 60.0, body.y);
        });

        Assert.test('per body gravity adds to world gravity', () -> {
            final world = newWorld();
            world.gravityY = 600;
            final body = new Body(0, 0, 10, 10);
            body.gravityY = 600;
            step(world, [body]);
            Assert.near(20, body.velocityY);
        });

        Assert.test('allowGravity=false opts a body out of gravity', () -> {
            final world = newWorld();
            world.gravityY = 600;
            final body = new Body(0, 0, 10, 10);
            body.allowGravity = false;
            steps(world, [body], 10);
            Assert.equals(0.0, body.velocityY);
            Assert.equals(0.0, body.y);
        });

        Assert.test('acceleration increases velocity', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.accelerationX = 600;
            step(world, [body]);
            Assert.near(10, body.velocityX);
            step(world, [body]);
            Assert.near(20, body.velocityX);
        });

        Assert.test('drag reduces velocity toward zero', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 100;
            body.dragX = 600;
            step(world, [body]);
            Assert.near(90, body.velocityX);
        });

        Assert.test('drag never overshoots past zero', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 5;
            body.dragX = 600; // 10 per frame, more than the remaining velocity
            step(world, [body]);
            Assert.equals(0.0, body.velocityX, 'drag should clamp at zero, not flip the sign');
        });

        Assert.test('drag applies symmetrically to negative velocity', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = -100;
            body.dragX = 600;
            step(world, [body]);
            Assert.near(-90, body.velocityX);
        });

        Assert.test('allowDrag=false disables drag', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 100;
            body.dragX = 600;
            body.allowDrag = false;
            step(world, [body]);
            Assert.near(100, body.velocityX);
        });

        Assert.test('velocity is clamped to maxVelocity', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.maxVelocityX = 50;
            body.accelerationX = 60000;
            step(world, [body]);
            Assert.equals(50.0, body.velocityX);
            body.accelerationX = -60000;
            step(world, [body]);
            Assert.equals(-50.0, body.velocityX);
        });

        Assert.test('speed is the magnitude of the velocity vector', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 30;
            body.velocityY = 40;
            step(world, [body]);
            Assert.near(50, body.speed);
        });

        Assert.test('angular velocity rotates the body', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.angularVelocity = 60;
            step(world, [body]);
            Assert.near(1, body.rotation);
        });

        Assert.test('angular acceleration and drag behave like linear ones', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.angularAcceleration = 600;
            step(world, [body]);
            Assert.near(10, body.angularVelocity);

            body.angularAcceleration = 0;
            body.angularDrag = 600;
            step(world, [body]);
            Assert.near(0, body.angularVelocity);
        });

        Assert.test('angular velocity is clamped to maxAngularVelocity', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.maxAngularVelocity = 90;
            body.angularAcceleration = 60000;
            step(world, [body]);
            Assert.equals(90.0, body.angularVelocity);
        });

        Assert.test('a body with no angular motion keeps its rotation', () -> {
            // The angular integration is skipped entirely for these bodies, so
            // check nothing else changes as a side effect
            final world = newWorld();
            final body = new Body(0, 0, 10, 10, 1.5);
            body.angularDrag = 600;
            body.maxAngularVelocity = 10;
            steps(world, [body], 10);
            Assert.equals(1.5, body.rotation, 'rotation must be left alone');
            Assert.equals(0.0, body.angularVelocity);
        });

        Assert.test('angular drag still stops a spinning body', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.angularVelocity = 100;
            body.angularDrag = 600;
            steps(world, [body], 20);
            Assert.equals(0.0, body.angularVelocity, 'drag should bring the spin to rest');
            final settled = body.rotation;
            steps(world, [body], 5);
            Assert.equals(settled, body.rotation, 'and it should stay at rest');
        });

        Assert.test('allowRotation=false freezes rotation', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.allowRotation = false;
            body.angularVelocity = 600;
            steps(world, [body], 10);
            Assert.equals(0.0, body.rotation);
        });

        Assert.test('elapsed drives the timestep, so a bigger delta moves further', () -> {
            final world = newWorld();
            world.elapsed = 1 / 30;
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 60;
            step(world, [body]);
            Assert.near(2, body.x);
            Assert.equals(33.0, world.elapsedMS);
        });

        Assert.test('isPaused halts all motion', () -> {
            final world = newWorld();
            world.gravityY = 800;
            world.isPaused = true;
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 60;
            steps(world, [body], 10);
            Assert.equals(0.0, body.x, 'a paused world must not move bodies');
            Assert.equals(0.0, body.y);
            Assert.equals(60.0, body.velocityX, 'velocity is preserved across the pause');
            Assert.equals(0.0, body.velocityY, 'gravity must not accumulate while paused');
        });

        Assert.test('unpausing resumes motion from where it stopped', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 60;
            step(world, [body]);
            Assert.near(1, body.x);

            world.isPaused = true;
            steps(world, [body], 10);
            Assert.near(1, body.x, 0.0001, 'no movement while paused');

            world.isPaused = false;
            step(world, [body]);
            Assert.near(2, body.x, 0.0001, 'motion resumes at the same velocity');
        });

        Assert.test('collision still works while the world is paused', () -> {
            // isPaused stops motion, but collide/overlap are documented to
            // keep working
            final world = newWorld();
            world.isPaused = true;
            final a = new Body(100, 100, 20, 20);
            final b = new Body(110, 100, 20, 20);
            Assert.isTrue(world.overlap(a, b), 'overlap should still be detected');
        });

    }

    static function worldBounds():Void {

        Assert.suite('World bounds');

        Assert.test('collideWorldBounds stops a body at the left edge', () -> {
            final world = newWorld();
            final body = new Body(5, 100, 10, 10);
            body.collideWorldBounds = true;
            body.velocityX = -600;
            step(world, [body]);
            Assert.equals(0.0, body.x);
            Assert.isTrue(body.blockedLeft);
            Assert.isTrue(body.isOnWall());
        });

        Assert.test('collideWorldBounds stops a body at the right edge', () -> {
            final world = newWorld();
            final body = new Body(795, 100, 10, 10);
            body.collideWorldBounds = true;
            body.velocityX = 600;
            step(world, [body]);
            Assert.equals(790.0, body.x, 'body should sit flush against the right edge');
            Assert.isTrue(body.blockedRight);
        });

        Assert.test('collideWorldBounds stops a body at the bottom edge', () -> {
            final world = newWorld();
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.velocityY = 600;
            step(world, [body]);
            Assert.equals(590.0, body.y);
            Assert.isTrue(body.blockedDown);
            Assert.isTrue(body.isOnFloor());
        });

        Assert.test('collideWorldBounds stops a body at the top edge', () -> {
            final world = newWorld();
            final body = new Body(100, 5, 10, 10);
            body.collideWorldBounds = true;
            body.velocityY = -600;
            step(world, [body]);
            Assert.equals(0.0, body.y);
            Assert.isTrue(body.blockedUp);
            Assert.isTrue(body.isOnCeiling());
        });

        Assert.test('bounce reflects velocity off the bounds', () -> {
            final world = newWorld();
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.bounceY = 0.5;
            body.velocityY = 600;
            step(world, [body]);
            Assert.near(-300, body.velocityY, 0.0001, 'velocity should reverse and halve');
        });

        Assert.test('zero bounce kills velocity at the bounds', () -> {
            final world = newWorld();
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.velocityY = 600;
            step(world, [body]);
            Assert.equals(0.0, body.velocityY);
        });

        Assert.test('useWorldBounce overrides bounce for the bounds only', () -> {
            final world = newWorld();
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.bounceY = 0;
            body.useWorldBounce = true;
            body.worldBounceY = 1;
            body.velocityY = 600;
            step(world, [body]);
            Assert.near(-600, body.velocityY);
        });

        Assert.test('bodies leave the world when collideWorldBounds is false', () -> {
            final world = newWorld();
            final body = new Body(5, 100, 10, 10);
            body.velocityX = -600;
            step(world, [body]);
            Assert.near(-5, body.x);
            Assert.isTrue(body.blockedNone);
        });

        Assert.test('world checkCollision flags disable individual edges', () -> {
            final world = newWorld();
            world.checkCollisionDown = false;
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.velocityY = 600;
            step(world, [body]);
            Assert.greater(590, body.y, 'body should fall through a disabled bottom edge');
            Assert.isFalse(body.blockedDown);
        });

        Assert.test('setBounds moves the world walls', () -> {
            final world = newWorld();
            world.setBounds(100, 100, 200, 200);
            final body = new Body(105, 150, 10, 10);
            body.collideWorldBounds = true;
            body.velocityX = -600;
            step(world, [body]);
            Assert.equals(100.0, body.x);
        });

        Assert.test('a bouncing body settles instead of tunnelling out', () -> {
            final world = newWorld();
            world.gravityY = 1000;
            final body = new Body(100, 100, 20, 20);
            body.collideWorldBounds = true;
            body.bounceY = 0.5;
            steps(world, [body], 600);
            Assert.isTrue(body.y <= 580, 'body should stay inside the world, got y=${body.y}');
            Assert.isTrue(body.y >= 0, 'body should stay inside the world, got y=${body.y}');
        });

    }

    static function bodyVsBody():Void {

        Assert.suite('Body vs body collision');

        Assert.test('collide separates two bodies that move into each other', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isFalse(world.intersects(a, b), 'bodies should not overlap after separation');
        });

        Assert.test('collide returns true only when a collision happened', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(500, 100, 20, 20);
            step(world, [a, b], () -> {
                Assert.isFalse(world.collide(a, b), 'distant bodies should not collide');
            });

            final c = new Body(100, 100, 20, 20);
            final d = new Body(120, 100, 20, 20);
            c.velocityX = 60;
            step(world, [c, d], () -> {
                Assert.isTrue(world.collide(c, d), 'overlapping bodies should collide');
            });
        });

        Assert.test('an immovable body does not move, the other one does', () -> {
            final world = newWorld();
            final mover = new Body(100, 100, 20, 20);
            final wall = new Body(120, 100, 20, 20);
            wall.immovable = true;
            mover.velocityX = 300;
            step(world, [mover, wall], () -> world.collide(mover, wall));
            Assert.equals(120.0, wall.x, 'immovable body must not be displaced');
            Assert.isFalse(world.intersects(mover, wall));
        });

        Assert.test('two immovable bodies are never separated', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(115, 100, 20, 20);
            a.immovable = true;
            b.immovable = true;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.equals(100.0, a.x);
            Assert.equals(115.0, b.x);
        });

        Assert.test('a body resting on immovable ground stops falling', () -> {
            final world = newWorld();
            world.gravityY = 1000;
            final ground = new Body(0, 500, 800, 100);
            ground.immovable = true;
            ground.allowGravity = false;
            final box = new Body(100, 100, 20, 20);
            steps(world, [box, ground], 200, () -> world.collide(box, ground));
            Assert.near(480, box.y, 1.0, 'box should come to rest on top of the ground');
            Assert.isTrue(box.touchingDown);
        });

        Assert.test('intersects is false for a body against itself', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            Assert.isFalse(world.intersects(body, body));
        });

        Assert.test('touching edges do not count as intersecting', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 10, 10);
            final b = new Body(10, 0, 10, 10);
            Assert.isFalse(world.intersects(a, b), 'edge contact is not an overlap');
        });

        Assert.test('checkCollisionNone opts a body out of all collisions', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            b.checkCollisionNone = true;
            step(world, [a, b], () -> {
                Assert.isFalse(world.collide(a, b));
            });
        });

        Assert.test('a disabled body is skipped by collide', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(110, 100, 20, 20);
            b.enable = false;
            step(world, [a, b], () -> {
                Assert.isFalse(world.collide(a, b));
            });
        });

        Assert.test('separate tolerates null bodies', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            Assert.isFalse(world.collide(a, null));
        });

        Assert.test('customSeparateX reports the collision without moving bodies', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.customSeparateX = true;
            a.velocityX = 60;
            b.immovable = true;
            step(world, [a, b], () -> {
                Assert.isTrue(world.collide(a, b), 'collision is still reported');
            });
            Assert.isTrue(world.intersects(a, b), 'but no separation took place');
        });

        Assert.test('overlapBias lets fast bodies pass through (tunnelling guard)', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(110, 100, 20, 20);
            a.forceX = true;
            // A huge overlap relative to the movement is treated as "already past"
            // and ignored, which is what stops bodies snapping backwards.
            world.overlapBias = 0;
            a.velocityX = 0.0001;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(world.intersects(a, b), 'overlap beyond the bias is not separated');
        });

    }

    static function massAndBounce():Void {

        Assert.suite('Mass and bounce');

        Assert.test('equal masses swap velocities in an elastic collision', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.bounceX = 1;
            b.bounceX = 1;
            a.velocityX = 100;
            b.velocityX = -100;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.near(-100, a.velocityX, 0.001, 'equal masses should exchange velocity');
            Assert.near(100, b.velocityX, 0.001);
        });

        Assert.test('a heavy body barely slows against a light one', () -> {
            final world = newWorld();
            final heavy = new Body(100, 100, 20, 20);
            final light = new Body(120, 100, 20, 20);
            heavy.forceX = true;
            heavy.mass = 1000;
            light.mass = 1;
            heavy.bounceX = 1;
            light.bounceX = 1;
            heavy.velocityX = 100;
            step(world, [heavy, light], () -> world.collide(heavy, light));
            Assert.greater(99, heavy.velocityX, 'heavy body should keep almost all its speed');
            Assert.greater(190, light.velocityX, 'light body should be knocked away fast');
        });

        Assert.test('momentum is conserved when both bodies are movable', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.mass = 3;
            b.mass = 1;
            a.bounceX = 1;
            b.bounceX = 1;
            a.velocityX = 80;
            b.velocityX = -40;
            final before = a.mass * a.velocityX + b.mass * b.velocityX;
            step(world, [a, b], () -> world.collide(a, b));
            final after = a.mass * a.velocityX + b.mass * b.velocityX;
            Assert.near(before, after, 0.001, 'total momentum should be preserved');
        });

        Assert.test('bounce scales the post-collision velocity', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.bounceX = 0.5;
            b.bounceX = 0.5;
            a.velocityX = 100;
            b.velocityX = -100;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.near(-50, a.velocityX, 0.001, 'bounce 0.5 should halve the exchanged velocity');
        });

        Assert.test('bodies are pushed apart symmetrically when both are movable', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.velocityX = 60;
            var aMoved:Float = 0;
            var bMoved:Float = 0;
            step(world, [a, b], () -> {
                // Measure the separation itself, after motion has been integrated
                final aBefore = a.x;
                final bBefore = b.x;
                world.collide(a, b);
                aMoved = aBefore - a.x;
                bMoved = b.x - bBefore;
            });
            Assert.greater(0, aMoved, 'the left body should be pushed left');
            Assert.near(aMoved, bMoved, 0.001, 'each body should absorb half the overlap');
        });

    }

    static function touchingAndBlockedFlags():Void {

        Assert.suite('Touching and blocked flags');

        Assert.test('touching flags are set on both sides of a collision', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.velocityX = 300;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(a.touchingRight, 'left body is touching on its right');
            Assert.isTrue(b.touchingLeft, 'right body is touching on its left');
            Assert.isFalse(a.touchingNone);
        });

        Assert.test('blocked is only set against an immovable body', () -> {
            final world = newWorld();
            final mover = new Body(100, 100, 20, 20);
            final wall = new Body(120, 100, 20, 20);
            wall.immovable = true;
            mover.forceX = true;
            mover.velocityX = 300;
            step(world, [mover, wall], () -> world.collide(mover, wall));
            Assert.isTrue(mover.blockedRight, 'blocked by an immovable body');
            Assert.isFalse(mover.blockedNone);
        });

        Assert.test('a collision against a movable body is touching but not blocked', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.velocityX = 300;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(a.touchingRight);
            Assert.isTrue(a.blockedNone, 'movable bodies do not block each other');
        });

        Assert.test('flags reset every frame and move into wasTouching', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.velocityX = 300;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(a.touchingRight);

            // Next frame with no collision at all
            final far = new Body(700, 100, 20, 20);
            step(world, [a, far], () -> world.collide(a, far));
            Assert.isFalse(a.touchingRight, 'touching flags clear at the start of a frame');
            Assert.isTrue(a.wasTouchingRight, 'previous frame state is preserved');
        });

        Assert.test('embedded is set when two static bodies overlap', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(105, 100, 20, 20);
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(a.embedded, 'overlapping motionless bodies are flagged as embedded');
            Assert.isTrue(b.embedded);
        });

    }

    static function overlapVsCollide():Void {

        Assert.suite('Overlap vs collide');

        Assert.test('overlap detects contact without separating', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(115, 100, 20, 20);
            a.velocityX = 60;
            step(world, [a, b], () -> {
                Assert.isTrue(world.overlap(a, b), 'overlap should be detected');
            });
            Assert.isTrue(world.intersects(a, b), 'overlap must not move the bodies');
        });

        Assert.test('overlap still sets touching flags', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.forceX = true;
            a.velocityX = 300;
            step(world, [a, b], () -> world.overlap(a, b));
            Assert.isFalse(a.touchingNone);
        });

        Assert.test('overlap does not change velocities', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 300;
            b.bounceX = 1;
            step(world, [a, b], () -> world.overlap(a, b));
            Assert.equals(300.0, a.velocityX);
            Assert.equals(0.0, b.velocityX);
        });

    }

    static function callbacks():Void {

        Assert.suite('Callbacks');

        Assert.test('collide callback receives both bodies', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            var calls = 0;
            step(world, [a, b], () -> world.collide(a, b, (b1, b2) -> {
                calls++;
                Assert.equals(a, b1);
                Assert.equals(b, b2);
            }));
            Assert.equals(1, calls);
        });

        Assert.test('process callback returning false cancels the separation', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            var collided = false;
            step(world, [a, b], () -> {
                Assert.isFalse(world.collide(a, b, (_, _) -> collided = true, (_, _) -> false));
            });
            Assert.isFalse(collided, 'collide callback must not fire when the process callback vetoes');
            Assert.isTrue(world.intersects(a, b), 'vetoed collisions do not separate');
        });

        Assert.test('process callback returning true allows the separation', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            step(world, [a, b], () -> world.collide(a, b, null, (_, _) -> true));
            Assert.isFalse(world.intersects(a, b));
        });

        Assert.test('one-way platform pattern works via the process callback', () -> {
            final world = newWorld();
            world.gravityY = 1000;
            final platform = new Body(80, 300, 200, 10);
            platform.immovable = true;
            platform.allowGravity = false;
            final player = new Body(100, 200, 20, 20);

            // Only collide when the player is moving down and above the platform
            final oneWay = (p:Body, plat:Body) -> p.velocityY > 0 && p.bottom <= plat.top + p.deltaAbsY() + 4;

            steps(world, [player, platform], 100, () -> world.collide(player, platform, null, oneWay));
            Assert.near(280, player.y, 2.0, 'player should land on the platform');

            // Now approach from below: the player must pass through
            player.reset(100, 400, 20, 20);
            steps(world, [player, platform], 12, () -> {
                player.velocityY = -600;
                world.collide(player, platform, null, oneWay);
            });
            Assert.less(300, player.y, 'player should pass upward through the platform, got y=${player.y}');
        });

        Assert.test('onCollide fires on both bodies', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            var aFired = false;
            var bFired = false;
            a.onCollide = (_, _) -> aFired = true;
            b.onCollide = (_, _) -> bFired = true;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(aFired);
            Assert.isTrue(bFired);
        });

        Assert.test('onOverlap fires for overlaps', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(115, 100, 20, 20);
            a.velocityX = 60;
            var fired = false;
            a.onOverlap = (_, _) -> fired = true;
            step(world, [a, b], () -> world.overlap(a, b));
            Assert.isTrue(fired);
        });

        Assert.test('onWorldBounds reports which edges were hit', () -> {
            final world = newWorld();
            final body = new Body(100, 595, 10, 10);
            body.collideWorldBounds = true;
            body.velocityY = 600;
            var down = false;
            var up = false;
            body.onWorldBounds = (_, u, d, _, _) -> { up = u; down = d; };
            step(world, [body]);
            Assert.isTrue(down, 'bottom edge should be reported');
            Assert.isFalse(up);
        });

    }

    static function circleBodies():Void {

        Assert.suite('Circle bodies');

        Assert.test('setCircle switches the shape and resizes the body', () -> {
            final body = new Body(0, 0, 10, 10);
            body.setCircle(25);
            Assert.isTrue(body.isCircle);
            Assert.equals(25.0, body.radius);
            Assert.equals(50.0, body.width);
            Assert.equals(50.0, body.height);
        });

        Assert.test('setCircle(0) reverts to a rectangle', () -> {
            final body = new Body(0, 0, 10, 10);
            body.setCircle(25);
            body.setCircle(0);
            Assert.isFalse(body.isCircle);
        });

        Assert.test('circle vs circle intersects by center distance', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 20, 20);
            final b = new Body(0, 0, 20, 20);
            a.setCircle(10);
            b.setCircle(10);

            // Centers 15 apart, radii sum to 20 -> overlap
            b.x = 15;
            b.updateCenter();
            Assert.isTrue(world.intersects(a, b));

            // Centers 30 apart -> no overlap
            b.x = 30;
            b.updateCenter();
            Assert.isFalse(world.intersects(a, b));
        });

        Assert.test('circle corners do not collide like rectangles', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 20, 20);
            final b = new Body(0, 0, 20, 20);
            a.setCircle(10);
            b.setCircle(10);
            // Diagonal offset: rectangles would overlap, circles do not
            b.x = 15;
            b.y = 15;
            b.updateCenter();
            Assert.isFalse(world.intersects(a, b), 'diagonal circles at this distance must not touch');
        });

        Assert.test('circle vs circle collision separates the bodies', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(119, 100, 20, 20);
            a.setCircle(10);
            b.setCircle(10);
            a.velocityX = 60;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isFalse(world.intersects(a, b), 'circles should be pushed apart');
        });

        Assert.test('circle vs rectangle collision is detected', () -> {
            final world = newWorld();
            final circle = new Body(100, 100, 20, 20);
            circle.setCircle(10);
            final rect = new Body(120, 100, 20, 20);
            rect.immovable = true;
            circle.velocityX = 300;
            step(world, [circle, rect], () -> {
                Assert.isTrue(world.collide(circle, rect));
            });
        });

        Assert.test('a circle resting on immovable ground stops falling', () -> {
            final world = newWorld();
            world.gravityY = 1000;
            final ground = new Body(0, 500, 800, 100);
            ground.immovable = true;
            ground.allowGravity = false;
            final ball = new Body(100, 100, 40, 40);
            ball.setCircle(20);
            steps(world, [ball, ground], 200, () -> world.collide(ball, ground));
            Assert.less(505, ball.y, 'ball should not sink through the ground, got y=${ball.y}');
            Assert.greater(400, ball.y, 'ball should have fallen to the ground, got y=${ball.y}');
        });

    }

    static function groups():Void {

        Assert.suite('Groups');

        Assert.test('add and remove maintain the object list', () -> {
            final group = new Group();
            final a = new Body(0, 0, 10, 10);
            final b = new Body(0, 0, 10, 10);
            group.add(a);
            group.add(b);
            Assert.equals(2, group.objects.length);
            group.remove(a);
            Assert.equals(1, group.objects.length);
            Assert.equals(b, group.objects[0]);
        });

        Assert.test('adding the same body twice is ignored', () -> {
            final group = new Group();
            final a = new Body(0, 0, 10, 10);
            group.add(a);
            group.add(a);
            Assert.equals(1, group.objects.length);
        });

        Assert.test('bodies track which groups contain them', () -> {
            final group = new Group();
            final a = new Body(0, 0, 10, 10);
            group.add(a);
            Assert.notNull(a.groups);
            Assert.equals(1, a.groups.length);
            group.remove(a);
            Assert.equals(0, a.groups.length);
        });

        Assert.test('the group setter moves a body between groups', () -> {
            final g1 = new Group();
            final g2 = new Group();
            final a = new Body(0, 0, 10, 10);
            a.group = g1;
            Assert.equals(1, g1.objects.length);
            a.group = g2;
            Assert.equals(0, g1.objects.length, 'body should leave its previous group');
            Assert.equals(1, g2.objects.length);
        });

        Assert.test('destroy removes the body from all its groups', () -> {
            final g1 = new Group();
            final g2 = new Group();
            final a = new Body(0, 0, 10, 10);
            g1.add(a);
            g2.add(a);
            a.destroy();
            Assert.equals(0, g1.objects.length);
            Assert.equals(0, g2.objects.length);
        });

        Assert.test('body vs group collides against every member', () -> {
            final world = newWorld();
            final group = new Group();
            final walls = [];
            for (i in 0...5) {
                final wall = new Body(200 + i * 30, 100, 20, 20);
                wall.immovable = true;
                group.add(wall);
                walls.push(wall);
            }
            final player = new Body(190, 100, 20, 20);
            player.velocityX = 300;
            final all = [player].concat(walls);
            var hits = 0;
            step(world, all, () -> world.collide(player, group, (_, _) -> hits++));
            Assert.equals(1, hits, 'player should hit exactly the first wall');
        });

        Assert.test('group vs group collides across both lists', () -> {
            final world = newWorld();
            final g1 = new Group();
            final g2 = new Group();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            g1.add(a);
            g2.add(b);
            var hits = 0;
            step(world, [a, b], () -> world.collide(g1, g2, (_, _) -> hits++));
            Assert.equals(1, hits);
        });

        Assert.test('group vs itself reports each pair exactly once', () -> {
            final world = newWorld();
            final group = new Group();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(115, 100, 20, 20);
            a.velocityX = 60;
            group.add(a);
            group.add(b);
            var hits = 0;
            var first:Body = null;
            var second:Body = null;
            step(world, [a, b], () -> world.overlap(group, (b1, b2) -> {
                hits++;
                first = b1;
                second = b2;
            }));
            Assert.equals(1, hits, 'each unordered pair is visited once');
            Assert.equals(a, first, 'the body earlier in the group is passed first');
            Assert.equals(b, second);
        });

        Assert.test('group vs itself checks every pair in a larger group', () -> {
            // n bodies, all mutually overlapping, means n*(n-1)/2 pairs
            final world = newWorld();
            final group = new Group();
            final bodies = [];
            for (i in 0...6) {
                final body = new Body(100 + i, 100, 20, 20);
                group.add(body);
                bodies.push(body);
            }
            bodies[0].velocityX = 1;
            var hits = 0;
            step(world, bodies, () -> world.overlap(group, (_, _) -> hits++));
            Assert.equals(15, hits, '6 bodies give 15 unordered pairs');
        });

        Assert.test('group vs itself separates a pair only once', () -> {
            // The second visit finds the bodies already separated
            final world = newWorld();
            final group = new Group();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(120, 100, 20, 20);
            a.velocityX = 60;
            group.add(a);
            group.add(b);
            var hits = 0;
            step(world, [a, b], () -> world.collide(group, (_, _) -> hits++));
            Assert.equals(1, hits);
        });

        Assert.test('a body never collides with itself inside a group', () -> {
            final world = newWorld();
            final group = new Group();
            final a = new Body(100, 100, 20, 20);
            group.add(a);
            var hits = 0;
            step(world, [a], () -> world.collide(group, (_, _) -> hits++));
            Assert.equals(0, hits);
        });

        Assert.test('overlap on a group of many bodies finds the right one', () -> {
            // More than maxObjectsWithoutQuadTree, so the QuadTree path is used
            final world = newWorld();
            final group = new Group();
            final bodies = [];
            for (i in 0...40) {
                final body = new Body(20 + (i % 20) * 38, 20 + Std.int(i / 20) * 200, 16, 16);
                body.immovable = true;
                group.add(body);
                bodies.push(body);
            }
            final target = bodies[7];
            final probe = new Body(target.x + 4, target.y + 4, 8, 8);
            probe.velocityX = 1;
            var found:Body = null;
            step(world, [probe].concat(bodies), () -> world.overlap(probe, group, (_, other) -> found = other));
            Assert.equals(target, found, 'quadtree path should find the overlapping body');
        });

    }

    static function sorting():Void {

        Assert.suite('Sorting');

        function makeGroup(xs:Array<Float>, ys:Array<Float>):Group {
            final group = new Group();
            for (i in 0...xs.length) {
                group.add(new Body(xs[i], ys[i], 10, 10));
            }
            return group;
        }

        Assert.test('sortLeftRight orders by ascending x', () -> {
            final group = makeGroup([50, 10, 30, 20], [0, 0, 0, 0]);
            group.sortLeftRight();
            Assert.equals(10.0, group.objects[0].x);
            Assert.equals(20.0, group.objects[1].x);
            Assert.equals(30.0, group.objects[2].x);
            Assert.equals(50.0, group.objects[3].x);
        });

        Assert.test('sortRightLeft orders by descending x', () -> {
            final group = makeGroup([50, 10, 30, 20], [0, 0, 0, 0]);
            group.sortRightLeft();
            Assert.equals(50.0, group.objects[0].x);
            Assert.equals(10.0, group.objects[3].x);
        });

        Assert.test('sortTopBottom orders by ascending y', () -> {
            final group = makeGroup([0, 0, 0, 0], [50, 10, 30, 20]);
            group.sortTopBottom();
            Assert.equals(10.0, group.objects[0].y);
            Assert.equals(50.0, group.objects[3].y);
        });

        Assert.test('sortBottomTop orders by descending y', () -> {
            final group = makeGroup([0, 0, 0, 0], [50, 10, 30, 20]);
            group.sortBottomTop();
            Assert.equals(50.0, group.objects[0].y);
            Assert.equals(10.0, group.objects[3].y);
        });

        Assert.test('sorting is stable for equal keys', () -> {
            final group = new Group();
            final bodies = [];
            for (i in 0...8) {
                final body = new Body(100, 0, 10, 10);
                body.index = i;
                group.add(body);
                bodies.push(body);
            }
            group.sortLeftRight();
            for (i in 0...8) {
                Assert.equals(i, group.objects[i].index, 'equal keys must keep their relative order');
            }
        });

        Assert.test('sorting a large group keeps every element', () -> {
            final group = new Group();
            var seed = 12345;
            for (i in 0...500) {
                seed = (seed * 1103515245 + 12345) & 0x7fffffff;
                group.add(new Body(seed % 800, 0, 10, 10));
            }
            group.sortLeftRight();
            Assert.equals(500, group.objects.length);
            for (i in 1...group.objects.length) {
                Assert.isTrue(group.objects[i - 1].x <= group.objects[i].x, 'array must be fully ordered');
            }
        });

        Assert.test('a nearly sorted group sorts correctly', () -> {
            // The insertion path: the array is already almost in order
            final group = new Group();
            final bodies = [];
            for (i in 0...300) {
                final body = new Body(i * 10, 0, 10, 10);
                body.index = i;
                group.add(body);
                bodies.push(body);
            }
            // Nudge each body a little, as a frame of motion would
            var state = 5;
            for (body in bodies) {
                state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                body.x += (state % 40) - 20;
            }
            group.sortLeftRight();
            Assert.equals(300, group.objects.length, 'no body may be lost');
            for (i in 1...group.objects.length) {
                Assert.isTrue(group.objects[i - 1].x <= group.objects[i].x, 'must be fully ordered at $i');
            }
        });

        Assert.test('a badly disordered group still sorts correctly', () -> {
            // Big enough and shuffled enough to exhaust the insertion budget
            // and hand over to the merge sort mid-way
            final group = new Group();
            var state = 77;
            final seen = new Map<Int, Bool>();
            for (i in 0...2000) {
                state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                final body = new Body(state % 100000, 0, 10, 10);
                body.index = i;
                group.add(body);
            }
            group.sortLeftRight();

            Assert.equals(2000, group.objects.length);
            for (i in 1...group.objects.length) {
                Assert.isTrue(group.objects[i - 1].x <= group.objects[i].x, 'must be fully ordered at $i');
            }
            // Every original body must still be present exactly once: bailing
            // out mid-insertion must not drop or duplicate one
            for (body in group.objects) {
                Assert.isFalse(seen.exists(body.index), 'body ${body.index} appears twice');
                seen.set(body.index, true);
            }
            Assert.equals(2000, Lambda.count(seen));
        });

        Assert.test('stability holds on both the insertion and merge paths', () -> {
            for (count in [50, 2000]) {
                final group = new Group();
                var state = 11;
                for (i in 0...count) {
                    state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                    // Only a handful of distinct keys, so ties are everywhere
                    final body = new Body(state % 5, 0, 10, 10);
                    body.index = i;
                    group.add(body);
                }
                group.sortLeftRight();

                for (i in 1...group.objects.length) {
                    final a = group.objects[i - 1];
                    final b = group.objects[i];
                    if (a.x == b.x) {
                        Assert.isTrue(a.index < b.index, 'ties must keep their original order (n=$count, at $i)');
                    }
                }
            }
        });

        Assert.test('every sort direction handles a disordered group', () -> {
            for (direction in [SortDirection.LEFT_RIGHT, SortDirection.RIGHT_LEFT, SortDirection.TOP_BOTTOM, SortDirection.BOTTOM_TOP]) {
                final world = newWorld();
                final group = new Group();
                var state = 909;
                for (i in 0...1500) {
                    state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                    group.add(new Body(state % 50000, (state >> 7) % 50000, 10, 10));
                }
                group.sortDirection = direction;
                world.sort(group);

                Assert.equals(1500, group.objects.length, 'direction $direction lost a body');
                for (i in 1...group.objects.length) {
                    final a = group.objects[i - 1];
                    final b = group.objects[i];
                    final ordered = switch direction {
                        case SortDirection.LEFT_RIGHT: a.x <= b.x;
                        case SortDirection.RIGHT_LEFT: a.x >= b.x;
                        case SortDirection.TOP_BOTTOM: a.y <= b.y;
                        case SortDirection.BOTTOM_TOP: a.y >= b.y;
                        default: true;
                    }
                    Assert.isTrue(ordered, 'direction $direction out of order at $i');
                }
            }
        });

        Assert.test('World.sort honours the group sort direction', () -> {
            final world = newWorld();
            final group = makeGroup([50, 10, 30], [0, 0, 0]);
            group.sortDirection = SortDirection.RIGHT_LEFT;
            world.sort(group);
            Assert.equals(50.0, group.objects[0].x);
        });

        Assert.test('SortDirection.NONE leaves the order untouched', () -> {
            final world = newWorld();
            final group = makeGroup([50, 10, 30], [0, 0, 0]);
            group.sortDirection = SortDirection.NONE;
            world.sort(group);
            Assert.equals(50.0, group.objects[0].x, 'no sorting should take place');
        });

    }

    static function quadTree():Void {

        Assert.suite('QuadTree');

        Assert.test('a tree below its capacity keeps everything at the root', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 10, 4);
            for (i in 0...5) {
                tree.insert(new Body(i * 100, 100, 10, 10));
            }
            Assert.equals(5, tree.retrieve(0, 0, 800, 600).length);
        });

        Assert.test('retrieve only returns candidates near the query rect', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 4, 4);
            // Fill the far corner so the tree splits
            for (i in 0...20) {
                tree.insert(new Body(700 + (i % 4), 500 + (i % 4), 8, 8));
            }
            final near = new Body(10, 10, 8, 8);
            tree.insert(near);
            final found = tree.retrieve(0, 0, 40, 40);
            Assert.less(21, found.length, 'quadtree should prune far away bodies');
        });

        Assert.test('populate fills the tree from a group', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 10, 4);
            final group = new Group();
            for (i in 0...6) {
                group.add(new Body(i * 100, 100, 10, 10));
            }
            tree.populate(group);
            Assert.equals(6, tree.retrieve(0, 0, 800, 600).length);
        });

        Assert.test('clear empties the tree', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 10, 4);
            for (i in 0...6) {
                tree.insert(new Body(i * 100, 100, 10, 10));
            }
            tree.clear();
            Assert.equals(0, tree.retrieve(0, 0, 800, 600).length);
        });

        Assert.test('getIndex maps rects to quadrants', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 10, 4);
            // Quadrant 1 is top-left, 0 is top-right, 2 is bottom-left, 3 is bottom-right
            Assert.equals(1, tree.getIndex(10, 10, 50, 50));
            Assert.equals(0, tree.getIndex(500, 10, 550, 50));
            Assert.equals(2, tree.getIndex(10, 400, 50, 450));
            Assert.equals(3, tree.getIndex(500, 400, 550, 450));
            Assert.equals(-1, tree.getIndex(300, 200, 500, 400), 'a rect straddling quadrants has no single index');
        });

        Assert.test('retrieve does not modify the tree it queries', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 4, 4);
            for (i in 0...20) {
                tree.insert(new Body((i % 5) * 150, Std.int(i / 5) * 130, 10, 10));
            }

            final first = tree.retrieve(0, 0, 50, 50).length;
            final second = tree.retrieve(0, 0, 50, 50).length;
            final third = tree.retrieve(0, 0, 50, 50).length;

            Assert.equals(first, second, 'repeating a query must return the same candidates');
            Assert.equals(first, third);
        });

        Assert.test('retrieve results stay correct after querying elsewhere', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 4, 4);
            for (i in 0...20) {
                tree.insert(new Body((i % 5) * 150, Std.int(i / 5) * 130, 10, 10));
            }

            final corner = tree.retrieve(0, 0, 50, 50).length;
            tree.retrieve(700, 500, 750, 550);
            Assert.equals(corner, tree.retrieve(0, 0, 50, 50).length, 'an unrelated query must not affect later ones');
        });

        Assert.test('retrieve can fill a caller supplied array', () -> {
            final tree = new QuadTree(null, 0, 0, 800, 600, 10, 4);
            for (i in 0...6) {
                tree.insert(new Body(i * 100, 100, 10, 10));
            }

            final output:Array<Body> = [];
            final result = tree.retrieve(0, 0, 800, 600, output);
            Assert.equals(output, result, 'the supplied array should be returned');
            Assert.equals(6, output.length);

            // And it is cleared, not appended to, on reuse
            tree.retrieve(0, 0, 800, 600, output);
            Assert.equals(6, output.length);
        });

        Assert.test('the world reuses pooled trees instead of allocating', () -> {
            final world = newWorld();
            final first = world.getQuadTree();
            world.releaseQuadTree(first);
            final second = world.getQuadTree();
            Assert.equals(first, second, 'a released tree should be handed back out');
        });

        Assert.test('two trees held at once are distinct', () -> {
            final world = newWorld();
            final first = world.getQuadTree();
            final second = world.getQuadTree();
            Assert.notEquals(first, second, 'a busy tree must not be handed out twice');
            world.releaseQuadTree(first);
            world.releaseQuadTree(second);
        });

        Assert.test('skipQuadTree still produces correct collisions', () -> {
            final world = newWorld();
            world.skipQuadTree = true;
            final group = new Group();
            final bodies = [];
            for (i in 0...30) {
                final body = new Body(20 + i * 25, 100, 16, 16);
                body.immovable = true;
                group.add(body);
                bodies.push(body);
            }
            final probe = new Body(bodies[10].x + 2, 100, 8, 8);
            probe.velocityX = 1;
            var hits = 0;
            step(world, [probe].concat(bodies), () -> world.overlap(probe, group, (_, _) -> hits++));
            Assert.equals(1, hits);
        });

        Assert.test('quadtree and brute force agree on the same scene', () -> {
            function run(skip:Bool):Int {
                final world = newWorld();
                world.skipQuadTree = skip;
                final group = new Group();
                final bodies = [];
                var seed = 987;
                for (i in 0...60) {
                    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
                    final body = new Body(seed % 700, (seed >> 8) % 500, 20, 20);
                    body.immovable = true;
                    group.add(body);
                    bodies.push(body);
                }
                final probe = new Body(300, 250, 60, 60);
                probe.velocityX = 1;
                var hits = 0;
                step(world, [probe].concat(bodies), () -> world.overlap(probe, group, (_, _) -> hits++));
                return hits;
            }
            Assert.equals(run(true), run(false), 'the quadtree must not change collision results');
        });

    }

    static function worldHelpers():Void {

        Assert.suite('World helpers');

        Assert.test('distanceBetween measures between body origins', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 10, 10);
            final b = new Body(30, 40, 10, 10);
            Assert.near(50, world.distanceBetween(a, b));
        });

        Assert.test('distanceBetween can measure between centers', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 20, 20);
            final b = new Body(30, 40, 20, 20);
            Assert.near(50, world.distanceBetween(a, b, true), 0.0001, 'equal sizes means the same distance');
        });

        Assert.test('distanceToXY measures to a point', () -> {
            final world = newWorld();
            final a = new Body(10, 10, 10, 10);
            Assert.near(5, world.distanceToXY(a, 13, 14));
        });

        Assert.test('angleBetween returns radians toward the target', () -> {
            final world = newWorld();
            final a = new Body(0, 0, 10, 10);
            final b = new Body(10, 0, 10, 10);
            Assert.near(0, world.angleBetween(a, b));
            final c = new Body(0, 10, 10, 10);
            Assert.near(Math.PI / 2, world.angleBetween(a, c));
        });

        Assert.test('closest and farthest pick the right targets', () -> {
            final world = newWorld();
            final source = new Body(0, 0, 10, 10);
            final near = new Body(10, 0, 10, 10);
            final mid = new Body(100, 0, 10, 10);
            final far = new Body(500, 0, 10, 10);
            final targets = [mid, far, near];
            Assert.equals(near, world.closest(source, targets));
            Assert.equals(far, world.farthest(source, targets));
        });

        Assert.test('moveToXY aims the velocity at the target', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            world.moveToXY(body, 100, 0, 200);
            Assert.near(200, body.velocityX);
            Assert.near(0, body.velocityY);

            world.moveToXY(body, 0, 100, 200);
            Assert.near(0, body.velocityX);
            Assert.near(200, body.velocityY);
        });

        Assert.test('moveToXY with maxTime picks the speed for the deadline', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            // 100px in 1000ms -> 100px/sec
            world.moveToXY(body, 100, 0, 0, 1000);
            Assert.near(100, body.velocityX);
        });

        Assert.test('moveToDestination aims at another body', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            final target = new Body(0, 50, 10, 10);
            world.moveToDestination(body, target, 120);
            Assert.near(0, body.velocityX);
            Assert.near(120, body.velocityY);
        });

        Assert.test('accelerateToXY sets acceleration, not velocity', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            world.accelerateToXY(body, 100, 0, 300);
            Assert.near(300, body.accelerationX);
            Assert.equals(0.0, body.velocityX);
            Assert.equals(1000.0, body.maxVelocityX, 'accelerateToXY also caps max velocity at its default');
        });

        Assert.test('velocityFromAngle builds a velocity vector from degrees', () -> {
            final world = newWorld();
            final point = world.velocityFromAngle(0, 100);
            Assert.near(100, point.x);
            Assert.near(0, point.y);

            final down = world.velocityFromAngle(90, 100);
            Assert.near(0, down.x, 0.001);
            Assert.near(100, down.y, 0.001);
        });

        Assert.test('velocityFromRotation builds a vector from radians', () -> {
            final world = newWorld();
            final point = world.velocityFromRotation(Math.PI / 2, 100);
            Assert.near(0, point.x, 0.001);
            Assert.near(100, point.y, 0.001);
        });

        Assert.test('getObjectsAtLocation finds bodies under a point', () -> {
            final world = newWorld();
            final group = new Group();
            final a = new Body(100, 100, 50, 50);
            final b = new Body(300, 300, 50, 50);
            group.add(a);
            group.add(b);
            final found = world.getObjectsAtLocation(120, 120, group);
            Assert.equals(1, found.length);
            Assert.equals(a, found[0]);
        });

        Assert.test('getObjectsAtLocation returns nothing for empty space', () -> {
            final world = newWorld();
            final group = new Group();
            group.add(new Body(100, 100, 50, 50));
            Assert.equals(0, world.getObjectsAtLocation(600, 500, group).length);
        });

        Assert.test('setVelocityToPolar drives a body by angle and speed', () -> {
            final body = new Body(0, 0, 10, 10);
            body.setVelocityToPolar(0, 150);
            Assert.near(150, body.velocityX);
            Assert.near(0, body.velocityY);
        });

        Assert.test('moveTo starts a tracked movement that completes', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            var completed = false;
            body.onMoveComplete = (_, _) -> completed = true;
            body.velocityX = 0;
            body.angle = 0;
            Assert.isTrue(body.moveTo(1, 100, 0), 'moveTo should start the movement');
            Assert.isTrue(body.isMoving);
            steps(world, [body], 120);
            Assert.isTrue(completed, 'onMoveComplete should fire once the distance is covered');
            Assert.isFalse(body.isMoving);
        });

        Assert.test('moveFrom with a duration stops on time', () -> {
            final world = newWorld();
            final body = new Body(0, 0, 10, 10);
            var completed = false;
            body.onMoveComplete = (_, _) -> completed = true;
            Assert.isTrue(body.moveFrom(0.5, 120, 0));
            steps(world, [body], 60);
            Assert.isTrue(completed);
        });

    }

    static function geometry():Void {

        Assert.suite('Geometry helpers');

        Assert.test('Point.setToPolar in radians', () -> {
            final point = new Point(0, 0);
            point.setToPolar(0, 10);
            Assert.near(10, point.x);
            Assert.near(0, point.y);
        });

        Assert.test('Point.setToPolar in degrees', () -> {
            final point = new Point(0, 0);
            point.setToPolar(180, 10, true);
            Assert.near(-10, point.x, 0.001);
            Assert.near(0, point.y, 0.001);
        });

        Assert.test('Line.length measures the segment', () -> {
            final line = new Line(0, 0, 3, 4);
            Assert.near(5, line.length());
        });

        Assert.test('Line.fromAngle builds a segment of the given length', () -> {
            final line = new Line(0, 0, 0, 0);
            line.fromAngle(10, 10, 0, 50);
            Assert.near(10, line.x1);
            Assert.near(60, line.x2);
            Assert.near(50, line.length());
        });

        Assert.test('Direction has a readable toString', () -> {
            final left:Direction = Direction.LEFT;
            final none:Direction = Direction.NONE;
            Assert.equals('Direction.LEFT', left.toString());
            Assert.equals('Direction.NONE', none.toString());
        });

    }

    static function extensions():Void {

        Assert.suite('Array extensions');

        Assert.test('unsafeGet reads the same values as []', () -> {
            final array = [10, 20, 30];
            Assert.equals(10, array.unsafeGet(0));
            Assert.equals(30, array.unsafeGet(2));
        });

        Assert.test('unsafeSet writes through', () -> {
            final array = [10, 20, 30];
            array.unsafeSet(1, 99);
            Assert.equals(99, array[1]);
        });

        Assert.test('setArrayLength grows and shrinks', () -> {
            final array = [1, 2, 3, 4, 5];
            array.setArrayLength(2);
            Assert.equals(2, array.length);
            Assert.equals(1, array[0]);

            final other = [1, 2];
            other.setArrayLength(4);
            Assert.equals(4, other.length);
        });

    }

    /**
     * The sweep-and-prune early exit, the per-frame sort cache and the group
     * owned QuadTree are all optimisations that must not change which pairs
     * collide. These tests check that against a brute force reference.
     */
    static function broadphase():Void {

        Assert.suite('Broadphase equivalence');

        /** Builds a deterministic scene of bodies with varied sizes. */
        function scene(count:Int, seed:Int):Array<Body> {
            var state = seed;
            function rnd():Float {
                state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                return state / 0x3FFFFFFF;
            }
            final bodies = [];
            for (_ in 0...count) {
                // Deliberately mixed sizes: a wide body is the case a naive
                // sweep would skip over
                final size = rnd() < 0.2 ? 120 + rnd() * 80 : 8 + rnd() * 20;
                final body = new Body(rnd() * 760, rnd() * 560, size, size);
                body.velocityX = rnd() * 20 - 10;
                bodies.push(body);
            }
            return bodies;
        }

        /** Collects the colliding pairs as a sorted list of index pairs. */
        function pairsOf(bodies:Array<Body>, run:(World, Group, Body->Body->Void)->Void, skipTree:Bool, direction:SortDirection):Array<String> {
            final world = newWorld();
            world.skipQuadTree = skipTree;
            world.maxObjectsWithoutQuadTree = skipTree ? 100000 : 4;
            final group = new Group();
            for (i in 0...bodies.length) {
                bodies[i].index = i;
                group.add(bodies[i]);
            }
            group.sortDirection = direction;

            final found = [];
            step(world, bodies, () -> run(world, group, (b1, b2) -> {
                // Order-independent key, so the two configurations are comparable
                final lo = b1.index < b2.index ? b1.index : b2.index;
                final hi = b1.index < b2.index ? b2.index : b1.index;
                found.push('$lo-$hi');
            }));
            found.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
            return found;
        }

        function sameLists(reference:Array<String>, candidate:Array<String>, label:String):Void {
            Assert.equals(reference.length, candidate.length, '$label: found ${candidate.length} pairs, brute force found ${reference.length}');
            if (reference.length != candidate.length) return;
            for (i in 0...reference.length) {
                Assert.equals(reference[i], candidate[i], '$label: pair $i differs');
            }
        }

        Assert.test('group vs itself finds the same pairs as brute force', () -> {
            for (seed in [1, 2, 3, 4, 5]) {
                final run = (world:World, group:Group, cb:Body->Body->Void) -> world.overlap(group, cb);
                final reference = pairsOf(scene(60, seed), run, true, SortDirection.NONE);
                final swept = pairsOf(scene(60, seed), run, false, SortDirection.LEFT_RIGHT);
                sameLists(reference, swept, 'seed $seed');
            }
        });

        Assert.test('group vs itself is unaffected by the sort axis', () -> {
            final run = (world:World, group:Group, cb:Body->Body->Void) -> world.overlap(group, cb);
            final reference = pairsOf(scene(60, 9), run, true, SortDirection.NONE);
            for (direction in [SortDirection.LEFT_RIGHT, SortDirection.RIGHT_LEFT, SortDirection.TOP_BOTTOM, SortDirection.BOTTOM_TOP]) {
                sameLists(reference, pairsOf(scene(60, 9), run, false, direction), 'direction $direction');
            }
        });

        Assert.test('group vs group finds the same pairs as brute force', () -> {
            for (seed in [11, 12, 13]) {
                final all = scene(80, seed);
                final half = Std.int(all.length / 2);

                function run(skipTree:Bool, direction:SortDirection):Array<String> {
                    final world = newWorld();
                    world.skipQuadTree = skipTree;
                    final g1 = new Group();
                    final g2 = new Group();
                    for (i in 0...all.length) {
                        all[i].index = i;
                        if (i < half) g1.add(all[i]) else g2.add(all[i]);
                    }
                    g1.sortDirection = direction;
                    g2.sortDirection = direction;

                    final found = [];
                    step(world, all, () -> world.overlap(g1, g2, (b1, b2) -> {
                        final lo = b1.index < b2.index ? b1.index : b2.index;
                        final hi = b1.index < b2.index ? b2.index : b1.index;
                        found.push('$lo-$hi');
                    }));
                    found.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
                    return found;
                }

                sameLists(run(true, SortDirection.NONE), run(false, SortDirection.LEFT_RIGHT), 'seed $seed');
            }
        });

        Assert.test('body vs group finds the same bodies with and without the tree', () -> {
            for (seed in [21, 22, 23]) {
                final bodies = scene(80, seed);
                final probe = new Body(300, 250, 90, 90);
                probe.velocityX = 1;

                function run(skipTree:Bool):Array<String> {
                    final world = newWorld();
                    world.skipQuadTree = skipTree;
                    world.maxObjectsWithoutQuadTree = 4;
                    final group = new Group();
                    for (i in 0...bodies.length) {
                        bodies[i].index = i;
                        group.add(bodies[i]);
                    }
                    final found = [];
                    // Two queries, so the second one goes through the tree
                    step(world, [probe].concat(bodies), () -> {
                        world.overlap(probe, group);
                        world.overlap(probe, group, (_, other) -> found.push('' + other.index));
                    });
                    found.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
                    return found;
                }

                sameLists(run(true), run(false), 'seed $seed');
            }
        });

        Assert.test('the tree is only built once several queries need it', () -> {
            // The first query after the bodies move is answered by scanning;
            // building a tree for a single query costs more than it saves
            final world = newWorld();
            world.maxObjectsWithoutQuadTree = 4;
            final group = new Group();
            final bodies = [];
            for (i in 0...40) {
                final body = new Body(20 + (i % 10) * 70, 20 + Std.int(i / 10) * 120, 16, 16);
                group.add(body);
                bodies.push(body);
            }
            final probe = new Body(bodies[13].x + 2, bodies[13].y + 2, 8, 8);
            probe.velocityX = 1;

            var first = 0;
            var second = 0;
            step(world, [probe].concat(bodies), () -> {
                world.overlap(probe, group, (_, _) -> first++);
                world.overlap(probe, group, (_, _) -> second++);
            });
            Assert.equals(1, first, 'the scanned query must find the body');
            Assert.equals(1, second, 'the tree backed query must agree with it');
        });

        Assert.test('a group re-sorts only after its bodies move', () -> {
            final world = newWorld();
            final group = new Group();
            final bodies = [];
            for (x in [300.0, 100.0, 200.0]) {
                final body = new Body(x, 0, 10, 10);
                group.add(body);
                bodies.push(body);
            }
            group.sortDirection = SortDirection.LEFT_RIGHT;

            world.sort(group);
            Assert.equals(100.0, group.objects[0].x, 'first sort orders the group');

            // Moving a body directly does not go through preUpdate, so the
            // cached order is deliberately kept until invalidated
            group.objects[2].x = 1;
            world.sort(group);
            Assert.equals(100.0, group.objects[0].x, 'the cached order is reused');

            group.invalidate();
            world.sort(group);
            Assert.equals(1.0, group.objects[0].x, 'invalidate forces a re-sort');
        });

        Assert.test('a body moved by its owner invalidates the caches', () -> {
            // The integration pattern where a visual object drives the body:
            // preUpdate is handed the owner's position, so the jump is visible
            final world = newWorld();
            final g1 = new Group();
            final g2 = new Group();
            g1.sortDirection = SortDirection.LEFT_RIGHT;
            g2.sortDirection = SortDirection.LEFT_RIGHT;

            final a = new Body(300, 0, 10, 10);
            final b = new Body(100, 0, 10, 10);
            a.allowGravity = false;
            b.allowGravity = false;
            for (group in [g1, g2]) {
                group.add(a);
                group.add(b);
            }

            world.sort(g1);
            world.sort(g2);
            Assert.equals(b, g1.objects[0]);

            // The owner moves `a` to the front, and passes that in
            a.preUpdate(world, 1, 0, a.width, a.height, 0);
            b.preUpdate(world, b.x, b.y, b.width, b.height, 0);
            a.postUpdate(world);
            b.postUpdate(world);

            world.sort(g1);
            world.sort(g2);
            Assert.equals(a, g1.objects[0], 'g1 should have been re-sorted');
            Assert.equals(a, g2.objects[0], 'g2 should have been re-sorted');
        });

        Assert.test('assigning to body.x directly is picked up on the next frame', () -> {
            // The caches remember where each body was when they were built, so
            // a direct assignment is noticed even though preUpdate is handed
            // the body's own position and sees no movement of its own
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            final a = new Body(300, 0, 10, 10);
            final b = new Body(100, 0, 10, 10);
            a.allowGravity = false;
            b.allowGravity = false;
            group.add(a);
            group.add(b);

            world.sort(group);
            Assert.equals(b, group.objects[0]);

            a.x = 1;
            step(world, [a, b]);
            world.sort(group);
            Assert.equals(a, group.objects[0], 'the direct move should have invalidated the group');
        });

        Assert.test('Body.reset invalidates without needing a manual call', () -> {
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            final a = new Body(300, 0, 10, 10);
            final b = new Body(100, 0, 10, 10);
            group.add(a);
            group.add(b);

            world.sort(group);
            a.reset(1, 0, 10, 10);
            world.sort(group);
            Assert.equals(a, group.objects[0], 'reset should invalidate the group');
        });

        Assert.test('adding or removing a body invalidates the caches', () -> {
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            group.add(new Body(300, 0, 10, 10));
            group.add(new Body(200, 0, 10, 10));
            world.sort(group);
            Assert.equals(200.0, group.objects[0].x);

            group.add(new Body(50, 0, 10, 10));
            world.sort(group);
            Assert.equals(50.0, group.objects[0].x, 'adding a body must force a re-sort');
        });

        Assert.test('body vs group finds the same bodies in every sort direction', () -> {
            for (seed in [31, 32]) {
                final bodies = scene(80, seed);
                final probe = new Body(300, 250, 90, 90);
                probe.velocityX = 1;

                function run(direction:SortDirection, skipTree:Bool):Array<String> {
                    final world = newWorld();
                    world.skipQuadTree = skipTree;
                    world.maxObjectsWithoutQuadTree = 4;
                    final group = new Group();
                    for (i in 0...bodies.length) {
                        bodies[i].index = i;
                        group.add(bodies[i]);
                    }
                    group.sortDirection = direction;
                    final found = [];
                    step(world, [probe].concat(bodies), () -> {
                        world.overlap(probe, group, (_, other) -> found.push('' + other.index));
                    });
                    found.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
                    return found;
                }

                // Unsorted and unindexed is the reference
                final reference = run(SortDirection.NONE, true);
                for (direction in [SortDirection.LEFT_RIGHT, SortDirection.RIGHT_LEFT, SortDirection.TOP_BOTTOM, SortDirection.BOTTOM_TOP]) {
                    sameLists(reference, run(direction, true), 'seed $seed direction $direction');
                }
            }
        });

        Assert.test('body vs group does not skip a wide body', () -> {
            // The narrowed scan must still reach a body that starts far back
            // along the axis but is wide enough to overlap the query
            for (direction in [SortDirection.LEFT_RIGHT, SortDirection.RIGHT_LEFT]) {
                final world = newWorld();
                world.skipQuadTree = true;
                final group = new Group();
                group.sortDirection = direction;

                final wide = new Body(0, 100, 400, 20);
                wide.allowGravity = false;
                group.add(wide);
                for (i in 0...10) {
                    final filler = new Body(500 + i * 20, 300, 10, 10);
                    filler.allowGravity = false;
                    group.add(filler);
                }

                final probe = new Body(380, 100, 10, 10);
                probe.velocityX = 1;
                var hits = 0;
                step(world, [probe].concat(group.objects), () -> world.overlap(probe, group, (_, _) -> hits++));
                Assert.equals(1, hits, 'direction $direction should find the wide body');
            }
        });

        Assert.test('a static group keeps its caches across frames', () -> {
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            final bodies = [];
            for (x in [300.0, 100.0, 200.0]) {
                final body = new Body(x, 0, 10, 10);
                body.allowGravity = false;
                group.add(body);
                bodies.push(body);
            }

            world.sort(group);
            Assert.equals(100.0, group.objects[0].x);

            // Nothing moves, so none of these frames should invalidate
            steps(world, bodies, 5);

            // A manual move with no invalidate: if the cache had been dropped
            // during those frames, this would be picked up by the next sort
            group.objects[2].x = 1;
            world.sort(group);
            Assert.equals(100.0, group.objects[0].x, 'the cache should have survived 5 static frames');
        });

        Assert.test('a moving body still invalidates its groups every frame', () -> {
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            final still = new Body(100, 0, 10, 10);
            still.allowGravity = false;
            final mover = new Body(300, 0, 10, 10);
            mover.velocityX = -600;
            group.add(still);
            group.add(mover);

            world.sort(group);
            Assert.equals(still, group.objects[0]);

            // The mover crosses to the left of the still body
            steps(world, [still, mover], 30);
            world.sort(group);
            Assert.equals(mover, group.objects[0], 'a moving body must keep its group re-sorting');
        });

        Assert.test('a body displaced by separation after the tree was built is not lost', () -> {
            // The hazard: a group's spatial index is built early in the
            // collision phase, then separation moves one of its bodies later in
            // that same phase. If the next frame only asks "did this body move
            // under its own power", the answer is no — it is sitting still where
            // separation left it — and the index stays stale forever.
            final world = newWorld();
            world.maxObjectsWithoutQuadTree = 4;
            world.maxObjects = 2; // force the tree to actually subdivide

            // Spread through the same quadrant as the runner, so the tree
            // actually subdivides there and a stale entry lands in the wrong node
            final group = new Group();
            final filler = [];
            for (i in 0...8) {
                final body = new Body(10 + i * 45, 30 + (i % 3) * 60, 12, 12);
                body.allowGravity = false;
                group.add(body);
                filler.push(body);
            }

            // Fast enough that the overlap bias allows a large push back, and
            // bounceX of 0 means it comes to a dead stop
            final runner = new Body(100, 100, 20, 20);
            runner.allowGravity = false;
            runner.velocityX = 9000;
            runner.bounceX = 0;
            group.add(runner);

            final wall = new Body(150, 100, 200, 20);
            wall.immovable = true;
            wall.allowGravity = false;

            final all = filler.concat([runner, wall]);

            step(world, all, () -> {
                // Two queries so the tree gets built, at the pre-separation
                // positions, and only then is the runner pushed back
                world.overlap(runner, group);
                world.overlap(runner, group);
                world.collide(runner, wall);
            });

            final restingX = runner.x;
            Assert.equals(0.0, runner.velocityX, 'the runner should have stopped dead');
            Assert.greater(60, 250 - restingX, 'the runner should have been pushed back a long way, ended at $restingX');

            // Next frame nothing moves under its own power, but a query where
            // the runner actually is must still find it
            var found = 0;
            final probe = new Body(restingX + 2, 102, 6, 6);
            probe.velocityX = 1;
            step(world, all.concat([probe]), () -> {
                world.overlap(probe, group);
                world.overlap(probe, group, (_, other) -> {
                    if (other == runner) found++;
                });
            });
            Assert.equals(1, found, 'the displaced body must be found where it now is');
        });

        Assert.test('resizing a body invalidates its groups', () -> {
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;
            final a = new Body(100, 0, 10, 10);
            final b = new Body(200, 0, 10, 10);
            a.allowGravity = false;
            b.allowGravity = false;
            group.add(a);
            group.add(b);

            world.sort(group);

            // Grow `a` so it now reaches `b`, via the preUpdate size argument
            a.preUpdate(world, a.x, a.y, 150, 10, 0);
            b.preUpdate(world, b.x, b.y, b.width, b.height, 0);
            var hits = 0;
            world.overlap(group, (_, _) -> hits++);
            a.postUpdate(world);
            b.postUpdate(world);
            Assert.equals(1, hits, 'the resized body should now overlap its neighbour');
        });

        Assert.test('the sweep stays correct over many frames of motion', () -> {
            // Overlap only, so both runs follow identical trajectories and any
            // difference is the broadphase dropping a pair
            function run(direction:SortDirection):Array<String> {
                final world = newWorld();
                world.skipQuadTree = true;
                world.gravityY = 300;

                var state = 4242;
                function rnd():Float {
                    state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                    return state / 0x3FFFFFFF;
                }

                final group = new Group();
                final bodies = [];
                for (i in 0...40) {
                    final body = new Body(rnd() * 700, rnd() * 500, 20 + rnd() * 40, 20 + rnd() * 40);
                    body.velocityX = rnd() * 200 - 100;
                    body.velocityY = rnd() * 200 - 100;
                    body.bounceX = 1;
                    body.bounceY = 1;
                    body.collideWorldBounds = true;
                    body.index = i;
                    group.add(body);
                    bodies.push(body);
                }
                group.sortDirection = direction;

                final log = [];
                for (frame in 0...40) {
                    step(world, bodies, () -> world.overlap(group, (b1, b2) -> {
                        final lo = b1.index < b2.index ? b1.index : b2.index;
                        final hi = b1.index < b2.index ? b2.index : b1.index;
                        log.push('$frame:$lo-$hi');
                    }));
                }
                log.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
                return log;
            }

            final reference = run(SortDirection.NONE);
            Assert.greater(0, reference.length, 'the scene should produce overlaps');
            sameLists(reference, run(SortDirection.LEFT_RIGHT), 'swept');
        });

        Assert.test('the cached tree stays correct over many frames with separation', () -> {
            // Both runs sort the same way, so bodies are separated in the same
            // order and follow identical trajectories. The only difference is
            // whether queries go through the group's cached spatial index, so
            // a stale tree shows up as a missing pair.
            function run(skipTree:Bool):Array<String> {
                final world = newWorld();
                world.skipQuadTree = skipTree;
                world.maxObjectsWithoutQuadTree = 4;
                world.gravityY = 300;

                var state = 909;
                function rnd():Float {
                    state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
                    return state / 0x3FFFFFFF;
                }

                final group = new Group();
                final targets = [];
                for (i in 0...40) {
                    final body = new Body(rnd() * 700, rnd() * 500, 30 + rnd() * 30, 30 + rnd() * 30);
                    body.allowGravity = false;
                    body.index = i;
                    group.add(body);
                    targets.push(body);
                }
                group.sortDirection = SortDirection.LEFT_RIGHT;

                final probes = [];
                for (i in 0...5) {
                    final probe = new Body(rnd() * 700, rnd() * 500, 24, 24);
                    probe.velocityX = rnd() * 300 - 150;
                    probe.velocityY = rnd() * 300 - 150;
                    probe.bounceX = 1;
                    probe.bounceY = 1;
                    probe.collideWorldBounds = true;
                    probe.index = 1000 + i;
                    probes.push(probe);
                }

                final all = targets.concat(probes);
                final log = [];
                for (frame in 0...40) {
                    step(world, all, () -> {
                        for (probe in probes) {
                            // Separation moves the group's bodies, so the tree
                            // built earlier this frame must not go stale
                            world.collide(probe, group, (b1, b2) -> log.push('$frame:${b1.index}-${b2.index}'));
                        }
                    });
                }
                return log;
            }

            final reference = run(true);
            Assert.greater(0, reference.length, 'the scene should produce collisions');
            sameLists(reference, run(false), 'cached tree');
        });

        Assert.test('a wide body is not skipped by the sweep', () -> {
            // A body far to the left but wide enough to reach the probe is the
            // case an early exit gets wrong if it breaks on the wrong edge
            final world = newWorld();
            final group = new Group();
            group.sortDirection = SortDirection.LEFT_RIGHT;

            final wide = new Body(0, 100, 400, 20);
            final narrow = new Body(390, 100, 20, 20);
            group.add(wide);
            group.add(narrow);

            var hits = 0;
            narrow.velocityX = 1;
            step(world, [wide, narrow], () -> world.overlap(group, (_, _) -> hits++));
            Assert.equals(1, hits, 'the wide body overlaps the narrow one');
        });

    }

    static function regressions():Void {

        Assert.suite('Regressions and edge cases');

        Assert.test('a light body hit by a heavy one is not launched absurdly fast', () -> {
            // Guards the "Improve collisions between light and heavy masses" fix
            final world = newWorld();
            final heavy = new Body(100, 100, 20, 20);
            final light = new Body(115, 100, 20, 20);
            heavy.forceX = true;
            heavy.mass = 100;
            light.mass = 1;
            heavy.bounceX = 1;
            light.bounceX = 1;
            heavy.velocityX = 100;
            step(world, [heavy, light], () -> world.collide(heavy, light));
            // Perfectly elastic transfer tops out just under 2x the heavy speed
            Assert.less(201, light.velocityX, 'light body speed must stay bounded');
        });

        Assert.test('a stack of bodies on the ground stays stable', () -> {
            final world = newWorld();
            world.gravityY = 800;
            final ground = new Body(0, 500, 800, 100);
            ground.immovable = true;
            ground.allowGravity = false;

            final boxes = [];
            for (i in 0...4) {
                boxes.push(new Body(100, 400 - i * 22, 20, 20));
            }
            final all = [ground].concat(boxes);
            final group = new Group();
            for (box in boxes) group.add(box);

            steps(world, all, 300, () -> {
                for (box in boxes) world.collide(box, ground);
                world.collide(group);
            });

            for (box in boxes) {
                Assert.isTrue(box.y <= 500, 'no box should sink through the ground, got y=${box.y}');
                Assert.isTrue(box.y > 300, 'no box should be flung away, got y=${box.y}');
            }
        });

        Assert.test('repeated collide calls do not corrupt a group', () -> {
            final world = newWorld();
            final group = new Group();
            final bodies = [];
            for (i in 0...40) {
                final body = new Body(20 + (i % 10) * 70, 20 + Std.int(i / 10) * 120, 16, 16);
                body.immovable = true;
                group.add(body);
                bodies.push(body);
            }
            final probe = new Body(400, 300, 10, 10);
            probe.velocityX = 1;

            for (frame in 0...5) {
                step(world, [probe].concat(bodies), () -> world.overlap(probe, group));
                Assert.equals(40, group.objects.length, 'group must keep exactly its own bodies (frame $frame)');
            }
        });

        Assert.test('many overlap queries against one group stay consistent', () -> {
            final world = newWorld();
            final group = new Group();
            final bodies = [];
            for (i in 0...40) {
                final body = new Body(20 + (i % 10) * 70, 20 + Std.int(i / 10) * 120, 16, 16);
                body.immovable = true;
                group.add(body);
                bodies.push(body);
            }

            final probes = [];
            for (i in 0...5) {
                final probe = new Body(bodies[i * 7].x + 2, bodies[i * 7].y + 2, 8, 8);
                probe.velocityX = 1;
                probes.push(probe);
            }

            final counts = [];
            step(world, probes.concat(bodies), () -> {
                for (probe in probes) {
                    var hits = 0;
                    world.overlap(probe, group, (_, _) -> hits++);
                    counts.push(hits);
                }
            });

            for (i in 0...counts.length) {
                Assert.equals(1, counts[i], 'probe $i should find exactly one body');
            }
        });

        Assert.test('bodies do not tunnel through a thin wall at moderate speed', () -> {
            final world = newWorld();
            final wall = new Body(400, 0, 10, 600);
            wall.immovable = true;
            wall.allowGravity = false;
            final bullet = new Body(100, 300, 10, 10);
            bullet.velocityX = 600; // 10px per frame, same as the wall thickness
            steps(world, [bullet, wall], 120, () -> world.collide(bullet, wall));
            Assert.less(401, bullet.x, 'bullet should be stopped by the wall, got x=${bullet.x}');
        });

        Assert.test('zero sized bodies do not crash collision', () -> {
            final world = newWorld();
            final a = new Body(100, 100, 0, 0);
            final b = new Body(100, 100, 20, 20);
            a.velocityX = 60;
            step(world, [a, b], () -> world.collide(a, b));
            Assert.isTrue(true, 'no exception thrown');
        });

        Assert.test('a very large elapsed value does not produce NaN positions', () -> {
            final world = newWorld();
            world.elapsed = 1;
            world.gravityY = 1000;
            final body = new Body(100, 100, 20, 20);
            body.collideWorldBounds = true;
            steps(world, [body], 10);
            Assert.isFalse(Math.isNaN(body.x), 'x must stay a number');
            Assert.isFalse(Math.isNaN(body.y), 'y must stay a number');
        });

    }

}
