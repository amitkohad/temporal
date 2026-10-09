\set ON_ERROR_STOP on
-- This fixture is destructive only to its named fixture table in an isolated database.
SELECT CASE current_database() WHEN 'temporal' THEN 'temporal_migrator' ELSE 'temporal_visibility_migrator' END AS migrator,
       CASE current_database() WHEN 'temporal' THEN 'temporal_runtime' ELSE 'temporal_visibility_runtime' END AS runtime,
       CASE current_database() WHEN 'temporal' THEN 'temporal_visibility' ELSE 'temporal' END AS other_database \gset
SET ROLE :"migrator";
CREATE TABLE public.nexusflow_role_fixture (id BIGSERIAL PRIMARY KEY, value TEXT NOT NULL);
RESET ROLE;
SELECT set_config('nexusflow.runtime', :'runtime', false), set_config('nexusflow.migrator', :'migrator', false);
SELECT NOT has_database_privilege(:'runtime', :'other_database', 'CONNECT') AS cross_database_denied \gset
\if :cross_database_denied
\else
  \echo 'Runtime unexpectedly has access to the other store.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
BEGIN;
SET SESSION AUTHORIZATION :"runtime";
INSERT INTO public.nexusflow_role_fixture(value) VALUES ('inserted');
UPDATE public.nexusflow_role_fixture SET value = 'updated';
DO $$ BEGIN
  IF (SELECT value FROM public.nexusflow_role_fixture LIMIT 1) <> 'updated' THEN
    RAISE EXCEPTION 'Runtime DML verification failed';
  END IF;
  BEGIN
    CREATE TABLE public.nexusflow_runtime_ddl_should_fail(id INT);
    RAISE EXCEPTION 'Runtime CREATE TABLE was allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    ALTER TABLE public.nexusflow_role_fixture ADD COLUMN denied INT;
    RAISE EXCEPTION 'Runtime ALTER TABLE was allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    CREATE TEMP TABLE nexusflow_runtime_temp_should_fail(id INT);
    RAISE EXCEPTION 'Runtime temporary DDL was allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    EXECUTE format('SET ROLE %I', current_setting('nexusflow.migrator'));
    RAISE EXCEPTION 'Runtime escalation to migrator was allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
DELETE FROM public.nexusflow_role_fixture;
COMMIT;
RESET SESSION AUTHORIZATION;
SET ROLE :"migrator";
DROP TABLE public.nexusflow_role_fixture;
RESET ROLE;
\echo 'ROLE_BOUNDARY_OK runtime DML allowed; runtime DDL, escalation, and cross-store CONNECT denied.'