#!/bin/bash

# Runs the headless assertion-based test suite.
#
# By default it runs on the Haxe interpreter, which needs no extra tooling.
# Pass --js to additionally compile to JavaScript and run it under node, which
# is a useful cross-target check (the library has target-specific code paths).

set -e

echo "Running unit tests on the Haxe interpreter..."
haxe build.hxml

if [ "$1" == "--js" ]; then
    echo ""
    echo "Running unit tests on JavaScript (node)..."
    haxe build-tests-js.hxml
    node out/test/unit-tests.js
fi
