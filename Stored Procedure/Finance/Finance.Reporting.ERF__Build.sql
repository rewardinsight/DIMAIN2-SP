USE [Finance]
GO
/****** Object:  StoredProcedure [Reporting].[ERF__Build]    Script Date: 9/1/2026 11:59:25 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [Reporting].[ERF__Build]
(
	@ReportDate DATE = NULL
)
AS
BEGIN
	/**********************************************************************
	Currently just doing the assumed queries that are required
	-- more steps to follow but this is the main section
	***********************************************************************/

	DECLARE @Date DATE
	IF @ReportDate IS NULL
	BEGIN
		SET @Date = DATEADD(MONTH, DATEDIFF(MONTH, 0, GETDATE()), 0)
		SET @Date = DATEADD(DAY, -1, @Date)
	END
	ELSE
		SET @Date = @ReportDate

	--SET @Date = '2022-03-31'

	----------------------------------------------------------------------
	-- Customers
	----------------------------------------------------------------------
	DROP TABLE IF EXISTS #EligibleDates
	SELECT
		1 AS EligibleID, 'Earnings Eligible for Redemption' AS EligibleType, CAST('1900-01-01' AS DATE) StartDate, @Date EndDate
	INTO #EligibleDates
	UNION ALL
	SELECT
		2 AS EligibleID, 'Potential Cashback Liability', DATEADD(DAY, 1, @Date), '9999-01-01'

	DROP TABLE IF EXISTS #Customers
	SELECT 
		c.CustomerID
		, db.DeactivatedBandID
		, db.DeactivatedBand
		, c.PublisherID
	INTO #Customers
	FROM dbo.Customer c
	JOIN dbo.DeactivatedBand db
		ON DATEDIFF(DAY, c.DeactivatedDate, @Date) BETWEEN db.DeactivatedBandMin AND db.DeactivatedBandMax
		OR (DeactivatedDate IS NULL AND db.DeactivatedBandID = -1)

	CREATE CLUSTERED INDEX CIX ON #Customers (CustomerID)

	DROP TABLE IF EXISTS #CustomerPaymentMethods
	SELECT
		CustomerID
		, CAST(PaymentMethodsAvailableID AS BIT) AS isCreditCardOnly
		, StartDate
		, ISNULL(EndDate, '9999-12-31') AS EndDate
	INTO #CustomerPaymentMethods
	FROM [WH_NWG].[Derived].[Customer_PaymentMethodsAvailable] cpma
	JOIN dbo.Customer c
		ON c.SourceID = cpma.FanID
	JOIN dbo.SourceType st
		ON c.SourceTypeID = st.SourceTypeID
		AND st.SourceSystemID = 1
	WHERE cpma.PaymentMethodsAvailableID = 1

	CREATE CLUSTERED INDEX CIX ON #CustomerPaymentMethods (CustomerID)

	----------------------------------------------------------------------
	-- Spend and Earn
	----------------------------------------------------------------------
	
	DROP TABLE IF EXISTS Reporting.ERF_Earnings
	SELECT 
		te.PublisherID
		, te.PaymentMethodID
		, te.EarningSourceID
		, pc.PaymentCardType
		, ed.EligibleType
		, ed.EligibleID
		, c.DeactivatedBand
		, c.DeactivatedBandID
		, ISNULL(cpm.isCreditCardOnly, 0) AS isCreditCardOnly
		, SUM(Earning) Earning
		, COUNT(1) AS TranCount
		, SUM(Spend) AS Spend
		, DATEADD(MONTH, DATEDIFF(MONTH, 0, TranDate), 0) AS MonthDate
	INTO Reporting.ERF_Earnings
	FROM dbo.Transactions te
	JOIN #Customers c
		ON te.CustomerID = c.CustomerID
	JOIN #EligibleDates ed
		ON te.EligibleDate BETWEEN ed.StartDate AND ed.EndDate
	JOIN dbo.PaymentCard pc
		ON te.PaymentCardID = pc.PaymentCardID
	LEFT JOIN #CustomerPaymentMethods cpm
		ON c.CustomerID = cpm.CustomerID
		AND te.EligibleDate BETWEEN cpm.StartDate and cpm.EndDate
	--WHERE te.EarningSourceID NOT IN 
	--	(
	--		2160 -- Breakage - Optout (from SLCPointsNegative)
	--		, 2158 -- Breakage - Deceased (from SLCPointsNegative)
	--		, 2159 -- Breakage - Deactivation (from SLCPointsNegative)
	--		, 2174 -- Breakage Negative Adjustment (from TransactionType)
	--	)
	WHERE te.[EarningSourceID] NOT IN (	2110, 2158, 14761 -- Breakage - Optout (from SLCPointsNegative)
									,	2159, 2111 -- Breakage - Deceased (from SLCPointsNegative)
									,	2112, 2160 -- Breakage - Deactivation (from SLCPointsNegative)
									,	14864, 2174 -- Breakage Negative Adjustment (from TransactionType)
									,	2173 -- Breakage Positive Adjustment
								)
	GROUP BY te.PublisherID
		, te.PaymentMethodID
		, te.EarningSourceID
		, pc.PaymentCardType
		, ed.EligibleType
		, ed.EligibleID
		, c.DeactivatedBand
		, c.DeactivatedBandID
		, ISNULL(cpm.isCreditCardOnly, 0)
		, DATEADD(MONTH, DATEDIFF(MONTH, 0, TranDate), 0)


	----------------------------------------------------------------------
	-- Reductions
	----------------------------------------------------------------------
	DROP TABLE IF EXISTS Reporting.ERF_Reductions

	SELECT  
		r.PublisherID
		, r.PaymentMethodID
		, r.EarningSourceID
		, pc.PaymentCardType
		, ed.EligibleType
		, ed.EligibleID
		, c.DeactivatedBand
		, c.DeactivatedBandID
		, ISNULL(cpm.isCreditCardOnly, 0) AS isCreditCardOnly
		, DATEADD(MONTH, DATEDIFF(MONTH, 0, r.ReductionDate), 0) MonthDate
		, SUM(CASE WHEN r.isBreakage = 0 THEN r.EarningAllocated ELSE 0 END) AS EarningsAllocated
		, SUM(CASE WHEN r.isBreakage = 1 THEN r.EarningAllocated ELSE 0 END) AS BreakageAllocated
	INTO Reporting.ERF_Reductions
	FROM FIFO.ReductionAllocations r
	JOIN #Customers c
		ON r.CustomerID = c.CustomerID
	JOIN #EligibleDates ed
		ON r.EarningDate BETWEEN ed.StartDate AND ed.EndDate
	JOIN dbo.PaymentCard pc
		ON r.PaymentCardID = pc.PaymentCardID
	LEFT JOIN #CustomerPaymentMethods cpm
		ON c.CustomerID = cpm.CustomerID
		AND r.TranDate BETWEEN cpm.StartDate and cpm.EndDate
	--WHERE ReductionDate <= @Date
	GROUP BY r.PublisherID
		, r.PaymentMethodID
		, r.EarningSourceID
		, pc.PaymentCardType
		, ed.EligibleType
		, ed.EligibleID
		, c.DeactivatedBand
		, c.DeactivatedBandID
		, ISNULL(cpm.isCreditCardOnly, 0)
		, DATEADD(MONTH, DATEDIFF(MONTH, 0, r.ReductionDate), 0)

	
	----------------------------------------------------------------------
	-- Cashback Totals
	----------------------------------------------------------------------
	
	DROP TABLE IF EXISTS #EarnRedeem
	SELECT
		ISNULL(r.PublisherID, e.PublisherID) AS PublisherID
		, ISNULL(r.PaymentMethodID, e.PaymentMethodID) AS PaymentMethodID
		, ISNULL(r.EarningSourceID, e.EarningSourceID) AS EarningSourceID
		, ISNULL(r.PaymentCardType, e.PaymentCardType) AS PaymentCardType
		, ISNULL(r.EligibleType, e.EligibleType) AS EligibleType
		, ISNULL(r.EligibleID, e.EligibleID) AS EligibleID
		, ISNULL(r.DeactivatedBand, e.DeactivatedBand) AS DeactivatedBand
		, ISNULL(r.DeactivatedBandID, e.DeactivatedBandID) AS DeactivatedBandID
		, ISNULL(r.isCreditCardOnly, e.isCreditCardOnly) AS isCreditCardOnly
		, ISNULL(r.MonthDate, e.MonthDate) AS MonthDate
		, ISNULL(SUM(e.Earning), 0)			AS Earnings
		, ISNULL(SUM(r.EarningsAllocated), 0) AS EarningsAllocated
		, ISNULL(SUM(r.BreakageAllocated), 0) AS BreakageAllocated
	INTO #EarnRedeem
	FROM Reporting.ERF_Reductions r
	FULL OUTER JOIN Reporting.ERF_Earnings e
		ON r.PublisherID = e.PublisherID 
		AND r.PaymentMethodID = e.PaymentMethodID
		AND r.EarningSourceID = e.EarningSourceID
		AND r.PaymentCardType = e.PaymentCardType
		AND r.EligibleType = e.EligibleType 
		AND r.EligibleID = e.EligibleID 
		AND r.DeactivatedBand = e.DeactivatedBand 
		AND r.DeactivatedBandID = e.DeactivatedBandID 
		AND r.isCreditCardOnly = e.isCreditCardOnly
		AND r.MonthDate = e.MonthDate
	GROUP BY ISNULL(r.PublisherID, e.PublisherID) 
		, ISNULL(r.PaymentMethodID, e.PaymentMethodID)
		, ISNULL(r.EarningSourceID, e.EarningSourceID)
		, ISNULL(r.PaymentCardType, e.PaymentCardType)
		, ISNULL(r.EligibleType, e.EligibleType) 
		, ISNULL(r.EligibleID, e.EligibleID) 
		, ISNULL(r.DeactivatedBand, e.DeactivatedBand) 
		, ISNULL(r.DeactivatedBandID, e.DeactivatedBandID) 
		, ISNULL(r.isCreditCardOnly, e.isCreditCardOnly)
		, ISNULL(r.MonthDate, e.MonthDate)

	DROP TABLE IF EXISTS Reporting.ERF_CashbackTotals
	;WITH Tbl
	AS
	(
		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.Earnings) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, 'Total' AS ColumnName
			, 1 AS ColumnID
		FROM #EarnRedeem r

		UNION ALL

		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.EarningsAllocated) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, 'Redeemed' AS ColumnName
			, 2 AS ColumnID
		FROM #EarnRedeem r


		UNION ALL

		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.BreakageAllocated) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, 'Breakage' AS ColumnName
			, 99 AS ColumnID
		FROM #EarnRedeem r
	

		UNION ALL

		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.Earnings - r.EarningsAllocated - r.BreakageAllocated) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, 'Unredeemed Earnings' AS ColumnName
			, 3 AS ColumnID
		FROM #EarnRedeem r


		UNION ALL

		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.Earnings - r.EarningsAllocated - r.BreakageAllocated) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
						, r.EligibleID
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, EligibleType AS ColumnName
			, 3+EligibleID AS ColumnID
		FROM #EarnRedeem r
		WHERE DeactivatedBandID < 0

		UNION ALL

		SELECT DISTINCT
			r.PublisherID
			, r.PaymentMethodID
			, r.EarningSourceID
			, r.PaymentCardType
			, r.isCreditCardOnly
			, SUM(r.Earnings - r.EarningsAllocated - r.BreakageAllocated) 
				OVER (PARTITION BY 
						r.PublisherID
						, r.PaymentMethodID
						, r.EarningSourceID
						, r.PaymentCardType
						, r.isCreditCardOnly 
						, r.DeactivatedBandID
					ORDER BY r.MonthDate
				) AS Earnings
			, MonthDate
			, DeactivatedBand AS ColumnName
			, 5+DeactivatedBandID AS ColumnID
		FROM #EarnRedeem r
		WHERE DeactivatedBandID > 0
	)
	SELECT 
		t.* 
	INTO Reporting.ERF_CashbackTotals
	FROM Tbl t
	
END





