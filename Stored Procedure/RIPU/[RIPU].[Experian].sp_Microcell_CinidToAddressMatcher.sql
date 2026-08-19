USE [RIPU]
GO
/****** Object:  StoredProcedure [Experian].[sp_Microcell_CinidToAddressMatcher]    Script Date: 18/08/2026 16:32:46 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


--create schema Experian
ALTER PROCEDURE [Experian].[sp_Microcell_CinidToAddressMatcher]
	--[Audit_CohortMappingSampleNewCustomersSP_Cleaned] 
	AS


/******************************************
	* Author		- William Allen 

	* Date			- 14/12/2022

	* Description	- Match customer addresses in warehouse to relevant cohort

	* Contents		- 1 - Extract Numbers for our relational.customer address fields
					- 2 - Normalise our Customer data using Royal mail PAF file
							- 92% on initial load 
					- 3 - clean data by removing duplicate customer IDS created from the joins
					- 4 - Hash all addresses matched so we can join to cohort file based on hash
					- 5 - Find all that hasnt been matched and add them to the -1 cohort
					- 6 - Insert new customers or customers that have changed address
					- 7 - Update customers previous rows to isCurrentChort = 0

	* Changes		-CJ 09/01/2024 moved into RIPU DB and amended tables
					-CJ 07/10/2024 amended customer tables from Warehouse to WH_NWG
******************************************/

/*
create table RIPU.Experian.Microcell_MatchedCinid (
	FanID int,
	CINID int,
	microcell_id int,
	HashedAddress varchar(255),
	UnhashedAddress nvarchar(255),
	loadDate datetime,
	isCurrentCohort int
)
;
create table RIPU.Experian.Microcell_Addresses (
	hashed_address varchar(255),
	postcode_sector varchar(8),
	microcell_id int
)
*/
	--function to extract numbers from address one and 2 
	drop table if exists #ProvidedPostcodes
	select warehouse.dbo.udf_GetNumeric(p.Address1) AdressOneNumber,warehouse.dbo.udf_GetNumeric(p.Address2) AdressTwoNumber,C.*, p.Address1, p.Address2
	into #ProvidedPostcodes
	from WH_NWG.derived.Customer C
		inner join WH_NWG.derived.Customer_PII p
			on p.FanID = C.FanID
	--LEFT OUTER JOIN Warehouse.MI.CINDuplicate D ON C.FanID = D.FanID
    --LEFT OUTER JOIN Warehouse.Relational.CAMEO cam ON cam.postcode = c.postcode
    --LEFT OUTER JOIN Warehouse.relational.cameo_code_group camG ON camG.CAMEO_CODE_GROUP =cam.CAMEO_CODE_GROUP
	where C.PostalSector in (
								select postcode_sector
								from RIPU.Experian.Microcell_Addresses s
								group by postcode_sector
	)
	
	CREATE NONCLUSTERED INDEX NCIX_tblProvidedPostcodes_AdressOneNumber ON #ProvidedPostcodes(AdressOneNumber,postcode)
	CREATE NONCLUSTERED INDEX NCIX_tblProvidedPostcodes_AdressTwoNumber ON #ProvidedPostcodes(AdressTwoNumber,postcode)
	CREATE NONCLUSTERED INDEX NCIX_tblProvidedPostcodes_Address1 ON #ProvidedPostcodes(Address1,postcode)

	----------
	-- Matching Process
		--Complex matching first to stop duplication issues I.e flat numbers having the same building number but different sub number
	----------

	--Match on
		--Postcode
		--Building Number
		--SubBuilding Number
	drop table if exists #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	into #t
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted rp
	on pp.PostCode = rp.Postcode
	and (rp.BuildingNumber = AdressTwoNumber
	and AdressOneNumber = subBuildingNumber )
	where AdressTwoNumber != ''


	insert into #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted rp
	on pp.PostCode = rp.Postcode
	and (rp.BuildingNumber = AdressOneNumber
	and AdressTwoNumber = subBuildingNumber )
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)
	and AdressTwoNumber != ''


	--Match on
		--Postcode
		--Building Number
	insert into #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted rp
	on pp.PostCode = rp.Postcode
	and (rp.BuildingNumber = AdressOneNumber)
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)
	and AdressOneNumber != ''

	--Match on
		--Postcode
		--Building Number
		--Address one = subbuilding name
	insert into #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted rp
	on pp.PostCode = rp.Postcode
	and (rp.BuildingNumber = AdressTwoNumber) 
	and Address1 = SubBuildingName
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)
	and AdressTwoNumber != ''

	--Match on
		--Postcode
		--Building Number
	insert into #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted rp
	on pp.PostCode = rp.Postcode
	and (rp.BuildingNumber = AdressTwoNumber) 
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)
	and AdressTwoNumber != ''

	--Match on
		--Postcode
		--Building Name matching
	insert into #t
	select  pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted  rp
	on pp.PostCode = rp.Postcode
	and pp.Address1 = rp.BuildingName
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)

	--Match on
		--Postcode
		--Building Name matching on subbuilding name				
	insert into #t
	select distinct pp.Address1,pp.Address2,rp.Postcode,rp.BuildingNumber,SubBuildingName,BuildingName,FanID
	from #ProvidedPostcodes pp
	join wh_allpublishers.internal.CohortGroups_RoyalMail_PAF_Formatted  rp
	on pp.PostCode = rp.Postcode
	and pp.Address1 = rp.SubBuildingName
	where not exists (
					select 1
					from #t t
					where pp.FanID = t.FanID
					)
	

	-------------------
	--remove any duplicates.  This is mainly due to flat numbers within addresses which havent been found resulting in joining multiple times
	-------------------

	;with cte1 as 
	(
	select FanID
	from #t
	group by FanID
	having count(FanID) >1 
	)
	delete from #t 
	where FanID in (
					select FanID
					from cte1
					)

	---------------------
	--Hashing of addresses
	---------------------

	drop table if exists #temp
	;with unhashed as (
		select UnhashedAddress = UPPER(REPLACE(('"' + rm1.SubBuildingName + '",' + '"' 
									+ COALESCE(NULLIF(rm1.BuildingNumber,''),rm1.BuildingName) + '",' + '"' + REPLACE(rm1.PostCode,' ','')+'"' ),' ',''))
		, rm1.*
		from #t rm1
	), hashing as (
		select		CONVERT(VARCHAR(64),HASHBYTES('SHA2_256', CONVERT(VARCHAR(255),UnhashedAddress)),2) AS HashedAddress
				,	*
		from unhashed
	)
	select FanID,s.cohort_id as microcell_id,HashedAddress,UnhashedAddress,getdate() loadDate,1 isCurrentChort
	into #temp
	from hashing h
	join RIPU.Experian.Microcell_Addresses s
	on s.hashed_address = h.HashedAddress


	----------------
	--Find all that hasnt been matched and add them to the -1 cohort
	----------------

	INSERT INTO RIPU.Experian.Microcell_MatchedCinid (FanID,CINID,microcell_id,loadDate,isCurrentCohort)
	select pp.FanID,cin.CINID,-1 as microcell_id, GETDATE() loaddate, 1 isCurrentCohort
	from #ProvidedPostcodes pp
	join WH_NWG.whb.Customer c
	on pp.FanID = c.FanID
	join WH_NWG.Derived.CINList cin
	on c.SourceUID = cin.CIN
	where not exists ( select 1
					from #temp cm
					where pp.FanID = cm.FanID
					)
	and not exists (
					select 1
					from RIPU.Experian.Microcell_MatchedCinid  cms
					where  cms.CINID = cin.cinID
					and cms.microcell_id = -1
					)



--19949759	14700512	-1	2023-08-25 09:46:00.357	1

	INSERT INTO RIPU.Experian.Microcell_MatchedCinid 
	select t.FanID,cin.CINID,MIN(microcell_id),HashedAddress,UnhashedAddress, loadDate,isCurrentChort
	from #temp t
	join WH_NWG.whb.customer c
	on t.FanID = c.FanID
	join WH_NWG.Derived.CINList cin
	on c.SourceUID = cin.CIN
	where not exists (
					select 1
					from RIPU.Experian.Microcell_MatchedCinid  cms
					where  cms.CINID = cin.cinID
					and t.microcell_id = cms.microcell_id
					)
	group by t.FanID,cin.CINID,HashedAddress,UnhashedAddress, loadDate,isCurrentChort


	-------------------
	--updating is currentcohort for existing rows 
	-------------------

	drop table if exists #newlyadded
	SELECT fanid ,max(loaddate) maxLoadDate
	into #newlyadded
	FROM RIPU.Experian.Microcell_MatchedCinid 
	GROUP BY FANID

	update cg
	set isCurrentCohort = 0
	from RIPU.Experian.Microcell_MatchedCinid cg
	join #newlyadded na
	on na.FanID = cg.FanID
	and cg.loaddate != na.maxLoadDate
	where cg.iscurrentcohort = 1 

	--Remove duplicate CINs

	;with cte1 as (
				SELECT cinid
				from RIPU.Experian.Microcell_MatchedCinid CGL
				group by cinid
				having count(fanid) > 1
	), cte2 as  (
				select  *,ROW_NUMBER() over (partition by cinID order by microcell_id desc) rn
				from RIPU.Experian.Microcell_MatchedCinid CGL
				where exists (
								select 1 
								from cte1
								where cte1.cinid = cgl.cinid
								)
	)
	delete  cgl
	from RIPU.Experian.Microcell_MatchedCinid cgl
	join cte2 c
	on cgl.FanID = c.FanID
	where rn > 1

	
	-------------------
	----for any unmatched or dupe deleted that we have a postcode for, apply the default microcell given to us by experian
	---------------------
	drop table if exists #defaults;
	select mc.cinid, pc.cohort_ID
	into #defaults
	from RIPU.Experian.Microcell_MatchedCinid mc
		inner join WH_NWG.whb.Customer c
			on c.FanID = mc.fanid
		inner join RIPU.Experian.Microcell_PostcodeDefault pc
			on pc.Postcode_Trim = c.postcode
	where mc.microcell_id = -1
	;
	update RIPU.Experian.Microcell_MatchedCinid
	set microcell_id = d.cohort_ID
	from #defaults as d, RIPU.Experian.Microcell_MatchedCinid as t
	where t.cinid = d.cinid
