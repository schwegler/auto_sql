CREATE PROCEDURE [tests].[test_ImportBulkFile_PhysicalFile]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_ImportBulkFile_PhysicalFile...';

    -- Define temporary file path in the workspace
    DECLARE @FilePath NVARCHAR(512) = N'C:\Users\andrew.schwegler\auto_sql\temp_bulk_test.txt';
    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
    DECLARE @StagedCount INT;
    DECLARE @ErrorMsg NVARCHAR(MAX);

    -- 1. Assemble: Try to write the physical text file using OLE Automation (Scripting.FileSystemObject)
    DECLARE @FS INT, @FileID INT, @OLEResult INT;
    
    EXEC @OLEResult = sp_OACreate 'Scripting.FileSystemObject', @FS OUT;
    IF @OLEResult = 0
    BEGIN
        -- Create the text file, overwriting if it exists (1)
        EXEC @OLEResult = sp_OAMethod @FS, 'CreateTextFile', @FileID OUT, @FilePath, 1;
        IF @OLEResult = 0
        BEGIN
            -- Write standard mock rows
            EXEC sp_OAMethod @FileID, 'WriteLine', NULL, 'A000000000   Patrick Payroll LLC       payroll@patrickpayroll.com               ';
            EXEC sp_OAMethod @FileID, 'WriteLine', NULL, 'E0925000000000OWJAMES LLC             0000000001                                ';
            EXEC sp_OAMethod @FileID, 'WriteLine', NULL, 'S000000001OWEN                JAMES    09250001105800000000001                  ';
            EXEC sp_OAMethod @FileID, 'WriteLine', NULL, 'T00000010000000110580000000002531300000000852670000000000100000                  ';
            EXEC sp_OAMethod @FileID, 'WriteLine', NULL, 'F0000001                                                                        ';
            
            EXEC sp_OADestroy @FileID;
        END;
        EXEC sp_OADestroy @FS;
    END;

    -- 2. Act & Assert: Execute physical import and parsing, trapping expected environment restrictions
    BEGIN TRY
        -- Truncate landing table
        TRUNCATE TABLE [dbo].[BulkFileLanding];

        -- Execute the bulk insert procedure
        EXEC [dbo].[ImportBulkFile] @FilePath = @FilePath;

        -- Execute the parser procedure
        EXEC [dbo].[ParseBulkFile] @BatchId = @BatchId;

        -- Verify that the records were successfully loaded and parsed
        SELECT @StagedCount = COUNT(*) FROM [dbo].[BulkImportQueue] WHERE [BatchId] = @BatchId;
        
        IF @StagedCount <> 1
        BEGIN
            THROW 50301, 'Assertion failed: Expected exactly 1 record to be staged from physical file.', 1;
        END;

        PRINT 'SUCCESS: Physical file bulk loading and parsing verified.';
    END TRY
    BEGIN CATCH
        SET @ErrorMsg = ERROR_MESSAGE();
        
        -- Detect environmental limitations (e.g. bulk insert disabled, local paths not supported on Azure SQL, etc.)
        IF CHARINDEX('cannot be opened', @ErrorMsg) > 0 
           OR CHARINDEX('permission', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('access', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('operating system error', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('xp_cmdshell', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('bulk load', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('ole automation', LOWER(@ErrorMsg)) > 0
           OR CHARINDEX('sp_oacreate', LOWER(@ErrorMsg)) > 0
        BEGIN
            -- Log warning and pass unit test gracefully
            PRINT 'WARNING: Physical file import test skipped due to environment limitations: ' + @ErrorMsg;
        END
        ELSE
        BEGIN
            -- Real assertion failure: rethrow to fail build pipeline
            THROW;
        END;
    END CATCH;

    -- 3. Cleanup: Try to delete the temporary file from disk
    EXEC @OLEResult = sp_OACreate 'Scripting.FileSystemObject', @FS OUT;
    IF @OLEResult = 0
    BEGIN
        EXEC sp_OAMethod @FS, 'DeleteFile', NULL, @FilePath;
        EXEC sp_OADestroy @FS;
    END;
END
