\set ON_ERROR_STOP on
-- Run as the database bootstrap administrator in one dedicated Temporal database.
SELECT current_database() IN ('temporal', 'temporal_visibility') AS supported_database \gset
\if :supported_database
\else
  \echo 'Refusing role bootstrap outside temporal or temporal_visibility.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
SELECT current_database() AS database, current_user AS bootstrap_administrator,
       CASE current_database() WHEN 'temporal' THEN 'temporal_migrator' ELSE 'temporal_visibility_migrator' END AS migrator,
       CASE current_database() WHEN 'temporal' THEN 'temporal_runtime' ELSE 'temporal_visibility_runtime' END AS runtime \gset
BEGIN;
SELECT format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', role_name)
FROM (VALUES (:'migrator'), (:'runtime')) AS roles(role_name)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) \gexec
SELECT bool_and(NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls AND NOT rolcanlogin)
AND NOT EXISTS (
  SELECT 1 FROM pg_auth_members membership JOIN pg_roles member_role ON member_role.oid = membership.member
  WHERE member_role.rolname IN (:'migrator', :'runtime')
)
AND NOT EXISTS (
  SELECT 1 FROM pg_class object JOIN pg_roles owner_role ON owner_role.oid = object.relowner
  WHERE owner_role.rolname = :'runtime'
)
AND NOT EXISTS (
  SELECT 1 FROM pg_namespace schema JOIN pg_roles owner_role ON owner_role.oid = schema.nspowner
  WHERE owner_role.rolname = :'runtime'
)
AND NOT EXISTS (
  SELECT 1 FROM pg_database database JOIN pg_roles owner_role ON owner_role.oid = database.datdba
  WHERE owner_role.rolname = :'runtime'
) AS safe_roles
FROM pg_roles WHERE rolname IN (:'migrator', :'runtime') \gset
\if :safe_roles
\else
  ROLLBACK;
  \echo 'Existing privilege roles must be unprivileged NOLOGIN roles; review before continuing.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
-- Azure administrators are not superusers; explicit membership permits role-owned defaults.
GRANT :"migrator" TO :"bootstrap_administrator" WITH INHERIT TRUE, SET TRUE;
CREATE SCHEMA IF NOT EXISTS nexusflow_migration AUTHORIZATION :"migrator";
SELECT pg_get_userbyid(nspowner) = :'migrator' AS safe_migration_schema
FROM pg_namespace WHERE nspname = 'nexusflow_migration' \gset
\if :safe_migration_schema
\else
  ROLLBACK;
  \echo 'Existing migration guard schema is not owned by the expected migrator.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
REVOKE ALL ON SCHEMA nexusflow_migration FROM PUBLIC, :"runtime";
REVOKE ALL ON DATABASE :"database" FROM PUBLIC;
REVOKE ALL ON DATABASE :"database" FROM :"migrator", :"runtime";
GRANT CONNECT ON DATABASE :"database" TO :"migrator";
GRANT CONNECT ON DATABASE :"database" TO :"runtime";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"migrator";
GRANT USAGE ON SCHEMA public TO :"runtime";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"runtime";
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO :"runtime";
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO :"runtime";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO :"runtime";
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator" IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO :"runtime";
-- Rerun after migrations to make migration audit tables read-only for runtime.
SELECT format('REVOKE INSERT, UPDATE, DELETE ON TABLE public.%I FROM %I', table_name, :'runtime')
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('schema_version', 'schema_update_history') \gexec
SELECT current_database() = 'temporal_visibility' AS visibility_database \gset
\if :visibility_database
CREATE EXTENSION IF NOT EXISTS btree_gin;
\endif
COMMIT;