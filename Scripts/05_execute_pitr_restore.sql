/*
Purpose:
- Restores the latest full backup to OpsLab_PITR using NORECOVERY.
- Restores the latest log backup using STOPAT to recover to the marker time.
- Verifies that the point-in-time recovery database is online & contains the expected row count.

Run order:
5 of 7

Notes:
- Uses RESTORE ... WITH MOVE because the database is restored under a different name & file path.
- Converts the marker time to DATETIME before building the STOPAT value.
- This script proves recovery to a known-good point before the accidental delete. */

USE master;
GO

-- Identify the latest successful full backup, log backup, & recovery marker.
DECLARE @full_backup NVARCHAR(4000);
DECLARE @log_backup  NVARCHAR(4000);
DECLARE @stopat_dt2  DATETIME2(7);
DECLARE @stopat_dt   DATETIME;
DECLARE @sql         NVARCHAR(MAX);

SELECT TOP (1) @full_backup = backup_file
FROM OpsAdmin.dbo.backup_runs
WHERE backup_type = 'FULL'
  AND status = 'SUCCESS'
ORDER BY backup_run_id DESC;

SELECT TOP (1) @log_backup = backup_file
FROM OpsAdmin.dbo.backup_runs
WHERE backup_type = 'LOG'
  AND status = 'SUCCESS'
ORDER BY backup_run_id DESC;

SELECT TOP (1) @stopat_dt2 = marker_time
FROM OpsAdmin.dbo.recovery_markers
WHERE marker_name = N'before_bad_delete_v2'
ORDER BY marker_id DESC;

-- Convert the marker to DATETIME so STOPAT uses a SQL Server-friendly format.
SET @stopat_dt = CAST(@stopat_dt2 AS DATETIME);

-- Restore the full backup to the PITR database in NORECOVERY mode.
SET @sql =
    N'RESTORE DATABASE [OpsLab_PITR] ' +
    N'FROM DISK = N''' + REPLACE(@full_backup, '''', '''''') + N''' ' +
    N'WITH MOVE N''OpsLab_Source_Data'' TO N''C:\SQLLab\Restore\OpsLab_PITR.mdf'', ' +
    N'     MOVE N''OpsLab_Source_Log''  TO N''C:\SQLLab\Restore\OpsLab_PITR_log.ldf'', ' +
    N'     NORECOVERY, REPLACE, STATS = 10;';

PRINT @sql;
EXEC(@sql);

-- Apply the log backup & recover only to the marker time.
SET @sql =
    N'RESTORE LOG [OpsLab_PITR] ' +
    N'FROM DISK = N''' + REPLACE(@log_backup, '''', '''''') + N''' ' +
    N'WITH STOPAT = ''' + CONVERT(VARCHAR(23), @stopat_dt, 121) + N''', ' +
    N'     RECOVERY, STATS = 10;';

PRINT @sql;
EXEC(@sql);
GO

-- Verify the PITR database is online after the restore sequence.
SELECT name, state_desc
FROM sys.databases
WHERE name = 'OpsLab_PITR';
GO

-- Compare the source & PITR row counts to confirm the deleted row was recovered in the restored copy.
SELECT COUNT(*) AS source_payments_count
FROM OpsLab_Source.dbo.payments;

SELECT COUNT(*) AS pitr_payments_count
FROM OpsLab_PITR.dbo.payments;
GO