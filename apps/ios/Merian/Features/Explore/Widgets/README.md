# Explore Widgets

The `Widgets` directory contains the logic necessary to bridge Explore content
to the iOS Home Screen.

## Purpose

This area manages the caching and data preparation for the Explore WidgetKit
extension. It securely serializes image-only Explore snapshots and metadata into
the shared App Group container, allowing the standalone widget process to render
trending captures efficiently.

## Visibility and write fencing

`ExploreWidgetSnapshotWriter` owns cancellable writes and a write generation on
the main actor. It checks the account/content context after image awaits and
before commit. Report invalidation removes hidden snapshot entries and unused
files; account changes clear all previous entries, including an empty snapshot.
