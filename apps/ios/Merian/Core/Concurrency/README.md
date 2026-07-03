# Core Concurrency

The `Concurrency` directory contains infrastructure supporting the app's Swift 6 concurrency model.

## Purpose
This area holds tools to enforce the zero-OOM (Out Of Memory) design and strict isolation domains. It may contain definitions for custom actors, like `BackgroundDatabaseActor` or `FileIOActor`, that ensure heavy database and file operations do not block the main thread or cause memory spikes during complex tasks.
