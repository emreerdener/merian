SET lock_timeout='5s';
SET statement_timeout='2min';

-- Pure held projection. No receipt, table, caller or upload authority.
CREATE FUNCTION internal.observation_video_source_cohort_items(p_input JSONB)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE graph JSONB; items JSONB; frames JSONB;
BEGIN
    PERFORM internal.observation_video_source_fingerprint(p_input);
    graph:=p_input->'evidence_manifest'->'provenance';
    items:=jsonb_build_array((graph->'source')||jsonb_build_object('role','source','index',NULL));
    SELECT jsonb_agg((frame->'artifact')||jsonb_build_object('role','frame','index',frame->'index') ORDER BY ordinal)
        INTO frames FROM jsonb_array_elements(graph->'frames') WITH ORDINALITY AS entries(frame,ordinal);
    items:=items||frames;
    IF graph->'audio'<>'null'::JSONB THEN
        items:=items||jsonb_build_array((graph->'audio'->'artifact')||jsonb_build_object('role','audio','index',NULL));
    END IF;
    RETURN items;
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_video_source_cohort_items(JSONB) FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON FUNCTION internal.observation_video_source_cohort_items(JSONB) IS
    'Held V4 ordered inventory only; not a durable cohort, receipt, upload permission or terminal release proof.';
RESET statement_timeout;
RESET lock_timeout;
