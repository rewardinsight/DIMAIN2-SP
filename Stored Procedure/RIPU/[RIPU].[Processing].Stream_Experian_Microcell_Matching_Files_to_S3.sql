USE [RIPU]
GO
/****** Object:  StoredProcedure [Processing].[Stream_Experian_Microcell_Matching_Files_to_S3]    Script Date: 19/08/2026 10:07:33 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO








ALTER PROCEDURE [Processing].[Stream_Experian_Microcell_Matching_Files_to_S3]
(
    @Directory VARCHAR(MAX) = ''
    , @additionalParams VARCHAR(MAX) = ''
)
AS
BEGIN

    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED --  
    DECLARE @sql varchar(4000)

    IF CHARINDEX(':', @Directory) = 0
        SET @Directory = 'E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-stream-mosaic'

    SET @Directory = REPLACE(@Directory, ' ', '" "')

    SET @sql = 'python "E:\DataOpsFunctions\RIRUPipelne\reward-dataops-dimain-s3-stream-mosaic\run_export_Experian_Microcell_Matching_Files.py"'

    --set @sql = 'whoami'

    IF OBJECT_ID('tempdb..#Output') IS NOT NULL DROP TABLE #Output; CREATE TABLE #output (line varchar(max))
    INSERT #output EXEC xp_cmdshell @sql

    DECLARE @RunID INT
    SELECT @RunID = NEXT VALUE FOR logs.RIRUPipeline_StreamToS3_Log_RunID_V2

    DECLARE @ErrorString VARCHAR(100) = '%Traceback%'
    DECLARE @ErrorString2 VARCHAR(100) = '%Error[^A-Z]%'

    IF OBJECT_ID('tempdb..#Log') IS NOT NULL
        DROP TABLE #Log

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

    INSERT INTO logs.RIRUPipeline_Log_V2 (Msg, isError, CreatedDateTime, RunID)
    SELECT
        Msg
        , isError
        , CreatedDateTime
        , RunID
    FROM #Log

    IF (SELECT TOP 1 1 FROM #Log where isError = 1) IS NOT NULL
    BEGIN

        DECLARE @Error VARCHAR(MAX)

        SELECT
            @Error = STUFF((
                    SELECT ' ' + msg
                    FROM #Log
                    ORDER BY LogID 
                    FOR XML PATH ('')
                ), 1, 1, '')
    
        DECLARE @ErrorEnd VARCHAR(300) = '... SELECT * FROM master.dbo.RIRUPipeline_Log_V2 WHERE RunID =' + CAST(@RunID AS varchar) + ' for more info'
        DECLARE @ErrorOutput VARCHAR(4096) = RIGHT(@Error, 1999 - LEN(@ErrorEnd)) + @ErrorEnd -- max is 2048 NVARCHAR

        ;THROW 100000, @ErrorOutput,1


    END

    DECLARE @Msg VARCHAR(300) = 'SELECT * FROM master.dbo.RIRUPipeline_Log_V2 WHERE RunID = ' + CAST(@RunID AS varchar) + ' for more info'
    RAISERROR(@Msg, 1, -1, -1)
END
