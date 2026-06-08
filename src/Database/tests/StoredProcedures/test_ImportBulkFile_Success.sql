CREATE PROCEDURE [tests].[test_ImportBulkFile_Success]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_ImportBulkFile_Success...';

    DECLARE @BatchId UNIQUEIDENTIFIER = NEWID();
    DECLARE @QueueCount INT;
    DECLARE @Status VARCHAR(20);
    DECLARE @Wages DECIMAL(18,2);
    DECLARE @Quarter INT;
    DECLARE @Year INT;
    DECLARE @SSN VARCHAR(9);
    DECLARE @Account VARCHAR(10);
    DECLARE @ErrorCount INT;
    DECLARE @ActualProcessed INT;
    DECLARE @ActualRejected INT;
    DECLARE @ProdCount INT;

    -- 1. Assemble: Populate mock file records in the landing table
    TRUNCATE TABLE [dbo].[BulkFileLanding];

    INSERT INTO [dbo].[BulkFileLanding]
        (RecordText)
    VALUES
        ('A000000000   Patrick Payroll LLC       payroll@patrickpayroll.com               '),
        ('E0925000000000OWJAMES LLC             0000000001                                '),
        ('S000000001OWEN                JAMES    09250001105800000000001                  '),
        ('T00000010000000110580000000002531300000000852670000000000100000                  '),
        ('F0000001                                                                        ');

    -- 2. Act: Execute the parser
    EXEC [dbo].[ParseBulkFile] @BatchId = @BatchId;

    -- 3. Assert (Stage 1): Verify the records are staged as 'Pending' with correct values
    SELECT @QueueCount = COUNT(*)
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId;
    IF @QueueCount <> 1
    BEGIN
    THROW 50101, 'Assertion failed: Expected exactly 1 record in BulkImportQueue.', 1;
END;



SELECT
    @Status = [Status],
    @Wages = [Wages],
    @Quarter = [Quarter],
    @Year = [Year],
    @SSN = [EmployeeSSN],
    @Account = [EmployerAccount]
FROM [dbo].[BulkImportQueue]
WHERE [BatchId] = @BatchId;

IF @Status <> 'Pending'
    BEGIN
THROW 50102, 'Assertion failed: Expected staging status to be Pending.', 1;
END;

IF @Wages <> 1105.80
    BEGIN
THROW 50103, 'Assertion failed: Expected Wages to be 1105.80.', 1;
END;

IF @Quarter <> 3 OR @Year <> 2025
    BEGIN
THROW 50104, 'Assertion failed: Expected Quarter 3 and Year 2025.', 1;
END;

IF @SSN <> '000000001' OR @Account <> '0000000001'
    BEGIN
THROW 50105, 'Assertion failed: SSN or Account mismatch in staging.', 1;
END;

-- Check that no parsing errors were logged
SELECT @ErrorCount = COUNT(*)
FROM [dbo].[BulkProcessErrors]
WHERE [BatchId] = @BatchId;
IF @ErrorCount <> 0
    BEGIN
THROW 50106, 'Assertion failed: Expected 0 error records in BulkProcessErrors.', 1;
END;

-- 4. Act: Process the staging queue using the main processor
EXEC [dbo].[ProcessBulkImport]
        @BatchId = @BatchId,
        @TotalProcessed = @ActualProcessed OUTPUT,
        @TotalRejected = @ActualRejected OUTPUT;

-- 5. Assert (Stage 2): Verify production table state
IF @ActualProcessed <> 1 OR @ActualRejected <> 0
    BEGIN
THROW 50107, 'Assertion failed: ProcessBulkImport output metrics mismatch.', 1;
END;

SELECT @ProdCount = COUNT(*)
FROM [dbo].[EmployeeWages]
WHERE [BatchId] = @BatchId;
IF @ProdCount <> 1
    BEGIN
THROW 50108, 'Assertion failed: Expected 1 record in final production EmployeeWages table.', 1;
END;
END
