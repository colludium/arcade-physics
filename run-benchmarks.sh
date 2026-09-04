#!/bin/bash

# Runs the performance stress tests.
#
# The JavaScript target is the default because interpreter timings are
# dominated by interpreter overhead. Pass --interp to run on the interpreter
# instead (no node required); the relative costs still hold, the absolute
# numbers are roughly two orders of magnitude larger.

set -e

if [ "$1" == "--interp" ]; then
    echo "Running benchmarks on the Haxe interpreter..."
    haxe build-benchmarks.hxml
else
    if ! command -v node &> /dev/null; then
        echo "node not found; falling back to the Haxe interpreter."
        echo "(run with --interp to skip this check)"
        haxe build-benchmarks.hxml
        exit 0
    fi

    echo "Building benchmarks for JavaScript..."
    haxe build-benchmarks-js.hxml
    echo ""
    node out/bench/benchmarks.js
fi
