# Capture Scan

The `Scan` directory drives the core visual camera experience.

## Purpose
This area orchestrates the `AVCaptureSession`. It handles complex hardware integrations such as:
- Device priority (preferring the Triple Camera for the full 0.5×–15× optical zoom range).
- LiDAR depth harvesting (`AVCaptureDepthDataOutput`) to provide absolute scale to the AI model.
- Real-time viewfinder intelligence (analyzing luma for brightness/motion blur at 3fps).
- The logarithmic zoom meter, manual exposure/focus, and physical hardware button events (Action Button / Camera Control).
