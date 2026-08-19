USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[RIRUPipeline_StreamToS3_DD_V2]    Script Date: 18/08/2026 04:33:32 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [Processing].[RIRUPipeline_StreamToS3_DD_V2]

AS
BEGIN

	DECLARE @LoadDate DATE = GETDATE()


	DROP TABLE IF EXISTS #CustomerList
	SELECT	cu.[FanID]
		,	cu.[DeactivatedDate]
	INTO #CustomerList
	FROM [WH_NWG].[Derived].[Customer] cu

	UPDATE #CustomerList
	SET [DeactivatedDate] = DATEADD(DAY, -90, [DeactivatedDate])
	WHERE [DeactivatedDate] >= '2024-09-15'

	UPDATE #CustomerList
	SET [DeactivatedDate] = '9999-12-31'
	WHERE [DeactivatedDate] IS NULL

	CREATE CLUSTERED INDEX [CIX] ON #CustomerList ([FanID], [DeactivatedDate])


	DROP TABLE IF EXISTS #Transactions
		SELECT	ct.[FileID]
			,	ct.[RowNum]
			,	ct.[BankAccountID]
			,	ct.[FanID]
			,	ct.[ConsumerCombinationID_DD]
			,	ct.[TranDate]
			,	ct.[Amount]
		INTO #Transactions
		FROM [Warehouse].[Relational].[ConsumerTransaction_DD] ct
		WHERE EXISTS (	SELECT 1
					FROM #CustomerList cl
					WHERE ct.[FanID] = cl.[FanID]
					AND ct.[TranDate] < cl.[DeactivatedDate])
		AND NOT EXISTS (SELECT 1
					FROM [AWSFile].[CT_DD_Log] ctl
					WHERE ct.[FileID] = ctl.[FileID]
					AND ct.[RowNum] = ctl.[RowNum])
	
	CREATE CLUSTERED INDEX [CIX] ON #Transactions ([FileID], [RowNum])
	CREATE NONCLUSTERED INDEX [IX_Fan] ON #Transactions ([FanID])
	CREATE NONCLUSTERED INDEX [IX_Bank] ON #Transactions ([BankAccountID])
	CREATE NONCLUSTERED INDEX [IX_CC] ON #Transactions ([ConsumerCombinationID_DD])



	DROP TABLE IF EXISTS #Customer
	SELECT	cu.[CustomerGUID]
		,	cu.[FanID]
		,	cu.[SourceUID]
		,	cl.[CINID]
		,	cup.[DOB]
		,	[UserPostcodeArea] =	CASE
										WHEN TRIM(UPPER(cu.[PostArea])) != TRIM(UPPER(pa.[PostAreaCode])) THEN NULL
										ELSE TRIM(UPPER(pa.[PostAreaCode]))
									END
		,	cu.[DeactivatedDate]
	INTO #Customer
	FROM [WH_NWG].[Derived].[Customer] cu
	LEFT JOIN [WH_NWG].[Derived].[Customer_PII] cup
		ON cu.[CustomerGUID] = cup.[CustomerGUID]
	INNER JOIN [WH_NWG].[Derived].[CINList] cl
		ON cu.[SourceUID] = cl.[CIN]
		AND NOT EXISTS (SELECT 1
						FROM [WH_NWG].[Derived].[Customer_DuplicateSourceUID] ds
						WHERE cl.[CIN] = ds.[SourceUID])
	LEFT JOIN [Warehouse].[Relational].[PostArea] pa 
		ON TRIM(UPPER(cu.[PostArea])) = TRIM(UPPER(pa.[PostAreaCode]))
	--CROSS APPLY (	SELECT	[Age] = DATEDIFF(YEAR, cup.[DOB], TranDate) -	CASE 
	--																			WHEN MONTH(TranDate) < MONTH(cup.[DOB]) OR (MONTH(@TranDate) = MONTH(cup.[DOB]) AND DAY(@TranDate) < DAY(cup.[DOB])) THEN 1 
	--																			ELSE 0 
	--																		END) a
	WHERE EXISTS (	SELECT 1
					FROM #Transactions tr
					WHERE cu.[FanID] = tr.[FanID])


	;WITH
	DupeDelete AS (	SELECT	[CustomerGUID]
						,	[CINID] = MAX([CINID])
					FROM #Customer
					GROUP BY [CustomerGUID]
					HAVING COUNT(*) > 1)

	DELETE cu
	FROM #Customer cu
	WHERE EXISTS (	SELECT 1
					FROM DupeDelete dd
					WHERE cu.[CustomerGUID] = dd.[CustomerGUID]
					AND cu.[CINID] = dd.[CINID])

	CREATE CLUSTERED INDEX [CIX] ON #Customer ([FanID])

	DROP TABLE IF EXISTS #BankAccount
	SELECT	bai.[BankAccountID]
		,	bai.[BankAccountGUID]
	INTO #BankAccount
	FROM [WH_NWG].[WHB].[BankAccountIDs] bai
	WHERE EXISTS (	SELECT 1
					FROM #Transactions tr
					WHERE bai.[BankAccountID] = tr.[BankAccountID])

	CREATE CLUSTERED INDEX [CIX] ON #BankAccount ([BankAccountID])

	DROP TABLE IF EXISTS #CC
	SELECT	cc.[ConsumerCombinationID_DD]
		,	cc.[BrandID]
		,	cc.[OIN]
	INTO #CC
	FROM [WH_NWG].[Trans].[ConsumerCombination_DD] cc
	WHERE EXISTS (	SELECT 1
					FROM #Transactions tr
					WHERE cc.[ConsumerCombinationID_DD] = tr.[ConsumerCombinationID_DD])

	CREATE CLUSTERED INDEX [CIX] ON #CC ([ConsumerCombinationID_DD])

	TRUNCATE TABLE [AWSFile].[CT_DD_DailyLoad_S3_Historic]
	INSERT INTO [AWSFile].[CT_DD_DailyLoad_S3_Historic]
	SELECT	[PublisherID] = 1
		,	ct.[FileID]
		,	ct.[RowNum]
		,	bai.[BankAccountGUID]
		,	cu.[CINID]
		,	ct.[ConsumerCombinationID_DD]
		,	cc.[OIN]
		,	cc.[BrandID]
		,	ct.[TranDate]
		,	ct.[Amount]
		,	cu.[UserPostcodeArea]
		,	[CurrentAgeBandText] =	CASE      
										WHEN a.[Age] < 18 OR a.[Age] IS NULL THEN '99. Unknown'
										WHEN a.[Age] BETWEEN 18 AND 24 THEN '01. 18 to 24'
										WHEN a.[Age] BETWEEN 25 AND 34 THEN '02. 25 to 34'
										WHEN a.[Age] BETWEEN 35 AND 44 THEN '03. 35 to 44'
										WHEN a.[Age] BETWEEN 45 AND 54 THEN '04. 45 to 54'
										WHEN a.[Age] BETWEEN 55 AND 64 THEN '05. 55 to 64' 
										WHEN a.[Age] BETWEEN 65 AND 74 THEN '06. 65 to 74'
										WHEN a.[Age] >= 75 Then '07. 75+'
									END
		,	[UpdateType] = 'N'
		,	[UpdateDate] = NULL
		,	[LoadDate] = @LoadDate -- GETDATE()
		--,	[_LoadDate] =  @LoadDate
	FROM #Transactions ct
	INNER JOIN #Customer cu
		ON ct.[FanID] = cu.[FanID]
	INNER JOIN #BankAccount bai
		ON ct.[BankAccountID] = bai.[BankAccountID]
	INNER JOIN #CC cc
		ON ct.[ConsumerCombinationID_DD] = cc.[ConsumerCombinationID_DD]
	CROSS APPLY (	SELECT	[Age] = DATEDIFF(YEAR, cu.[DOB], TranDate) -	CASE 
																				WHEN MONTH(TranDate) < MONTH(cu.[DOB]) OR (MONTH(TranDate) = MONTH(cu.[DOB]) AND DAY(TranDate) < DAY(cu.[DOB])) THEN 1 
																				ELSE 0 
																			END) a

	EXEC [Processing].[DD_Daily_upload_Process]
	EXEC [Processing].[DD_Daily_upload_Process_v3]

	DECLARE @sql NVARCHAR(4000);
	--DECLARE @Directory NVARCHAR(4000) = 'E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-daily-dd-stream_Test_WA';
	DECLARE @Directory NVARCHAR(4000) = 'E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-daily-dd-stream_V2';
	--DECLARE @TranDate DATE;
	
	-- Replace spaces in @Directory with quoted strings
	
		SET @Directory = REPLACE(@Directory, ' ', '" "');
	
	-- Base Python script command
		--THIS NEEDS CHANGED!
		--SET @sql = N'python "E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-historic-dd-stream\run_export_dd.py"';
		--SET @sql = N'python "E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-daily-dd-stream_Test_WA\run_export_dd_reload.py"';

		SET @sql = N'python "E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-daily-dd-stream_V2\run_export_dd_reload.py"';
	-- Append TranDate to the command
		SET @sql = @sql + N' ' + CONVERT(NVARCHAR(20), @LoadDate, 120);

	-- Execute the command using xp_cmdshell

		DROP TABLE IF EXISTS #Output; CREATE TABLE #Output (line varchar(max))
		INSERT #Output EXEC xp_cmdshell @sql

		DELETE
		FROM #Output
		WHERE [line] IS NULL
		OR [line] = 'rwrd_consumer_transaction_DD done'
		OR [line] = 'rwrd_consumer_transaction_DD_load_date done'

		INSERT INTO [AWSFile].[CT_DD_Log_Error]
		SELECT	[@TranDate] = @LoadDate
			,	[line]
		FROM #Output
	
	--INSERT INTO [AWSFile].[CT_DD_Log_Testing]
	INSERT INTO [AWSFile].[CT_DD_Log]
	SELECT	[FileID]
		,	[RowNum]
		,	[ProcessedDate] = GETDATE()
	FROM [AWSFile].[CT_DD_DailyLoad_S3_Historic]


END