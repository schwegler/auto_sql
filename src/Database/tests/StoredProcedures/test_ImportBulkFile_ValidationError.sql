CREATE PROCEDURE [tests].[test_ImportBulkFile_ValidationError]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_ImportBulkFile_ValidationError...';

    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
    DECLARE @RejectedCount INT;
    DECLARE @PendingCount INT;
    DECLARE @LoggedErrors INT;
    DECLARE @ActualProcessed INT;
    DECLARE @ActualRejected INT;
    DECLARE @ProdCount INT;

    -- 1. Assemble: Setup records containing multiple distinct validation errors
    TRUNCATE TABLE [dbo].[BulkFileLanding];

    INSERT INTO [dbo].[BulkFileLanding]
        (RecordText)
    VALUES
        -- Account 1: Count mismatch (2 employee detail records, but trailer reports 1)
        -- Wages match (500 + 1000 = 1500), balance is correct (1500 - 0 = 1500)
        ('E0925000000000OWJAMES LLC             0000000001                                '),
        ('S000000001OWEN                JAMES    09250000500000000000001                  '),
        ('S000000002WINKLES             PATRICIA 09250001000000000000001                  '),
        ('T000000100000001500000000000000000000000015000000000000000000                   '),

        -- Account 2: Wage sum mismatch (parsed sum is 1000.00, but trailer reports 1200.00)
        -- Count matches (1), balance is correct (1200 - 0 = 1200)
        ('E0925000000000Alabama Property Managem0000000002                                '),
        ('S000000003WINKLES             ISAAC    09250001000000000000002                  '),
        ('T000000100000001200000000000000000000000012000000000000000000                   '),

        -- Account 3: Balance mismatch (Wages 1000.00, Excess 100.00, Taxable 800.00 -> 1000 - 100 = 900 <> 800)
        -- Count matches (1), wages match (1000)
        ('E0925000000000Ivaldi Engineering PLLC 0000000003                                '),
        ('S000000004TORRES              JOHNATHAN09250001000000000000003                  '),
        ('T000000100000001000000000000010000000000008000000000000000000                   ');

    -- 2. Act: Execute the parser
    EXEC [dbo].[ParseBulkFile] @BatchId = @BatchId;

    -- 3. Assert: Verify staging table states and error logs

    -- All staged records (4 in total) must be marked as 'Rejected'
    SELECT @RejectedCount = COUNT(*)
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId AND [Status] = 'Rejected';
    IF @RejectedCount <> 4
    BEGIN
        THROW 50201, 'Assertion failed: Expected all 4 records to be staged as Rejected.', 1;
    END;

    SELECT @PendingCount = COUNT(*)
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId AND [Status] = 'Pending';
    IF @PendingCount <> 0
    BEGIN
        THROW 50202, 'Assertion failed: Expected 0 records to be staged as Pending.', 1;
    END;

    -- Verify that 3 distinct validation error logs were recorded
    SELECT @LoggedErrors = COUNT(*)
    FROM [dbo].[BulkProcessErrors]
    WHERE [BatchId] = @BatchId;
    IF @LoggedErrors <> 3
    BEGIN
        THROW 50203, 'Assertion failed: Expected exactly 3 errors to be logged in BulkProcessErrors.', 1;
    END;

    -- Verify error messages correspond to expected validations
    IF NOT EXISTS (SELECT 1
        FROM [dbo].[BulkProcessErrors]
        WHERE [BatchId] = @BatchId AND [ErrorMessage] LIKE '%Validation Mismatch (960)%')
    BEGIN
        THROW 50204, 'Assertion failed: Expected record count mismatch error (960) to be logged.', 1;
    END;

    IF NOT EXISTS (SELECT 1
        FROM [dbo].[BulkProcessErrors]
        WHERE [BatchId] = @BatchId AND [ErrorMessage] LIKE '%Validation Mismatch (950)%')
    BEGIN
        THROW 50205, 'Assertion failed: Expected wage sum mismatch error (950) to be logged.', 1;
    END;

    IF NOT EXISTS (SELECT 1
        FROM [dbo].[BulkProcessErrors]
        WHERE [BatchId] = @BatchId AND [ErrorMessage] LIKE '%Validation Mismatch (955)%')
    BEGIN
        THROW 50206, 'Assertion failed: Expected wage balance mismatch error (955) to be logged.', 1;
    END;

    -- 4. Act: Call the main processing stored procedure to verify rejected records do not migrate
    EXEC [dbo].[ProcessBulkImport]
        @BatchId = @BatchId,
        @TotalProcessed = @ActualProcessed OUTPUT,
        @TotalRejected = @ActualRejected OUTPUT;

    -- 5. Assert: Verify no records were processed and all 4 remain rejected
    -- ProcessBulkImport only processes 'Pending' records; 'Rejected' ones are ignored by design.
    -- So @ActualProcessed should be 0, and @ActualRejected should be 4.
    IF @ActualProcessed <> 0
    BEGIN
        THROW 50207, 'Assertion failed: Staged Rejected records must not be migrated to production.', 1;
    END;

    IF @ActualRejected <> 4
    BEGIN
        THROW 50209, 'Assertion failed: Expected 4 rejected records in output parameter.', 1;
    END;

    SELECT @ProdCount = COUNT(*)
    FROM [dbo].[EmployeeWages]
    WHERE [BatchId] = @BatchId;
    IF @ProdCount <> 0
    BEGIN
        THROW 50208, 'Assertion failed: Expected 0 records in production EmployeeWages table.', 1;
    END;
END
