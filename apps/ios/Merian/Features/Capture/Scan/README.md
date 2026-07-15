# Capture Scan

The `Scan` directory drives the core visual camera experience.

## Purpose
This area orchestrates the `AVCaptureSession`. It handles complex hardware integrations such as:
- Device priority (preferring the Triple Camera for the full 0.5×–15× optical zoom range).
- LiDAR depth harvesting (`AVCaptureDepthDataOutput`) to provide absolute scale to the AI model.
- Real-time viewfinder intelligence (analyzing luma for brightness/motion blur at 3fps).
- The logarithmic zoom meter, manual exposure/focus, and physical hardware button events (Action Button / Camera Control).

## Automatic still-image focus

After the final square crop is encoded, `ImageFocusRegionDetector` runs Vision's
objectness saliency request on a 512 px derivative with a 300 ms deadline. A
region is accepted only when it is confident, bounded, neither tiny nor
scene-sized, and not ambiguous with a similarly confident separate subject.
The accepted top-left-normalized rectangle is transient metadata on
`StagedImage`; camera, gallery, multi-capture, recrop, and historical reanalysis
all use the same detector. Detection never blocks capture submission after its
deadline and never replaces the full inference image.
