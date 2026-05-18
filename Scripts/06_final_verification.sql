/*
Purpose:
- Summarizes the final state of the lab after validation restore & point-in-time recovery.
- Confirms database states.
- Compares key row counts across source, validation restore, & PITR databases.
- Displays operational log tables for auditability.

Run order:
6 of 7

Notes:
- This script is intended for final proof, screenshots, & README evidence.
- Use the output of this file in GitHub documentation to show the end-to-end workflow succeeded. */

USE master;
GO

-- Confirm the current state of the source, validation, & PITR databases.
SELECT name, state_desc
FROM sys.databases
WHERE name IN ('OpsLab_Source', 'OpsLab_Restore', 'OpsLab_PITR');
GO

-- Compare payment counts across all three databases.
SELECT COUNT(*) AS source_payments_count
FROM OpsLab_Source.dbo.payments;

SELECT COUNT(*) AS restore_payments_count
FROM OpsLab_Restore.dbo.payments;

SELECT COUNT(*) AS pitr_payments_count
FROM OpsLab_PITR.dbo.payments;
GO

-- Review logged backup history.
SELECT * 
FROM OpsAdmin.dbo.backup_runs
ORDER BY backup_run_id DESC;

-- Review logged restore history.
SELECT * 
FROM OpsAdmin.dbo.restore_runs
ORDER BY restore_run_id DESC;

-- Review validation results from the restore test.
SELECT * 
FROM OpsAdmin.dbo.validation_results
ORDER BY validation_id DESC;

-- Review recovery markers used for PITR testing.
SELECT *
FROM OpsAdmin.dbo.recovery_markers
ORDER BY marker_id DESC;
GO