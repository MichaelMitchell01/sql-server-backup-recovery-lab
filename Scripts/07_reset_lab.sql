/*
Purpose:
- Resets the restore targets used during testing without rebuilding the full lab.
- Safely clears OpsLab_PITR even if it is stuck in RESTORING state.
- Drops OpsLab_Restore so validation tests can be rerun cleanly.

Run order:
Utility script

Notes:
- Does not drop OpsLab_Source or OpsAdmin.
- Useful between repeated PITR & restore-validation test cycles. */

USE master;
GO

-- Recover & drop the PITR database, even if it is stuck in RESTORING state.
IF DB_ID(N'OpsLab_PITR') IS NOT NULL
BEGIN
    BEGIN TRY
        RESTORE DATABASE OpsLab_PITR WITH RECOVERY;
    END TRY
    BEGIN CATCH
        PRINT ERROR_MESSAGE();
    END CATCH;

    DROP DATABASE OpsLab_PITR;
END
GO

-- Drop the validation restore database so it can be recreated cleanly on the next run.
IF DB_ID(N'OpsLab_Restore') IS NOT NULL
BEGIN
    ALTER DATABASE OpsLab_Restore SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE OpsLab_Restore;
END
GO