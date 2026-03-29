# Request DwC-A Export Queue

The fast, synchronous client endpoint for initiating data exports.
**Client → HTTP Edge**
Because zipping thousands of images takes longer than HTTP socket timeout limits allow, this function merely:
1. Validates the user's JWT.
2. Checks the exact rate limit (1 export maximum per 24 hours).
3. Inserts a `pending` row into `export_jobs`.
4. Returns a fast `200 OK`.
This ensures the iOS app UI never blocks, while the `export-dwca` webhook secretly handles the heavy-lifting chronologically.

## Architecture

To keep the synchronous router perfectly readable, the logic is extracted:

- **`index.ts`**: The strict HTTP orchestrator. It receives the JSON payload, checks the rate limit helper, fires the queue insertion helper, and ensures the `.swift` client UI gets a 200 OK immediately.
- **`db.ts`**: Encapsulates the explicit PostgreSQL queries (such as comparing `export_jobs.created_at` against the `gte` 24-hour bounding constraint).
