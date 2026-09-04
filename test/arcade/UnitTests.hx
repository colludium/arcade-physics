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
        regressions();
        knownIssues();

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

        Assert.test('hitTest rejects points outside the bounding box of a circle', () -> {
            final body = new Body(0, 0, 20, 20);
            body.setCircle(10);
            Assert.isFalse(body.hitTest(-5, 10));
            Assert.isFalse(body.hitTest(10, 25));
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

        Assert.test('isPaused is a caller-side flag, it does not stop preUpdate', () -> {
            // World.isPaused is documented as making preUpdate skip, but it is
            // the caller's job to honour it: the library never reads it.
            final world = newWorld();
            world.isPaused = true;
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 60;
            step(world, [body]);
            Assert.near(1, body.x, 0.0001, 'isPaused is advisory; callers must skip preUpdate themselves');
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

        Assert.test('group vs itself visits every ordered pair', () -> {
            // The implementation runs a full n^2 loop rather than n^2/2, so
            // every unordered pair is reported in both orders. Using overlap
            // (which does not separate) makes the double visit observable.
            final world = newWorld();
            final group = new Group();
            final a = new Body(100, 100, 20, 20);
            final b = new Body(115, 100, 20, 20);
            a.velocityX = 60;
            group.add(a);
            group.add(b);
            var hits = 0;
            step(world, [a, b], () -> world.overlap(group, (_, _) -> hits++));
            Assert.equals(2, hits, 'group vs itself visits (a,b) and (b,a)');
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
     * Behaviour that looks like a defect but is what the library currently does.
     *
     * These tests pin the current behaviour so a change to it is deliberate
     * rather than accidental. If any of these are fixed, the assertions here
     * are the ones to update.
     */
    static function knownIssues():Void {

        Assert.suite('Known issues (current behaviour pinned)');

        Assert.test('circle hitTest measures from the corner, not the center', () -> {
            // `Body.circleContains` uses body.x/body.y as the circle origin, but
            // everywhere else (World.intersects, separateCircle) the circle is
            // centered on centerX/centerY. So hitTest describes a circle sitting
            // on the top-left corner of the body, clipped to its bounding box.
            final body = new Body(0, 0, 20, 20);
            body.setCircle(10);

            Assert.isFalse(body.hitTest(10, 10), 'the actual center currently reports a miss');
            Assert.isTrue(body.hitTest(1, 1), 'the top-left corner currently reports a hit');

            // What it should be, once fixed:
            //   Assert.isTrue(body.hitTest(10, 10));
            //   Assert.isFalse(body.hitTest(1, 1));
        });

        Assert.test('QuadTree.retrieve mutates the node it is called on', () -> {
            // retrieve() appends the results of child nodes into `this.objects`
            // instead of into a copy, so calling it twice on the same tree
            // returns progressively more (duplicated) candidates.
            //
            // The library's own code paths build a fresh tree per query, so this
            // is latent there, but it does affect direct users of the public API.
            final tree = new QuadTree(null, 0, 0, 800, 600, 4, 4);
            for (i in 0...20) {
                tree.insert(new Body((i % 5) * 150, Std.int(i / 5) * 130, 10, 10));
            }

            final first = tree.retrieve(0, 0, 50, 50).length;
            final second = tree.retrieve(0, 0, 50, 50).length;

            Assert.greater(first, second, 'the second identical query currently returns more results');

            // What it should be, once fixed:
            //   Assert.equals(first, second);
        });

        Assert.test('World.isPaused is declared but never read', () -> {
            // Documented as halting motion, but no code path checks it: callers
            // have to skip preUpdate themselves.
            final world = newWorld();
            world.isPaused = true;
            final body = new Body(0, 0, 10, 10);
            body.velocityX = 600;
            steps(world, [body], 10);
            Assert.greater(0, body.x, 'the body still moves while the world is "paused"');
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
