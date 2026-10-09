\set ON_ERROR_STOP on
-- Connect as the isolated runtime LOGIN with PGOPTIONS='-c role=matching_runtime_role'.
SELECT CASE current_database() WHEN 'temporal' THEN 'temporal_runtime' ELSE 'temporal_visibility_runtime' END AS runtime,
       CASE current_database() WHEN 'temporal' THEN 'temporal_migrator' ELSE 'temporal_visibility_migrator' END AS migrator \gset
SELECT current_user = :'runtime' AND session_user <> current_user AS role_selected \gset
\if :role_selected
\else
DO $$ BEGIN RAISE EXCEPTION 'Runtime login did not select its privilege role'; END $$;
\endif
SELECT set_config('nexusflow.migrator', :'migrator', false);
BEGIN;
INSERT INTO public.nexusflow_login_fixture(value) VALUES ('fixture');
UPDATE public.nexusflow_login_fixture SET value = 'updated';
SELECT value FROM public.nexusflow_login_fixture;
DELETE FROM public.nexusflow_login_fixture;
DO $$ BEGIN
  BEGIN
    CREATE TABLE public.nexusflow_login_ddl_should_fail(id INT);
    RAISE EXCEPTION 'Runtime LOGIN can create tables';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    UPDATE public.schema_version SET curr_version = curr_version;
    RAISE EXCEPTION 'Runtime LOGIN can write schema audit';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    EXECUTE format('SET ROLE %I', current_setting('nexusflow.migrator'));
    RAISE EXCEPTION 'Runtime LOGIN can escalate to migrator';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
ROLLBACK;
\echo 'LOGIN_BOUNDARY_OK authenticated runtime DML allowed; DDL, audit DML, and escalation denied.'