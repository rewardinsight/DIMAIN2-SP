USE [WH_NWG]
GO
/****** Object:  StoredProcedure [Inbound].[S3FileNames_Braze_AssignFileType]    Script Date: 24/08/2026 16:30:09 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [Inbound].[S3FileNames_Braze_AssignFileType]
AS
BEGIN

UPDATE s3
SET s3.[EventChannelID] = et.[EventChannelID]
,	s3.[EventTypeID] = et.[EventTypeID]
,	s3.[FileName] = SUBSTRING(fpt.[FilePath_Trimmed], fpt_l.[FileType_End] + 1, 999)
FROM [Inbound].[S3FileNames_Braze] s3
CROSS APPLY (	SELECT	[FilePath_Trimmed] = REPLACE(s3.[FilePath], 'currents/dataexport.prod-02.S3.integration.68d3e158195d710722161651/event_type=', '')) fpt
CROSS APPLY (	SELECT	[FileType_End] = PATINDEX('%/date=%', fpt.[FilePath_Trimmed])) fpt_l
LEFT JOIN [WH_AllPublishers].[WHB].[BrazeExports_EventTypes] et
	ON s3.[FilePath] LIKE '%' + et.[EventName] + '%'
WHERE s3.[EventTypeID] IS NULL

END

