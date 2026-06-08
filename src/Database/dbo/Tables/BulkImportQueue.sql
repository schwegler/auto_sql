CREATE TABLE [dbo].[BulkImportQueue]
(
    [QueueId] INT IDENTITY(1,1) NOT NULL,
    [BatchId] UNIQUEIDENTIFIER NOT NULL,
    [EmployeeSSN] VARCHAR(9) NOT NULL,
    [EmployerAccount] VARCHAR(10) NOT NULL,
    [Wages] DECIMAL(18, 2) NOT NULL,
    [Quarter] INT NOT NULL,
    [Year] INT NOT NULL,
    [Status] VARCHAR(20) NOT NULL CONSTRAINT [DF_BulkImportQueue_Status] DEFAULT ('Pending'), -- Pending, Processed, Rejected
    [ProcessedAt] DATETIME2 NULL,
    CONSTRAINT [PK_BulkImportQueue] PRIMARY KEY CLUSTERED ([QueueId] ASC)
);
