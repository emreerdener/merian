# Scans Collections

The `Collections` directory contains the logic and UI for managing user-created collections (albums) of scans.

## Structure

- **Views**: Contains screens for viewing a list of collections, viewing a specific collection's contents, and the flow for creating or editing collections.
- **Components**: Reusable UI elements specific to collections (e.g., collection grid tiles, header views).
- **Models**: Defines the local SwiftData and synchronization models for collections and their many-to-many relationships with individual scans.

## Purpose
This area allows users to organize their captures into custom groups. It handles the display of these groups and integrates with the backend synchronization pipeline to ensure collections are persisted via Supabase.
