#!/usr/bin/env bash
set -euo pipefail
case_dir="$(cd "$(dirname "$0")" && pwd)"
cp -R "$case_dir/../fixtures/value_contract/." .
cp "$case_dir/../fixtures/value_contract_ruby31_overlay/.ruby-version" .
cp "$case_dir/../fixtures/value_contract_ruby31_overlay/lib/tax_band.rb" lib/
