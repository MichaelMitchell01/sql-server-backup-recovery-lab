USE master;
GO

-- Confirm all expected databases exist
IF DB_ID(N'OpsLab_Source') IS NULL
    THROW 51001, 'OpsLab_Source does not exist.', 1;

IF DB_ID(N'OpsLab_Restore') IS NULL
    THROW 51002, 'OpsLab_Restore does not exist.', 1;

IF DB_ID(N'OpsLab_PITR') IS NULL
    THROW 51003, 'OpsLab_PITR does not exist.', 1;

-- Confirm all databases are online
IF EXISTS
(
    SELECT 1
    FROM sys.databases
    WHERE name IN
    (
        N'OpsLab_Source',
        N'OpsLab_Restore',
        N'OpsLab_PITR'
    )
    AND state_desc <> 'ONLINE'
)
    THROW 51004, 'One or more lab databases are not ONLINE.', 1;

-- Verify expected data-loss state in source
IF (SELECT COUNT(*) FROM OpsLab_Source.dbo.payments) <> 4
    THROW 51005, 'Unexpected payment count in OpsLab_Source.', 1;

-- Verify full-backup validation restore
IF (SELECT COUNT(*) FROM OpsLab_Restore.dbo.payments) <> 5
    THROW 51006, 'Unexpected payment count in OpsLab_Restore.', 1;

-- Verify PITR recovered the deleted row
IF (SELECT COUNT(*) FROM OpsLab_PITR.dbo.payments) <> 5
    THROW 51007, 'Point-in-time recovery did not recover the expected payment row.', 1;

-- Confirm a successful full backup exists
IF NOT EXISTS
(
    SELECT 1
    FROM OpsAdmin.dbo.backup_runs
    WHERE backup_type = 'FULL'
      AND status = 'SUCCESS'
)
    THROW 51008, 'No successful full backup was recorded.', 1;

-- Confirm a successful log backup exists
IF NOT EXISTS
(
    SELECT 1
    FROM OpsAdmin.dbo.backup_runs
    WHERE backup_type = 'LOG'
      AND status = 'SUCCESS'
)
    THROW 51009, 'No successful log backup was recorded.', 1;

-- Confirm validation restore succeeded
IF NOT EXISTS
(
    SELECT 1
    FROM OpsAdmin.dbo.restore_runs
    WHERE target_db = N'OpsLab_Restore'
      AND status = 'SUCCESS'
)
    THROW 51010, 'No successful validation restore was recorded.', 1;

DECLARE @latest_restore_run_id INT;

SELECT @latest_restore_run_id = MAX(restore_run_id)
FROM OpsAdmin.dbo.restore_runs
WHERE target_db = N'OpsLab_Restore'
  AND status = 'SUCCESS';

-- Fail CI if any validation check failed
IF EXISTS
(
    SELECT 1
    FROM OpsAdmin.dbo.validation_results
    WHERE restore_run_id = @latest_restore_run_id
      AND status <> 'PASS'
)
    THROW 51011, 'One or more restore validation checks failed.', 1;

-- Confirm all 8 data checks plus DBCC CHECKDB passed
IF
(
    SELECT COUNT(*)
    FROM OpsAdmin.dbo.validation_results
    WHERE restore_run_id = @latest_restore_run_id
      AND status = 'PASS'
) <> 9
    THROW 51012, 'Expected 9 successful validation checks.', 1;

PRINT 'All SQL Server CI assertions passed.';
GO