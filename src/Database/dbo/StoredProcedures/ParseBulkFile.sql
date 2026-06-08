CREATE PROCEDURE [dbo].[ParseBulkFile]
    @BatchId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    -- Staging table for employee records parsed under the current employer
    CREATE TABLE #StagedEmployees
    (
        EmployeeSSN VARCHAR(9) NOT NULL,
        Wages DECIMAL(18,2) NOT NULL,
        Quarter INT NOT NULL,
        Year INT NOT NULL,
        EmployerAccount VARCHAR(10) NOT NULL
    );

    -- Cursor to iterate over lines in landing table in order of insertion
    DECLARE @RecordText VARCHAR(1000);
    
    DECLARE line_cursor CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
    SELECT [RecordText]
    FROM [dbo].[BulkFileLanding]
    ORDER BY [LineId] ASC;

    -- Running parse state variables
    DECLARE @CurrentEmployerAccount VARCHAR(10) = NULL;
    DECLARE @CurrentQuarter INT = NULL;
    DECLARE @CurrentYear INT = NULL;
    DECLARE @ParsedCount INT = 0;
    DECLARE @ParsedWageSum DECIMAL(18,2) = 0.0;
    DECLARE @ErrorLogged BIT = 0;

    OPEN line_cursor;
    FETCH NEXT FROM line_cursor INTO @RecordText;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Pad record to ensure substring doesn't fail out-of-bounds
        SET @RecordText = LEFT(@RecordText + SPACE(200), 200);

        DECLARE @RecordType CHAR(1) = LEFT(@RecordText, 1);

        IF @RecordType = 'E'
        BEGIN
            -- Clear previous staging state
            TRUNCATE TABLE #StagedEmployees;
            SET @ParsedCount = 0;
            SET @ParsedWageSum = 0.0;
            SET @ErrorLogged = 0;

            -- Parse employer context
            DECLARE @QtrYearRaw CHAR(4) = SUBSTRING(@RecordText, 2, 4);
            DECLARE @MonthRaw CHAR(2) = LEFT(@QtrYearRaw, 2);
            DECLARE @YearRaw CHAR(2) = RIGHT(@QtrYearRaw, 2);

            SET @CurrentQuarter = CASE @MonthRaw
                WHEN '03' THEN 1
                WHEN '06' THEN 2
                WHEN '09' THEN 3
                WHEN '12' THEN 4
                ELSE 0
            END;
            SET @CurrentYear = 2000 + TRY_CAST(@YearRaw AS INT);
            SET @CurrentEmployerAccount = RTRIM(SUBSTRING(@RecordText, 39, 10));
        END
        ELSE IF @RecordType = 'S'
        BEGIN
            -- Parse employee detail
            DECLARE @EmployeeSSN VARCHAR(9) = SUBSTRING(@RecordText, 2, 9);
            DECLARE @WagesRaw VARCHAR(9) = SUBSTRING(@RecordText, 44, 9);
            DECLARE @EmployeeWages DECIMAL(18,2) = TRY_CAST(@WagesRaw AS DECIMAL(18,2)) / 100.0;
            DECLARE @EmpAccount VARCHAR(10) = RTRIM(SUBSTRING(@RecordText, 53, 10));

            IF @EmployeeWages IS NULL SET @EmployeeWages = 0.0;

            -- Validate context match (ensure employee record matches the employer section)
            IF @EmpAccount = @CurrentEmployerAccount
            BEGIN
                INSERT INTO #StagedEmployees (EmployeeSSN, Wages, Quarter, Year, EmployerAccount)
                VALUES (@EmployeeSSN, @EmployeeWages, @CurrentQuarter, @CurrentYear, @EmpAccount);

                SET @ParsedCount = @ParsedCount + 1;
                SET @ParsedWageSum = @ParsedWageSum + @EmployeeWages;
            END
            ELSE
            BEGIN
                -- Mismatched employer account indicator
                INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
                VALUES (@BatchId, 0, @EmployeeSSN, N'Employer account mismatch in S record: Expected ' + ISNULL(@CurrentEmployerAccount, 'NULL') + N', got ' + ISNULL(@EmpAccount, 'NULL') + N'.');
                SET @ErrorLogged = 1;
            END
        END
        ELSE IF @RecordType = 'T'
        BEGIN
            -- Parse Trailer totals
            DECLARE @TrailerCount INT = TRY_CAST(SUBSTRING(@RecordText, 2, 7) AS INT);
            DECLARE @TrailerWages DECIMAL(18,2) = TRY_CAST(SUBSTRING(@RecordText, 9, 13) AS DECIMAL(18,2)) / 100.0;
            DECLARE @TrailerExcess DECIMAL(18,2) = TRY_CAST(SUBSTRING(@RecordText, 22, 13) AS DECIMAL(18,2)) / 100.0;
            DECLARE @TrailerTaxable DECIMAL(18,2) = TRY_CAST(SUBSTRING(@RecordText, 35, 13) AS DECIMAL(18,2)) / 100.0;

            IF @TrailerWages IS NULL SET @TrailerWages = 0.0;
            IF @TrailerExcess IS NULL SET @TrailerExcess = 0.0;
            IF @TrailerTaxable IS NULL SET @TrailerTaxable = 0.0;

            -- Validation Checks
            
            -- 1. Check record counts
            IF @ParsedCount <> @TrailerCount
            BEGIN
                INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
                VALUES (@BatchId, 0, 'SYSTEM', N'Validation Mismatch (960): Parsed employee count (' + CAST(@ParsedCount AS NVARCHAR(10)) + N') does not match trailer count (' + CAST(@TrailerCount AS NVARCHAR(10)) + N') for account ' + ISNULL(@CurrentEmployerAccount, 'NULL') + N'.');
                SET @ErrorLogged = 1;
            END

            -- 2. Check total wages sum
            IF @ParsedWageSum <> @TrailerWages
            BEGIN
                INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
                VALUES (@BatchId, 0, 'SYSTEM', N'Validation Mismatch (950): Parsed wage sum (' + CAST(@ParsedWageSum AS NVARCHAR(20)) + N') does not match trailer wage sum (' + CAST(@TrailerWages AS NVARCHAR(20)) + N') for account ' + ISNULL(@CurrentEmployerAccount, 'NULL') + N'.');
                SET @ErrorLogged = 1;
            END

            -- 3. Check wage balance
            IF (@TrailerWages - @TrailerExcess <> @TrailerTaxable) OR (@TrailerWages < @TrailerExcess)
            BEGIN
                INSERT INTO [dbo].[BulkProcessErrors] (BatchId, QueueId, EmployeeSSN, ErrorMessage)
                VALUES (@BatchId, 0, 'SYSTEM', N'Validation Mismatch (955): Wage balance mismatch (Total: ' + CAST(@TrailerWages AS NVARCHAR(20)) + N', Excess: ' + CAST(@TrailerExcess AS NVARCHAR(20)) + N', Taxable: ' + CAST(@TrailerTaxable AS NVARCHAR(20)) + N') for account ' + ISNULL(@CurrentEmployerAccount, 'NULL') + N'.');
                SET @ErrorLogged = 1;
            END

            -- Save staged records from temp to final staging table BulkImportQueue
            DECLARE @TargetStatus VARCHAR(20) = CASE WHEN @ErrorLogged = 1 THEN 'Rejected' ELSE 'Pending' END;

            INSERT INTO [dbo].[BulkImportQueue] (BatchId, EmployeeSSN, EmployerAccount, Wages, Quarter, Year, Status)
            SELECT @BatchId, EmployeeSSN, EmployerAccount, Wages, Quarter, Year, @TargetStatus
            FROM #StagedEmployees;

            -- Clean up for next employer context
            TRUNCATE TABLE #StagedEmployees;
            SET @CurrentEmployerAccount = NULL;
            SET @CurrentQuarter = NULL;
            SET @CurrentYear = NULL;
            SET @ParsedCount = 0;
            SET @ParsedWageSum = 0.0;
            SET @ErrorLogged = 0;
        END

        FETCH NEXT FROM line_cursor INTO @RecordText;
    END

    CLOSE line_cursor;
    DEALLOCATE line_cursor;

    DROP TABLE #StagedEmployees;
END
