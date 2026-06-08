CREATE PROCEDURE [tests].[RunTests]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '==============================================';
    PRINT '  STARTING DATABASE UNIT TESTS';
    PRINT '==============================================';

    -- Clear previous test results
    TRUNCATE TABLE [tests].[TestResults];

    DECLARE @testName NVARCHAR(256);
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @success INT = 1;

    -- Query all test stored procedures in the 'tests' schema starting with 'test_'
    DECLARE test_cursor CURSOR FOR
    SELECT [name]
    FROM sys.procedures
    WHERE schema_id = SCHEMA_ID('tests')
      AND [name] LIKE 'test_%';

    OPEN test_cursor;
    FETCH NEXT FROM test_cursor INTO @testName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = 'EXEC [tests].[' + @testName + '];';
        
        BEGIN TRANSACTION;
        BEGIN TRY
            -- Run the test procedure
            EXEC sp_executesql @sql;
            
            -- If we reach here, the test passed
            INSERT INTO [tests].[TestResults] (TestName, Status)
            VALUES (@testName, 'PASS');
            PRINT 'PASS: ' + @testName;
            
            -- Rollback changes to keep the database state completely clean
            ROLLBACK TRANSACTION;
        END TRY
        BEGIN CATCH
            -- Rollback any modified data
            ROLLBACK TRANSACTION;
            
            SET @success = 0;
            DECLARE @errMsg NVARCHAR(MAX) = ERROR_MESSAGE();
            
            INSERT INTO [tests].[TestResults] (TestName, Status, ErrorMessage)
            VALUES (@testName, 'FAIL', @errMsg);
            PRINT 'FAIL: ' + @testName + ' - Error: ' + @errMsg;
        END CATCH

        FETCH NEXT FROM test_cursor INTO @testName;
    END

    CLOSE test_cursor;
    DEALLOCATE test_cursor;

    PRINT '==============================================';
    PRINT '  DATABASE UNIT TESTS COMPLETED';
    PRINT '==============================================';

    -- Throw exception with detailed failures if any test failed
    IF @success = 0
    BEGIN
        DECLARE @FailedTestList NVARCHAR(2000) = N'';
        
        SELECT @FailedTestList = @FailedTestList + NCHAR(13) + NCHAR(10) + N' * ' + TestName + N': ' + LEFT(ErrorMessage, 150)
        FROM [tests].[TestResults]
        WHERE [Status] = 'FAIL';

        DECLARE @FinalErrMsg NVARCHAR(2048) = N'Database unit tests failed:' + @FailedTestList;
        THROW 50000, @FinalErrMsg, 1;
    END
    ELSE
    BEGIN
        PRINT 'All database tests passed successfully!';
    END
END
