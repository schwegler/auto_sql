CREATE TABLE [dbo].[EmployeeWages]
(
    [WageId] INT IDENTITY(1,1) NOT NULL,
    [BatchId] UNIQUEIDENTIFIER NOT NULL,
    [EmployeeSSN] VARCHAR(9) NOT NULL,
    [EmployerAccount] VARCHAR(10) NOT NULL,
    [Wages] DECIMAL(18, 2) NOT NULL,
    [Quarter] INT NOT NULL,
    [Year] INT NOT NULL,
    [CreatedAt] DATETIME2 NOT NULL CONSTRAINT [DF_EmployeeWages_CreatedAt] DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_EmployeeWages] PRIMARY KEY CLUSTERED ([WageId] ASC)
);
