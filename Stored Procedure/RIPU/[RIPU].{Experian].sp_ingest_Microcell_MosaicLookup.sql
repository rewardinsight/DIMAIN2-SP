USE [RIPU]
GO
/****** Object:  StoredProcedure [Experian].[sp_ingest_Microcell_MosaicLookup]    Script Date: 18/08/2026 16:31:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER procedure [Experian].[sp_ingest_Microcell_MosaicLookup] as

DECLARE @code varchar(1000)
SET @code = 'python "C:\SSIS\ExperianRIPUPipeline\microcell_mosaiclookup_sftp_to_dimain.py"'

IF OBJECT_ID('tempdb..#Output') IS NOT NULL DROP TABLE #Output; 
CREATE TABLE #output (line varchar(max));
INSERT #output EXEC xp_cmdshell @code

DECLARE @RunID INT = 1
DECLARE @ErrorString VARCHAR(100) = '%Traceback%'
DECLARE @ErrorString2 VARCHAR(100) = '%Error[^A-Z]%'
IF OBJECT_ID('tempdb..#Log') IS NOT NULL DROP TABLE #Log;
CREATE TABLE #Log
(
    [LogID] [int] IDENTITY(1,1) NOT NULL,
    [RunID] [int] NOT NULL,
    [Msg] [varchar](max) NULL,
    [CreatedDateTime] [datetime2](7) NOT NULL,
    [isError] [bit] NOT NULL
)
INSERT INTO #Log (Msg, isError, CreatedDateTime, RunID)
SELECT 
    o.line
    , x.isError
    , GETDATE() AS InsertedDate
    , @RunID
FROM #output o
CROSS APPLY (
    SELECT CAST(COALESCE(MAX(1), 0) AS BIT)
    FROM #output
    WHERE line like @ErrorString
        or line like @ErrorString2
) x(isError)
;
select * from #Log
--if needed can add the below to a running log, not atm though
