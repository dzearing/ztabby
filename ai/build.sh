#!/bin/bash

xcodebuild \
  -workspace ztabby.xcworkspace \
  -scheme Debug \
  -configuration Debug \
  -derivedDataPath ~/git/ztabby/DerivedData
