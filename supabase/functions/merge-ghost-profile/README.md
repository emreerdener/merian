# Merge Ghost Profile

Handles the critical transition from **Anonymous Scan** to **Authenticated User**.
When a user downloads Merian and identifies something without creating an account first, the `/identify` API assigns them an anonymous "Ghost Profile". Once they decide to log in, this endpoint merges all historical scans attached to their temporary UUID over into their newly authenticated Auth UUID, ensuring zero data loss during onboarding.

## Architecture

To enforce clean separation of concerns, the module is split:

- **`index.ts`**
  The lightweight HTTP router. Orchestrates the 3-step transition protocol (Verify, Transfer, Purge) while enforcing boundaries like validating `ghost_id` doesn't randomly match the current JWT.
  
- **`db.ts`**
  Houses the privileged Postgres functions that modify the `auth.users` schema. Includes IDOR (Insecure Direct Object Reference) prevention by guaranteeing the target account is purely an `is_anonymous` ghost.
