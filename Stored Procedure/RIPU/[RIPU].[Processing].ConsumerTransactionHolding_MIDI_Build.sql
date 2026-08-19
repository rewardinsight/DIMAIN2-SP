USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[ConsumerTransactionHolding_MIDI_Build]    Script Date: 18/08/2026 16:33:58 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






--drop procedure [Processing].[ConsumerTransactionHolding_MIDI_Build]

ALTER  PROCEDURE [Processing].[ConsumerTransactionHolding_MIDI_Build]
AS
BEGIN

	DECLARE @RowCount INT -- Logging row count

	----------------------------------------------------------------------
	-- Clear Down debit holding
	----------------------------------------------------------------------
	TRUNCATE TABLE [Ripu].Processing.ConsumerTransactionHolding_MIDI_Debit;

	/*IF EXISTS
		(
			SELECT
				1
			FROM sys.indexes
			WHERE name = 'PK_ConsumerTransaction_MIDI_DebitCardHolding_RIPU'
				AND object_id = OBJECT_ID('Processing.ConsumerTransactionHolding_MIDI_Debit')
		)
		DROP INDEX [PK_ConsumerTransaction_MIDI_DebitCardHolding_RIPU] ON Processing.ConsumerTransactionHolding_MIDI_Debit */
	----------------------------------------------------------------------
	-- Insert into debit holding
	----------------------------------------------------------------------



	--INSERT INTO [Ripu].Processing.ConsumerTransactionHolding_MIDI_Debit
	--
	-- SELECT
	--	 mh.FileID
	--   , mh.RowNum
	--   , mh.CINID
	--   , TranDate
	--   , MID
	--   , MCCID
	--   , Narrative
	--   , mh.LocationCountry
	--   , mh.OriginatorID
	--   , Amount
	--   , mh.CardholderPresentData
	--   , mh.PaymentTypeID
	--   , mh.LocationID
	-- FROM [Warehouse].[Staging].[CTLoad_MIDIHolding] mh --[WH_NWG].[MIDI].[MIDIHolding_Debit] mh
	-- JOIN RIPU.Processing.CustomersAffinity c
	--	 ON c.CINID = mh.CINID
	--		AND c.rw = 1
	--	WHERE NOT EXISTS (	SELECT 1
	--						FROM  [RIPU].[Processing].[RowNum_Log] rnl WITH (NOLOCK)
	--						WHERE mh.RowNum = rnl.RowNum
	--						AND mh.FileID = rnl.FileID)
	--OPTION(RECOMPILE)	


	DROP TABLE IF EXISTS #MIDIHolding
	SELECT
			 mh.FileID
		   , mh.RowNum
		   , mh.CINID
		   , TranDate
		   , MID
		   , MCCID
		   , Narrative
		   , mh.LocationCountry
		   , mh.OriginatorID
		   , Amount
		   , mh.CardholderPresentData
		   , mh.PaymentTypeID
		   , mh.LocationID
	INTO #MIDIHolding
	FROM [Warehouse].[Staging].[CTLoad_MIDIHolding] mh
	--23 secs
	
	CREATE NONCLUSTERED INDEX nccix ON #MIDIHolding (cinid)
	-- 1.47
	
	INSERT INTO [Ripu].Processing.ConsumerTransactionHolding_MIDI_Debit
	SELECT *
	FROM #MIDIHolding t 
	WHERE exists (
					SELECT 1 
					FROM RIPU.Processing.CustomersAffinity c
					WHERE c.CINID = t.CINID
					)
	AND NOT EXISTS (	SELECT 1
						FROM  [RIPU].[Processing].[RowNum_Log] rnl WITH (NOLOCK)
						WHERE T.RowNum = rnl.RowNum
						AND T.FileID = rnl.FileID)
	--0.24 SECS


	SELECT @RowCount = @@rowcount


   /*CREATE UNIQUE CLUSTERED INDEX [PK_ConsumerTransaction_MIDI_DebitCardHolding_RIPU] ON Processing.ConsumerTransactionHolding_MIDI_Debit (FileID, RowNum)*/

	----------------------------------------------------------------------
	-- Clear Down credit holding
	----------------------------------------------------------------------
	TRUNCATE TABLE [RIPU].Processing.ConsumerTransactionHolding_MIDI_Credit;

	/*IF EXISTS
		(
			SELECT
				1
			FROM sys.indexes
			WHERE name = 'PK_ConsumerTransaction_MIDI_CreditCardHolding_RIPU'
				AND object_id = OBJECT_ID('Processing.ConsumerTransactionHolding_MIDI_Credit')
		)
		DROP INDEX [PK_ConsumerTransaction_MIDI_CreditCardHolding_RIPU] ON Processing.ConsumerTransactionHolding_MIDI_Credit*/
	----------------------------------------------------------------------
	-- Insert into credit holding
	----------------------------------------------------------------------
	INSERT INTO [RIPU].Processing.ConsumerTransactionHolding_MIDI_Credit
	 SELECT 
		 mh.FileID
	   , mh.RowNum
	   , mh.CINID
	   , TranDate
	   , MID
	   , MCCID
	   , Narrative
	   , mh.LocationCountry
	   , mh.OriginatorReference as OriginatorID
	   , Amount
	   , mh.CardholderPresentMc AS CardholderPresentData
	   , mh.PaymentTypeID
	   , mh.LocationID
	 FROM [Warehouse].[Staging].[CreditCardLoad_MIDIHolding] mh--[WH_NWG].[MIDI].[MIDIHolding_Credit] mh
	 JOIN RIPU.Processing.CustomersAffinity c
	    ON c.CINID = mh.CINID
		  AND c.rw = 1
	WHERE NOT EXISTS (	SELECT 1
					FROM  [RIPU].[Processing].[RowNum_Log] rnl WITH (NOLOCK)
					WHERE mh.RowNum = rnl.RowNum
					AND mh.FileID = rnl.FileID)
	OPTION(RECOMPILE)	

	 --LEFT JOIN  [RIPU].[Processing].[RowNum_Log] rnl
	--	 ON mh.RowNum = rnl.RowNum
	--		 AND mh.FileID = rnl.FileID
	 --WHERE rnl.FileID IS NULL

	 SELECT @RowCount = @@rowcount

    /*CREATE UNIQUE CLUSTERED INDEX [PK_ConsumerTransaction_MIDI_CreditCardHolding_RIPU] ON Processing.ConsumerTransactionHolding_MIDI_Credit (FileID, RowNum)*/

	----------------------------------------------------------------------
	-- First, insert CREDIT holding trans into quarantine table
	----------------------------------------------------------------------
	--TranTime added in, currently returning NULL
	TRUNCATE TABLE [RIPU].Processing.ConsumerTransaction_Quarentine

	INSERT INTO [RIPU].Processing.ConsumerTransaction_Quarentine
	(
		FileID
	  , RowNum
	  , ConsumerCombinationID
	  , CardholderPresentData
	  , TranDate
	  , Amount
	  , FanID
	  , CINID
	  --, ProxyUserID
	  --, ProxyMIDTupleID
	  , CurrencyCode
	  , CardholderPresentFlag
	  , CardType
	  , CardholderPostalArea
	  , SourceUID
	  , CardholderPostcodeDistrict
	  , TransSequenceID
	  , OriginatorID
	  , LocationCountry
	  , Narrative
	  , MCCID
	  , locationid
	  , MID
	  --, TempProxyMIDTupleID
	  , MCC
	  , TranTime
	)
	 SELECT
		 ct.FileID
	   , ct.RowNum
	   , NULL															   AS ConsumerCombinationID
	   , ct.CardholderPresentData
	   , ct.TranDate
	   , ct.Amount
	   , c.FanID
	   , ct.CINID													       
	   --, NULL															   AS ProxyMIDTupleID
	   , 'GBP'															   AS CurrencyCode
	   , CardholderPresentData
	   , CASE
			 WHEN
				 ct.PaymentTypeID = 1
			  THEN 'D'
			 WHEN ct.PaymentTypeID = 2
			  THEN 'C'
			 ELSE 'U'
		 END															   AS CardType
	   , c.PostalArea													   AS CardholderPostalArea
	   , c.SourceUID													   AS SourceUID
	   , c.PostcodeDistrict												   AS CardholderPostcodeDistrict
	   , CONCAT('1','-',cast (ct.FileID as varchar),'-', cast(ct.RowNum as varchar)) AS TransSequenceID
	   , ct.OriginatorID
	   , ct.LocationCountry
	   , ct.Narrative
	   , ct.MCCID
	   , ct.locationid
	   , REPLACE([MID], ',', '') AS [MID]
	   --, CAST(HASHBYTES('SHA2_256', CONCAT(ct.MID, mcc.MCC, ct.Narrative, ct.LocationCountry, ct.OriginatorID)) AS BINARY(32))
	   , mcc.MCC
	   ,CONVERT(VARCHAR(8), 
					CAST(
					 RIGHT('0' + CAST(DATEPART(HOUR, t.TransactionTime) AS VARCHAR), 2) + ':' +
					 CASE WHEN DATEPART(MINUTE, t.TransactionTime) < 30 THEN '00' ELSE '30' END + ':00'
					 AS TIME
					), 108
				) AS TranTime
	 FROM [RIPU].Processing.ConsumerTransactionHolding_MIDI_debit ct
	 INNER JOIN RIPU.Processing.CustomersAffinity c
		 ON c.CINID = ct.CINID
			 AND c.rw = 1
	JOIN Warehouse.Relational.MCCList mcc
		ON mcc.MCCID = ct.MCCID
	LEFT JOIN WH_NWG.[WHB].[Inbound_Transactions] t
		ON t.FileID = ct.FileID
		AND t.RowNum = ct.RowNum
	 --INNER JOIN Warehouse.[Relational].[CardholderPresentData] cp
	--	 ON cp.CardholderPresentData = ct.CardholderPresentData
	----------------------------------------------------------------------
	-- Second, insert credit holding trans into quarentine table
	----------------------------------------------------------------------
	--10/10/2025 - AK - Added TranTime field to the select statement below to match debit insert above but will return NULL as credit
		INSERT INTO [RIPU].Processing.ConsumerTransaction_Quarentine
	(
		FileID
	  , RowNum
	  , ConsumerCombinationID
	  , CardholderPresentData
	  , TranDate
	  , Amount
	  , FanID
	  , CINID
	  --, ProxyMIDTupleID
	  , CurrencyCode
	  , CardholderPresentFlag
	  , CardType
	  , CardholderPostalArea
	  , SourceUID
	  , CardholderPostcodeDistrict
	  , TransSequenceID
	  , OriginatorID
	  , LocationCountry
	  , Narrative
	  , MCCID
	  , locationid
	  , MID
	  --, TempProxyMIDTupleID
	  , MCC
	  , TranTime
	)
	 SELECT
		 ct.FileID
	   , ct.RowNum
	   , NULL															   AS ConsumerCombinationID
	   , ct.CardholderPresentData
	   , ct.TranDate
	   , ct.Amount
	   , c.FanID
	   , ct.CINID														   
	   --, NULL															   AS ProxyMIDTupleID
	   , 'GBP'															   AS CurrencyCode
	   , CardholderPresentData
	   , CASE
			 WHEN
				 ct.PaymentTypeID = 1
			  THEN 'D'
			 WHEN ct.PaymentTypeID = 2
			  THEN 'C'
			 ELSE 'U'
		 END															   AS CardType
	   , c.PostalArea													   AS CardholderPostalArea
	   , c.SourceUID													   AS SourceUID
	   , c.PostcodeDistrict												   AS CardholderPostcodeDistrict
	   , CONCAT('1','-',cast (ct.FileID as varchar),'-', cast(ct.RowNum as varchar)) AS TransSequenceID
	   , ct.OriginatorID
	   , ct.LocationCountry
	   , ct.Narrative
	   , ct.MCCID
	   , ct.locationid
	   , REPLACE([MID], ',', '') AS [MID]
	   --, CAST(HASHBYTES('SHA2_256', CONCAT(ct.MID, mcc.MCC, ct.Narrative, ct.LocationCountry, ct.OriginatorID)) AS BINARY(32))
	   , mcc.MCC
	   ,CONVERT(VARCHAR(8), 
					CAST(
					 RIGHT('0' + CAST(DATEPART(HOUR, t.TransactionTime) AS VARCHAR), 2) + ':' +
					 CASE WHEN DATEPART(MINUTE, t.TransactionTime) < 30 THEN '00' ELSE '30' END + ':00'
					 AS TIME
					), 108
				) AS TranTime
	 FROM [RIPU].Processing.ConsumerTransactionHolding_MIDI_Credit ct
	 INNER JOIN RIPU.processing.CustomersAffinity c
		 ON c.CINID = ct.CINID
			 AND c.rw = 1
	JOIN Warehouse.Relational.MCCList mcc
		ON mcc.MCCID = ct.MCCID
	LEFT JOIN WH_NWG.[WHB].[Inbound_Transactions] t
		ON t.FileID = ct.FileID
		AND t.RowNum = ct.RowNum

	----------------------------------------------------------------------
	-- Third, insert from staging table into AWS upload quarentine table additional etl
	----------------------------------------------------------------------
	DROP TABLE IF EXISTS [RIPU].AWSFile.ConsumerTransaction_Quarantine 

	SELECT
		TransSequenceID
        --1 as PublisherID
      --, ct.FileID
	  --, ct.RowNum
	  , ct.CINID
	  , TranDate
	  --, (SELECT CAST(ct.MID AS VARBINARY(MAX))
	--			 FOR XML PATH (''), BINARY BASE64)
		--AS ProxyMID
	  , mcc.MCC
	  , RIPU.processing.RemoveCommas(Narrative) AS MerchantNarrative
	  , ct.locationcountry AS CountryCode
	  , l.LocationAddress As MerchantLocation
	  , p.merchantzip AS MerchantPostcode
	  --, OriginatorReference As OriginatorID --CJ removed 270225, mistake, the field is completely null, unsure why its still in the schema for the table
	  , originatorid as OriginatorID
	  --, CONVERT(VARCHAR(64), ct.TempProxyMIDTupleID, 2) As TemporaryProxyMIDTupleID
	  , amount
	  , CurrencyCode
	  , CardholderPresentData AS CardholderPresentFlag
	  , CASE 
			WHEN cardholderpresentdata = 0 THEN 'P'
			WHEN cardholderpresentdata = 1 THEN 'U'
			WHEN cardholderpresentdata = 2 THEN 'C'
			WHEN cardholderpresentdata = 3 THEN 'C'
			WHEN cardholderpresentdata = 4 THEN 'R'
			WHEN cardholderpresentdata = 5 THEN 'E'
			WHEN cardholderpresentdata = 9 THEN 'N'
			ELSE 'Unknown'
		END AS TerminalType 
	  , CardType
	  , REPLACE([MID], ',', '') AS [MID]
	  , '944' As brandid
	  , [currentagebandtext] =	CASE  
								WHEN c.[AgeCurrent] < 18 OR c.[AgeCurrent] IS NULL THEN '99. Unknown'
								WHEN c.[AgeCurrent] BETWEEN 18 AND 24 THEN '01. 18 to 24'
								WHEN c.[AgeCurrent] BETWEEN 25 AND 34 THEN '02. 25 to 34'
								WHEN c.[AgeCurrent] BETWEEN 35 AND 44 THEN '03. 35 to 44'
								WHEN c.[AgeCurrent] BETWEEN 45 AND 54 THEN '04. 45 to 54'
								WHEN c.[AgeCurrent] BETWEEN 55 AND 64 THEN '05. 55 to 64'
								WHEN c.[AgeCurrent] >= 65 Then '06. 65+'
							END
	  , TranTime --added in final output
	  , NULL AS UpdateType
	  , CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS UpdateDate
	  , CAST(DATEADD(HOUR, -6, GETDATE()) AS DATE) AS LoadDate
	INTO [RIPU].AWSFile.ConsumerTransaction_Quarantine 
	FROM [RIPU].Processing.ConsumerTransaction_Quarentine ct
	JOIN [Warehouse].[Relational].[CINList] cl
		ON cl.CINID = ct.CINID
	join WH_NWG.Derived.Customer c 
		ON c.SourceUID = cl.cin  
	JOIN Warehouse.Relational.MCCList mcc
		ON mcc.MCCID = ct.MCCID
	LEFT JOIN Warehouse.Relational.[Location] l 
		ON ct.LocationID = l.LocationID
	LEFT JOIN [Affinity].[Processing].[MerchantPostcodes] p
		ON ct.mid = p.merchantid
	WHERE NOT EXISTS (  
    SELECT 1
    FROM [Warehouse].[MI].[CINDuplicate] cd  
    WHERE cd.CIN = c.SourceUID  
    AND cd.FanID = c.FanID  
)
	AND c.CurrentlyActive = 1
	

	INSERT INTO 
		[RIPU].[Processing].[RowNum_Log] (fileid, rownum)
	SELECT fileid, rownum FROM [Ripu].Processing.ConsumerTransactionHolding_MIDI_Debit
	UNION ALL
	SELECT fileid, rownum FROM [RIPU].Processing.ConsumerTransactionHolding_MIDI_Credit;
END
