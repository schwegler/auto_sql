CREATE PROCEDURE [tests].[test_ProcessBulkImport_PartialFailure]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_ProcessBulkImport_PartialFailure...';

    -- 1. Assemble: Setup a mixed batch (2 valid, 2 invalid) in the staging queue
    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO [dbo].[BulkImportQueue] (BatchId, EmployeeSSN, EmployerAccount, Wages, Quarter, Year, Status)
    VALUES 
        (@BatchId, '123456789', 'ACCT123456', 1000.00, 2, 2026, 'Pending'),  -- Valid
        (@BatchId, '987654321', 'ACCT654321', 1500.50, 2, 2026, 'Pending'),  -- Valid
        (@BatchId, '12345',     'ACCT111222', 2000.00, 2, 2026, 'Pending'),  -- Invalid: Short SSN
        (@BatchId, '111222333', 'ACCT333444', -50.00,  2, 2026, 'Pending');  -- Invalid: Negative Wages

    -- 2. Act: Call the processing stored procedure
    DECLARE @ActualProcessed INT;
    DECLARE @ActualRejected INT;

    EXEC [dbo].[ProcessBulkImport] 
        @BatchId = @BatchId, 
        @TotalProcessed = @ActualProcessed OUTPUT, 
        @TotalRejected = @ActualRejected OUTPUT;

    -- 3. Assert: Verify metrics and database states
    DECLARE @ExpectedProcessed INT = 2;
    DECLARE @ExpectedRejected INT = 2;

    -- Check output parameters
    IF @ActualProcessed <> @ExpectedProcessed
    BEGIN
        THROW 50008, 'Assertion failed: Expected 2 processed records in output parameter.', 1;
    END

    IF @ActualRejected <> @ExpectedRejected
    BEGIN
        THROW 50009, 'Assertion failed: Expected 2 rejected records in output parameter.', 1;
    END

    -- Check production table inserts (only the 2 valid rows should migrate)
    DECLARE @ProductionCount INT;
    SELECT @ProductionCount = COUNT(*) FROM [dbo].[EmployeeWages] WHERE [BatchId] = @BatchId;
    IF @ProductionCount <> @ExpectedProcessed
    BEGIN
        THROW 50010, 'Assertion failed: Expected 2 records in EmployeeWages production table.', 1;
    END

    -- Check error logging (the 2 invalid rows should write errors)
    DECLARE @ErrorCount INT;
    SELECT @ErrorCount = COUNT(*) FROM [dbo].[BulkProcessErrors] WHERE [BatchId] = @BatchId;
    IF @ErrorCount <> 2
    BEGIN
        THROW 50011, 'Assertion failed: Expected 2 error records in BulkProcessErrors table.', 1;
    END

    -- Check staging status transitions (2 Processed, 2 Rejected, 0 Pending)
    DECLARE @StagingProcessedCount INT;
    SELECT @StagingProcessedCount = COUNT(*) FROM [dbo].[BulkImportQueue] WHERE [BatchId] = @BatchId AND [Status] = 'Processed';
    IF @StagingProcessedCount <> 2
    BEGIN
        THROW 50012, 'Assertion failed: Expected 2 staging records to be marked as Processed.', 1;
    END

    DECLARE @StagingRejectedCount INT;
    SELECT @StagingRejectedCount = COUNT(*) FROM [dbo].[BulkImportQueue] WHERE [BatchId] = @BatchId AND [Status] = 'Rejected';
    IF @StagingRejectedCount <> 2
    BEGIN
        THROW 50013, 'Assertion failed: Expected 2 staging records to be marked as Rejected.', 1;
    END
END
