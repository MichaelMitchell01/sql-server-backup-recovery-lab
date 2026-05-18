/*
Purpose:
- Creates a controlled point-in-time recovery scenario.
- Takes a fresh full backup.
- Inserts a recovery marker representing a known-good point.
- Deletes a target row after the marker.
- Takes a log backup that captures the delete.

Run order:
4 of 7

Notes:
- This script intentionally introduces a recoverable data loss event.
- The marker is created after the full backup & before the delete so the later STOPAT value lands in the correct window.
- payment_id = 1 is used as the recovery target for the demo. */

USE OpsAdmin;
GO

-- Take a fresh full backup to establish the PITR starting point.
EXEC dbo.usp_take_full_backup;
GO

-- Pause so the recovery marker is clearly later than the full backup end time.
WAITFOR DELAY '00:00:03';
GO

-- Record a known-good recovery marker before introducing data loss.
INSERT INTO dbo.recovery_markers (marker_name, notes)
VALUES (N'before_bad_delete_v2', N'Known good point after full backup and before delete');
GO

-- Pause again so the delete happens after the recovery marker.
WAITFOR DELAY '00:00:05';
GO

-- Confirm the target row exists before simulating accidental deletion.
SELECT *
FROM OpsLab_Source.dbo.payments
WHERE payment_id = 1;
GO

-- Simulate accidental data loss after the recovery marker.
DELETE FROM OpsLab_Source.dbo.payments
WHERE payment_id = 1;
GO

-- Capture the delete in a transaction log backup for PITR testing.
EXEC dbo.usp_take_log_backup;
GO