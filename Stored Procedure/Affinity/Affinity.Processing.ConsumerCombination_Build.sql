USE [Affinity]
GO
/****** Object:  StoredProcedure [Processing].[ConsumerCombination_Build]    Script Date: 9/3/2026 1:25:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/******************************************************************************
-- Author:		Hayden Reid
-- Create date: 01/09/2020
-- Description:	Empties, inserts and recreates index on the ConsumerCombination table
				from Warehouse.

				Columns are transformed according to specifications and loaded with
				appropriate debugging columns included (especially in relation to
				how a combination was masked, if at all)

				Raw Transactions for: YYYY_MM_DD-Daily.csv

------------------------------------------------------------------------------
Modification History

[Date] [User]
	- [Description]

******************************************************************************/
ALTER PROCEDURE [Processing].[ConsumerCombination_Build]
AS 
BEGIN

		SET NOCOUNT ON

	DECLARE @RowCount INT -- Logging row count
	
	INSERT INTO dbo.MIDTupleID (ConsumerCombinationID, ProxyMIDTupleID, ProxyMID, LocationCountry, Narrative, OriginatorID, MCC, MID)
	SELECT
		cc.ConsumerCombinationID
	   , HASHBYTES(
			'SHA2_256'
			, CONCAT(cc.LocationCountry, cc.Narrative, cc.OriginatorID, mcc.mcc, cc.MID)
		) AS ProxyMIDTupleID -- Hashed according to spec
	   , (
			 SELECT
				 CAST(cc.MID AS VARBINARY(MAX))
			 FOR XML PATH (''), BINARY BASE64
		 )																							   
		 AS ProxyMID -- Encoded according to spec
		, cc.LocationCountry
		, cc.Narrative
		, cc.OriginatorID
		, mcc.MCC
		, cc.MID
	FROM Warehouse.Relational.ConsumerCombination cc
	LEFT JOIN Warehouse.Relational.MCCList mcc	
		ON mcc.MCCID = cc.MCCID
	WHERE NOT EXISTS (
		SELECT 1
		FROM dbo.MIDTupleID mti
		WHERE cc.ConsumerCombinationID = mti.ConsumerCombinationID
	)

	----------------------------------------------------------------------
	-- Clear Down
	----------------------------------------------------------------------
	TRUNCATE TABLE Processing.ConsumerCombination;

	IF EXISTS (
		SELECT 1
		FROM sys.indexes 
		WHERE name='cix_Processing_consumercombination' AND object_id = OBJECT_ID('Processing.ConsumerCombination')
	)
		DROP INDEX cix_Processing_consumercombination ON [Processing].[consumercombination]

	----------------------------------------------------------------------
	-- Staging table of transformed columns
	----------------------------------------------------------------------
	IF OBJECT_ID('tempdb..#RelationalCombos') IS NOT NULL
		DROP TABLE #RelationalCombos

	SELECT
		cc.*
		, mti.ProxyMIDTupleID -- Hashed according to spec
		, mti.ProxyMID -- Encoded according to spec
		, mcc.MCC
		, ROW_NUMBER() OVER (
			PARTITION BY cc.MID, cc.BrandID 
			ORDER BY cc.ConsumerCombinationID DESC
		) AS rw -- for nFI transactions because there is only a brandid/mid to join
		, REPLACE(REPLACE(p.MerchantZip, CHAR(9), ' '), CHAR(10), ' ') AS MerchantZip -- Some Zips have newlines which will break the csv
		, l.LocationAddress
		, b.BrandName
	INTO #RelationalCombos
	FROM Warehouse.Relational.ConsumerCombination cc
	JOIN dbo.MIDTupleID mti
		ON cc.ConsumerCombinationID = mti.ConsumerCombinationID
	LEFT JOIN Warehouse.Relational.MCCList mcc	
		ON mcc.MCCID = cc.MCCID
	LEFT JOIN Processing.MIDTupleConversion mmt
		ON cc.ConsumerCombinationID = mmt.ConsumerCombinationID
	LEFT JOIN Processing.MerchantPostcodes p 
		ON cc.MID = p.MerchantID
	LEFT JOIN Processing.MerchantLocation l 
		ON l.ConsumerCombinationID = cc.ConsumerCombinationID
	LEFT JOIN Warehouse.Relational.Brand b 
		ON b.BrandID = cc.BrandID


	CREATE UNIQUE CLUSTERED INDEX cix_tempdb_relationalcombo ON #RelationalCombos (ConsumerCombinationID)


	----------------------------------------------------------------------
	-- Insert
	----------------------------------------------------------------------
	INSERT INTO Processing.ConsumerCombination 
	(
		ConsumerCombinationID
	  , BrandMIDID
	  , BrandID
	  , MID
	  , Narrative
	  , LocationCountry
	  , MCCID
	  , OriginatorID
	  , IsHighVariance
	  , IsUKSpend
	  , PaymentGatewayStatusID
	  , IsCreditOrigin
	  , MerchantZip
	  , MCC
	  , BrandName
	  , LocationAddress
	  , RowNum
	  , ProxyMIDTupleID
	  , ProxyMID
	  , MaskedNarrative
	  , isBlanketMasked
	  , isSensitiveMasked
	  , isHeavyMasked
	  , isLightMasked
	)

	SELECT 
		x.ConsumerCombinationID
		, x.BrandMIDID
		, x.BrandID
		, x.MID
		, UPPER(x.Narrative) AS Narrative
		, x.LocationCountry
		, x.MCCID
		, x.OriginatorID
		, x.IsHighVariance
		, x.IsUKSpend
		, x.PaymentGatewayStatusID
		, x.IsCreditOrigin
		, x.MerchantZip
		, x.MCC
		, x.BrandName
		, x.LocationAddress 
		, x.rw AS RowNum
		, x.ProxyMIDTupleID
		, x.ProxyMID
		, UPPER(COALESCE(ccm.MaskedNarrative, x.Narrative)) AS MaskedNarrative
		, COALESCE(ccm.isBlanketMasked, 0)
		, COALESCE(ccm.isSensitiveMasked, 0)
		, COALESCE(ccm.isHeavyMasked, 0)
		, COALESCE(ccm.isLightMasked, 0)
	FROM #RelationalCombos x
	LEFT JOIN dbo.ConsumerCombination_Masked ccm
		ON ccm.ConsumerCombinationID = x.ConsumerCombinationID

	SELECT @RowCount = @@RowCount

	----------------------------------------------------------------------
	-- Recreate index
	----------------------------------------------------------------------
	CREATE UNIQUE CLUSTERED INDEX cix_Processing_consumercombination ON Processing.ConsumerCombination (ConsumerCombinationID)

	RETURN @RowCount


END


