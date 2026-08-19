USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[Daily_upload_Process_HDI]    Script Date: 18/08/2026 16:37:15 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO





/*
Replaces the conditional processing section in the ConsumerTransactionHoldingLoad package
*/
ALTER PROCEDURE [Processing].[Daily_upload_Process_HDI]

AS 

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @Subject VARCHAR(8000)

DECLARE	@Time DATETIME,	@Msg VARCHAR(2048), @SSMS BIT = 1
--EXEC master.dbo.oo_TimerMessagev2 'Start Processing.MIDI_ConditionalPart_RIPU_test_day 2', @Time OUTPUT, @SSMS OUTPUT


-- Set MainTableLoadOrMIDI Variable (this is used elsewhere, not here)
DECLARE @DayName VARCHAR(10) = UPPER(DATENAME(DW, GETDATE()));
SELECT @DayName = CASE WHEN @DayName IN ('SATURDAY','SUNDAY') THEN @DayName ELSE 'WEEKDAY' END


-- execute experian table AND lookup process
--exec RIPU.Experian.sp_ingest_Microcell_Addresses;
--exec RIPU.Experian.sp_ingest_Microcell_MosaicLookup;
--exec RIPU.Experian.sp_Microcell_CinidToAddressMatcher;


-- truncate table for stream to S3 so it can be refreshed with new daily data
DROP TABLE IF EXISTS RIPU.[AWSFile].[CT_DailyLoad_S3_HDI]

--drop AND recreate table of customers that can be flagged as inprogram AND reused as S3 customer table

DROP TABLE IF EXISTS #Customer;
SELECT [CIN] = C.[SourceUID]
	, C.[Gender]
	, whb.[DOB]
	, C.[PostCode]
	, [PostalSector] = CONCAT(LEFT(c.[PostCode], CHARINDEX(' ', c.[PostCode] + ' ') - 1),' ',SUBSTRING(c.[PostCode], CHARINDEX(' ', c.[PostCode]) + 1, 1))
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


DROP TABLE IF EXISTS [RIPU].[Derived].[Customer_HDI]

PRINT N'Insert INTO customer_HDI';

SELECT DISTINCT
	CIN.[cinid],
	[gender] = NULLIF(RTRIM(LTRIM(c.[Gender])), ''),
	[postalsector] = NULLIF(c.[PostalSector], ''),
	[postcodedistrict] = NULLIF(c.[postcodedistrict], ''),
	[postarea] = NULLIF(c.[PostArea], ''),
	[postcode] = NULLIF(c.[PostCode], ''),
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
INTO [RIPU].[Derived].[Customer_HDI]
FROM [WH_NWG].[Derived].[CINList]	CIN
	LEFT JOIN #Customer C
	ON CIN.[CIN] = C.[CIN]




DROP TABLE IF EXISTS RIPU.AWSFile.Consumercombination_HDI
SELECT
	cc.ConsumerCombinationID,
	cc.BrandMIDID,
	cc.BrandID,
	RIPU.processing.RemoveCommas(cc.MID) as MID,
	RIPU.processing.RemoveCommas(cc.Narrative) as Narrative,
	cc.LocationCountry,
	cc.MCCID,
	cc.OriginatorID,
	cc.IsHighVariance,
	cc.IsUKSpend,
	cc.PaymentGatewayStatusID,
	cc.IsCreditOrigin,
	[Postcode] = COALESCE(CASE WHEN al.[PostCode] = '' THEN NULL ELSE al.[PostCode] END, p.[Postcode])
INTO RIPU.AWSFile.Consumercombination_HDI
FROM Warehouse.Relational.ConsumerCombination cc
	LEFT JOIN [Warehouse].[AWSFile].[ComboPostcode] p
		ON cc.[ConsumerCombinationID] = p.[ConsumerCombinationID]
	LEFT JOIN [Warehouse].[AWSFile].[ConsumerCombination_AlternateLocation] a
		ON cc.[ConsumerCombinationID] = a.[ConsumerCombinationID]
	LEFT JOIN [Warehouse].[AWSFile].[AlternateLocation] al
		ON a.[AlternateLocationID] = al.[ID]


-------------------------------------------------------------------------------------------------
--load transactions 
-------------------------------------------------------------------------------------------------


DROP TABLE IF EXISTS [AWSFile].[CT_DailyLoad_S3_HDI]
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
	trantime TIME,
	brandid INT,
	subscription_flag INT,
	publisherid INT,
	mcc [varchar](4),
	[MID] [varchar](50),
	[currentagebandtext] [varchar](12),
	InputModeID INT
);

------------------------------------------------
--Prereg logic
------------------------------------------------

DROP TABLE IF EXISTS #preRegCustomers
select cinid
INTO #preRegCustomers
from  [RIPU].[Derived].[Customer] c 
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

--to be used to populate the prereg flag in the uploaded customer table 
DROP TABLE IF EXISTS RiPU.processing.Customer_PreReg_flag_cinids
SELECT c.cinid
into RiPU.processing.Customer_PreReg_flag_cinids
from #preRegCustomers c;


--Load Pre Reg Debit

DROP TABLE IF EXISTS #PreReg_Debit_Staging
SELECT ct.FileID 
		, ct.RowNum
		, ct.ConsumerCombinationID
		, ct.CardholderPresentData
		, ct.TranDate
		, ct.CINID
		, ct.Amount
		, ct.IsOnline
		, 1 paymenttypeid
		, t.TranTime
		, ct.InputModeID
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
CREATE TABLE #PreReg
(
	[FileID] [int] NOT NULL,
	[RowNum] [int] NOT NULL,
	[ConsumerCombinationID] [int] NULL,
	[CardholderPresentData] [int] NULL,
	[TranDate] [date] NULL,
	[CINID] [int] NULL,
	[Amount] [decimal](18, 2) NULL,
	[IsOnline] [int] NULL,
	[paymenttypeid] [int] NOT NULL,
	[TranTime] [time] NULL,
	[InputModeID] [int] NULL
)

INSERT INTO #PreReg
	([FileID], [RowNum], [ConsumerCombinationID], [CardholderPresentData], [TranDate], [CINID], [Amount], [IsOnline], [paymenttypeid], [TranTime], [InputModeID])
SELECT p.[FileID]
		, p.[RowNum]
		, p.[ConsumerCombinationID]
		, p.[CardholderPresentData]
		, p.[TranDate]
		, p.[CINID]
		, p.[Amount]
		, p.[IsOnline]
		, p.[paymenttypeid]
		, p.[TranTime]
		, p.[InputModeID]
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
		, 2 paymenttypeid
		, t.TranTime
		, NULL as InputModeID
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
 	([FileID], [RowNum], [ConsumerCombinationID], [CardholderPresentData], [TranDate], [CINID], [Amount], [IsOnline], [paymenttypeid], [TranTime], [InputModeID])
SELECT p.[FileID]
		, p.[RowNum]
		, p.[ConsumerCombinationID]
		, p.[CardholderPresentData]
		, p.[TranDate]
		, p.[CINID]
		, p.[Amount]
		, p.[IsOnline]
		, p.[paymenttypeid]
		, p.[TranTime]
		, p.[InputModeID]
FROM #PreReg_Credit_Staging p
WHERE not exists (
					SELECT 1
					FROM [RIPU].[Processing].[RowNum_Log_Import] l
					WHERE p.FileID = l.FileID
					AND p.RowNum = l.RowNum
					)
ORDER BY	[FileID]
		,	[RowNum]


---- TEMP ADDITION FOR BACKFILL
INSERT INTO #PreReg
 	([FileID], [RowNum], [ConsumerCombinationID], [CardholderPresentData], [TranDate], [CINID], [Amount], [IsOnline], [paymenttypeid], [TranTime], [InputModeID])
SELECT p.[FileID]
		, p.[RowNum]
		, p.[ConsumerCombinationID]
		, p.[CardholderPresentData]
		, p.[TranDate]
		, p.[CINID]
		, p.[Amount]
		, p.[IsOnline]
		, p.[paymenttypeid]
		, NULL
		, NULL
FROM sandbox.williama.preregbackfill p
WHERE NOT EXISTS (
	SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import_HDI] par
	WHERE p.FileID = par.fileid
		AND p.RowNum = par.RowNum 
) AND NOT EXISTS (
	SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import] l
	WHERE p.FileID = l.fileid
		AND p.RowNum = l.RowNum 
) AND NOT EXISTS ( select 1 
				from #prereg pr
				where p.fileID = pr.fileID
				and p.rownum = pr.rownum
				);


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
	, t.TranTime
	, ct.InputModeID
INTO #ct_dailyload_creditcard
FROM [RIPU].[Staging].[ConsumerTransaction_CreditCardHolding] ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
	ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE NOT EXISTS (
	SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import_HDI] par
	WHERE ct.FileID = par.fileid
		AND ct.RowNum = par.RowNum  
);

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
	, t.TranTime
	, ct.InputModeID
INTO #ct_dailyload_debitcard
FROM [RIPU].[staging].[ConsumerTransactionHolding] ct
LEFT JOIN [WH_NWG].[Trans].[ConsumerTransaction_Timestamp] t
	ON ct.FileID = t.FileID AND ct.RowNum = t.RowNum
WHERE NOT EXISTS (
	SELECT 1
	FROM [RIPU].[Processing].[RowNum_Log_Import_HDI] par
	WHERE ct.FileID = par.fileid
		AND ct.RowNum = par.RowNum 
);


-- Insert data INTO the temporary table using separate steps
-- For #ct_dailyload_creditcard
INSERT INTO #TempResults
SELECT 
	ct.FileID,
	ct.RowNum,
	CONCAT('1','-',cast (ct.FileID as varchar),'-', cast(ct.RowNum as varchar)) AS TranSequenceID,
	ct.consumercombinationid,
	cardholderpresentdata,
	ct.cinid,
	ct.amount,
	isonline,
	2 as paymenttypeid,
	ct.trandate,
	trantime,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	ct.InputModeID
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


-- For #ct_dailyload_debitcard
INSERT INTO #TempResults
SELECT 
	ct.FileID,
	ct.RowNum,
	CONCAT('1','-',cast (ct.FileID as varchar),'-', cast(ct.RowNum as varchar)) AS TranSequenceID,
	ct.consumercombinationid,
	cardholderpresentdata,
	ct.cinid,
	ct.amount,
	isonline,
	1 as paymenttypeid,
	ct.trandate,
	trantime,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	ct.InputModeID
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

-- For #prereg
INSERT INTO #TempResults
SELECT 
	pr.FileID, 
	pr.RowNum,
	CONCAT('1','-',cast (pr.FileID as varchar),'-', cast(pr.RowNum as varchar)) AS TranSequenceID,
	pr.consumercombinationid,
	cardholderpresentdata,
	pr.cinid,
	pr.amount,
	isonline,
	paymenttypeid,
	pr.trandate,
	trantime,
	cc.brandid,
	case when sf.BrandID is null then 0 else 1 end AS subscription_flag,
	1 as publisherid,
	mcc.mcc as mcc,
	cc.mid,
	cu.insight_ageband as currentagebandtext,
	pr.InputModeID
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

-- Select the final results
SELECT 	
	[FileID],
	[RowNum],
	[TranSequenceID],
	[ConsumerCombinationID],
	[cardholderpresentdata],
	[CINID],
	[amount],
	[isonline],
	[paymenttypeid],
	[trandate],
	[trantime],
	[brandid],
	[subscription_flag],
	[publisherid],
	[mcc],
	[mid],
	[currentagebandtext],
	[InputModeID],
	'N' AS [UpdateType],
	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [UpdateDate],
	CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS [LoadDate]
INTO [AWSFile].[CT_DailyLoad_S3_HDI]
FROM #TempResults;




--Add new daily rows to row log 
INSERT INTO [RIPU].[Processing].[RowNum_Log_Import_HDI]
SELECT [FILEID], RowNum
FROM #TempResults
