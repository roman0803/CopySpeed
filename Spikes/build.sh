#!/bin/zsh
# Baut alle Spike-Tools nach Spikes/bin
set -e
cd "${0:A:h}"
mkdir -p bin
for f in ax-spike progress-spike io-spike; do
  echo "→ $f"
  swiftc -O -swift-version 5 "$f.swift" -o "bin/$f"
done
echo "Fertig: $(pwd)/bin"
