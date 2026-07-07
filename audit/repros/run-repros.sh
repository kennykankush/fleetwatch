#!/bin/bash
# Bedrock regression sweep: copies audit probes into the test tree, runs
# them, cleans up. A probe PASSING means its flaw is still present
# (probes assert the flaw). After a fix, the probe should FAIL — then
# invert it into a real regression test and retire it here.
set -euo pipefail
cd "$(dirname "$0")/../.."
cp audit/repros/AuditProbeF001.swift Core/Tests/InventoryKitTests/
cp audit/repros/AuditProbeF002.swift Core/Tests/LedgerKitTests/
cp audit/repros/AuditProbeF003.swift Core/Tests/ScannerKitTests/
trap 'rm -f Core/Tests/InventoryKitTests/AuditProbeF001.swift Core/Tests/LedgerKitTests/AuditProbeF002.swift Core/Tests/ScannerKitTests/AuditProbeF003.swift' EXIT
cd Core && swift test --filter AuditProbe
