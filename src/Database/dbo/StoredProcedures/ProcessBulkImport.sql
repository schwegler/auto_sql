CREATE PROCEDURE [dbo].[ProcessBulkImport]
    @BatchId UNIQUEIDENTIFIER,
    @TotalProcessed INT OUTPUT,
    @TotalRejected INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Run validation
    EXEC [dbo].[ValidateBulkImport] @BatchId = @BatchId;

    -- 2. Migrate valid Pending records to the production EmployeeWages table
    INSERT INTO [dbo].[EmployeeWages] (BatchId, EmployeeSSN, EmployerAccount, Wages, Quarter, Year)
    SELECT 
        [BatchId],
        [EmployeeSSN],
        [EmployerAccount],
        [Wages],
        [Quarter],
        [Year]
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Pending';

    -- Get total processed in this transaction
    SET @TotalProcessed = @@ROWCOUNT;

    -- 3. Update the processed status in staging
    UPDATE [dbo].[BulkImportQueue]
    SET [Status] = 'Processed',
        [ProcessedAt] = SYSUTCDATETIME()
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Pending';

    -- 4. Count rejected records in the staging table
    SELECT @TotalRejected = COUNT(*)
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Rejected';
END
