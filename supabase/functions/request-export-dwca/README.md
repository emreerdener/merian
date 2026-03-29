# Request DwC-A Export Queue

The fast, synchronous client endpoint for initiating data exports.
**Client → HTTP Edge**
Because zipping thousands of images takes longer than HTTP socket timeout limits allow, this function merely:
1. Validates the user's JWT.
2. Checks the exact rate limit (1 export maximum per 24 hours).
3. Inserts a `pending` row into `export_jobs`.
4. Returns a fast `200 OK`.
This ensures the iOS app UI never blocks, while the `export-dwca` webhook secretly handles the heavy-lifting chronologically.
