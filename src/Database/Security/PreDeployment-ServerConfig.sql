/*
   Pre-Deployment Server Configuration Script (Placeholder)
   This script contains server-level configurations (Logins, Server Roles, Linked Servers).
   It is automatically executed by the local/on-prem CI/CD pipeline BEFORE the DACPAC schema deployment.
   Use the Extract-ServerConfig.ps1 utility in the scripts/ folder to update this file automatically.
*/

PRINT 'Executing pre-deployment server-level configurations...';
GO

-- Example: Add custom login if not exists (preserves SID and Hashed password in real exports)
-- IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'AppUserLogin')
-- BEGIN
--     CREATE LOGIN [AppUserLogin] WITH PASSWORD = 'MySecurePassword123!', DEFAULT_DATABASE = [master];
--     PRINT 'Created Login: AppUserLogin';
-- END
-- GO

PRINT 'Pre-deployment server-level configurations completed successfully.';
GO
