# Core AI

The `AI` directory contains the app-wide infrastructure for on-device machine learning and inference.

## Purpose
This area is responsible for tasks like `VNClassifyImageRequest` which runs concurrently on-device during a capture to generate status phrases. It may also hold any CoreML models or utilities that are not strictly bound to a single feature like `Capture`, ensuring reusable AI processing pipelines.
