\set ON_ERROR_STOP on
-- Execute only against Azure's postgres database as the configured Entra administrator.
-- Pass identity_name, object_id, tenant_id and privilege_role with psql -v; none are credentials.
SELECT current_database() = 'postgres' AND :'privilege_role' IN
  ('temporal_runtime', 'temporal_migrator', 'temporal_visibility_runtime', 'temporal_visibility_migrator')
  AND length(:'identity_name') BETWEEN 1 AND 63
  AND :'object_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  AND :'tenant_id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' AS valid_mapping \gset
\if :valid_mapping
\else
  \echo 'Invalid Azure principal mapping database or privilege role.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
BEGIN;
SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'identity_name') AS principal_exists \gset
\if :principal_exists
\else
  SELECT * FROM pg_catalog.pgaadauth_create_principal_with_oid(:'identity_name', :'object_id', 'service', false, false);
\endif
SELECT NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls
       AND NOT pg_has_role(rolname, 'azure_pg_admin', 'MEMBER') AS safe_principal
FROM pg_roles WHERE rolname = :'identity_name' \gset
\if :safe_principal
\else
  ROLLBACK;
  \echo 'Entra application principal must not hold administrator capabilities.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
SELECT EXISTS (
  SELECT 1 FROM pg_catalog.pgaadauth_list_principals(false) principal
  WHERE rolename = :'identity_name'
    AND lower(COALESCE(to_jsonb(principal)->>'objectId', to_jsonb(principal)->>'objectid')) = lower(:'object_id')
    AND lower(COALESCE(to_jsonb(principal)->>'tenantId', to_jsonb(principal)->>'tenantid')) = lower(:'tenant_id')
    AND COALESCE(to_jsonb(principal)->>'principalType', to_jsonb(principal)->>'principaltype') = 'service'
    AND COALESCE(to_jsonb(principal)->>'isAdmin', to_jsonb(principal)->>'isadmin') = '0'
) AND NOT EXISTS (
  SELECT 1 FROM pg_auth_members membership JOIN pg_roles granted ON granted.oid = membership.roleid
  JOIN pg_roles login ON login.oid = membership.member
  WHERE login.rolname = :'identity_name'
    AND granted.rolname <> :'privilege_role'
) AND NOT EXISTS (
  SELECT 1 FROM pg_catalog.pgaadauth_list_principals(false) principal
  WHERE rolename <> :'identity_name'
    AND lower(COALESCE(to_jsonb(principal)->>'objectId', to_jsonb(principal)->>'objectid')) = lower(:'object_id')
) AS correct_identity \gset
\if :correct_identity
\else
  ROLLBACK;
  \echo 'Existing principal object/tenant/type or store-role mapping differs; no reassignment performed.'
  DO $$ BEGIN RAISE EXCEPTION 'Database role policy rejected'; END $$;
\endif
SELECT CASE WHEN :'privilege_role' IN ('temporal_runtime', 'temporal_migrator')
       THEN 'temporal' ELSE 'temporal_visibility' END AS target_database \gset
-- LOGIN admission precedes least-privilege SET ROLE and requires a direct CONNECT grant.
REVOKE ALL ON DATABASE temporal, temporal_visibility FROM :"identity_name";
GRANT CONNECT ON DATABASE :"target_database" TO :"identity_name";
GRANT :"privilege_role" TO :"identity_name" WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
COMMIT;