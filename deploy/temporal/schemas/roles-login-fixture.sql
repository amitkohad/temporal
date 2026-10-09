\set ON_ERROR_STOP on
-- Isolated PostgreSQL test only; these logins have no password and use local test trust.
-- Run after roles.sql in both test databases. Never execute against Azure.
BEGIN;
CREATE ROLE nexusflow_test_temporal_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE nexusflow_test_temporal_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE nexusflow_test_visibility_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE nexusflow_test_visibility_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
GRANT temporal_runtime TO nexusflow_test_temporal_runtime WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT temporal_migrator TO nexusflow_test_temporal_migrator WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT temporal_visibility_runtime TO nexusflow_test_visibility_runtime WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT temporal_visibility_migrator TO nexusflow_test_visibility_migrator WITH ADMIN FALSE, INHERIT FALSE, SET TRUE;
GRANT CONNECT ON DATABASE temporal TO nexusflow_test_temporal_runtime, nexusflow_test_temporal_migrator;
GRANT CONNECT ON DATABASE temporal_visibility TO nexusflow_test_visibility_runtime, nexusflow_test_visibility_migrator;
COMMIT;