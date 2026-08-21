USE [WH_NWG]
GO
/****** Object:  StoredProcedure [Inbound].[S3FileNames_Update]    Script Date: 8/21/2026 3:31:58 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [Inbound].[S3FileNames_Update]	@Script NVARCHAR(4000)
AS
BEGIN

	--	DECLARE @Script NVARCHAR(4000);

		DROP TABLE IF EXISTS #Output;
		CREATE TABLE #Output ([Message] VARCHAR(MAX))

		INSERT #Output
		EXEC xp_cmdshell @Script

END
