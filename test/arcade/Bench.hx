package arcade;

/**
 * A single benchmark measurement.
 */
class BenchResult {

    /** Human readable name of the scenario. */
    public var name:String;

    /** The group this scenario is reported under. */
    public var section:String;

    /** Number of bodies (or other work units) involved in one frame. */
    public var units:Int;

    /** Number of frames that were timed. */
    public var frames:Int;

    /** Best observed wall time for the whole run, in milliseconds. */
    public var totalMs:Float;

    /** Best observed wall time for a single frame, in milliseconds. */
    public var msPerFrame:Float;

    /** Frames per second this scenario would sustain if it were the only work. */
    public var fps:Float;

    /** Microseconds spent per work unit per frame. */
    public var usPerUnit:Float;

    /** Optional note printed alongside the row. */
    public var note:String;

    public function new(section:String, name:String, units:Int, frames:Int, totalMs:Float, ?note:String) {

        this.section = section;
        this.name = name;
        this.units = units;
        this.frames = frames;
        this.totalMs = totalMs;
        this.msPerFrame = totalMs / frames;
        this.fps = this.msPerFrame > 0 ? 1000 / this.msPerFrame : 0;
        this.usPerUnit = units > 0 ? (this.msPerFrame * 1000) / units : 0;
        this.note = note;

    }

}

/**
 * Minimal benchmark harness: warm up, time a number of repeats, keep the best.
 *
 * Keeping the best (rather than the mean) filters out GC pauses and scheduler
 * noise, which matters because the numbers are compared against each other to
 * spot bottlenecks rather than quoted as absolutes.
 */
class Bench {

    /** Every result recorded so far, in order. */
    public static var results(default, null):Array<BenchResult> = [];

    /** How many times each scenario is repeated (the best run is kept). */
    public static var repeats:Int = 3;

    /** Fraction of frames run untimed first, to let the JIT settle. */
    public static var warmupFrames:Int = 8;

    static var currentSection:String = '';

    /**
     * Starts a new reporting section.
     */
    public static function section(title:String):Void {

        currentSection = title;
        println('');
        println('▸ $title');

    }

    /**
     * Times `frame`, called `frames` times per repeat.
     *
     * `setup` (when given) runs before every repeat and is not timed, so each
     * repeat starts from the same state.
     *
     * @param name A short description of the scenario.
     * @param units The number of bodies (or pairs) processed per frame.
     * @param frames How many frames make up one timed run.
     * @param frame The work of a single frame.
     * @param setup Optional untimed per-repeat setup.
     * @param note Optional note printed with the row.
     */
    public static function measure(name:String, units:Int, frames:Int, frame:Void->Void, ?setup:Void->Void, ?note:String):BenchResult {

        if (setup != null) setup();
        for (_ in 0...warmupFrames) frame();

        var best:Float = -1;

        for (_ in 0...repeats) {
            if (setup != null) setup();

            final start = haxe.Timer.stamp();
            for (_ in 0...frames) frame();
            final elapsed = (haxe.Timer.stamp() - start) * 1000;

            if (best < 0 || elapsed < best) best = elapsed;
        }

        final result = new BenchResult(currentSection, name, units, frames, best, note);
        results.push(result);
        printRow(result);
        return result;

    }

    static function printRow(result:BenchResult):Void {

        final name = pad(result.name, 46);
        final perFrame = padLeft(format(result.msPerFrame, 4) + ' ms', 13);
        final fps = padLeft(result.fps >= 100000 ? '>100k' : format(result.fps, 0), 9);
        final perUnit = result.units > 0 ? padLeft(format(result.usPerUnit, 3) + ' µs', 12) : padLeft('-', 12);
        final note = result.note != null ? '  ' + result.note : '';

        println('  $name $perFrame $fps fps $perUnit/unit$note');

    }

    /**
     * Prints the column header for the rows that follow.
     */
    public static function header():Void {

        println('  ' + pad('scenario', 46) + padLeft('per frame', 13) + padLeft('budget', 13) + padLeft('per unit', 12));

    }

    /**
     * Looks up a previous result by name so scenarios can be compared.
     */
    public static function find(name:String):BenchResult {

        for (result in results) {
            if (result.name == name) return result;
        }
        return null;

    }

    /**
     * Prints how a candidate scenario compares against a baseline one.
     *
     * The direction is taken from the measurement rather than assumed, so a
     * result that contradicts expectations still reads correctly.
     *
     * @param label What is being compared.
     * @param baselineName Name of the scenario to compare against.
     * @param candidateName Name of the scenario being judged.
     */
    public static function compare(label:String, baselineName:String, candidateName:String):Void {

        final baseline = find(baselineName);
        final candidate = find(candidateName);

        if (baseline == null || candidate == null) {
            println('  ' + pad(label, 44) + ' (missing measurement)');
            return;
        }

        if (baseline.msPerFrame <= 0) {
            println('  ' + pad(label, 44) + ' (baseline too fast to measure)');
            return;
        }

        final ratio = candidate.msPerFrame / baseline.msPerFrame;
        final verdict = ratio >= 1
            ? '${format(ratio, 2)}x SLOWER'
            : '${format(1 / ratio, 2)}x faster';

        println('  ' + pad(label, 44) + ' ' + padLeft(verdict, 16)
            + '   (${format(candidate.msPerFrame, 3)} ms vs ${format(baseline.msPerFrame, 3)} ms baseline)');

    }

/// Deterministic pseudo random, so runs are comparable

    static var seed:Int = 1;

    /** Reseeds the generator so a scenario always builds the same scene. */
    public static function reseed(value:Int = 1):Void {

        seed = value;

    }

    /** Returns a pseudo random float in [0, 1). */
    public static function random():Float {

        seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
        return seed / 0x3FFFFFFF;

    }

    /** Returns a pseudo random float in [min, max). */
    public static function range(min:Float, max:Float):Float {

        return min + random() * (max - min);

    }

/// Formatting

    /** Formats a float with a fixed number of decimals. */
    public static function format(value:Float, decimals:Int):String {

        if (decimals <= 0) {
            return '' + Math.round(value);
        }

        var multiplier = 1.0;
        for (_ in 0...decimals) multiplier *= 10;

        final rounded = Math.round(value * multiplier) / multiplier;
        var text = '' + rounded;

        final dot = text.indexOf('.');
        if (dot == -1) {
            text += '.';
            for (_ in 0...decimals) text += '0';
        }
        else {
            var missing = decimals - (text.length - dot - 1);
            while (missing > 0) {
                text += '0';
                missing--;
            }
        }

        return text;

    }

    /** Pads `text` on the right to `width` characters. */
    public static function pad(text:String, width:Int):String {

        var result = text;
        while (result.length < width) result += ' ';
        return result;

    }

    /** Pads `text` on the left to `width` characters. */
    public static function padLeft(text:String, width:Int):String {

        var result = text;
        while (result.length < width) result = ' ' + result;
        return result;

    }

    /** Prints a line on whichever target this is running on. */
    public static function println(s:String):Void {

        #if sys
        Sys.println(s);
        #elseif js
        js.Syntax.code("console.log({0})", s);
        #else
        trace(s);
        #end

    }

}
