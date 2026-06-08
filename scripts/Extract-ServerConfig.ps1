<#
.SYNOPSIS
    Extracts server-level configurations (Logins with SID/Password Hash, Server Roles, and Linked Servers) from a source SQL Server.
.DESCRIPTION
    This script connects to a source SQL Server instance, queries the system catalogs, and generates an idempotent T-SQL script
    (PreDeployment-ServerConfig.sql) containing DDL statements for logins, roles, and linked servers.
    This script must be run on the target database server BEFORE deploying the DACPAC.
.PARAMETER ServerInstance
    The source SQL Server instance name (e.g., "localhost" or "mySourceServer").
.PARAMETER OutputFile
    The path to save the generated T-SQL script.
.PARAMETER SqlUser
    Optional SQL Username (if using SQL Authentication).
.PARAMETER SqlPassword
    Optional SQL Password (if using SQL Authentication).
.EXAMPLE
    .\Extract-ServerConfig.ps1 -ServerInstance "myServer" -OutputFile "src/Database/PreDeployment-ServerConfig.sql"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "src/Database/Security/PreDeployment-ServerConfig.sql",

    [Parameter(Mandatory = $false)]
    [string]$SqlUser,

    [Parameter(Mandatory = $false)]
    [string]$SqlPassword
)

# Build the connection string
$connString = "Server=$ServerInstance;Database=master;Integrated Security=True;Encrypt=True;TrustServerCertificate=True;Connection Timeout=15;"
if (-not [string]::IsNullOrEmpty($SqlUser)) {
    $connString = "Server=$ServerInstance;Database=master;User ID=$SqlUser;Password=$SqlPassword;Encrypt=True;TrustServerCertificate=True;Connection Timeout=15;"
}

# Helper to convert byte array to Hex string (0x...)
function ConvertTo-HexStr ($bytes) {
    if ($null -eq $bytes) { return "NULL" }
    $hex = [System.BitConverter]::ToString($bytes).Replace("-", "")
    return "0x" + $hex
}

Write-Host "Connecting to SQL Server instance: $ServerInstance..." -ForegroundColor Cyan

$connection = New-Object Microsoft.Data.SqlClient.SqlConnection($connString)
try {
    $connection.Open()
}
catch {
    Write-Host "Windows Auth failed. Attempting legacy System.Data.SqlClient..." -ForegroundColor Yellow
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connString)
        $connection.Open()
    }
    catch {
        Write-Error "Could not connect to SQL Server: $_"
        exit 1
    }
}

$sqlOutput = @()
$sqlOutput += "/*"
$sqlOutput += "   Generated Pre-Deployment Server Configuration Script"
$sqlOutput += "   Source Server: $ServerInstance"
$sqlOutput += "   Generated On: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$sqlOutput += "   Run this script on your target server BEFORE publishing the database DACPAC."
$sqlOutput += "*/"
$sqlOutput += ""
$sqlOutput += "PRINT 'Starting Pre-Deployment Server Configurations...';"
$sqlOutput += "GO"
$sqlOutput += ""

# 1. EXTRACT LOGINS
Write-Host "Extracting Server Logins..." -ForegroundColor Green
$sqlOutput += "-- =============================================="
$sqlOutput += "-- 1. CREATE LOGINS (SQL & Windows)"
$sqlOutput += "-- =============================================="

$loginQuery = @"
SELECT 
    name, 
    type, 
    sid, 
    LOGINPROPERTY(name, 'PasswordHash') AS password_hash, 
    default_database_name, 
    default_language_name
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G')
  AND name NOT IN ('sa', 'NT SERVICE\MSSQLSERVER', 'NT SERVICE\SQLSERVERAGENT', 'NT SERVICE\SQLWriter', 'NT AUTHORITY\SYSTEM', 'NT SERVICE\Winmgmt')
  AND name NOT LIKE '##%' 
  AND name NOT LIKE 'NT AUTHORITY\%';
"@

$cmd = $connection.CreateCommand()
$cmd.CommandText = $loginQuery
$adapter = New-Object Microsoft.Data.SqlClient.SqlDataAdapter($cmd)
if ($connection.GetType().Namespace -eq "System.Data.SqlClient") {
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
}
$loginsTable = New-Object System.Data.DataTable
$adapter.Fill($loginsTable) | Out-Null

foreach ($row in $loginsTable.Rows) {
    $name = $row.name
    $type = $row.type
    $defaultDb = $row.default_database_name
    $defaultLang = $row.default_language_name
    $sidHex = ConvertTo-HexStr $row.sid

    if ($type -eq "S") {
        # SQL Login (Need Password Hash and SID to prevent orphans)
        $passHex = ConvertTo-HexStr $row.password_hash
        $sqlOutput += "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$name')"
        $sqlOutput += "BEGIN"
        $sqlOutput += "    CREATE LOGIN [$name] WITH PASSWORD = $passHex HASHED, SID = $sidHex, DEFAULT_DATABASE = [$defaultDb], DEFAULT_LANGUAGE = [$defaultLang];"
        $sqlOutput += "    PRINT 'Created SQL Login: $name';"
        $sqlOutput += "END"
    }
    else {
        # Windows User or Group Login
        $sqlOutput += "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$name')"
        $sqlOutput += "BEGIN"
        $sqlOutput += "    CREATE LOGIN [$name] FROM WINDOWS WITH DEFAULT_DATABASE = [$defaultDb];"
        $sqlOutput += "    PRINT 'Created Windows Login: $name';"
        $sqlOutput += "END"
    }
    $sqlOutput += "GO"
}
$sqlOutput += ""

# 2. EXTRACT SERVER ROLE MEMBERSHIPS
Write-Host "Extracting Server Role Memberships..." -ForegroundColor Green
$sqlOutput += "-- =============================================="
$sqlOutput += "-- 2. SERVER ROLE MEMBERSHIPS"
$sqlOutput += "-- =============================================="

$roleQuery = @"
SELECT 
    r.name AS RoleName, 
    m.name AS MemberName
FROM sys.server_role_members rm
JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name NOT IN ('sa') 
  AND m.name NOT LIKE '##%' 
  AND m.name NOT LIKE 'NT AUTHORITY\%';
"@

$cmd.CommandText = $roleQuery
$rolesTable = New-Object System.Data.DataTable
$adapter.Fill($rolesTable) | Out-Null

foreach ($row in $rolesTable.Rows) {
    $roleName = $row.RoleName
    $memberName = $row.MemberName

    $sqlOutput += "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$memberName')"
    $sqlOutput += "   AND NOT EXISTS (SELECT 1 FROM sys.server_role_members rm "
    $sqlOutput += "                   JOIN sys.server_principals r ON rm.role_principal_id = r.principal_id "
    $sqlOutput += "                   JOIN sys.server_principals m ON rm.member_principal_id = m.principal_id "
    $sqlOutput += "                   WHERE r.name = N'$roleName' AND m.name = N'$memberName')"
    $sqlOutput += "BEGIN"
    $sqlOutput += "    ALTER SERVER ROLE [$roleName] ADD MEMBER [$memberName];"
    $sqlOutput += "    PRINT 'Added login $memberName to role $roleName';"
    $sqlOutput += "END"
    $sqlOutput += "GO"
}
$sqlOutput += ""

# 3. EXTRACT SERVER PERMISSIONS
Write-Host "Extracting Server Permissions..." -ForegroundColor Green
$sqlOutput += "-- =============================================="
$sqlOutput += "-- 3. EXPLICIT SERVER PERMISSIONS"
$sqlOutput += "-- =============================================="

$permQuery = @"
SELECT 
    p.class_desc, 
    p.permission_name, 
    p.state_desc, 
    pr.name AS GranteeName
FROM sys.server_permissions p
JOIN sys.server_principals pr ON p.grantee_principal_id = pr.principal_id
WHERE pr.name NOT IN ('sa') 
  AND pr.name NOT LIKE '##%' 
  AND pr.name NOT LIKE 'NT AUTHORITY\%';
"@

$cmd.CommandText = $permQuery
$permsTable = New-Object System.Data.DataTable
$adapter.Fill($permsTable) | Out-Null

foreach ($row in $permsTable.Rows) {
    $permName = $row.permission_name
    $stateDesc = $row.state_desc
    $grantee = $row.GranteeName

    $sqlState = "GRANT"
    if ($stateDesc -eq "DENY") { $sqlState = "DENY" }
    
    $sqlOutput += "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$grantee')"
    $sqlOutput += "BEGIN"
    if ($stateDesc -eq "GRANT_WITH_GRANT_OPTION") {
        $sqlOutput += "    GRANT $permName TO [$grantee] WITH GRANT OPTION;"
    } else {
        $sqlOutput += "    $sqlState $permName TO [$grantee];"
    }
    $sqlOutput += "    PRINT 'Applied server permission: $sqlState $permName TO $grantee';"
    $sqlOutput += "END"
    $sqlOutput += "GO"
}
$sqlOutput += ""

# 4. EXTRACT LINKED SERVERS
Write-Host "Extracting Linked Servers..." -ForegroundColor Green
$sqlOutput += "-- =============================================="
$sqlOutput += "-- 4. LINKED SERVERS"
$sqlOutput += "-- =============================================="

$linkedQuery = @"
SELECT 
    name, 
    product, 
    provider, 
    data_source, 
    location, 
    provider_string, 
    catalog
FROM sys.servers
WHERE is_linked = 1;
"@

$cmd.CommandText = $linkedQuery
$linkedTable = New-Object System.Data.DataTable
$adapter.Fill($linkedTable) | Out-Null

foreach ($row in $linkedTable.Rows) {
    $linkName = $row.name
    $srvProduct = $row.product
    $srvProvider = $row.provider
    $srvSource = $row.data_source
    $srvLoc = $row.location
    $srvProvString = $row.provider_string
    $srvCatalog = $row.catalog

    $sqlOutput += "IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = N'$linkName')"
    $sqlOutput += "BEGIN"
    $sqlOutput += "    EXEC sp_addlinkedserver "
    $sqlOutput += "        @server = N'$linkName',"
    $sqlOutput += "        @srvproduct = N'$srvProduct',"
    $sqlOutput += "        @provider = N'$srvProvider',"
    $sqlOutput += "        @datasrc = N'$srvSource',"
    $sqlOutput += "        @location = N'$srvLoc',"
    $sqlOutput += "        @provstr = N'$srvProvString',"
    $sqlOutput += "        @catalog = N'$srvCatalog';"
    $sqlOutput += "    PRINT 'Created Linked Server: $linkName';"
    $sqlOutput += "END"
    $sqlOutput += "GO"
}
$sqlOutput += ""
$sqlOutput += "PRINT 'Server-level configurations completed successfully.';"
$sqlOutput += "GO"

$connection.Close()

# Write output file
$dir = [System.IO.Path]::GetDirectoryName($OutputFile)
if (-not [System.IO.Directory]::Exists($dir)) {
    [System.IO.Directory]::CreateDirectory($dir) | Out-Null
}

$sqlOutput | Out-File -FilePath $OutputFile -Encoding utf8 -Force
Write-Host "T-SQL server script generated successfully at: $OutputFile" -ForegroundColor Yellow
