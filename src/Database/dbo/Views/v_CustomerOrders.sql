CREATE VIEW [dbo].[v_CustomerOrders]
AS
SELECT 
    c.[CustomerId],
    c.[FirstName],
    c.[LastName],
    c.[Email],
    o.[OrderId],
    o.[OrderDate],
    o.[TotalAmount],
    o.[Status]
FROM [dbo].[Customers] c
LEFT JOIN [dbo].[Orders] o ON c.[CustomerId] = o.[CustomerId];
