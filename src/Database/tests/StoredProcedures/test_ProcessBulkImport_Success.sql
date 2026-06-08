CREATE PROCEDURE [tests].[test_ProcessBulkImport_Success]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_ProcessBulkImport_Success...';

    -- 1. Assemble: Setup a clean batch in the staging queue
    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO [dbo].[BulkImportQueue] (BatchId, EmployeeSSN, EmployerAccount, Wages, Quarter, Year, Status)
    VALUES 
        (@BatchId, '123456789', 'ACCT123456', 1000.00, 2, 2026, 'Pending'),
        (@BatchId, '987654321', 'ACCT654321', 1500.50, 2, 2026, 'Pending'),
        (@BatchId, '111222333', 'ACCT111222', 2000.00, 2, 2026, 'Pending');

    -- 2. Act: Call the processing stored procedure
    DECLARE @ActualProcessed INT;
    DECLARE @ActualRejected INT;

    EXEC [dbo].[ProcessBulkImport] 
        @BatchId = @BatchId, 
        @TotalProcessed = @ActualProcessed OUTPUT, 
        @TotalRejected = @ActualRejected OUTPUT;

    -- 3. Assert: Verify metrics and database states
    DECLARE @ExpectedProcessed INT = 3;
    DECLARE @ExpectedRejected INT = 0;

    -- Check output parameters
    IF @ActualProcessed <> @ExpectedProcessed
    BEGIN
        THROW 50003, 'Assertion failed: Expected 3 processed records in output parameter.', 1;
    END

    IF @ActualRejected <> @ExpectedRejected
    BEGIN
        THROW 50004, 'Assertion failed: Expected 0 rejected records in output parameter.', 1;
    END

    -- Check production table inserts
    DECLARE @ProductionCount INT;
    SELECT @ProductionCount = COUNT(*) FROM [dbo].[EmployeeWages] WHERE [BatchId] = @BatchId;
    IF @ProductionCount <> @ExpectedProcessed
    BEGIN
        THROW 50005, 'Assertion failed: Expected 3 records in EmployeeWages production table.', 1;
    END

    -- Check error logging
    DECLARE @ErrorCount INT;
    SELECT @ErrorCount = COUNT(*) FROM [dbo].[BulkProcessErrors] WHERE [BatchId] = @BatchId;
    IF @ErrorCount <> 0
    BEGIN
        THROW 50006, 'Assertion failed: Expected 0 error records in BulkProcessErrors table.', 1;
    END

    -- Check staging status transitions
    DECLARE @PendingCount INT;
    SELECT @PendingCount = COUNT(*) FROM [dbo].[BulkImportQueue] WHERE [BatchId] = @BatchId AND [Status] = 'Pending';
    IF @PendingCount <> 0
    BEGIN
        THROW 50007, 'Assertion failed: Expected 0 remaining Pending staging records.', 1;
    END
END
