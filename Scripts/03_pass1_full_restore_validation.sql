/*
Purpose:
- Executes the initial backup/restore validation workflow.
- Takes a full backup of OpsLab_Source.
- Restores the latest full backup to OpsLab_Restore.
- Runs validation checks against the restored copy.

Run order:
3 of 7

Notes:
- This is the baseline recovery validation pass.
- OpsLab_Restore is used as a non-production restore target to prove the backup is usable. */

USE master;
GO

-- Take a fresh full backup of the source database.
EXEC OpsAdmin.dbo.usp_take_full_backup;
GO
-- Restore the latest successful full backup to the validation database.
EXEC OpsAdmin.dbo.usp_restore_latest_full_to_validation;
GO
-- Validate the restored copy against the source database.
EXEC OpsAdmin.dbo.usp_validate_latest_restore;
GO

-- Review logged results for backup, restore, & validation activity.
SELECT * FROM OpsAdmin.dbo.backup_runs ORDER BY backup_run_id DESC;
SELECT * FROM OpsAdmin.dbo.restore_runs ORDER BY restore_run_id DESC;
SELECT * FROM OpsAdmin.dbo.validation_results ORDER BY validation_id DESC;
GO