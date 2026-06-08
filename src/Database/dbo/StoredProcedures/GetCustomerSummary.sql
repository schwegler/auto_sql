CREATE PROCEDURE [dbo].[GetCustomerSummary]
    @CustomerId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        c.[CustomerId],
        c.[FirstName],
        c.[LastName],
        c.[Email],
        COUNT(o.[OrderId]) AS [TotalOrders],
        COALESCE(SUM(o.[TotalAmount]), 0) AS [TotalSpent]
    FROM [dbo].[Customers] c
    LEFT JOIN [dbo].[Orders] o ON c.[CustomerId] = o.[CustomerId]
    WHERE c.[CustomerId] = @CustomerId
    GROUP BY c.[CustomerId], c.[FirstName], c.[LastName], c.[Email];
END
