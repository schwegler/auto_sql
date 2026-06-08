/*
Post-Deployment Script Template							
--------------------------------------------------------------------------------------
 This file contains SQL statements that will be appended to the build script.		
 Use SQLCMD syntax to include a file in the post-deployment script.			
 Example:      :r .\myfile.sql																
 Use SQLCMD syntax to reference a variable in the post-deployment script.		
 Example:      :setvar TableName MyTable													
               SELECT * FROM [$(TableName)]					
--------------------------------------------------------------------------------------
*/

PRINT 'Executing Post-Deployment Script...';

-- 1. SQL Agent Jobs and Schedules setup
-- Because SQL Agent is not supported on Azure SQL Database, we guard this script to run only on on-prem/local SQL Server instances
IF CHARINDEX('Azure', @@VERSION) = 0
BEGIN
    PRINT 'Configuring SQL Agent Job for local SQL Server...';

    DECLARE @jobName NVARCHAR(128) = N'PocDailyCleanupJob';
    DECLARE @jobId BINARY(16);
    DECLARE @scheduleName NVARCHAR(128) = N'PocDailyCleanupSchedule';
    DECLARE @currentDb NVARCHAR(128) = DB_NAME();

    -- Check if Job already exists and delete it to make the script idempotent
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @jobName)
    BEGIN
        PRINT 'Job already exists. Re-creating to apply updates...';
        EXEC msdb.dbo.sp_delete_job @job_name = @jobName;
    END

    -- Add the Job
    EXEC msdb.dbo.sp_add_job 
        @job_name = @jobName,
        @enabled = 1,
        @description = N'Poc Daily cleanup and reporting job.',
        @category_name = N'[Uncategorized (Local)]',
        @owner_login_name = N'sa',
        @job_id = @jobId OUTPUT;

    -- Add Job Step (running a cleanup or SP in the local database)
    EXEC msdb.dbo.sp_add_jobstep 
        @job_id = @jobId,
        @step_name = N'Run Diagnostics',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1, -- Quit with success
        @on_fail_action = 2, -- Quit with failure
        @os_run_priority = 0,
        @subsystem = N'TSQL',
        @command = N'EXEC [dbo].[GetCustomerSummary] @CustomerId = 1;',
        @database_name = @currentDb, -- Passed via variable to satisfy T-SQL parser
        @retry_attempts = 0,
        @retry_interval = 0;

    -- Add Schedule (Daily at 1:00 AM)
    EXEC msdb.dbo.sp_add_jobschedule 
        @job_id = @jobId, 
        @name = @scheduleName,
        @enabled = 1,
        @freq_type = 4, -- Daily
        @freq_interval = 1, -- Every 1 day
        @freq_subday_type = 1, 
        @freq_subday_interval = 0, 
        @freq_relative_interval = 0, 
        @freq_recurrence_factor = 0, 
        @active_start_date = 20260608, 
        @active_end_date = 99991231, 
        @active_start_time = 010000, -- 01:00:00
        @active_end_time = 235959;

    -- Attach Job to the local server
    EXEC msdb.dbo.sp_add_jobserver 
        @job_id = @jobId, 
        @server_name = N'(local)';

    PRINT 'SQL Agent Job and Schedule successfully configured.';
END
ELSE
BEGIN
    PRINT 'Running on Azure SQL. Skipping SQL Agent Job setup (not supported).';
END

-- 2. Orphaned Database Users Auto-Fixing
-- When deploying database schemas via DACPAC, the mapped database users can become orphaned
-- if their corresponding logins on the host server have different Security Identifiers (SIDs).
-- This script dynamically maps database users to server logins with the same name if they are orphaned.
IF CHARINDEX('Azure', @@VERSION) = 0
BEGIN
    PRINT 'Scanning for and repairing orphaned database users...';

    DECLARE @orphanUser NVARCHAR(128);
    DECLARE @repairSql NVARCHAR(MAX);

    DECLARE orphan_cursor CURSOR FOR
    -- Select database users whose SID does not match the server-level login's SID,
    -- but a server-level login with the exact same name exists.
    SELECT dp.name
    FROM sys.database_principals dp
    JOIN sys.server_principals sp ON dp.name = sp.name
    WHERE dp.type IN ('S', 'U') -- SQL User or Windows User
      AND dp.sid <> sp.sid;     -- Mismatched SIDs (orphaned)

    OPEN orphan_cursor;
    FETCH NEXT FROM orphan_cursor INTO @orphanUser;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @repairSql = 'ALTER USER [' + @orphanUser + '] WITH LOGIN = [' + @orphanUser + '];';
        PRINT 'Repairing orphan user: Linking user [' + @orphanUser + '] to server login [' + @orphanUser + ']';
        
        BEGIN TRY
            EXEC sp_executesql @repairSql;
        END TRY
        BEGIN CATCH
            PRINT 'Failed to repair orphan user [' + @orphanUser + ']: ' + ERROR_MESSAGE();
        END CATCH

        FETCH NEXT FROM orphan_cursor INTO @orphanUser;
    END

    CLOSE orphan_cursor;
    DEALLOCATE orphan_cursor;
END
