USE [RIPU]
GO
/****** Object:  StoredProcedure [Staging].[CustomerAddressesHistoric_Load]    Script Date: 19/08/2026 10:24:26 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [Staging].[CustomerAddressesHistoric_Load]
AS 
BEGIN

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED


DROP TABLE if EXISTS RIPU.staging.CustomerAddressesHistoric;

WITH BaseData AS (
    SELECT *
    FROM WH_NWG.Inbound.CustomerAddresses
    WHERE CAST(LoadDate AS DATE) >= '2022-04-01'
),
sourceuids AS (SELECT	cei.[CustomerGUID]
	,	[SourceUID] = cei.[ExternalID]
FROM [WH_NWG].[WHB].[Inbound_CustomerExternalIDs] cei
WHERE cei.[ExternalIDSource] IN ('backbook', 'natwest', 'royalbank')
),

RecordsWithLag AS (
    -- Compare each record's UpdatedAt to the previous record's UpdatedAt (ordered by LoadDate)
    SELECT *,
           LAG(UpdatedAt) OVER (PARTITION BY CustomerGUID ORDER BY LoadDate) AS PrevUpdatedAt
    FROM BaseData
),

FinalSet AS (
    -- Include: first record for each customer (PrevUpdatedAt IS NULL) OR records where UpdatedAt actually changed
    -- Also validate postcode length to avoid incomplete postcodes blocking fallback to customer_pii
    SELECT *,
           LEAD(UpdatedAt) OVER (PARTITION BY CustomerGUID ORDER BY UpdatedAt) AS NextUpdatedAt
    FROM RecordsWithLag
    WHERE (UpdatedAt <> PrevUpdatedAt OR PrevUpdatedAt IS NULL)
    AND LEN(TRIM(PostCode)) >= 6
),

-- Get customers from customer_pii that don't exist in InboundCustomerAddresses
MissingCustomersFromPII AS (
    SELECT 
        c.CustomerGUID,
        c.Address1,
        c.Address2,
        c.PostCode,
        NULL AS UpdatedAt,
        NULL AS NextUpdatedAt,
        cl.CINID
    FROM WH_NWG.derived.customer_pii c
    INNER JOIN warehouse.relational.CINList cl
        ON c.SourceUID = cl.CIN
    WHERE c.CustomerGUID NOT IN (
        SELECT DISTINCT CustomerGUID
        FROM BaseData
    )
    AND c.SourceUID NOT IN (
        SELECT SourceUID
        FROM [WH_NWG].[Derived].[Customer_DuplicateSourceUID] du
        WHERE [EndDate] IS NULL
    )
    AND cl.CINID NOT IN (
        SELECT CINID
        FROM RIPU.Derived.cinid_exclude_nw_migration
    )
    AND cl.CINID NOT IN (
        SELECT DISTINCT cl2.CINID
        FROM FinalSet f
        INNER JOIN sourceuids c2
            ON f.CustomerGUID = c2.CustomerGUID
        INNER JOIN WH_NWG.Derived.CINList cl2
            ON cl2.CIN = c2.SourceUID
    )
)

SELECT DISTINCT
    cl.CINID,
    f.CustomerAddress1,
    f.CustomerAddress2,
    f.CustomerAddress3,
    f.PostCode,
    f.UpdatedAt,
    f.NextUpdatedAt
INTO RIPU.staging.CustomerAddressesHistoric
FROM FinalSet f
INNER JOIN sourceuids c
    ON f.CustomerGUID = c.CustomerGUID
INNER JOIN WH_NWG.Derived.CINList cl
	ON cl.CIN = c.SourceUID

UNION ALL

SELECT DISTINCT
    mcp.CINID,
    mcp.Address1,
    mcp.Address2,
    NULL,
    mcp.PostCode,
    mcp.UpdatedAt,
    mcp.NextUpdatedAt
FROM MissingCustomersFromPII mcp;

END;