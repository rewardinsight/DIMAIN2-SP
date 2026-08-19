USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[Customer_Build_Affinity]    Script Date: 18/08/2026 16:35:21 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




/******************************************************************************
-- Author:		Hayden Reid
-- Create date: 01/09/2020
-- Description:	Empties, inserts and recreates index on the Customer table
				from SLC fan to be used for transaction pulls

------------------------------------------------------------------------------
Modification History

[Date] [User]
	- [Description]

******************************************************************************/
ALTER PROCEDURE [Processing].[Customer_Build_Affinity]
AS 
BEGIN

	DECLARE @RowCount INT -- Logging row count;

	----------------------------------------------------------------------
	-- Clear Down
	----------------------------------------------------------------------
	--TRUNCATE TABLE [Processing].[Customers];
	--ALTER INDEX [cx_FanID] ON [Processing].[Customers] DISABLE
	--ALTER INDEX [ix_ClubID_CompositeID] ON [Processing].[Customers] DISABLE
	--ALTER INDEX [ix_rw_CINID] ON [Processing].[Customers] DISABLE

	----------------------------------------------------------------------
	-- Insert
	----------------------------------------------------------------------
	
	DROP TABLE IF EXISTS #Customers
	SELECT	TOP 0 
			*
	INTO #Customers
	FROM [Processing].[CustomersAffinity]

	INSERT INTO #Customers ([FanID]
						,	[ProxyUserID]
						,	[CompositeID]
						,	[CINID]
						,	[ClubID]
						,	[PostcodeDistrict]
						,	[SourceUID]
						,	[rw]
						,	[PostalArea]
						,	[isNew]
						,	[Chksum])
	-- MyRewards FI
	SELECT	[FanID]
		,	[ProxyUserID]
		,	[CompositeID]
		,	[CINID]
		,	[ClubID]
		,	[PostcodeDistrict]
		,	[SourceUID]
		,	[rw]
		,	[PostalArea]
		,	[isNew] = 0
		,	[ChkSum]
	FROM (	SELECT *
			FROM (	SELECT	cu.[FanID]
						,	cu.[CompositeID]
						,	cl.[CINID] 
						,	cu.[ClubID]
						,	cu.[PostcodeDistrict]
						,	cu.[SourceUID]
						,	[rw] = ROW_NUMBER() OVER (PARTITION BY cu.[SourceUID] ORDER BY cu.[ClubID])	-- when a customer has multiple cards, use the Natwest card
						,	[PostalArea] = cu.[PostArea]
					FROM [WH_NWG].[Derived].[Customer] cu
					INNER JOIN [WH_NWG].[Derived].[CINList] cl
						on cu.[SourceUID] = cl.[CIN]
					WHERE cu.[ClubID] IN (132, 138)
					AND EXISTS (SELECT 1
								FROM [WH_NWG].[WHB].[Inbound_Customers] ic
								WHERE cu.[CustomerGUID] = ic.[CustomerGUID]
								AND ic.[AgreedTermssAndCons] = 1)) x
			WHERE x.[rw] = 1

			UNION ALL
			-- MyRewards nFI
			SELECT	[FanID] = f.[ID]
				,	f.[CompositeID]
				,	[CINID] = NULL
				,	f.[ClubID]
				,	[PostcodeDistrict] = NULL 
				,	f.[SourceUID]
				,	[rw] = 1
				,	[PostalArea] = NULL
			FROM [SLC_REPL].[dbo].[Fan] f 
			WHERE f.[ClubID] in (144, 145, 147)) x
	CROSS APPLY (	SELECT [ProxyUserID] = HASHBYTES('SHA2_256', CONCAT([FanID] + 2384, ',', [SourceUID]))) y -- hashed according to specification
	CROSS APPLY (	SELECT [ChkSum] = CHECKSUM(	[ProxyUserID]
											,	[CompositeID]
											,	[CINID]
											,	[ClubID]
											,	[PostcodeDistrict]
											,	[SourceUID]
											,	[rw]
											,	[PostalArea]
											,	CAST(0 AS BIT))) z

	SELECT @RowCount = @@RowCount

	CREATE CLUSTERED INDEX [CIX] ON #Customers ([CINID])
	--CREATE UNIQUE NONCLUSTERED INDEX UNIX ON #Customers (CINID, Chksum) WHERE CINID IS NOT NULL

	-- Update Existing
	UPDATE c
	SET [PostcodeDistrict] = cx.[PostcodeDistrict]
	,	[PostalArea] = cx.[PostalArea]
	,	[Chksum] = cx.[Chksum]
	FROM [Processing].[CustomersAffinity] c
	INNER JOIN #Customers cx
		ON c.[FanID] = cx.[FanID]
		AND c.[Chksum] != cx.[Chksum]
		
	-- Insert New
	INSERT INTO [Processing].[CustomersAffinity] (	[FanID]
										,	[ProxyUserID]
										,	[CompositeID]
										,	[CINID]
										,	[ClubID]
										,	[PostcodeDistrict]
										,	[SourceUID]
										,	[rw]
										,	[PostalArea]
										,	[Chksum]
										,	[isNew])
	SELECT	[FanID]
		,	[ProxyUserID]
		,	[CompositeID]
		,	[CINID]
		,	[ClubID]
		,	[PostcodeDistrict]
		,	[SourceUID]
		,	[rw]
		,	[PostalArea]
		,	[Chksum]
		,	[isNew] = 1
	FROM #Customers c
	WHERE NOT EXISTS (	SELECT 1
						FROM [Processing].[CustomersAffinity] cx
						WHERE c.[FanID] = cx.[FanID])
	AND NOT EXISTS (	SELECT 1
						FROM [Processing].[CustomersAffinity] cx
						WHERE c.[CINID] = cx.[CINID])

	----------------------------------------------------------------------
	-- Create Index
	----------------------------------------------------------------------
	--ALTER INDEX [cx_FanID] ON [Processing].[Customers] REBUILD PARTITION = ALL WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80, DATA_COMPRESSION = PAGE)
	--ALTER INDEX [ix_ClubID_CompositeID] ON [Processing].[Customers] REBUILD PARTITION = ALL WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80, DATA_COMPRESSION = PAGE)
	--ALTER INDEX [ix_rw_CINID] ON [Processing].[Customers] REBUILD PARTITION = ALL WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80, DATA_COMPRESSION = PAGE)


	RETURN @RowCount


END
