# Core Security

The `Security` directory handles identity, authentication, and secure storage on the device.

## Purpose
This area contains the infrastructure for managing user sessions. It handles the creation and merging of anonymous IDFV-backed Ghost Sessions, Sign in with Apple/Google integrations, and secure Keychain wrappers to ensure that sensitive tokens (like the Supabase Auth token) remain protected.
