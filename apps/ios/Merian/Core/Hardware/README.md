# Core Hardware

The `Hardware` directory contains managers for monitoring and interacting with the device's physical state.

## Purpose
This area houses the `HardwareOrchestrator`, which monitors `ProcessInfo.thermalState` and `isLowPowerModeEnabled`. It dynamically manages resource intensity (such as capping framerates to 24fps or dropping heavy shaders) under thermal pressure to ensure the app remains stable during intense camera and AI usage.

## Camera recording concurrency

`CameraManager` owns AVFoundation session mutations and all movie-output and
connection state on its serial camera queue. A video request is identified by
both a UUID generation and its UUID-derived output URL. Delayed timeouts and
automatic stops also carry an action UUID so a cooperatively cancelled task
cannot act after replacement. Recording delegate callbacks must match the
configured output and the current URL before they may clear state or resume a
continuation. Keep observable UI updates on `@MainActor` and guard them with the
same recording generation.

The recording state lives as one value under `videoRecordingLock`. Do not split
the continuation, URL, timer tasks, or start metadata into independently mutable
properties, and never nest `videoRecordingLock` with the camera manager's other
locks.
