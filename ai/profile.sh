#!/bin/bash

profileFile="/tmp/profile_$(date +%Y%m%d_%H%M%S)"

xcrun xctrace record \
  --instrument 'Time Profiler' \
  --time-limit 20s \
  --no-prompt --quiet \
  --output "$profileFile".trace \
  --launch -- \
    ~/git/ztabby/DerivedData/Build/Products/Debug/Ztabby.app --benchmark showUi 3

xcrun xctrace export \
  --input "$profileFile".trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output "$profileFile".xml
