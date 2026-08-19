USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[DD_Daily_upload_Process]    Script Date: 18/08/2026 16:37:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






/*
Replaces the conditional processing section in the ConsumerTransactionHoldingLoad package
*/
ALTER PROCEDURE [Processing].[DD_Daily_upload_Process]

AS 

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @Subject VARCHAR(8000)

DECLARE	@Time DATETIME,	@Msg VARCHAR(2048), @SSMS BIT = 1
EXEC master.dbo.oo_TimerMessagev2 'Start Processing.DD_Daily_upload_Process', @Time OUTPUT, @SSMS OUTPUT

-- creation of daily Brand Taxonomy File for Affinity daily load (CIP Pipeline)
DROP TABLE IF EXISTS [RIPU].[AWSFile].[BrandTaxonomyDD]
	SELECT DISTINCT
	br2.BrandID AS BrandID,
	CASE
		WHEN br2.brandid IN (6625, 1096, 2239, 1046, 2058, 2359, 2117, 6665, 1265, 6622, 6983, 6632, 3233) --OR ccd.Narrative_RBS LIKE '%Barclays%'
            THEN 'High Street Bank'
        WHEN br2.brandid IN (2056, 6624, 2328, 2055, 2233, 6654)
            THEN 'Building Society'
        WHEN br2.brandid IN (2335, 2338, 6984) --OR ccd.Narrative_RBS LIKE '%Starling%'
            THEN 'Digital Bank'
        WHEN br2.brandid IN (784, 776, 1269)
            THEN 'Supermarket Bank'
        WHEN br2.brandid IN (2349, 6643, 2143, 6716, 2158, 6650, 2326, 6636)
            THEN 'Mortgage'
        WHEN br2.brandid IN (1716, 6623, 1185)
            THEN 'Loans'
        WHEN br2.brandid IN (683, 758, 788, 1286, 1979, 2116, 2347, 6531, 6580, 6809)
            THEN 'Credit Provider'
        WHEN br2.brandid IN (2528, 1787, 1266, 2245)
            THEN 'Savings & Investments'
        ELSE br2.BrandName
    END AS BrandName,
	bsg.GroupName AS GroupName,
	bs.SectorName AS SectorName
INTO [RIPU].[AWSFile].[BrandTaxonomyDD]
FROM [Warehouse].[Relational].[ConsumerCombination_DD] ccd
	INNER JOIN [Warehouse].[Relational].[Brand] br2
	ON ccd.[BrandID] = br2.[BrandID]
	INNER JOIN Warehouse.Relational.BrandSector bs
	ON br2.SectorID = bs.SectorID
	INNER JOIN Warehouse.Relational.BrandSectorGroup bsg
	ON bs.SectorGroupID = bsg.SectorGroupID


-- creation of daily Merchant Details File for Affinity daily load (CIP Pipeline)

	DROP TABLE IF EXISTS #BrandUpdate
	CREATE TABLE #BrandUpdate
(
	[BrandID] INT
							,
	[BrandName] VARCHAR(50)
							,
	[MerchantNarrative] VARCHAR(50)
)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'High Street Bank'
		, [MerchantNarrative] = 'High Street Bank'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (6625, 1096, 2239, 1046, 2058, 2359, 2117, 6665, 1265, 6622, 6983, 6632, 3233) --OR ccd.Narrative_RBS LIKE '%Barclays%'

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Building Society'
		, [MerchantNarrative] = 'Building Society'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (2056, 6624, 2328, 2055, 2233, 6654)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Digital Bank'
		, [MerchantNarrative] = 'Digital Bank'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (2335, 2338, 6984) --OR ccd.Narrative_RBS LIKE '%Starling%'

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Supermarket Bank'
		, [MerchantNarrative] = 'Supermarket Bank'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (784, 776, 1269)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Mortgage'
		, [MerchantNarrative] = 'Mortgage'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (2349, 6643, 2143, 6716, 2158, 6650, 2326, 6636)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Loans'
		, [MerchantNarrative] = 'Loans'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (1716, 6623, 1185)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Credit Provider'
		, [MerchantNarrative] = 'Credit Provider'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (683, 758, 788, 1286, 1979, 2116, 2347, 6531, 6580, 6809)

	INSERT INTO #BrandUpdate
SELECT br.[BrandID]
		, [BrandName] = 'Savings & Investments'
		, [MerchantNarrative] = 'Savings & Investments'
FROM [WH_AllPublishers].[Trans].[Brand] br
WHERE br.[BrandID] IN (2528, 1787, 1266, 2245)
	
	DROP TABLE IF EXISTS #CCs
	SELECT DISTINCT
	[ProxyOINTupleID] = SUBSTRING(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ccd.[Narrative_RBS] + CAST(ccd.[OIN] AS VARCHAR(10))), 2), 3, 64)
		, [ProxyOIN] = (SELECT CAST(ccd.[OIN] AS VARBINARY(MAX))
	FOR XML PATH(''), BINARY BASE64)
		, ccd.[BrandID]
		, [BrandName] = COALESCE(bu.[BrandName], br.[BrandName])
		, [MerchantNarrative] = COALESCE(bu.[MerchantNarrative], ccd.[Narrative_RBS])
		, [MyRewarsCCIDDD] = ccd.[ConsumerCombinationID_DD]
		, [CCIDDD] = ccd.[ConsumerCombinationID_DD]
INTO #CCs
FROM [Warehouse].[Relational].[ConsumerCombination_DD] ccd
	INNER JOIN [Warehouse].[Relational].[Brand] br
	ON ccd.[BrandID] = br.[BrandID]
	LEFT JOIN #BrandUpdate bu
	ON ccd.[BrandID] = bu.[BrandID]

	CREATE UNIQUE CLUSTERED INDEX [UCIX_CCID] ON #CCs ([CCIDDD])

	DROP TABLE IF EXISTS [RIPU].[AWSFile].[DDMerchantDetailsFile]
	SELECT DISTINCT cc.[ProxyOINTupleID]
		, cc.[ProxyOIN]
		, cc.[BrandID]
		, cc.[BrandName]
		, cc.[MerchantNarrative]
INTO [RIPU].[AWSFile].[DDMerchantDetailsFile]
FROM #CCs cc
WHERE EXISTS (	SELECT 1
FROM [Warehouse].[Relational].[ConsumerTransaction_DD_MyRewards] ctd
	INNER JOIN [Warehouse].[Relational].[Customer] c
	ON c.[FanID] = ctd.[FanID]
WHERE cc.[CCIDDD] = ctd.[ConsumerCombinationID_DD])

	--Deleting duplicates
	DELETE FROM [RIPU].[AWSFile].[DDMerchantDetailsFile]
	WHERE proxyointupleid IN (
		SELECT proxyointupleid
	FROM [RIPU].[AWSFile].[DDMerchantDetailsFile]
	GROUP BY proxyointupleid
	HAVING COUNT(*) > 1
	)
	AND BrandID = 944;


		-- creation of daily DD Proxy Mapping File for Affinity daily load (CIP Pipeline)
-- Prep temp tables (your originals)
DROP TABLE IF EXISTS #dd_consumertrans_fanids;
SELECT DISTINCT fanid, BankAccountID
INTO #dd_consumertrans_fanids
FROM Warehouse.Relational.ConsumerTransaction_DD;

DROP TABLE IF EXISTS #customer_cinids;
SELECT
	cl.cinid
INTO #customer_cinids
FROM WH_NWG.Derived.Customer cu
	JOIN WH_NWG.Derived.CINList cl
	ON cu.SourceUID = cl.CIN
WHERE NOT EXISTS (SELECT 1
FROM [WH_NWG].[Derived].[Customer_DuplicateSourceUID] ds
WHERE cl.[CIN] = ds.[SourceUID])


DROP TABLE IF EXISTS RIPU.AWSFile.DDProxyMappingFile;

WITH
	Combined
	AS
	(
									SELECT
				cl.cinid AS ProxyUserID,
				CONVERT(VARCHAR(64), rcu.ProxyUserID, 2) AS NeonProxyUserID,
				bai.BankAccountGUID AS ProxyAccountID
			FROM #dd_consumertrans_fanids f
				JOIN WH_NWG.Derived.Customer cu ON f.fanid = cu.fanid
				JOIN WH_NWG.Derived.CINList cl ON cu.SourceUID = cl.CIN
				LEFT JOIN RIPU.Processing.Customers rcu ON rcu.fanid = cu.fanid
				JOIN WH_NWG.WHB.BankAccountIDs bai ON f.BankAccountID = bai.BankAccountID

		UNION ALL

			SELECT
				cl.cinid AS ProxyUserID,
				CONVERT(VARCHAR(64), af.ProxyUserID, 2) AS NeonProxyUserID,
				bai.BankAccountGUID AS ProxyAccountID
			FROM RIPU.Processing.CustomersAffinity af
				JOIN WH_NWG.Derived.CINList cl ON af.SourceUID = cl.CIN
				LEFT JOIN WH_NWG.Derived.Customer cu ON af.fanid = cu.fanid
				LEFT JOIN WH_NWG.Derived.Cards c ON c.CustomerGUID = cu.CustomerGUID
				LEFT JOIN WH_NWG.WHB.BankAccountIDs bai ON c.AccountGUID = bai.BankAccountGUID

		UNION ALL

			SELECT
				c.CINID AS ProxyUserID,
				CONVERT(VARCHAR(64), af.ProxyUserID, 2) AS NeonProxyUserID,
				c.BankAccountGUID AS ProxyAccountID
			FROM RIPU.Processing.CINID_BankAccountGUID_2015 c
				LEFT JOIN RIPU.Processing.Customers af ON c.CINID = af.cinid

		UNION ALL

			SELECT
				t.cinid     AS ProxyUserID,
				t.neonproxyuserid AS NeonProxyUserID,
				t.bankaccountguid AS ProxyAccountID
			FROM (VALUES
					(13587775, '1F68836844EAC4446D4DF85BBA7D5C4D95E603535DFB6F1890B9F29CF692E2FF', 'D18224F3-CFB2-49B1-BE50-BA944039E0AC'),
					(11146271, '699FAAFDEA623AB811DE26F836ADBA789A7D4DED14676FE179E84B1591A1A6A2', '09D74983-74FA-4FA9-8C80-4941A3B8865E'),
					(260132, 'ED9EE2AB6573461D66A27A025364E2329B5640A846061AEA2E6C99557EFBA95A', '3ED705D1-189D-422D-B5C4-58AEBC5B1F9F')
    ) AS t(cinid, neonproxyuserid, bankaccountguid)
	),
	MissingCINs
	AS
	(
		-- CINIDs from #customer_cinids not present in Combined
		SELECT
			c.cinid                                             AS ProxyUserID,
			CAST(NULL AS VARCHAR(64))                           AS NeonProxyUserID,
			CAST(NULL AS UNIQUEIDENTIFIER)                      AS ProxyAccountID
		FROM #customer_cinids c
			LEFT JOIN (SELECT DISTINCT ProxyUserID
			FROM Combined) k
			ON k.ProxyUserID = c.cinid
		WHERE k.ProxyUserID IS NULL
	),
	FinalSet
	AS
	(
					SELECT *
			FROM Combined
		UNION ALL
			SELECT *
			FROM MissingCINs
	)
SELECT DISTINCT
	ProxyUserID,
	NeonProxyUserID,
	ProxyAccountID
INTO RIPU.AWSFile.DDProxyMappingFile
FROM FinalSet;


	drop table if exists [RIPU].[AWSFile].[DDProxyMappingFileDailyFilecount];
	select ceiling((count(*)*1.0)/2000000) as filecount
--2000000 is the row count within the streamer split file, if that changes here needs to change
into [RIPU].[AWSFile].[DDProxyMappingFileDailyFilecount]
from [RIPU].[AWSFile].[DDProxyMappingFile]
	;
	--select count(*) from [RIPU].[AWSFile].[DDProxyMappingFile]

	--select * from [RIPU].[AWSFile].[DDProxyMappingFileDailyFilecount]


	DROP TABLE if exists RIPU.AWSFile.Consumercombination_dd;
		SELECT DISTINCT
	SUBSTRING(CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', ccd.Narrative_RBS + CAST(ccd.OIN AS VARCHAR(10))), 2), 3, 64) AS ProxyOINTupleID,
	--(SELECT CAST(ccd.OIN AS VARBINARY(MAX)) FOR XML PATH(''), BINARY BASE64) AS ProxyOIN,
	OIN,
	br2.BrandID AS BrandID,
	CASE
			WHEN br2.brandid IN (6625, 1096, 2239, 1046, 2058, 2359, 2117, 6665, 1265, 6622, 6983) --OR ccd.Narrative_RBS LIKE '%Barclays%'
				THEN 'High Street Bank'
			WHEN br2.brandid IN (2056, 6624, 2328, 2055, 2233, 6654)
				THEN 'Building Society'
			WHEN br2.brandid IN (2335, 2338, 6984) --OR ccd.Narrative_RBS LIKE '%Starling%'
				THEN 'Digital Bank'
			WHEN br2.brandid IN (784, 776, 1269)
				THEN 'Supermarket Bank'
			WHEN br2.brandid IN (2349, 6643, 2143, 6716, 2158, 6650, 2326, 6636)
				THEN 'Mortgage'
			WHEN br2.brandid IN (1716, 6623, 1185)
				THEN 'Loans'
			WHEN br2.brandid IN (683, 758, 788, 1286, 1979, 2116, 2347, 6531, 6580, 6809)
				THEN 'Credit Provider'
			WHEN br2.brandid IN (2528, 1787, 1266, 2245)
				THEN 'Savings & Investments'
			ELSE br2.BrandName
		END AS BrandName,
	CASE
			WHEN br2.brandid IN (6625, 1096, 2239, 1046, 2058, 2359, 2117, 6665, 1265, 6622, 6983) --OR ccd.Narrative_RBS LIKE '%Barclays%'
				THEN 'High Street Bank'
			WHEN br2.brandid IN (2056, 6624, 2328, 2055, 2233, 6654)
				THEN 'Building Society'
			WHEN br2.brandid IN (2335, 2338, 6984) --OR ccd.Narrative_RBS LIKE '%Starling%'
				THEN 'Digital Bank'
			WHEN br2.brandid IN (784, 776, 1269)
				THEN 'Supermarket Bank'
			WHEN br2.brandid IN (2349, 6643, 2143, 6716, 2158, 6650, 2326, 6636)
				THEN 'Mortgage'
			WHEN br2.brandid IN (1716, 6623, 1185)
				THEN 'Loans'
			WHEN br2.brandid IN (683, 758, 788, 1286, 1979, 2116, 2347, 6531, 6580, 6809)
				THEN 'Credit Provider'
			WHEN br2.brandid IN (2528, 1787, 1266, 2245)
				THEN 'Savings & Investments'
			ELSE ccd.Narrative_RBS
		END AS Narrative
into RIPU.AWSFile.Consumercombination_dd
FROM [Warehouse].[Relational].[ConsumerCombination_DD] ccd
	LEFT JOIN [Warehouse].[Relational].[Brand] br2
	ON ccd.[BrandID] = br2.[BrandID]
	;
		--deleting duplicates which are double branded
	delete from RIPU.AWSFile.Consumercombination_dd
	WHERE
		proxyointupleid IN (
		SELECT proxyointupleid
	FROM RIPU.AWSFile.Consumercombination_dd
	GROUP BY proxyointupleid
	HAVING COUNT(*) > 1
		)
	AND BrandID = 944
	;
