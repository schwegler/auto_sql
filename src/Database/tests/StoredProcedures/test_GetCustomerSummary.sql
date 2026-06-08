CREATE PROCEDURE [tests].[test_GetCustomerSummary]
AS
BEGIN
    SET NOCOUNT ON;

    PRINT 'Running test: test_GetCustomerSummary...';

    -- 1. Assemble: Setup test data
    DECLARE @CustomerId INT = 999999; -- Safe test ID

    SET IDENTITY_INSERT [dbo].[Customers] ON;
    INSERT INTO [dbo].[Customers] (CustomerId, FirstName, LastName, Email)
    VALUES (@CustomerId, 'TestFirst', 'TestLast', 'test.user@example.com');
    SET IDENTITY_INSERT [dbo].[Customers] OFF;

    INSERT INTO [dbo].[Orders] (CustomerId, TotalAmount, Status)
    VALUES (@CustomerId, 100.00, 'Completed');
    INSERT INTO [dbo].[Orders] (CustomerId, TotalAmount, Status)
    VALUES (@CustomerId, 50.00, 'Completed');

    -- 2. Act: Execute stored procedure into a temp table
    CREATE TABLE #TestActual (
        CustomerId INT,
        FirstName NVARCHAR(50),
        LastName NVARCHAR(50),
        Email NVARCHAR(100),
        TotalOrders INT,
        TotalSpent DECIMAL(18,2)
    );

    INSERT INTO #TestActual
    EXEC [dbo].[GetCustomerSummary] @CustomerId = @CustomerId;

    -- 3. Assert: Verify expectations
    DECLARE @ActualOrders INT;
    DECLARE @ActualSpent DECIMAL(18,2);

    SELECT 
        @ActualOrders = [TotalOrders],
        @ActualSpent = [TotalSpent]
    FROM #TestActual;

    DECLARE @ExpectedOrders INT = 2;
    DECLARE @ExpectedSpent DECIMAL(18,2) = 150.00;

    IF @ActualOrders <> @ExpectedOrders
    BEGIN
        DROP TABLE #TestActual;
        THROW 50001, 'Assertion failed: Expected 2 total orders.', 1;
    END

    IF @ActualSpent <> @ExpectedSpent
    BEGIN
        DROP TABLE #TestActual;
        THROW 50002, 'Assertion failed: Expected 150.00 total spent.', 1;
    END

    -- Cleanup temp tables
    DROP TABLE #TestActual;
END
