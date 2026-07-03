# Core Hardware

The `Hardware` directory contains managers for monitoring and interacting with the device's physical state.

## Purpose
This area houses the `HardwareOrchestrator`, which monitors `ProcessInfo.thermalState` and `isLowPowerModeEnabled`. It dynamically manages resource intensity (such as capping framerates to 24fps or dropping heavy shaders) under thermal pressure to ensure the app remains stable during intense camera and AI usage.
