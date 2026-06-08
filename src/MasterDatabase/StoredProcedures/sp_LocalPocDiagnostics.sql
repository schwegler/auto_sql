CREATE PROCEDURE [dbo].[sp_LocalPocDiagnostics]
AS
BEGIN
    SET NOCOUNT ON;

    -- Diagnostic query to list databases and their status on the host server
    SELECT 
        [name] AS [DatabaseName],
        [database_id] AS [DatabaseId],
        [create_date] AS [CreationDate],
        [state_desc] AS [Status],
        [recovery_model_desc] AS [RecoveryModel]
    FROM sys.databases;
END
