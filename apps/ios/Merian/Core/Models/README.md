# Core Models

The `Models` directory contains shared entity definitions and domain models utilized across the entire application.

## Purpose
This area houses definitions that don't belong strictly to a single feature (like a standard `User` model, or generic error types). If a model is only used by `Scans`, it should live in `Features/Scans/Models`. But if it's passed between `Explore`, `Scans`, and `Profile`, it belongs here in `Core/Models`.
