# Generate Upload URLs

Implements the **Secure Direct-To-Storage Upload Pattern**.
Instead of pushing multi-megabyte image binaries directly through the Edge Function RAM (which causes V8 Isolates to crash), the iOS client calls this lightweight endpoint.
It provisions and returns a short-lived **S3 Presigned URL**, allowing the iOS client to natively `PUT` the image payload straight into Cloudflare R2 bypassing the proxy entirely.
