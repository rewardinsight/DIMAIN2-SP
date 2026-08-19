USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[Daily_upload_Process]    Script Date: 18/08/2026 16:36:18 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
Replaces the conditional processing section in the ConsumerTransactionHoldingLoad package
*/
ALTER PROCEDURE [Processing].[Daily_upload_Process]

AS 

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @Subject VARCHAR(8000)

DECLARE	@Time DATETIME,	@Msg VARCHAR(2048), @SSMS BIT = 1
--EXEC master.dbo.oo_TimerMessagev2 'Start Processing.MIDI_ConditionalPart_RIPU_test_day 2', @Time OUTPUT, @SSMS OUTPUT


-- Set MainTableLoadOrMIDI Variable (this is used elsewhere, not here)
DECLARE @DayName VARCHAR(10) = UPPER(DATENAME(DW, GETDATE()));
SELECT @DayName = CASE WHEN @DayName IN ('SATURDAY','SUNDAY') THEN @DayName ELSE 'WEEKDAY' END




-- execute experian table AND lookup process
exec RIPU.Experian.sp_ingest_Microcell_Addresses;
exec RIPU.Experian.sp_ingest_Microcell_MosaicLookup;
exec RIPU.Experian.sp_Microcell_CinidToAddressMatcher;


--Find the last load date 
declare @LastLoadDate as date 
SELECT @LastLoadDate = max(LoadDate)
FROM Processing.Affinity_LastLoadDate
where loadDate < cast(getdate() as date)

-- truncate table for stream to S3 so it can be refreshed with new daily data
DROP TABLE IF EXISTS RIPU.[AWSFile].[CT_DailyLoad_S3]
--add in timestamp

--drop AND recreate table of customers that can be flagged as inprogram AND reused as S3 customer table

DROP TABLE IF EXISTS #Customer;
SELECT [CIN] = C.[SourceUID]
	, C.[Gender]
	, whb.[DOB]
	, C.[PostCode]
	, C.[PostalSector]
	, c.[PostCodeDistrict]
	, c.[PostArea]
	, [AgeCurrentBandNumber] = CASE  
							WHEN c.[AgeCurrent] < 18 OR c.[AgeCurrent] IS NULL THEN 0
							WHEN c.[AgeCurrent] BETWEEN 18 AND 24 THEN 1
							WHEN c.[AgeCurrent] BETWEEN 25 AND 29 THEN 2
							WHEN c.[AgeCurrent] BETWEEN 30 AND 39 THEN 3
							WHEN c.[AgeCurrent] BETWEEN 40 AND 49 THEN 4
							WHEN c.[AgeCurrent] BETWEEN 50 AND 59 THEN 5
							WHEN c.[AgeCurrent] BETWEEN 60 AND 64 THEN 6
							WHEN c.[AgeCurrent] >= 65 THEN 7
						END
	, [AgeGroup] =	CASE  
							WHEN c.[AgeCurrent] < 18 OR c.[AgeCurrent] IS NULL THEN '99. Unknown'
							WHEN c.[AgeCurrent] BETWEEN 18 AND 24 THEN '01. 18 to 24'
							WHEN c.[AgeCurrent] BETWEEN 25 AND 29 THEN '02. 25 to 29'
							WHEN c.[AgeCurrent] BETWEEN 30 AND 39 THEN '03. 30 to 39'
							WHEN c.[AgeCurrent] BETWEEN 40 AND 49 THEN '04. 40 to 49'
							WHEN c.[AgeCurrent] BETWEEN 50 AND 59 THEN '05. 50 to 59'
							WHEN c.[AgeCurrent] BETWEEN 60 AND 64 THEN '06. 60 to 64'
							WHEN c.[AgeCurrent] >= 65 THEN '07. 65+' 
						END
	, [Insight_AgeBand] =	CASE  
								WHEN c.[AgeCurrent] < 18 OR c.[AgeCurrent] IS NULL THEN '99. Unknown'
								WHEN c.[AgeCurrent] BETWEEN 18 AND 24 THEN '01. 18 to 24'
								WHEN c.[AgeCurrent] BETWEEN 25 AND 34 THEN '02. 25 to 34'
								WHEN c.[AgeCurrent] BETWEEN 35 AND 44 THEN '03. 35 to 44'
								WHEN c.[AgeCurrent] BETWEEN 45 AND 54 THEN '04. 45 to 54'
								WHEN c.[AgeCurrent] BETWEEN 55 AND 64 THEN '05. 55 to 64'
								WHEN c.[AgeCurrent] >= 65 Then '06. 65+'
							END
	, [HDI_AgeBand] =		CASE      
								WHEN c.[AgeCurrent] < 18 OR c.[AgeCurrent] IS NULL THEN '99. Unknown'
								WHEN c.[AgeCurrent] BETWEEN 18 AND 24 THEN '01. 18 to 24'
								WHEN c.[AgeCurrent] BETWEEN 25 AND 34 THEN '02. 25 to 34'
								WHEN c.[AgeCurrent] BETWEEN 35 AND 44 THEN '03. 35 to 44'
								WHEN c.[AgeCurrent] BETWEEN 45 AND 54 THEN '04. 45 to 54'
								WHEN c.[AgeCurrent] BETWEEN 55 AND 64 THEN '05. 55 to 64'
								WHEN c.[AgeCurrent] BETWEEN 65 AND 74 THEN '06. 65 to 74'
								WHEN c.[AgeCurrent] >= 75 Then '07. 75+'
							END
	, [Region] = COALESCE(c.[Region],'Unknown')
	, [CAMEO_CODE_GRP] = ISNULL((cam.[CAMEO_CODE_GROUP] +'-'+ camg.[CAMEO_CODE_GROUP_Category]),'99. Unknown')
	, [acorncode2022] = trim('"' FROM a.[acorncode2022])
	, [acorncode2023] = trim('"' FROM a.[acorncode2023])
	, 1 as inprogram
	, mi.[microcell_id]
	, c.[RegistrationDate]
	, c.[DeactivatedDate]
	, CL.CINID
INTO #Customer
FROM [WH_NWG].[Derived].[Customer] C
	LEFT JOIN [WH_NWG].[WHB].[Customer] whb
	on whb.FanID = C.FanID
	INNER JOIN [WH_NWG].[Derived].[CINList] cl
	ON c.SourceUID = cl.CIN
	LEFT JOIN [Warehouse].[inbound].[acorn] a
	ON REPLACE(TRIM('" ' FROM (upper(a.[postcode no spaces]))), ' ', '') = REPLACE(TRIM('" ' FROM (upper(c.[PostCode]))), ' ', '')
	LEFT JOIN [Warehouse].[Relational].[CAMEO] cam
	ON cam.[postcode] = c.[postcode]
	LEFT JOIN [Warehouse].[Relational].[cameo_code_group] camG
	ON camG.[CAMEO_CODE_GROUP] = cam.[CAMEO_CODE_GROUP]
	LEFT JOIN [RIPU].[Experian].[Microcell_MatchedCinid] mi
	ON mi.cinid = Cl.CINID

WHERE 
    C.SourceUID NOT IN (SELECT SourceUID
	FROM [WH_NWG].[Derived].[Customer_DuplicateSourceUID]
	WHERE [EndDate] IS NULL
                       )
	AND Cl.cinid NOT IN (SELECT cinid
	FROM RIPU.Derived.cinid_exclude_nw_migration
                        );

CREATE CLUSTERED INDEX [CIX_CIN] ON #Customer ([CIN])											




DROP TABLE IF EXISTS [RIPU].[Derived].[Customer]

PRINT N'Insert INTO customer';

SELECT DISTINCT
	CIN.[cinid],
	[gender] = NULLIF(RTRIM(LTRIM(c.[Gender])), ''),
	[postalsector] = NULLIF(c.[PostalSector], ''),
	[postcodedistrict] = NULLIF(c.[postcodedistrict], ''),
	[postarea] = NULLIF(c.[PostArea], ''),
	[region] = NULLIF(c.[Region], ''),
	[agecurrentbandnumber] = NULLIF(c.[AgeCurrentBandNumber], ''),
	[agegroup] = NULLIF(c.[AgeGroup], ''),
	[cameo_code_grp] = NULLIF(c.[CAMEO_CODE_GRP], ''),
	[insight_ageband] = ISNULL(c.[Insight_AgeBand], '99. Unknown'),
	[hdi_ageband] = NULLIF(c.[HDI_AgeBand], ''),
	[acorncode2022] = NULLIF(RTRIM(LTRIM(c.[acorncode2022])), ''),
	[acorncode2023] = NULLIF(RTRIM(LTRIM(c.[acorncode2023])), ''),
	[inprogram] =	CASE
							WHEN c.[CIN] IS NOT NULL AND c.deactivateddate is null THEN 1
							ELSE 0
						END,
	[microcell_id] = NULLIF(c.[microcell_id], ''),
	[RegistrationDate] = NULLIF(c.[RegistrationDate], ''),
	[DeactivatedDate] = NULLIF(c.[DeactivatedDate], '')
INTO [RIPU].[Derived].[Customer]
FROM [WH_NWG].[Derived].[CINList]	CIN
	LEFT JOIN #Customer C
	ON CIN.[CIN] = C.[CIN]



INSERT INTO [Processing].[ConsumerCombination_NarrativeCleaned_CJM]
	(Narrative, NarrativeCleaned)
SELECT d.Narrative, x.NarrativeCleaned
FROM (
    SELECT DISTINCT Narrative
	FROM [Warehouse].[Relational].[ConsumerCombination] cc
	WHERE NOT EXISTS (
        SELECT 1
		FROM [Processing].[ConsumerCombination_NarrativeCleaned_CJM] nc
		WHERE nc.Narrative = cc.Narrative
    )
		AND cc.Narrative > ''
) d
CROSS APPLY [Processing].[il_CleanNarrative] (d.Narrative) x
-- (3 rows affected) / 00:00:26

--function that cleans MID 

--INSERT INTO [Processing].[ConsumerCombination_MIDCleaned]
--	(MID, MIDCleaned)
--SELECT d.MID, x.NarrativeCleaned
--FROM (
--    SELECT DISTINCT MID
--	FROM [Warehouse].[Relational].[ConsumerCombination] cc
--	WHERE NOT EXISTS (
--        SELECT 1
--		FROM [Processing].[ConsumerCombination_MIDCleaned] nc
--		WHERE nc.MID = cc.MID
--    )
--		AND cc.MID > ''
--) d
--CROSS APPLY [Processing].[il_CleanNarrative] (d.MID) x
--
--
---- Function that cleans postcode 
--
--INSERT INTO [Processing].[ConsumerCombination_PostcodeCleaned]
--	(Postcode, PostcodeCleaned)
--SELECT d.Postcode, x.NarrativeCleaned
--FROM (
--    SELECT DISTINCT Postcode
--	FROM [Warehouse].[AWSFile].[AlternateLocation] al
--	WHERE NOT EXISTS (
--        SELECT 1
--		FROM [Processing].[ConsumerCombination_PostcodeCleaned] nc
--		WHERE nc.Postcode = al.Postcode
--    )
--		AND al.Postcode > ''
--) d
--CROSS APPLY [Processing].[il_CleanNarrative] (d.Postcode) x



DROP TABLE IF EXISTS #ConsumerCombination
SELECT cc.[ConsumerCombinationID]
    , cc.[BrandID], cc.[LocationCountry]
    , cc.[MCCID]
    , cc.[IsUKSpend]
    , [PostCode] = ISNULL(p.[PostCode], '')
    , [LocationID] = ISNULL(p.[LocationID], 0)
    , [AlternatePostCode] = ISNULL(al.[PostCode], '')
    , [AlternateLocationID] = ISNULL(a.[AlternateLocationID], 0)
    , [MID] = REPLACE(cc.[MID], ',', '')
    , [Narrative] = nc.[NarrativeCleaned]
    , [FinalPostcode] = COALESCE(CASE WHEN al.[PostCode] = '' THEN NULL ELSE al.[PostCode] END, p.[Postcode])
    , cc.OriginatorID
INTO #ConsumerCombination
FROM [Warehouse].[Relational].[ConsumerCombination] cc
	LEFT JOIN [Warehouse].[AWSFile].[ComboPostcode] p
	ON cc.[ConsumerCombinationID] = p.[ConsumerCombinationID]
	LEFT JOIN [Warehouse].[AWSFile].[ConsumerCombination_AlternateLocation] a
	ON cc.[ConsumerCombinationID] = a.[ConsumerCombinationID]
	LEFT JOIN [Warehouse].[AWSFile].[AlternateLocation] al
	ON a.[AlternateLocationID] = al.[ID]
	LEFT JOIN [RIPU].[Processing].[ConsumerCombination_NarrativeCleaned_CJM] nc
	ON cc.[Narrative] = nc.[Narrative]



DROP TABLE IF EXISTS ripu.AWSFile.Consumercombinationalternate
-- Create and populate the AWSFile.consumercombinationalternate table
SELECT
	ConsumerCombinationID,
	BrandID,
	TRIM(LocationCountry) AS LocationCountry,
	cc.MCCID,
	PostCode,
	MID,
	Narrative,
	Postcode As rawPostcode,
	AlternatePostCode AS rawAlternatePostcode,
	MID As rawMID,
	Narrative AS rawNarrative,
	FinalPostcode,
	UPPER(
        'MID' + CAST(RIPU.processing.RemoveNonAlphanumeric(MID) AS VARCHAR) + Narrative + 
        CASE 
            WHEN LEN(FinalPostcode) > 2 
            THEN SUBSTRING(RIPU.processing.RemoveNonAlphanumeric(FinalPostcode), 1, LEN(RIPU.processing.RemoveNonAlphanumeric(FinalPostcode)) - 2) 
            ELSE ''  -- If the length is 2 or less, just use the entire FinalPostcode
        END
	) AS ComboID,
	CONVERT(VARCHAR(MAX), HASHBYTES('SHA2_256', CONCAT(cc.LocationCountry, cc.Narrative, cc.OriginatorID, mcc.MCC, cc.MID)), 2) AS ProxyMIDTupleID
INTO ripu.AWSFile.Consumercombinationalternate
FROM #consumercombination cc
	inner JOIN [Warehouse].[Relational].[MCCList] mcc
	ON cc.MCCID = mcc.MCCID

SET IDENTITY_INSERT [AWSFile].[ConsumerCombination] ON

INSERT INTO [AWSFile].[ConsumerCombination] (	[ConsumerCombinationID]
											,	[BrandMIDID]
											,	[BrandID]
											,	[MID]
											,	[Narrative]
											,	[LocationCountry]
											,	[MCCID]
											,	[OriginatorID]
											,	[IsHighVariance]
											,	[IsUKSpend]
											,	[PaymentGatewayStatusID]
											,	[IsCreditOrigin])
SELECT	cc.[ConsumerCombinationID]
	,	cc.[BrandMIDID]
	,	cc.[BrandID]
	,	[MID] = REPLACE(cc.[MID], ',', '')
	,	[Narrative] = [RIPU].[Processing].[RemoveCommas](cc.[Narrative])
	,	cc.[LocationCountry]
	,	cc.[MCCID]
	,	cc.[OriginatorID]
	,	cc.[IsHighVariance]
	,	cc.[IsUKSpend]
	,	cc.[PaymentGatewayStatusID]
	,	cc.[IsCreditOrigin]
FROM (	SELECT *
		FROM [WH_NWG].[Trans].[ConsumerCombination] cc
		WHERE NOT EXISTS (	SELECT 1
							FROM [AWSFile].[ConsumerCombination] cc2 WITH(NOLOCK)
							WHERE cc.[ConsumerCombinationID] = cc2.[ConsumerCombinationID])) cc
ORDER BY cc.[ConsumerCombinationID]

SET IDENTITY_INSERT [AWSFile].[ConsumerCombination] OFF

UPDATE cc
SET cc.[BrandID] = cc2.[BrandID]
FROM [AWSFile].[ConsumerCombination] cc
INNER JOIN [WH_NWG].[Trans].[ConsumerCombination] cc2
	ON cc.[ConsumerCombinationID] = cc2.[ConsumerCombinationID]
	AND cc.[BrandID] != cc2.[BrandID]

----------------------------------------------------------------------------------------------------------------------
-- insert data INTO ETL temp table to scope data down to only contain in program data AND OOP Hospitality data 
----------------------------------------------------------------------------------------------------------------------

DROP TABLE IF EXISTS #ccids;
    SELECT CC.*
INTO #ccids
FROM Warehouse.Relational.Brand b
	JOIN Warehouse.Relational.BrandSector bs
	on bs.SectorID = b.SectorID
	JOIN [Warehouse].[Relational].[consumercombination] cc on cc.BrandID = b.BrandID
WHERE bs.SectorGroupID = 3
	or b.BrandID in (2518,1122,2009,6349)

DROP TABLE IF EXISTS #ccids_hospitality;
    SELECT c.*
INTO #ccids_hospitality
FROM Warehouse.relational.ConsumerCombination C
	JOIN Warehouse.Relational.MCCList l ON l.MCCID = c.MCCID
WHERE l.MCCID IN (740, 777, 778, 779, 780, 843, 845, 909, 911, 913, 918, 992, 989, 987, 988, 986, 660)


DROP TABLE IF EXISTS #ccids_merged;
    			SELECT *
	INTO #ccids_merged
	FROM #ccids
UNION
	SELECT *
	FROM #ccids_hospitality


DROP TABLE IF EXISTS #checkingccs;
    SELECT cc.*
INTO #checkingccs
FROM #ccids_merged cc
WHERE (
            CC.Narrative NOT IN ('CRV*', 'IZ *', 'IZ%', 'AIRBNB%', 'PLAYSTATIONNETWORK')
	AND cc.Narrative NOT LIKE ('%SPOTIFY%')
	AND LTRIM(RTRIM(cc.LocationCountry)) IN ('GB')
        )
	OR cc.mid IN ('498750000020090')
	OR cc.Narrative LIKE '%DELIVEROO%'
	OR cc.Narrative LIKE '%JUST EAT%'
	OR cc.Narrative LIKE '%JUST%EAT%'
	OR cc.Narrative LIKE '%JUSTEAT%'
	OR cc.Narrative LIKE '%UBER%EAT%'
	OR cc.Narrative LIKE '%UBER%'
	OR cc.Narrative LIKE '%UBR%'
	OR cc.Narrative LIKE '%COFFEE%NO%1%'
	OR 'MID'+CAST(cc.mid AS VARCHAR) IN ('MID41374193', 'MID337538695889', 'MID1646588')
	OR (
            TRIM(NARRATIVE) IN (
                'WELCOME BPRET A MANAG',
                'PRETMFG VICTORIA ROAD',
                'WELCOME BREAK NEWARK',
                'BIRCHANGER  PRET',
                'FLEET SOUTH  PRET',
                'WARWICK SOUTH  PRET'
            )
	AND CC.MCCID IN (741, 747)
        )

DROP TABLE IF EXISTS #ComboIDs;
    SELECT
	cc.consumercombinationid,
	cc.brandid,
	cc.locationcountry,
	cc.mccid,
	cc.mid,
	cc.narrative,
	REPLACE(UPPER('MID' + CAST(cca.mid AS VARCHAR) + cca.narrative + ISNULL(CASE WHEN LEN(cca.Finalpostcode) >= 2 THEN LEFT(cca.Finalpostcode, LEN(cca.Finalpostcode) - 2) ELSE '' END, '')), ' ', '') AS comboid_generated
INTO #ComboIDs
FROM
	#checkingccs cc
	INNER JOIN
	RIPU.AWSFile.Consumercombinationalternate cca ON CAST(cc.consumercombinationid AS VARCHAR) = CAST(cca.consumercombinationid AS VARCHAR)

DROP TABLE IF EXISTS #ComboIDs_All;
    SELECT
	cca.consumercombinationid,
	cca.brandid,
	cca.locationcountry,
	cca.mccid,
	cca.mid,
	cca.narrative,
	REPLACE(UPPER('MID' + CAST(cca.mid AS VARCHAR) + cca.narrative + ISNULL(CASE WHEN LEN(cca.Finalpostcode) >= 2 THEN LEFT(cca.Finalpostcode, LEN(cca.Finalpostcode) - 2) ELSE '' END, '')), ' ', '') AS comboid_generated
INTO #ComboIDs_All
FROM
	RIPU.AWSFile.Consumercombinationalternate cca
WHERE
        EXISTS (
            SELECT 1
FROM #ComboIDs c
WHERE REPLACE(UPPER('MID' + CAST(cca.mid AS VARCHAR) + cca.narrative + ISNULL(CASE WHEN LEN(cca.Finalpostcode) >= 2 THEN LEFT(cca.Finalpostcode, LEN(cca.Finalpostcode) - 2) ELSE '' END, '')), ' ', '') = c.comboid_generated
        )


CREATE CLUSTERED INDEX [CIX_CCID] ON #ComboIDs_All ([consumercombinationid])


-------------------------------------------------------------------------------------------------
--load transactions 
-------------------------------------------------------------------------------------------------


DROP TABLE IF EXISTS [AWSFile].[CT_DailyLoad_S3]
DROP TABLE IF EXISTS #TempResults
CREATE TABLE #TempResults
(
	[FileID] [int],
	[RowNum] [int],
	TranSequenceID VARCHAR(50),
	ConsumerCombinationID INT,
	cardholderpresentdata INT,
	CINID INT,
	amount DECIMAL(18, 2),
	isonline INT,
	paymenttypeid INT,
	trandate DATE,
	brandid INT,
	subscription_flag INT,
	publisherid INT,
	mcc [varchar](4),
	[MID] [varchar](50),
	[currentagebandtext] [varchar](12),
	[TranTime] TIME
);

--Grab new pre reg customers 
DROP TABLE IF EXISTS #preRegCustomers
SELECT CINID
INTO #preRegCustomers
FROM  [RIPU].[Derived].[Customer] c 
where not exists (
					select 1 
					from [RIPU].[Derived].[Customer_archive] ca 
					where c.cinid = ca.cinid
					)
and inprogram = 1
union 
select cinid
from RIPU.derived.customer c 
where RegistrationDate > DATEADD(mm,-1,cast(getdate() as date))

create clustered index ci_CIN on #preRegCustomers (CINID)


--Load Pre Reg Debit

DROP TABLE IF EXISTS #PreReg_Debit_Staging
SELECT ct.FileID 
		, ct.RowNum
		, ConsumerCombinationID
		, CardholderPresentData
		, ct.TranDate
		, CINID
		, ct.Amount
		, IsOnline
		, 1 paymenttypeid
		,
		CONVERT(VARCHAR(8), 
			CAST(
			RIGHT('0' + CAST(DATEPART(HOUR, t.TranTime) AS VARCHAR), 2) + ':' +
			CASE WHEN DATEPART(MINUTE, t.TranTime) < 30 THEN '00' ELSE '30' END + ':00'
			AS TIME
			), 108
		) AS TranTime
INTO #PreReg_Debit_Staging
FROM Warehouse.Relational.ConsumerTransaction ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE exists (
				SELECT 1
	FROM #preRegCustomers c
	WHERE ct.CINID = c.CINID
				)
	AND ct.[TranDate] > CAST(DATEADD(YEAR,-5,DATEADD(MONTH, DATEDIFF(MONTH, 0,GETDATE()), 0))as DATE)
OPTION(RECOMPILE)

CREATE CLUSTERED INDEX [CIX_FileRow] ON #PreReg_Debit_Staging ([FileID], [RowNum])

DROP TABLE IF EXISTS #PreReg
SELECT *
INTO #PreReg
FROM #PreReg_Debit_Staging p
WHERE not exists (
					SELECT 1
FROM [RIPU].[Processing].[RowNum_Log_Import] l
WHERE p.FileID = l.FileID
	AND p.RowNum = l.RowNum
					)

CREATE CLUSTERED INDEX [CIX_FileRow] ON #PreReg ([FileID], [RowNum])

--Load Pre Reg Credit 

DROP TABLE IF EXISTS #PreReg_Credit_Staging
SELECT ct.FileID 
		, ct.RowNum
		, ct.ConsumerCombinationID
		, ct.CardholderPresentData
		, ct.TranDate
		, ct.CINID
		, ct.Amount
		, ct.IsOnline
		, 2 AS paymenttypeid
		,
		CONVERT(VARCHAR(8), 
			CAST(
			RIGHT('0' + CAST(DATEPART(HOUR, t.TranTime) AS VARCHAR), 2) + ':' +
			CASE WHEN DATEPART(MINUTE, t.TranTime) < 30 THEN '00' ELSE '30' END + ':00'
			AS TIME
			), 108
		) AS TranTime
INTO #PreReg_Credit_Staging
FROM Warehouse.Relational.ConsumerTransaction_CreditCard ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE exists (
				SELECT 1
	FROM #preRegCustomers c
	WHERE ct.CINID = c.CINID
				)
	AND ct.[TranDate] > CAST(DATEADD(YEAR,-5,DATEADD(MONTH, DATEDIFF(MONTH, 0,GETDATE()), 0))as DATE)
OPTION(RECOMPILE)

CREATE CLUSTERED INDEX [CIX_FileRow] ON #PreReg_Credit_Staging ([FileID], [RowNum])

INSERT INTO #PreReg
SELECT *
FROM #PreReg_Credit_Staging p
WHERE not exists (
					SELECT 1
FROM [RIPU].[Processing].[RowNum_Log_Import] l
WHERE p.FileID = l.FileID
	AND p.RowNum = l.RowNum
					)
ORDER BY	[FileID]
		,	[RowNum]

-- Grab new data INTO temp table for credit card data
DROP TABLE IF EXISTS #ct_dailyload_creditcard
SELECT ct.FileID
	, ct.RowNum
	, ct.ConsumerCombinationID
	, ct.CardholderPresentData
	, ct.TranDate
	, ct.CINID
	, ct.Amount
	, ct.IsOnline
	,
	CONVERT(VARCHAR(8), 
		CAST(
		 RIGHT('0' + CAST(DATEPART(HOUR, t.TranTime) AS VARCHAR), 2) + ':' +
		 CASE WHEN DATEPART(MINUTE, t.TranTime) < 30 THEN '00' ELSE '30' END + ':00'
		 AS TIME
		), 108
	) AS TranTime
INTO #ct_dailyload_creditcard
FROM [RIPU].[Staging].[ConsumerTransaction_CreditCardHolding] ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE NOT EXISTS (
				SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import] l
	WHERE ct.FileID = l.fileid
		AND ct.RowNum = l.RowNum 
)
	AND NOT EXISTS (
				SELECT 1
	FROM #PreReg pr
	WHERE pr.FileID = ct.FileID
		AND pr.RowNum = ct.RowNum
				)


CREATE CLUSTERED INDEX [CIX_CIN] ON #ct_dailyload_creditcard ([CINID], [Fileid], [RowNum], ConsumerCombinationID)	


-- Grab new data INTO temp table for debit card data
DROP TABLE IF EXISTS #ct_dailyload_debitcard
SELECT ct.FileID
	, ct.RowNum
	, ct.ConsumerCombinationID
	, ct.CardholderPresentData
	, ct.TranDate
	, ct.CINID
	, ct.Amount
	, ct.IsOnline
	,
	CONVERT(VARCHAR(8), 
		CAST(
		 RIGHT('0' + CAST(DATEPART(HOUR, t.TranTime) AS VARCHAR), 2) + ':' +
		 CASE WHEN DATEPART(MINUTE, t.TranTime) < 30 THEN '00' ELSE '30' END + ':00'
		 AS TIME
		), 108
	) AS TranTime
INTO #ct_dailyload_debitcard
FROM [RIPU].[staging].[ConsumerTransactionHolding] ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE NOT EXISTS (
				SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import] l
	WHERE ct.FileID = l.fileid
		AND ct.RowNum = l.RowNum 
)
	AND NOT EXISTS (
				SELECT 1
	FROM #PreReg pr
	WHERE pr.FileID = ct.FileID
		AND pr.RowNum = ct.RowNum
				)


-- Insert data INTO the temporary table using separate steps
-- For #ct_dailyload_creditcard
INSERT INTO #TempResults
SELECT fileid
		, rowNum
		, CONCAT('1','-',cast (FileID as varchar),'-', cast(RowNum as varchar)) AS TranSequenceID,
	ct.consumercombinationid,
	cardholderpresentdata,
	ct.cinid,
	ct.amount,
	isonline,
	2 as paymenttypeid,
	trandate,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	ct.TranTime
FROM #ct_dailyload_creditcard ct
	JOIN RIPU.Derived.Customer cu
	ON cu.cinid = cast(ct.cinid as varchar)
	JOIN Warehouse.Relational.consumercombination cc
	ON cc.consumercombinationid = ct.consumercombinationid
	LEFT JOIN [wh_allpublishers].[derived].[subscription_combinations] sf
	ON cc.brandid = sf.brandid
		AND sf.Amount = ct.amount
		AND ct.trandate >= sf.startdate
		AND ct.trandate < coalesce(enddate,cast('2100-01-01' as date))
	LEFT JOIN Warehouse.Relational.MCCList mcc
	ON cc.mccid = mcc.mccid
WHERE inprogram = 1


-- For #ct_dailyload_debitcard
INSERT INTO #TempResults
SELECT FileID
		, RowNum
		, CONCAT('1','-',cast (FileID as varchar),'-', cast(RowNum as varchar)) AS TranSequenceID,
	ct.consumercombinationid,
	cardholderpresentdata,
	ct.cinid,
	ct.amount,
	isonline,
	1 as paymenttypeid,
	trandate,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	ct.TranTime
FROM #ct_dailyload_debitcard ct
	JOIN RIPU.Derived.Customer cu
	ON cu.cinid = cast(ct.cinid as varchar)
	JOIN Warehouse.Relational.consumercombination cc
	ON cc.consumercombinationid = ct.consumercombinationid
	LEFT JOIN [wh_allpublishers].[derived].[subscription_combinations] sf
	ON cc.brandid = sf.brandid
		AND sf.Amount = ct.amount
		AND ct.trandate >= sf.startdate
		AND ct.trandate < coalesce(enddate,cast('2100-01-01' as date))
	LEFT JOIN Warehouse.Relational.MCCList mcc
	ON cc.mccid = mcc.mccid
WHERE inprogram = 1

INSERT INTO #TempResults
SELECT FileID
		, RowNum
		, CONCAT('1','-',cast (FileID as varchar),'-', cast(RowNum as varchar)) AS TranSequenceID,
	pr.consumercombinationid,
	cardholderpresentdata,
	pr.cinid,
	pr.amount,
	isonline,
	paymenttypeid,
	trandate,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	pr.TranTime
FROM #preReg pr
	JOIN RIPU.Derived.Customer cu
	ON cu.cinid = cast(pr.cinid as varchar)
	JOIN Warehouse.Relational.consumercombination cc
	ON cc.consumercombinationid = pr.consumercombinationid
	LEFT JOIN [wh_allpublishers].[derived].[subscription_combinations] sf
	ON cc.brandid = sf.brandid
		AND sf.Amount = pr.amount
		AND pr.trandate >= sf.startdate
		AND pr.trandate < coalesce(enddate,cast('2100-01-01' as date))
	LEFT JOIN Warehouse.Relational.MCCList mcc
	ON cc.mccid = mcc.mccid
WHERE inprogram = 1

	/*
INSERT INTO #TempResults
	SELECT	FileID
		,	RowNum
		,CONCAT('1','-',cast (FileID as varchar),'-', cast(RowNum as varchar)) AS TranSequenceID,
		pr.consumercombinationid,
		cardholderpresentdata,
		pr.cinid,
		pr.amount,
		isonline,
		paymenttypeid,
		trandate,
		cc.brandid,
		case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
		1 as publisherid,
		mcc.mcc as mcc,
		cc.mid,
		cu.insight_ageband as currentagebandtext
	FROM sandbox.williama.AfinityDeltaLoad20250604 pr
		JOIN RIPU.Derived.Customer cu 
		ON cu.cinid = cast(pr.cinid as varchar)
		JOIN Warehouse.Relational.consumercombination cc 
		ON cc.consumercombinationid = pr.consumercombinationid
		LEFT JOIN [wh_allpublishers].[derived].[subscription_combinations] sf 
		ON cc.brandid = sf.brandid
			AND sf.Amount = pr.amount
			AND pr.trandate >= sf.startdate
			AND pr.trandate < coalesce(enddate,cast('2100-01-01' as date))
		LEFT JOIN Warehouse.Relational.MCCList mcc
		ON cc.mccid = mcc.mccid
	WHERE  not exists (
					select 1 
					from #TempResults tr
					where tr.FileID = pr.FileID
					and tr.RowNum = pr.RowNum
					)

*/

-- Select the final results
SELECT [TranSequenceID],
	[ConsumerCombinationID],
	[cardholderpresentdata],
	[CINID],
	[amount],
	[isonline],
	[paymenttypeid],
	[trandate],
	[brandid],
	[subscription_flag],
	[publisherid],
	[mcc],
	REPLACE([mid], ',', '') AS [mid],
	[currentagebandtext],
	[TranTime],
	'N' AS [UpdateType],
	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [UpdateDate],
	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [LoadDate]
INTO [AWSFile].[CT_DailyLoad_S3]
FROM #TempResults;


-- INSERT INTO instead of other above so it is incremented.
-- adding into a new table for timestamp
-- INSERT INTO [AWSFile].[CT_DailyLoad_S3_Timestamp]
-- SELECT [TranSequenceID],
-- 	[ConsumerCombinationID],
-- 	[cardholderpresentdata],
-- 	[CINID],
-- 	[amount],
-- 	[isonline],
-- 	[paymenttypeid],
-- 	[trandate],
-- 	[brandid],
-- 	[subscription_flag],
-- 	[publisherid],
-- 	[mcc],
-- 	[mid],
-- 	[currentagebandtext],
-- 	[TranTime],
-- 	'N' AS [UpdateType],
-- 	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [UpdateDate],
-- 	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [LoadDate]
-- FROM #TempResults;

-- -- Create index on CT_DailyLoad_S3_Timestamp for faster streaming queries
-- IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_CT_DailyLoad_S3_Timestamp_LoadDate_CINID' AND object_id = OBJECT_ID('[AWSFile].[CT_DailyLoad_S3_Timestamp]'))
-- BEGIN
--     CREATE NONCLUSTERED INDEX [IX_CT_DailyLoad_S3_Timestamp_LoadDate_CINID] 
--     ON [AWSFile].[CT_DailyLoad_S3_Timestamp] ([LoadDate], [CINID], [trandate])
--     INCLUDE ([TranSequenceID], [ConsumerCombinationID], [amount], [brandid], [mcc], [mid])
-- END

--Add new loadDate for pre reg 

INSERT INTO Processing.Affinity_LastLoadDate
VALUES
	(cast(DATEADD(hh,-6,getdate()) as date))

--Add new daily rows to row log 
INSERT INTO [RIPU].[Processing].[RowNum_Log_Import]
SELECT [FILEID], RowNum
FROM #TempResults

TRUNCATE TABLE [RIPU].[Derived].[Customer_archive]
INSERT INTO [RIPU].[Derived].[Customer_archive]
select cinid
from [RIPU].[Derived].[Customer]
where inprogram = 1 
ORDER BY CINID

-- Truncate matched cinid table (to remain privicy complaint)
TRUNCATE TABLE [RIPU].[Experian].[Microcell_matchedcinid]

-- truncate table on Saturday
IF @DayName = 'SATURDAY' BEGIN

	TRUNCATE TABLE [RIPU].[Staging].[ConsumerTransaction_CreditCardHolding]
	TRUNCATE TABLE [RIPU].[staging].[ConsumerTransactionHolding]
	--adding in timestamp table to truncate with the others
	--TRUNCATE TABLE [AWSFile].[CT_DailyLoad_S3_Timestamp] --MAYBE NOT NEEDED STILL AS THIS IS ONLY FOR TESTING??
END
