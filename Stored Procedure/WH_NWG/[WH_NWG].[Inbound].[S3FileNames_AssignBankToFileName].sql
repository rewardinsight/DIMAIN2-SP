USE [WH_NWG]
GO
/****** Object:  StoredProcedure [Inbound].[S3FileNames_AssignBankToFileName]    Script Date: 24/08/2026 16:29:57 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [Inbound].[S3FileNames_AssignBankToFileName]
AS
BEGIN

UPDATE s3
SET s3.[FileName] =	CASE
						WHEN s3.[FilePath] LIKE 'offers/royalbank%' THEN 'ROYALBANK_DIMAIN_' + s3.[FileName]
						WHEN s3.[FilePath] LIKE 'offers/natwest%' THEN 'NATWEST_DIMAIN_' + s3.[FileName]
						ELSE s3.[FileName]
					END
FROM [Inbound].[S3FileNames] s3
WHERE s3.[FileName] LIKE 'BurnCollateral_%'
OR s3.[FileName] LIKE 'EarnCollateral_%'

END