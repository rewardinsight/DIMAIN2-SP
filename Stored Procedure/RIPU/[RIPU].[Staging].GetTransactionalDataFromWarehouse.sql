USE [RIPU]
GO
/****** Object:  StoredProcedure [Staging].[GetTransactionalDataFromWarehouse]    Script Date: 19/08/2026 10:28:31 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
Conor Donnelly 23/02/2024
Grabs new transactions from Warehouse MIDI job
*/
ALTER PROCEDURE [Staging].[GetTransactionalDataFromWarehouse]

AS

SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

-- Copy data from holding tables to RIPU
INSERT INTO Staging.ConsumerTransactionHolding WITH (TABLOCKX)
	(FileID, RowNum, ConsumerCombinationID, CardholderPresentData,
	TranDate, CINID, Amount, IsOnline, PaymentTypeID)
SELECT 
	FileID, RowNum, ConsumerCombinationID, CardholderPresentData,
	TranDate, CINID, Amount, IsOnline, 1
FROM Warehouse.Relational.ConsumerTransactionHolding ct
WHERE NOT EXISTS (SELECT 1 FROM RIPU.Staging.ConsumerTransactionHolding a WHERE a.FileID = ct.FileID AND a.RowNum = ct.RowNum)
-- (4,3196,778 rows affected) / 00:03:00

INSERT INTO Staging.ConsumerTransaction_CreditCardHolding WITH (TABLOCKX)
	(FileID, RowNum, ConsumerCombinationID, CardholderPresentData, 
	TranDate, CINID, Amount, IsOnline, PaymentTypeID)
SELECT 
	FileID, RowNum, ConsumerCombinationID, CardholderPresentData, 
	TranDate, CINID, Amount, IsOnline, 2
FROM Warehouse.Relational.ConsumerTransaction_CreditCardHolding ct
WHERE NOT EXISTS (SELECT 1 FROM RIPU.Staging.ConsumerTransaction_CreditCardHolding a WHERE a.FileID = ct.FileID AND a.RowNum = ct.RowNum)
-- (334,116 rows affected) / 00:00:15


RETURN 0

