#!/usr/bin/env bash
set -euo pipefail
case_dir="$(cd "$(dirname "$0")" && pwd)"
cp -R "$case_dir/../fixtures/rails_safety/." .
