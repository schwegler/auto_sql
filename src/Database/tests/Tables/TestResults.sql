CREATE TABLE [tests].[TestResults]
(
    [TestId] INT IDENTITY(1,1) NOT NULL,
    [TestName] NVARCHAR(256) NOT NULL,
    [ExecutionTime] DATETIME2 NOT NULL CONSTRAINT [DF_TestResults_ExecutionTime] DEFAULT (SYSUTCDATETIME()),
    [Status] NVARCHAR(10) NOT NULL, -- 'PASS' or 'FAIL'
    [ErrorMessage] NVARCHAR(MAX) NULL,
    CONSTRAINT [PK_TestResults] PRIMARY KEY CLUSTERED ([TestId] ASC)
);
