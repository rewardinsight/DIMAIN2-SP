USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[DD_Daily_upload_Process_v3]    Script Date: 18/08/2026 16:38:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [Processing].[DD_Daily_upload_Process_v3]

AS 

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @Subject VARCHAR(8000)

DECLARE	@Time DATETIME,	@Msg VARCHAR(2048), @SSMS BIT = 1
EXEC master.dbo.oo_TimerMessagev2 'Start Processing.DD_Daily_upload_Process_v2', @Time OUTPUT, @SSMS OUTPUT

-- creation of daily Merchant Details File for Affinity daily load (CIP Pipeline)


	DROP TABLE if exists RIPU.AWSFile.Consumercombination_dd_v3;
		SELECT DISTINCT
		ccd.ConsumerCombinationID_DD,
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
		REPLACE(
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
			END,
		',','') AS Narrative
		into RIPU.AWSFile.Consumercombination_dd_v3
		FROM [Warehouse].[Relational].[ConsumerCombination_DD] ccd
		LEFT JOIN [Warehouse].[Relational].[Brand] br2
			ON ccd.[BrandID] = br2.[BrandID]
