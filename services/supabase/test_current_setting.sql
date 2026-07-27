DO $$
BEGIN
  RAISE NOTICE 'Role is: "%"', pg_catalog.CURRENT_SETTING('role', TRUE);
END;
$$;
