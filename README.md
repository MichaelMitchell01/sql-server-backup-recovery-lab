# SQL Server Backup, Restore, and Point-in-Time Recovery Lab
![SQL Server CI/CD](https://github.com/YOUR_USERNAME/YOUR_REPOSITORY/actions/workflows/sqlserver-ci-cd.yml/badge.svg)

## Overview

This project is a hands-on SQL Server recovery lab built in T-SQL & SQL Server Management Studio. It simulates a production-style backup & recovery workflow using a source database, a validation restore target, a point-in-time recovery target, & an admin database for logging.

The lab covers:

- Full backups
- Transaction log backups
- Validation restores
- Restore verification checks
- Point-in-time recovery using `STOPAT`
- Operational logging through admin tables and stored procedures

This project was built to demonstrate practical SQL Server recovery knowledge rather than just schema design or classroom CRUD work.

---

## What This Project Does

The lab uses four databases:

- **OpsLab_Source**: Primary source database
- **OpsLab_Restore**: Validation restore target
- **OpsLab_PITR**: Point-in-time recovery target
- **OpsAdmin**: Admin database for logging and stored procedures

It proves that backups are not just created, but also:

- Restored to a separate target
- Validated with row-count and aggregate checks
- Checked with `DBCC CHECKDB`
- Used in a point-in-time recovery scenario after simulated data loss

---

## Key Features

- Executes **full backups** & **log backups**
- Restores full backups to a separate validation database
- Validates restored data with:
  - 6 table row-count checks
  - 2 aggregate checks
  - `DBCC CHECKDB`
- Simulates accidental data loss
- Restores a separate recovery database to a known-good point using:
  - `RESTORE ... WITH MOVE`
  - `NORECOVERY`
  - `RECOVERY`
  - `STOPAT`
- Logs backup, restore, validation, & recovery-marker activity in admin tables

---

## Project Structure

```text
C:\SQLLab\
├── Backups\
│   ├── Full\
│   └── Log\
├── Data\
├── Restore\
└── Scripts\
    ├── 01_setup_databases.sql
    ├── 02_create_admin_objects.sql
    ├── 03_pass1_full_restore_validation.sql
    ├── 04_prepare_pitr_test.sql
    ├── 05_execute_pitr_restore.sql
    ├── 06_final_verification.sql
    └── 07_reset_lab.sql
