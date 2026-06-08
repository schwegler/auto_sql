CREATE PROCEDURE [dbo].[ValidateBulkImport]
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Identify and log invalid SSNs (must be exactly 9 numeric digits)
    INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
    SELECT 
        @BatchId,
        [QueueId],
        [EmployeeSSN],
        N'Invalid SSN format: SSN must be exactly 9 numeric digits.'
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Pending'
      AND [EmployeeSSN] NOT LIKE '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]';

    -- 2. Identify and log invalid Wages (cannot be negative)
    INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
    SELECT 
        @BatchId,
        [QueueId],
        [EmployeeSSN],
        N'Invalid Wages: Wages cannot be negative.'
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Pending'
      AND [Wages] < 0.00;

    -- 3. Identify and log invalid Employer Accounts (must be exactly 10 characters)
    INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
    SELECT 
        @BatchId,
        [QueueId],
        [EmployeeSSN],
        N'Invalid Employer Account: Employer Account must be exactly 10 characters.'
    FROM [dbo].[BulkImportQueue]
    WHERE [BatchId] = @BatchId
      AND [Status] = 'Pending'
      AND LEN([EmployerAccount]) <> 10;

    -- 4. Update status of staging records that had errors to 'Rejected'
    UPDATE q
    SET q.[Status] = 'Rejected',
        q.[ProcessedAt] = SYSUTCDATETIME()
    FROM [dbo].[BulkImportQueue] q
    JOIN [dbo].[BulkProcessErrors] e ON q.[QueueId] = e.[QueueId]
    WHERE q.[BatchId] = @BatchId
      AND q.[Status] = 'Pending';
END
