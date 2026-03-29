# Auto-Purge Domesticated Scans

This background Edge Function (triggered via Database Webhook or `pg_cron`) is responsible for silently sweeping and hard-deleting records flagged with `ecology_type = 'domesticated'`.
Because Merian strictly focuses on wild biology for its global research dataset, domesticated pets and potted houseplants are discarded automatically over time to preserve storage space and dataset integrity.
