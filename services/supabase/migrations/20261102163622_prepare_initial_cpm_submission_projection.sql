-- Private CPM admission projection, not verification/funding/admission authority.
-- Legacy constructors, NOT NULL/proof constraints and activation remain unchanged.
SET statement_timeout = '60s';
SET lock_timeout = '5s';

CREATE FUNCTION internal.initial_cpm_admission_submission(p_candidate TEXT,p_assignment TEXT)
RETURNS JSONB LANGUAGE plpgsql IMMUTABLE SET search_path = '' AS $$
DECLARE candidate JSONB; assignment JSONB; input_text TEXT; descriptions_text TEXT;
BEGIN
    candidate:=internal.parse_initial_cpm_photo_candidate(p_candidate);
    assignment:=internal.parse_initial_cpm_photo_assignment(p_candidate,p_assignment);
    -- Schema 2 stores the exact content-v1 bytes, not a legacy input-v1 rewrite.
    input_text:=candidate->>'content_canonical';
    descriptions_text:=internal.initial_canonical(input_text::JSONB->'contexts');
    RETURN jsonb_build_object(
        'input_schema_version',2,'binding_version',4,
        'submission_canonical',input_text,'submission_digest',assignment->>'content_digest',
        'descriptions_canonical',descriptions_text,
        'descriptions_digest',encode(extensions.digest(convert_to(
            'merian.initial-analysis.cpm-photo-contexts.v1'||E'\n'||descriptions_text,
            'UTF8'),'sha256'),'hex'));
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_cpm_admission_submission(TEXT,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;

RESET lock_timeout;
RESET statement_timeout;
