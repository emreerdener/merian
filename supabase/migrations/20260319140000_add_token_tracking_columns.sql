ALTER TABLE scans
ADD COLUMN llm_prompt_tokens INT DEFAULT NULL,
ADD COLUMN llm_candidate_tokens INT DEFAULT NULL,
ADD COLUMN llm_total_tokens INT DEFAULT NULL;
