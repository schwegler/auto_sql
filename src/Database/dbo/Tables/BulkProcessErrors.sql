CREATE TABLE [dbo].[BulkProcessErrors]
(
    [ErrorId] INT IDENTITY(1,1) NOT NULL,
    [BatchId] UNIQUEIDENTIFIER NOT NULL,
    [QueueId] INT NOT NULL,
    [EmployeeSSN] VARCHAR(9) NOT NULL,
    [ErrorMessage] NVARCHAR(500) NOT NULL,
    [LoggedAt] DATETIME2 NOT NULL CONSTRAINT [DF_BulkProcessErrors_LoggedAt] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_BulkProcessErrors] PRIMARY KEY CLUSTERED ([ErrorId] ASC)
);
