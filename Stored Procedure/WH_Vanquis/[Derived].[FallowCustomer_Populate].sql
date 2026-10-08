USE [WH_Vanquis]
GO
/****** Object:  StoredProcedure [Derived].[FallowCustomer_Populate]    Script Date: 10/8/2026 9:23:28 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [Derived].[FallowCustomer_Populate] 

AS
BEGIN

	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;


DECLARE @ForceRefresh int = 0; -- setting this to 1 refreshes all the temp tables (Included in case part of the script fails so that it isn't necessary to wait for previously loaded tables to load)
DECLARE @ControlSize float = 0.1; --Agreed size (as a % of the total marketable base) 
DECLARE @FallowPeriod_Cycles int = 6 --How long customers should be in fallow for (in cycles not months) ;
DECLARE @NewCustomerMaxTenure_Months int = 2; --How long customers should be excluded from registration
DECLARE @RegistrationCutOffDate date = GETDATE() -- For WH_BarclaysBlue only - filter out customers who registered post September 2024
DECLARE @ExclusionPeriod_Cycles int = 13 -- How long customers should be barred for re-entry once they've been in the group (in cycles)

DECLARE @EndDate date
DECLARE @StartDate date 
DECLARE @sqlcmd VARCHAR(MAX); 
DECLARE @EmailKeyCount int;
DECLARE @EmailSendCount1 int;
DECLARE @EmailSendCount2 int;
DECLARE @QuarterlyEmailCount int;

DECLARE @WhileStartDate AS DATE = '2022-12-01'
DECLARE @WhileEndDate AS DATE = DATEADD(year,20,@WhileStartDate)
DECLARE @CurrentDate AS DATE = @WhileStartDate
DECLARE @LatestCycleStartDate date

--THIS SECTION ENSURES THE CONTROL SIZE % IS DYNAMIC--
DECLARE @ControlLOG int = ABS(FLOOR(LOG(@ControlSize,10)))+1;
DECLARE @SplitSize int = POWER(10,@ControlLOG);
DECLARE @ControlPick int = (@ControlSize * @SplitSize) - 1;

IF OBJECT_ID('tempdb..#PreviousFallowTableHere') IS NOT NULL

BEGIN
SET @SplitSize = @SplitSize - (@ControlPick + 1)
END
--------------------------------------------------------------------------
--							TABLE DROPS									--
--------------------------------------------------------------------------

DROP TABLE IF EXISTS #CycleStartDates

IF @ForceRefresh = 1

BEGIN

	DROP TABLE IF EXISTS #MarketableBase;
	DROP TABLE IF EXISTS #GeneralSpend1;
	DROP TABLE IF EXISTS #MonthlySpend;
	DROP TABLE IF EXISTS #PartnerTrans_Raw;
	DROP TABLE IF EXISTS #Annual_PartnerTrans;
	DROP TABLE IF EXISTS #CashbackRefunds;
	DROP TABLE IF EXISTS #LogIns1
	DROP TABLE IF EXISTS #Annual_LogIns
	DROP TABLE IF EXISTS #Annual_Redemptions
	DROP TABLE IF EXISTS #Email_Keys
	DROP TABLE IF EXISTS #Email_Sends
	DROP TABLE IF EXISTS #Quarterly_Emails
	DROP TABLE IF EXISTS #Current_Offers
	DROP TABLE IF EXISTS #Current_OfferBalance
	DROP TABLE IF EXISTS #KPI_Dash;
	DROP TABLE IF EXISTS #PreSplit
	DROP TABLE IF EXISTS #FallowSelection;

END

--------------------------------------------------------------------------
--						FORTNIGHTLY CYCLE DATES							--
--------------------------------------------------------------------------

CREATE TABLE #CycleStartDates
(TargetDate date PRIMARY KEY);

WHILE (@CurrentDate < @WhileEndDate)
BEGIN

INSERT INTO #CycleStartDates  
SELECT @CurrentDate Currentdate
    IF @@ROWCOUNT < 1
        print @CurrentDate    
		
    SET @CurrentDate = DATEADD(day,14,@CurrentDate); 
END

SET @LatestCycleStartDate = (SELECT TargetDate FROM #CycleStartDates iom WHERE CAST(GETDATE() AS date) >= iom.TargetDate AND  CAST(GETDATE() AS date) < DATEADD(day,14,iom.TargetDate))
SET @EndDate = DATEFROMPARTS(YEAR(@LatestCycleStartDate),MONTH(@LatestCycleStartDate),1)
SET @StartDate = DATEADD(year,-1,@EndDate)

--select *
--into WH_AllPublishers.email.CycleDates
--from #CycleStartDates


--------------------------------------------------------------------
--							MARKETABLE BASE								--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#MarketableBase') IS NULL

BEGIN

CREATE TABLE #MarketableBase(
	CustomerGUID char(36) PRIMARY KEY
	,FanID int
	,CompositeID bigint
	,CINID int
	,ClubID int
	,AccountType varchar(100)
	,Gender char(1)
	,AgeCurrent int
	,CashbackLTV money
	,MarketingStatus int
	,EmailTracking int
	,RegistrationMonth date
	,MonthTenure int
	,MultiProductStatus int
	,LastUpdatedDate datetime)

END

IF (SELECT COUNT(*) FROM #MarketableBase) = 0

BEGIN

	IF EXISTS(  
	 SELECT * FROM INFORMATION_SCHEMA.COLUMNS  
	 WHERE TABLE_SCHEMA = 'Derived' AND TABLE_NAME = 'CINList' AND COLUMN_NAME = 'OriginalCIN'  
	 )  
	 BEGIN  
	 SET @sqlcmd = '  

	 DECLARE @RegistrationCutOffDate date = GETDATE()

	INSERT INTO #MarketableBase

 		SELECT 
			c.CustomerGUID
			,c.FanID
			,c.CompositeID
			,cin.CINID
			,c.ClubID
			,c.AccountType
			,c.Gender
			,c.AgeCurrent
			,c.CashbackLTV
			,CASE WHEN c.MarketableByEmail = 1 AND c.MarketableByPush = 1 THEN 3
				WHEN c.MarketableByEmail = 1 THEN 1
				WHEN c.MarketableByPush = 1 THEN 2 END MarketableStatus
			,CASE WHEN c.MarketableByEmail = 1 THEN c.EmailTracking ELSE 0 END EmailTracking
			,DATEFROMPARTS(YEAR(c.RegistrationDate),MONTH(c.RegistrationDate),1)
			,DATEDIFF(MONTH,c.RegistrationDate,GETDATE())
			,CASE WHEN c.IsCredit = 1 AND c.IsDebit = 1 THEN 3
				WHEN c.IsDebit = 1 THEN 2
				WHEN c.IsCredit = 1 THEN 1
				ELSE 0 END MultiProductStatus
			,GETDATE()

		FROM Derived.Customer c
		LEFT JOIN Derived.CINList cin
			ON cin.OriginalCIN = c.SourceUID

		WHERE 1 = 1
			AND c.CurrentlyActive = 1
			AND (c.MarketableByEmail = 1 OR c.MarketableByPush = 1)
			AND c.RegistrationDate < @RegistrationCutOffDate
				AND NOT EXISTS (
							SELECT 1 
							FROM derived.FallowEligibility fe
							where c.fanid = fe.fanid
							and fe.NextEligibleDate >= getdate()
							)
			AND NOT EXISTS  (
							select 1
							from Selections.PrioritisedCustomerAccounts PCA
							where enddate is null
							AND PCA.FanID = c.Fanid
							)'; 
	 END  
      
	 ELSE  
      
	 BEGIN  
	 SET @sqlcmd = '  
 	
	DECLARE @RegistrationCutOffDate date = GETDATE()

	INSERT INTO #MarketableBase	
		SELECT 
			c.CustomerGUID
			,c.FanID
			,c.CompositeID
			,cin.CINID
			,c.ClubID
			,c.AccountType
			,c.Gender
			,c.AgeCurrent
			,c.CashbackLTV
			,CASE WHEN c.MarketableByEmail = 1 AND c.MarketableByPush = 1 THEN 3
				WHEN c.MarketableByEmail = 1 THEN 1
				WHEN c.MarketableByPush = 1 THEN 2 END MarketableStatus
			,CASE WHEN c.MarketableByEmail = 1 THEN c.EmailTracking ELSE 0 END EmailTracking
			,DATEFROMPARTS(YEAR(c.RegistrationDate),MONTH(c.RegistrationDate),1)
			,DATEDIFF(MONTH,c.RegistrationDate,GETDATE())
			,CASE WHEN c.IsCredit = 1 AND c.IsDebit = 1 THEN 3
				WHEN c.IsDebit = 1 THEN 2
				WHEN c.IsCredit = 1 THEN 1
				ELSE 0 END MultiProductStatus
			,GETDATE()

		FROM Derived.Customer c
		LEFT JOIN Derived.CINList cin
			ON cin.CIN = c.SourceUID

		WHERE 1 = 1
			AND c.CurrentlyActive = 1
			AND (c.MarketableByEmail = 1 OR c.MarketableByPush = 1)
			AND c.RegistrationDate < @RegistrationCutOffDate
			AND NOT EXISTS (
							SELECT 1 
							FROM derived.FallowEligibility fe
							where c.fanid = fe.fanid
							and fe.NextEligibleDate >= getdate()
							)
			AND NOT EXISTS 
							select 1
							from Selections.PrioritisedCustomerAccounts PCA
							where enddate is null
							AND PCA.FanID = c.Fanid
							)';  
	 END  
 EXEC(@sqlcmd);  

 END

 DELETE FROM #MarketableBase

 WHERE MonthTenure < @NewCustomerMaxTenure_Months

--------------------------------------------------------------------------
--						HISTORICAL ACCOUNT SPEND						--
--------------------------------------------------------------------------




IF OBJECT_ID('tempdb..#GeneralSpend1') IS NULL

BEGIN

CREATE TABLE #GeneralSpend1(
	CINID int
	,TranMonth int
	,TranYear int
	,Transactions float
	,Spend float
	,LastUpdatedDate datetime)

CREATE CLUSTERED INDEX Customer ON #GeneralSpend1 (CINID)

END

IF OBJECT_ID('tempdb..#MonthlySpend') IS NULL

BEGIN

CREATE TABLE #MonthlySpend(
	CINID int PRIMARY KEY
	,AvgGeneralSpend money
	,AvgGeneralTransactions float
	,MonthsActive float
	,LastUpdatedDate datetime)

END


	IF (SELECT COUNT(*) FROM #GeneralSpend1) = 0
	AND (SELECT COUNT(*) FROM #MonthlySpend) = 0

BEGIN

INSERT INTO #GeneralSpend1

SELECT 
	ct.CINID
	,MONTH(ct.TranDate) TranMonth
	,YEAR(ct.TranDate) TranYear
	,COUNT(*) Transactions
	,SUM(ct.Amount) Spend
	,GETDATE()

FROM Trans.ConsumerTransaction ct

WHERE 1=1
	AND EXISTS(SELECT 1 FROM #MarketableBase mb WHERE mb.CINID = ct.CINID)
	AND ct.TranDate >= @StartDate
	AND ct.TranDate < @EndDate
	AND ct.Amount > 0

GROUP BY 	ct.CINID
	,MONTH(ct.TranDate)
	,YEAR(ct.TranDate)

END

--------------------------------------------------------------------------------


IF (SELECT COUNT(*) FROM #MonthlySpend) = 0

BEGIN

INSERT INTO #MonthlySpend

SELECT 
	s.CINID
	,AVG(s.Spend) AvgGeneralSpend
	,AVG(s.Transactions) AvgGeneralTransactions
	,COUNT(*) MonthsActive
	,GETDATE()

FROM #GeneralSpend1 s

GROUP BY s.CINID

END

DROP TABLE #GeneralSpend1 

--------------------------------------------------------------------------
--					HISTORICAL MERCHANT TRANSACTIONS					--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#PartnerTrans_Raw') IS NULL

BEGIN

CREATE TABLE #PartnerTrans_Raw(
	CustomerGUID char(36)
	,TransactionDate date
	,TransactionMonth date
	,PartnerID int
	,TranType int
	,CashbackEarned money
	,Transactions float
	,LastUpdatedDate datetime)

CREATE CLUSTERED INDEX Customer ON #PartnerTrans_Raw (CustomerGUID)
CREATE INDEX TranMonth ON #PartnerTrans_Raw (TransactionMonth)

END

IF OBJECT_ID('tempdb..#Annual_PartnerTrans') IS NULL

BEGIN

CREATE TABLE #Annual_PartnerTrans(
	CustomerGUID char(36) PRIMARY KEY
	,RewardedTransactions float
	,MFDD_Transactions float
	,CLO_Transactions float
	,PartnersUsed float
	,RewardedMonths float
	,MonthsSinceTransact int
	,LastUpdatedDate datetime)

END

	IF (SELECT COUNT(*) FROM #PartnerTrans_Raw) = 0
	AND (SELECT COUNT(*) FROM #Annual_PartnerTrans) = 0

BEGIN

INSERT INTO #PartnerTrans_Raw

SELECT
	pt.CustomerGUID
	,pt.TransactionDate
	,DATEFROMPARTS(YEAR(pt.TransactionDate),MONTH(pt.TransactionDate),1) TransactionMonth
	,pt.PartnerID
	,CASE WHEN pt.DirectDebitOriginatorID IS NULL THEN 1 ELSE 2 END
	,pt.CashbackEarned
	,1
	,GETDATE()

FROM Derived.PartnerTrans pt

WHERE 1 = 1
	AND EXISTS(SELECT 1 FROM #MarketableBase mb WHERE mb.CustomerGUID = pt.CustomerGUID)
	AND pt.TransactionDate >= @StartDate
	AND pt.TransactionDate < @EndDate
	AND PARTNERID NOT IN (4921, 5030,5132)
	;
	--need to exclude partnerIDs
END


--------------------------------------------------------------------------

IF (SELECT COUNT(*) FROM #Annual_PartnerTrans) = 0

BEGIN

INSERT INTO #Annual_PartnerTrans

SELECT 
	pt.CustomerGUID
	,SUM(pt.Transactions)
	,ISNULL(SUM(CASE WHEN TranType = 2 THEN pt.Transactions END),0)
	,ISNULL(SUM(CASE WHEN TranType = 1 THEN pt.Transactions END),0)
	,COUNT(DISTINCT pt.PartnerID)
	,COUNT(DISTINCT pt.TransactionMonth)
	,DATEDIFF(month,MAX(pt.TransactionDate),@EndDate)
	,GETDATE()

FROM #PartnerTrans_Raw pt

WHERE pt.CashbackEarned > 0

GROUP BY pt.CustomerGUID;

END

--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#CashbackRefunds') IS NULL

BEGIN

CREATE TABLE #CashbackRefunds(
	CustomerGUID char(36) PRIMARY KEY
	,RefundFlag int
	,LastUpdatedDate datetime)

END

IF (SELECT COUNT(*) FROM #CashbackRefunds) = 0

BEGIN

INSERT INTO #CashbackRefunds

SELECT
		CustomerGUID
		,1
		,GETDATE()

FROM #PartnerTrans_Raw

WHERE CashbackEarned < 0

GROUP BY CustomerGUID

END

DROP TABLE #PartnerTrans_Raw
	
--------------------------------------------------------------------------
--						HISTORICAL LOG INS								--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#LogIns1') IS NULL

BEGIN

CREATE TABLE #LogIns1(
	CustomerGUID char(36) 
	,LogInMonth int
	,LogInYear int
	,LogIns float
	,LastLogInDate date
	,LastUpdatedDate datetime)

CREATE CLUSTERED INDEX Customer ON #LogIns1 (CustomerGUID)

END

IF OBJECT_ID('tempdb..#Annual_LogIns') IS NULL

BEGIN

CREATE TABLE #Annual_LogIns(
	CustomerGUID char(36) PRIMARY KEY
	,AvgMonthlyLogIns float
	,LogInMonths float
	,AnnualLogIns float
	,MonthsSinceLogIn int
	,LastUpdatedDate datetime)

END

IF (SELECT COUNT(*) FROM #LogIns1) = 0
	AND (SELECT COUNT(*) FROM #Annual_LogIns) = 0

BEGIN

INSERT INTO #LogIns1

SELECT 
	al.CustomerGUID
	,MONTH(al.TrackDate)
	,YEAR(al.TrackDate)
	,COUNT(DISTINCT DAY(al.TrackDate))
	,MAX(al.TrackDate)
	,GETDATE()

FROM Derived.AppLogins al

WHERE 1 = 1
	AND EXISTS(SELECT 1 FROM #MarketableBase mc WHERE mc.CustomerGUID = al.CustomerGUID)
	AND al.TrackDate >= @StartDate
	AND al.TrackDate < @EndDate

GROUP BY 	al.CustomerGUID
	,MONTH(al.TrackDate)
	,YEAR(al.TrackDate);

END

--------------------------------------------------------------------------

IF (SELECT COUNT(*) FROM #Annual_LogIns) = 0

BEGIN

INSERT INTO #Annual_LogIns

SELECT 
	l.CustomerGUID
	,AVG(l.LogIns) AvgMonthlyLogIns
	,COUNT(*) LogInMonths
	,SUM(l.LogIns) AnnualLogIns
	,DATEDIFF(month,MAX(l.LastLogInDate),@EndDate)
	,GETDATE()

FROM #LogIns1 l

GROUP BY l.CustomerGUID

END

DROP TABLE #LogIns1;

--------------------------------------------------------------------------
--						HISTORICAL REDEMPTIONS							--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#Annual_Redemptions') IS NULL

BEGIN

CREATE TABLE #Annual_Redemptions(
	CustomerGUID char(36) PRIMARY KEY
	,Redemptions float
	,RedeemingMonths float
	,TradeUps float
	,TradeUpPartners float
	,MonthsSinceRedemption int
	,LastUpdatedDate datetime)

END

IF (SELECT COUNT(*) FROM #Annual_Redemptions) = 0

BEGIN
	
INSERT INTO #Annual_Redemptions

SELECT 
	r.CustomerGUID
	,COUNT(DISTINCT CAST(r.RedeemedDate AS date)) Redemptions
	,COUNT(DISTINCT MONTH(r.RedeemedDate)) RedeemingMonths
	,COUNT(DISTINCT CASE WHEN r.RedemptionType LIKE 'Tr%' THEN CAST(r.RedeemedDate AS date) END) TradeUps
	,COUNT(DISTINCT CASE WHEN r.RedemptionType LIKE 'Tr%' THEN r.RedemptionPartnerGUID END) TradeUpPartners
	,DATEDIFF(month,MAX(CAST(r.RedeemedDate AS date)),@EndDate)
	,GETDATE()

FROM Derived.Redemptions r

WHERE 1 = 1
	AND EXISTS(SELECT 1 FROM #MarketableBase mb WHERE mb.CustomerGUID = r.CustomerGUID)
	AND r.RedeemedDate >= @StartDate
	AND r.RedeemedDate < @EndDate

GROUP BY r.CustomerGUID;

END

--------------------------------------------------------------------------
--					HISTORICAL EMAIL ENGAGEMENT							--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#Email_Keys') IS NULL

BEGIN

CREATE TABLE #Email_Keys(
	CampaignKey varchar(50) PRIMARY KEY
	,LastUpdatedDate datetime)
	
END

IF OBJECT_ID('tempdb..#Email_Sends') IS NULL

BEGIN

CREATE TABLE #Email_Sends(
	CampaignKey varchar(50) 
	,EventCodeID int
	,EventDate date
	,CustomerGUID char(36)
	,LastUpdatedDate datetime);

CREATE CLUSTERED INDEX Customer ON #Email_Sends (CustomerGUID)
CREATE INDEX Campaign ON #Email_Sends (CampaignKey)

END


IF OBJECT_ID('tempdb..#Quarterly_Emails') IS NULL

BEGIN

CREATE TABLE #Quarterly_Emails(
	CustomerGUID char(36) PRIMARY KEY
	,AttemptedSends float
	,Sends float
	,Delivered float
	,Opens float
	,Clicks float
	,Failures float
	,LastUpdatedDate datetime)

END

SET @EmailKeyCount = (SELECT COUNT(*) FROM #Email_Keys)
SET @EmailSendCount1 = (SELECT COUNT(*) FROM #Email_Sends)
SET @EmailSendCount2 = (SELECT COUNT(*) FROM #Email_Sends WHERE EventCodeID IN (701, 702, 1301, 605))
SET @QuarterlyEmailCount = (SELECT COUNT(*) FROM #Quarterly_Emails)


IF @EmailKeyCount = 0
	AND @EmailSendCount1 = 0
	AND @QuarterlyEmailCount = 0

BEGIN

INSERT INTO #Email_Keys

SELECT 
	ec.CampaignKey
	,GETDATE()
	
FROM Derived.EmailCampaign ec

WHERE 1=1
	AND ec.CampaignName LIKE '%newsletter%'
	AND ec.SendDate >= DATEADD(month,-4,@EndDate)
	AND ec.SendDate < @EndDate;

END

------------------------------------------------------------------


IF @EmailSendCount1 = 0
	AND @QuarterlyEmailCount = 0

BEGIN

INSERT INTO #Email_Sends

SELECT 
		ee.CampaignKey
		,ee.EmailEventCodeID
		,ee.EventDate
		,ee.CustomerGUID 
		,GETDATE()

FROM Derived.EmailEvent ee

WHERE 1=1
	AND ee.EmailEventCodeID IN (910, 666)
	AND EXISTS(SELECT 1 FROM #MarketableBase mb WHERE mb.CustomerGUID = ee.CustomerGUID)
	AND EXISTS(SELECT 1 FROM #Email_Keys ek WHERE ek.CampaignKey = ee.CampaignKey);

--------------------------------------------------------------

END

IF @EmailSendCount2 = 0
	AND @QuarterlyEmailCount = 0

BEGIN

INSERT INTO #Email_Sends

SELECT 
		ee.CampaignKey
		,ee.EmailEventCodeID
		,ee.EventDate
		,ee.CustomerGUID
		,GETDATE()

FROM Derived.EmailEvent ee
JOIN #Email_Sends ns
	ON ns.CustomerGUID = ee.CustomerGUID
	AND ns.CampaignKey = ee.CampaignKey
	AND ee.EventDate BETWEEN ns.EventDate AND DATEADD(day,5,ns.EventDate)

WHERE ee.EmailEventCodeID IN (701, 702, 1301, 605)
	AND ee.EventDate >= DATEADD(month,-4,@EndDate);

END

--------------------------------------------------------------------------------------


IF @QuarterlyEmailCount = 0

BEGIN

INSERT INTO #Quarterly_Emails

SELECT 
	b.CustomerGUID
	,SUM(1) AttemptedSends
	,SUM(CASE WHEN b.[910] IS NOT NULL THEN 1 ELSE 0 END) Sends
	,SUM(CASE WHEN b.[910] IS NOT NULL AND ISNULL(b.[701],b.[702]) IS NULL THEN 1 ELSE 0 END) Delivered
	,SUM(CASE WHEN b.[1301] IS NOT NULL THEN 1 ELSE 0 END) Opens
	,SUM(CASE WHEN b.[605] IS NOT NULL THEN 1 ELSE 0 END) Clicks
	,SUM(CASE WHEN b.[666] IS NOT NULL THEN 1 ELSE 0 END) Failures
	,GETDATE()

FROM #Email_Sends ns

PIVOT(MIN(ns.EventDate) FOR ns.EventCodeID IN ([910], [666], [701], [702], [1301], [605])) b

GROUP BY b.CustomerGUID;

END

DROP TABLE #Email_Keys;
DROP TABLE #Email_Sends;

--------------------------------------------------------------------------
--						RECENT OFFERS RETAILERS							--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#Current_Offers') IS NULL

BEGIN

CREATE TABLE #Current_Offers(
	CustomerGUID char(36) PRIMARY KEY
	,AcquireOffers float
	,LapsedOffers float
	,ShopperOffers float
	,TotalOffers float
	,LastUpdatedDate datetime)

END

IF OBJECT_ID('tempdb..#Current_OfferBalance') IS NULL

BEGIN

CREATE TABLE #Current_OfferBalance(
	CustomerGUID char(36) PRIMARY KEY
	,OfferBalance float
	,LastUpdatedDate datetime)

END


IF (SELECT COUNT(*) FROM #Current_Offers) = 0
	AND (SELECT COUNT(*) FROM #Current_OfferBalance) = 0

BEGIN

INSERT INTO #Current_Offers

SELECT 
	iom.CustomerGUID
	,COUNT(CASE WHEN io.SegmentName LIKE 'A%' THEN iom.IronOfferID END) AcquireOffers
	,COUNT(CASE WHEN io.SegmentName LIKE 'L%' THEN iom.IronOfferID END) LapsedOffers
	,COUNT(CASE WHEN io.SegmentName LIKE 'S%' THEN iom.IronOfferID END) ShopperOffers
	,COUNT(*) TotalOffers
	,GETDATE()

FROM Derived.IronOfferMember iom
JOIN Derived.IronOffer io
	ON io.IronOfferID = iom.IronOfferID

WHERE 1=1
	AND EXISTS(SELECT 1 FROM #MarketableBase mb WHERE iom.CustomerGUID = mb.CustomerGUID AND mb.CINID IS NOT NULL)
	AND iom.StartDate = @LatestCycleStartDate

GROUP BY 	iom.CustomerGUID;

END

--------------------------------------------------------------------------

IF (SELECT COUNT(*) FROM #Current_OfferBalance) = 0

BEGIN
	
INSERT INTO #Current_OfferBalance		

SELECT
	CustomerGUID
	, ((co.LapsedOffers + co.ShopperOffers - co.AcquireOffers) / co.TotalOffers)
	,GETDATE()

FROM #Current_Offers co

END

DROP TABLE #Current_Offers

--------------------------------------------------------------------------
--		NATWEST SPECIFIC DETAILS - IGNORE FOR OTHER CLIENTS				--
--------------------------------------------------------------------------

IF OBJECT_ID('tempdb..#KPI_Dash') IS NULL

BEGIN

CREATE TABLE #KPI_Dash(
	CustomerGUID char(36) PRIMARY KEY
	,NomineeStatus int
	,AccountSegmentation varchar(100)
	,LastUpdatedDate datetime)


END

IF (SELECT COUNT(*) FROM #KPI_Dash) = 0

BEGIN
	
	IF OBJECT_ID ('Report.NW_KPIDashboardRawData') IS NOT NULL 
	
	BEGIN		

	SET @sqlcmd ='	
	
		INSERT INTO #KPI_Dash

			SELECT
				kpi.CustomerGUID
				,kpi.NomineeStatus
				,kpi.AccountSegmentation
				,GETDATE()

			FROM Report.NW_KPIDashboardRawData kpi

			WHERE EXISTS(SELECT 1 FROM #MarketableBase mb WHERE mb.CustomerGUID = kpi.CustomerGUID)
				AND kpi.Date = EOMONTH(GETDATE(),-2)

		GROUP BY 		kpi.CustomerGUID
				,kpi.NomineeStatus
				,kpi.AccountSegmentation
			;'

	EXEC(@sqlcmd)
	END
END

--------------------------------------------------------------------------
--				BRING ALL TABLES TOGETHER FOR SPLIT						--
--------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#PreSplit') IS NULL

BEGIN

CREATE TABLE #PreSplit(
	CustomerGUID char(36) PRIMARY KEY
	,FanID int
	,CompositeID bigint
	,CINID int
	,ClubID int
	,AccountType varchar(100)
	,AgeCurrent int
	,CashbackLTV money
	,MarketingStatus smallint
	,EmailTracking smallint
	,RegistrationMonth date
	,MultiProductStatus smallint
	,AvgGeneralSpend money
	,AvgGeneralTransactions int
	,MonthsSpendActive int
	,AnnualLogIns int
	,LogInMonths smallint
	,AvgMonthlyLogIns float
	,MonthsSinceLogIn float
	,RewardedTransactions float
	,RewardedMonths smallint
	,MerchantBalance float
	,PartnersUsed int
	,MonthsSinceTransact int
	,RefundFlag smallint
	,RedeemingMonths smallint
	,RedemptionBalance float
	,TradeUpPartners int
	,MonthsSinceRedeem int
	,OfferBalance float
	,DeliveredRate float
	,Opens float
	,Clicks float
	,LastUpdatedDate datetime)

END

BEGIN

IF (SELECT COUNT(*) FROM #PreSplit) = 0
	
INSERT INTO #PreSplit

SELECT 
	mb.CustomerGUID
	,mb.FanID
	,mb.CompositeID
	,mb.CINID
	,mb.ClubID
	,CASE WHEN kpi.AccountSegmentation IS NULL THEN mb.AccountType 
		ELSE CONCAT(mb.AccountType,'-',kpi.AccountSegmentation,'-',ISNULL(kpi.NomineeStatus,0)) END AccountType
	,mb.AgeCurrent
	,mb.CashbackLTV
	,mb.MarketingStatus
	,mb.EmailTracking
	,mb.RegistrationMonth
	,mb.MultiProductStatus
	,ISNULL(ms.AvgGeneralSpend,0)
	,ISNULL(ms.AvgGeneralTransactions,0)
	,ISNULL(ms.MonthsActive,0)
	,ISNULL(al.AnnualLogIns,0)
	,ISNULL(al.LogInMonths,0)
	,ISNULL(al.AvgMonthlyLogIns,0)
	,ISNULL(al.MonthsSinceLogIn,999)
	,ISNULL(pt.RewardedTransactions,0)
	,ISNULL(pt.RewardedMonths,0)
	,ISNULL((pt.CLO_Transactions - pt.MFDD_Transactions) / pt.RewardedTransactions,0) MerchantBalance
	,ISNULL(pt.PartnersUsed,0)
	,ISNULL(pt.MonthsSinceTransact,999)
	,ISNULL(cr.RefundFlag,0)
	,ISNULL(ar.RedeemingMonths,0)
	,ISNULL((ar.Redemptions - (2 * ar.TradeUps)) / ar.Redemptions,0) RedemptionBalance
	,ISNULL(ar.TradeUpPartners,0)
	,ISNULL(ar.MonthsSinceRedemption,999)
	,ISNULL(co.OfferBalance,-1)
	,ISNULL(CASE WHEN qe.AttemptedSends = 0 THEN 0 ELSE qe.Delivered / qe.AttemptedSends END,0) DeliveredRate
	,ISNULL(CASE WHEN qe.Delivered = 0 THEN 0 ELSE qe.Opens/qe.Delivered END,0)
	,ISNULL(CASE WHEN qe.Opens = 0 THEN 0 ELSE qe.Clicks/qe.Opens END,0)
	,GETDATE()

FROM #MarketableBase mb

LEFT JOIN #KPI_Dash kpi
	ON kpi.CustomerGUID = mb.CustomerGUID
LEFT JOIN #MonthlySpend ms
	ON ms.CINID = mb.CINID
LEFT JOIN #Annual_LogIns al
	ON al.CustomerGUID = mb.CustomerGUID
LEFT JOIN #Annual_PartnerTrans pt
	ON pt.CustomerGUID = mb.CustomerGUID
LEFT JOIN #CashbackRefunds cr
	ON cr.CustomerGUID = mb.CustomerGUID
LEFT JOIN #Annual_Redemptions ar
	ON ar.CustomerGUID = mb.CustomerGUID
LEFT JOIN #Current_OfferBalance co
	ON co.CustomerGUID = mb.CustomerGUID
LEFT JOIN #Quarterly_Emails qe
	ON qe.CustomerGUID = mb.CustomerGUID;

END

--------------------------------------------------------------------------
--			SPLIT FALLOW BASED ON RULES DEFINED AT SCRIPT START			--
--------------------------------------------------------------------------
DROP TABLE IF EXISTS Derived.FallowSelection_Staging

CREATE TABLE Derived.FallowSelection_Staging(
	CustomerGUID char(36) PRIMARY KEY
	,FanID int
	,CompositeID bigint
	,CINID int
	,ClubID int
	,AccountType varchar(100)
	,AgeCurrent int
	,CashbackLTV money
	,MarketingStatus smallint
	,EmailTracking smallint
	,RegistrationMonth date
	,MultiProductStatus smallint
	,AvgGeneralSpend money
	,AvgGeneralTransactions int
	,MonthsSpendActive money
	,AnnualLogIns int
	,LogInMonths smallint
	,AvgMonthlyLogIns float
	,MonthsSinceLogIn int
	,RewardedTransactions float
	,RewardedMonths smallint
	,MerchantBalance float
	,PartnersUsed int
	,MonthsSinceTransact int
	,RefundFlag smallint
	,RedeemingMonths smallint
	,RedemptionBalance float
	,TradeUpPartners int
	,MonthsSinceRedemption int
	,OfferBalance float
	,DeliveredRate float
	,Opens float
	,Clicks float
	,FallowFlag smallint
	,StartDate date
	,EndDate date
	,NextEligibleDate date
	,LastUpdatedDate datetime)

INSERT INTO Derived.FallowSelection_Staging

SELECT
	CustomerGUID
	,FanID 
	,CompositeID 
	,CINID 
	,ClubID 
	,AccountType 
	,AgeCurrent 
	,CashbackLTV 
	,MarketingStatus 
	,EmailTracking 
	,RegistrationMonth 
	,MultiProductStatus 
	,AvgGeneralSpend 
	,AvgGeneralTransactions 
	,MonthsSpendActive 
	,AnnualLogIns 
	,LogInMonths 
	,AvgMonthlyLogIns 
	,MonthsSinceLogIn
	,RewardedTransactions 
	,RewardedMonths 
	,MerchantBalance 
	,PartnersUsed 
	,MonthsSinceTransact
	,RefundFlag 
	,RedeemingMonths 
	,RedemptionBalance 
	,TradeUpPartners 
	,MonthsSinceRedeem
	,OfferBalance 
	,DeliveredRate 
	,Opens 
	,Clicks
	,CASE WHEN ROW_NUMBER() OVER(ORDER BY AccountType ,MarketingStatus ,EmailTracking ,RegistrationMonth ,MultiProductStatus ,AvgGeneralSpend ,AvgGeneralTransactions ,MonthsSpendActive ,AnnualLogIns ,LogInMonths ,AvgMonthlyLogIns 
								,MonthsSinceLogIn ,RewardedTransactions ,RewardedMonths ,MerchantBalance ,PartnersUsed ,MonthsSinceTransact ,RefundFlag ,RedeemingMonths ,RedemptionBalance ,TradeUpPartners ,MonthsSinceRedeem ,OfferBalance	,DeliveredRate ,Opens, Clicks)
				% @SplitSize
				<= @ControlPick
				THEN 1 ELSE 0 END FallowFlag
	,@LatestCycleStartDate
	,DATEADD(day,(@FallowPeriod_Cycles*14),@LatestCycleStartDate)
	,DATEADD(day,((@ExclusionPeriod_Cycles*14)-1),@LatestCycleStartDate)
	,GETDATE()

FROM #PreSplit ps


INSERT INTO Derived.FallowSelection_Archive
SELECT *
FROM Derived.FallowSelection

TRUNCATE TABLE Derived.FallowSelection

INSERT INTO Derived.FallowSelection
select *
from Derived.FallowSelection_Staging
where FallowFlag = 1 

--Seed Account to be removed



MERGE Derived.FallowEligibility target											-- Destination table
			USING Derived.FallowSelection source								-- Source table
			ON target.fanid = source.fanid										-- Match criteria
			WHEN MATCHED THEN
				UPDATE SET	target.[NextEligibleDate]	= source.[NextEligibleDate]	-- If matched, update to new value						
			WHEN NOT MATCHED THEN	-- If not matched, add new rows
				INSERT ([FanID]
					,	[NextEligibleDate]
					)
				VALUES (source.[FanID]
					,	source.[NextEligibleDate]
					);



END







