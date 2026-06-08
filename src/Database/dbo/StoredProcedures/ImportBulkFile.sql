CREATE PROCEDURE [dbo].[ImportBulkFile]
    @FilePath NVARCHAR(512)
AS
BEGIN
    SET NOCOUNT ON;

    -- Clear any previous runs
    TRUNCATE TABLE [dbo].[BulkFileLanding];

    DECLARE @Sql NVARCHAR(MAX);
    -- We use FIELDTERMINATOR = '\0' to load the entire line (up to 1000 characters) as a single column.
    -- TABLOCK is used to speed up insertion and minimize lock contention.
    SET @Sql = N'BULK INSERT [dbo].[BulkFileLanding] FROM ''' + REPLACE(@FilePath, '''', '''''') + N''' WITH (ROWTERMINATOR = ''\n'', FIELDTERMINATOR = ''\0'', TABLOCK);';
    
    EXEC sp_executesql @Sql;
END
