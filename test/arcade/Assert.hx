package arcade;

/**
 * A tiny zero-dependency assertion library and test runner.
 *
 * The library itself has no haxelib dependencies, so the test suite doesn't
 * introduce any either. Tests are grouped into suites and each test is run
 * inside a try/catch so a single crash doesn't abort the whole run.
 *
 * Usage:
 * ```haxe
 * Assert.suite('My suite');
 * Assert.test('does a thing', () -> {
 *     Assert.equals(2, 1 + 1);
 * });
 * Sys.exit(Assert.report());
 * ```
 */
class Assert {

    /** Number of assertions that passed. */
    public static var passed(default, null):Int = 0;

    /** Number of assertions that failed. */
    public static var failed(default, null):Int = 0;

    /** Number of tests that ran. */
    public static var testCount(default, null):Int = 0;

    /** Number of tests with at least one failed assertion (or that threw). */
    public static var failedTests(default, null):Int = 0;

    /** Set to true to print a line for every test, not just failing ones. */
    public static var verbose:Bool = false;

    static var currentSuite:String = '';
    static var currentTest:String = '';
    static var currentTestFailed:Bool = false;
    static var failures:Array<String> = [];

    /**
     * Starts a new named suite. Every following `test()` is reported under it.
     */
    public static function suite(name:String):Void {

        currentSuite = name;
        if (verbose) {
            println('');
            println('  $name');
        }

    }

    /**
     * Runs a single test. Exceptions thrown by `fn` are caught and reported
     * as a failure rather than aborting the run.
     */
    public static function test(name:String, fn:Void->Void):Void {

        currentTest = name;
        currentTestFailed = false;
        testCount++;

        try {
            fn();
        }
        catch (e:Dynamic) {
            fail('threw: $e');
        }

        if (currentTestFailed) {
            failedTests++;
        }
        else if (verbose) {
            println('    ✓ $name');
        }

        currentTest = '';

    }

    /** Asserts `value` is true. */
    public static function isTrue(value:Bool, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(value, msg != null ? msg : 'expected true, got false', pos);

    }

    /** Asserts `value` is false. */
    public static function isFalse(value:Bool, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(!value, msg != null ? msg : 'expected false, got true', pos);

    }

    /** Asserts `actual` equals `expected` (using `==`). */
    public static function equals<T>(expected:T, actual:T, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(expected == actual, msg != null ? msg : 'expected $expected, got $actual', pos);

    }

    /** Asserts `actual` differs from `unexpected` (using `!=`). */
    public static function notEquals<T>(unexpected:T, actual:T, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(unexpected != actual, msg != null ? msg : 'expected anything but $unexpected', pos);

    }

    /**
     * Asserts two floats are equal within `epsilon`. Physics is full of
     * accumulated floating point error, so this is the usual numeric assert.
     */
    public static function near(expected:Float, actual:Float, epsilon:Float = 0.0001, ?msg:String, ?pos:haxe.PosInfos):Void {

        final diff = expected > actual ? expected - actual : actual - expected;
        check(diff <= epsilon, msg != null ? msg : 'expected $expected (±$epsilon), got $actual', pos);

    }

    /** Asserts `actual` is strictly greater than `min`. */
    public static function greater(min:Float, actual:Float, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(actual > min, msg != null ? msg : 'expected value greater than $min, got $actual', pos);

    }

    /** Asserts `actual` is strictly less than `max`. */
    public static function less(max:Float, actual:Float, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(actual < max, msg != null ? msg : 'expected value less than $max, got $actual', pos);

    }

    /** Asserts `value` is null. */
    public static function isNull(value:Dynamic, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(value == null, msg != null ? msg : 'expected null, got $value', pos);

    }

    /** Asserts `value` is not null. */
    public static function notNull(value:Dynamic, ?msg:String, ?pos:haxe.PosInfos):Void {

        check(value != null, msg != null ? msg : 'expected a value, got null', pos);

    }

    /** Records an unconditional failure. */
    public static function fail(msg:String, ?pos:haxe.PosInfos):Void {

        check(false, msg, pos);

    }

    static function check(condition:Bool, msg:String, ?pos:haxe.PosInfos):Void {

        if (condition) {
            passed++;
        }
        else {
            failed++;
            currentTestFailed = true;
            final where = pos != null ? '${pos.fileName}:${pos.lineNumber}' : '?';
            failures.push('  ✗ $currentSuite › $currentTest\n      $msg\n      at $where');
        }

    }

    /**
     * Prints the summary and returns a process exit code:
     * 0 when everything passed, 1 otherwise.
     */
    public static function report():Int {

        println('');
        if (failures.length > 0) {
            println('Failures:');
            println('');
            for (failure in failures) {
                println(failure);
                println('');
            }
        }

        println('─────────────────────────────────────────────');
        println('$testCount tests, $passed assertions passed, $failed failed');
        println(failed == 0 ? '✅ ALL TESTS PASSED' : '❌ $failedTests TEST(S) FAILED');
        println('');

        return failed == 0 ? 0 : 1;

    }

    static inline function println(s:String):Void {

        #if sys
        Sys.println(s);
        #elseif js
        js.Syntax.code("console.log({0})", s);
        #else
        trace(s);
        #end

    }

}
