USE [WH_Mashreq]
GO
/****** Object:  StoredProcedure [MIDI].[ConsumerCombination_Insert]    Script Date: 9/8/2026 1:38:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [MIDI].[ConsumerCombination_Insert] 
AS
BEGIN

DROP TABLE IF EXISTS #ConsumerCombination
SELECT	DISTINCT 
		[BrandID] = [UpdatedBrandID]
	,	[MID]
	,	[UpdatedNarrative]
	,	[LocationCountry]
	,	[MCCID]
	,	[OriginatorID]
	,	[IsHighVariance]
	,	[IsUKSpend]
	,	[PaymentGatewayStatusID] =	CASE
										WHEN [UpdatedBrandID] = 943 THEN CONVERT(TINYINT, 2)
										WHEN [OriginalNarrative] LIKE '%PP*%' THEN CONVERT(TINYINT, 2)
										WHEN [OriginalNarrative] LIKE '%PayPal*%' THEN CONVERT(TINYINT, 2)
										ELSE CONVERT(TINYINT, 0)
									END
INTO #ConsumerCombination
FROM [MIDI].[CTLoad_MIDINewCombo] mnc
WHERE NOT EXISTS (	SELECT 1
					FROM [Trans].[ConsumerCombination] cc
					WHERE mnc.[MID] = cc.[MID]
					AND mnc.[UpdatedNarrative] = cc.[Narrative]
					AND mnc.[LocationCountry] = cc.[LocationCountry]
					AND mnc.[OriginatorID] = cc.[OriginatorID]
					AND mnc.[MCCID] = cc.[MCCID])
AND [UpdatedBrandID] IS NOT NULL
AND [UpdatedNarrative] IS NOT NULL

--	INSERT INTO [Trans].[ConsumerCombination]
SELECT	cc.[BrandID]
	,	cc.[MID]
	,	cc.[UpdatedNarrative]
	,	cc.[LocationCountry]
	,	cc.[MCCID]
	,	cc.[OriginatorID]
	,	cc.[IsHighVariance]
	,	cc.[IsUKSpend]
	,	cc.[PaymentGatewayStatusID]
	,	[ModifiedDate] = GETDATE()
FROM #ConsumerCombination cc
ORDER BY	(SELECT [BrandName] FROM [WH_AllPublishers].[Trans].[Brand] br WHERE cc.[BrandID] = br.[BrandID])
		,	cc.[MID]
		,	cc.[UpdatedNarrative]

END

