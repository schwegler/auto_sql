-- Role Memberships
ALTER ROLE [AppRole] ADD MEMBER [AppUser];
GO
ALTER ROLE [AppRole] ADD MEMBER [CORP\AppDomainGroup];
GO
-- Schema Permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[dbo] TO [AppRole];
GO
GRANT EXECUTE ON SCHEMA::[dbo] TO [AppRole];
GO
-- Direct User (Non-Role-Based) Permissions
GRANT SELECT ON OBJECT::[dbo].[Customers] TO [AppUser];
GO
GRANT EXECUTE ON OBJECT::[dbo].[GetCustomerSummary] TO [AppUser];
GO

