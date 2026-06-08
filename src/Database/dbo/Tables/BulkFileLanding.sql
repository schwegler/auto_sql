CREATE TABLE [dbo].[BulkFileLanding]
(
    [LineId] INT IDENTITY(1,1) NOT NULL,
    [RecordText] VARCHAR(1000) NOT NULL,
    CONSTRAINT [PK_BulkFileLanding] PRIMARY KEY CLUSTERED ([LineId] ASC)
);
