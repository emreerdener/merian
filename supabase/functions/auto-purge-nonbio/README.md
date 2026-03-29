# Auto-Purge Non-Biological Scans

This Edge Function silently purges records flagged as `is_biological_subject = false`.
Commonly triggered by users attempting to identify rocks, food, cars, or buildings. These records are discarded to prevent database bloat and strictly maintain focus on the taxonomic core.
