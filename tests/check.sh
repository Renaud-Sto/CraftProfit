#!/bin/sh
# Full check: unit tests, then static analysis. Works from any directory.
set -e
cd "$(dirname "$0")/.."
luajit tests/run.lua
luacheck CraftProfit tests --config .luacheckrc
