# Core Network

The `Network` directory manages the application's communication with remote servers.

## Purpose
This area provides the central infrastructure for API interactions. It contains the clients that interface with the Supabase Edge Functions (e.g., `/identify-multimodal`), handles request retries via `NWPathMonitor`, and manages the background `URLSession` behaviors required for the offline-first sync pipeline.
