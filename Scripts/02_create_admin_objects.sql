/*
Purpose:
- Creates the administrative tables used to log backup, restore, validation, & recovery marker activity.
- Creates stored procedures for full backup, log backup, validation restore, & restore verification.

Run order:
2 of 7

Notes:
- Run after 01_setup_databases.sql
- recovery_markers.marker_time uses DATETIME2(7) to support more precise STOPAT testing.
- Procedures are written to log both success & failure outcomes. */

USE OpsAdmin;
GO

-- Create admin tables used to track operational backup, restore, validation, & recovery-marker activity.
CREATE TABLE dbo.backup_runs
(
    backup_run_id INT IDENTITY(1,1) PRIMARY KEY,
    backup_type   VARCHAR(10) NOT NULL,
    backup_file   NVARCHAR(4000) NOT NULL,
    started_at    DATETIME2(0) NOT NULL,
    ended_at      DATETIME2(0) NULL,
    status        VARCHAR(20) NOT NULL,
    error_message NVARCHAR(4000) NULL
);

CREATE TABLE dbo.restore_runs
(
    restore_run_id INT IDENTITY(1,1) PRIMARY KEY,
    backup_run_id  INT NOT NULL,
    target_db      SYSNAME NOT NULL,
    started_at     DATETIME2(0) NOT NULL,
    ended_at       DATETIME2(0) NULL,
    status         VARCHAR(20) NOT NULL,
    error_message  NVARCHAR(4000) NULL
);

CREATE TABLE dbo.validation_results
(
    validation_id   INT IDENTITY(1,1) PRIMARY KEY,
    restore_run_id  INT NOT NULL,
    check_name      VARCHAR(100) NOT NULL,
    source_value    NVARCHAR(255) NULL,
    restored_value  NVARCHAR(255) NULL,
    status          VARCHAR(20) NOT NULL,
    checked_at      DATETIME2(0) NOT NULL
);

CREATE TABLE dbo.recovery_markers
(
    marker_id    INT IDENTITY(1,1) PRIMARY KEY,
    marker_name  VARCHAR(100) NOT NULL,
    marker_time  DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    notes        NVARCHAR(4000) NULL
);
GO

-- Create procedure for full database backups with RESTORE VERIFYONLY validation.
CREATE OR ALTER PROC dbo.usp_take_full_backup
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @started_at DATETIME2(0) = SYSDATETIME();
    DECLARE @backup_file NVARCHAR(4000) =
        N'C:\SQLLab\Backups\Full\OpsLab_Source_FULL_' +
        CONVERT(CHAR(8), GETDATE(), 112) + N'_' +
        REPLACE(CONVERT(CHAR(8), GETDATE(), 108), N':', N'') + N'.bak';

    BEGIN TRY
        DECLARE @sql NVARCHAR(MAX) =
            N'BACKUP DATABASE [OpsLab_Source] ' +
            N'TO DISK = N''' + REPLACE(@backup_file, '''', '''''') + N''' ' +
            N'WITH CHECKSUM, STATS = 10;';

        EXEC(@sql);

        SET @sql =
            N'RESTORE VERIFYONLY ' +
            N'FROM DISK = N''' + REPLACE(@backup_file, '''', '''''') + N''' ' +
            N'WITH CHECKSUM;';

        EXEC(@sql);

        INSERT INTO dbo.backup_runs
        (
            backup_type, backup_file, started_at, ended_at, status, error_message
        )
        VALUES
        (
            'FULL', @backup_file, @started_at, SYSDATETIME(), 'SUCCESS', NULL
        );
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.backup_runs
        (
            backup_type, backup_file, started_at, ended_at, status, error_message
        )
        VALUES
        (
            'FULL', @backup_file, @started_at, SYSDATETIME(), 'FAILED', ERROR_MESSAGE()
        );

        THROW;
    END CATCH
END;
GO

-- Create procedure for transaction log backups used in point-in-time recovery.
CREATE OR ALTER PROC dbo.usp_take_log_backup
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @started_at DATETIME2(0) = SYSDATETIME();
    DECLARE @backup_file NVARCHAR(4000) =
        N'C:\SQLLab\Backups\Log\OpsLab_Source_LOG_' +
        CONVERT(CHAR(8), GETDATE(), 112) + N'_' +
        REPLACE(CONVERT(CHAR(8), GETDATE(), 108), N':', N'') + N'.trn';

    BEGIN TRY
        DECLARE @sql NVARCHAR(MAX) =
            N'BACKUP LOG [OpsLab_Source] ' +
            N'TO DISK = N''' + REPLACE(@backup_file, '''', '''''') + N''' ' +
            N'WITH CHECKSUM, STATS = 10;';

        EXEC(@sql);

        INSERT INTO dbo.backup_runs
        (
            backup_type, backup_file, started_at, ended_at, status, error_message
        )
        VALUES
        (
            'LOG', @backup_file, @started_at, SYSDATETIME(), 'SUCCESS', NULL
        );
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.backup_runs
        (
            backup_type, backup_file, started_at, ended_at, status, error_message
        )
        VALUES
        (
            'LOG', @backup_file, @started_at, SYSDATETIME(), 'FAILED', ERROR_MESSAGE()
        );

        THROW;
    END CATCH
END;
GO

-- Create procedure to restore the latest successful full backup into the validation database.
CREATE OR ALTER PROC dbo.usp_restore_latest_full_to_validation
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @backup_run_id INT;
    DECLARE @backup_file NVARCHAR(4000);
    DECLARE @started_at DATETIME2(0) = SYSDATETIME();

    SELECT TOP (1)
        @backup_run_id = backup_run_id,
        @backup_file = backup_file
    FROM dbo.backup_runs
    WHERE backup_type = 'FULL'
      AND status = 'SUCCESS'
    ORDER BY backup_run_id DESC;

    IF @backup_file IS NULL
        THROW 50001, 'No successful full backup found.', 1;

    BEGIN TRY
        IF DB_ID(N'OpsLab_Restore') IS NOT NULL
        BEGIN
            ALTER DATABASE OpsLab_Restore SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
            DROP DATABASE OpsLab_Restore;
        END;

        DECLARE @sql NVARCHAR(MAX) =
            N'RESTORE DATABASE [OpsLab_Restore] ' +
            N'FROM DISK = N''' + REPLACE(@backup_file, '''', '''''') + N''' ' +
            N'WITH MOVE N''OpsLab_Source_Data'' TO N''C:\SQLLab\Restore\OpsLab_Restore.mdf'', ' +
            N'     MOVE N''OpsLab_Source_Log''  TO N''C:\SQLLab\Restore\OpsLab_Restore_log.ldf'', ' +
            N'     REPLACE, RECOVERY, CHECKSUM, STATS = 10;';

        EXEC(@sql);

        INSERT INTO dbo.restore_runs
        (
            backup_run_id, target_db, started_at, ended_at, status, error_message
        )
        VALUES
        (
            @backup_run_id, N'OpsLab_Restore', @started_at, SYSDATETIME(), 'SUCCESS', NULL
        );
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.restore_runs
        (
            backup_run_id, target_db, started_at, ended_at, status, error_message
        )
        VALUES
        (
            @backup_run_id, N'OpsLab_Restore', @started_at, SYSDATETIME(), 'FAILED', ERROR_MESSAGE()
        );

        THROW;
    END CATCH
END;
GO

-- Create procedure to validate the restored database using row counts, aggregate checks, & DBCC CHECKDB.
CREATE OR ALTER PROC dbo.usp_validate_latest_restore
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @restore_run_id INT;

    SELECT TOP (1)
        @restore_run_id = restore_run_id
    FROM dbo.restore_runs
    WHERE status = 'SUCCESS'
      AND target_db = N'OpsLab_Restore'
    ORDER BY restore_run_id DESC;

    IF @restore_run_id IS NULL
        THROW 50002, 'No successful restore found.', 1;

    INSERT INTO dbo.validation_results
    (
        restore_run_id, check_name, source_value, restored_value, status, checked_at
    )
    SELECT
        @restore_run_id,
        check_name,
        source_value,
        restored_value,
        CASE WHEN source_value = restored_value THEN 'PASS' ELSE 'FAIL' END,
        SYSDATETIME()
    FROM
    (
        SELECT 'customers_rowcount'      AS check_name,
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.customers) AS NVARCHAR(255)) AS source_value,
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.customers) AS NVARCHAR(255)) AS restored_value
        UNION ALL
        SELECT 'products_rowcount',
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.products) AS NVARCHAR(255)),
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.products) AS NVARCHAR(255))
        UNION ALL
        SELECT 'orders_rowcount',
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.orders) AS NVARCHAR(255)),
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.orders) AS NVARCHAR(255))
        UNION ALL
        SELECT 'order_items_rowcount',
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.order_items) AS NVARCHAR(255)),
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.order_items) AS NVARCHAR(255))
        UNION ALL
        SELECT 'payments_rowcount',
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.payments) AS NVARCHAR(255)),
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.payments) AS NVARCHAR(255))
        UNION ALL
        SELECT 'audit_log_rowcount',
               CAST((SELECT COUNT(*) FROM OpsLab_Source.dbo.audit_log) AS NVARCHAR(255)),
               CAST((SELECT COUNT(*) FROM OpsLab_Restore.dbo.audit_log) AS NVARCHAR(255))
        UNION ALL
        SELECT 'orders_total_amount_sum',
               CAST((SELECT COALESCE(SUM(total_amount),0) FROM OpsLab_Source.dbo.orders) AS NVARCHAR(255)),
               CAST((SELECT COALESCE(SUM(total_amount),0) FROM OpsLab_Restore.dbo.orders) AS NVARCHAR(255))
        UNION ALL
        SELECT 'payments_amount_sum',
               CAST((SELECT COALESCE(SUM(amount),0) FROM OpsLab_Source.dbo.payments) AS NVARCHAR(255)),
               CAST((SELECT COALESCE(SUM(amount),0) FROM OpsLab_Restore.dbo.payments) AS NVARCHAR(255))
    ) x;

    BEGIN TRY
        DBCC CHECKDB (N'OpsLab_Restore') WITH NO_INFOMSGS;

        INSERT INTO dbo.validation_results
        (
            restore_run_id, check_name, source_value, restored_value, status, checked_at
        )
        VALUES
        (
            @restore_run_id, 'dbcc_checkdb', 'OK', 'OK', 'PASS', SYSDATETIME()
        );
    END TRY
    BEGIN CATCH
        INSERT INTO dbo.validation_results
        (
            restore_run_id, check_name, source_value, restored_value, status, checked_at
        )
        VALUES
        (
            @restore_run_id, 'dbcc_checkdb', NULL, ERROR_MESSAGE(), 'FAIL', SYSDATETIME()
        );

        THROW;
    END CATCH
END;
GO