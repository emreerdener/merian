SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- A sealed proof contains immutable owner identity. Do not reparent it, and do
-- not block unrelated empty-owner merges merely because the table exists.
CREATE INDEX ordinary_initial_evidence_owner ON internal.ordinary_initial_evidence(owner_id);
INSERT INTO internal.ghost_profile_merge_reference_policies
    (source_schema,source_table,source_column,referenced_schema,referenced_table,referenced_column,strategy,execution_order,handler_key,purpose)
VALUES('internal','ordinary_initial_evidence','owner_id','public','users','id','preserve',920,NULL,
    'Hold identity transfer only while the source owns immutable ordinary initial evidence; never rewrite admitted ownership.');

RESET lock_timeout;
RESET statement_timeout;
