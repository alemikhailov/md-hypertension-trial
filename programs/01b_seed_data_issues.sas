/*****************************************************************************
* Program:     01b_seed_data_issues.sas
* Study:       MHT-2026-001
*
* Purpose:     Introduce a fixed set of known data issues into the simulated
*              raw datasets so that the edit-check program (03_edit_checks.sas)
*              can be validated against a known answer key.
*
*              This is the same principle CROs use to qualify edit-check
*              specifications: seed defects of each type the checks are
*              supposed to catch, run the checks, and confirm that every
*              seeded defect is reported. A check program that has only ever
*              been run against clean data has not been tested.
*
* Input:       RAW.SUBJECTS, RAW.VITALS, RAW.AE, RAW.LABS,
*              RAW.DOSING, RAW.DISP   (modified in place)
*
* Output:      The same datasets, with 15 defects introduced
*              RAW.SEEDED_ISSUES - the answer key, one record per defect
*
* IMPORTANT:   Run this ONCE after 01_simulate_source.sas, then re-run
*              02_create_sdtm.sas. Running it twice is harmless but
*              unnecessary, since it overwrites the same records.
*
* Author:      Aleksandr Mikhailov
* Date:        September 2026
*****************************************************************************/

options notes source;

libname raw "/home/u63064984/md-hypertension-trial/data/raw";


/*===========================================================================
  STEP 1: Select target subjects
  Targets are chosen by position in a sorted list rather than at random, so
  that the same subjects are selected every time the program runs.
  Only completers are used for the visit-specific defects, so that the
  targeted visit is guaranteed to exist.
===========================================================================*/

proc sort data=raw.subjects(where=(LASTVIS = 7)) out=work.compl(keep=SUBJID);
    by SUBJID;
run;

data _null_;
    set work.compl;
    if _N_ =   5 then call symputx('S_VS1', SUBJID);
    if _N_ =  18 then call symputx('S_VS2', SUBJID);
    if _N_ =  31 then call symputx('S_VS3', SUBJID);
    if _N_ =  44 then call symputx('S_VS4', SUBJID);
    if _N_ =  57 then call symputx('S_VS5', SUBJID);
    if _N_ =  70 then call symputx('S_LB1', SUBJID);
    if _N_ =  83 then call symputx('S_LB2', SUBJID);
    if _N_ =  96 then call symputx('S_DM1', SUBJID);
    if _N_ = 109 then call symputx('S_DM2', SUBJID);
    if _N_ = 122 then call symputx('S_EX1', SUBJID);
run;

/*--- Adverse event defects need subjects who actually reported an event ---*/
proc sort data=raw.ae(keep=SUBJID) out=work.aesub nodupkey;
    by SUBJID;
run;

data _null_;
    set work.aesub;
    if _N_ = 10 then call symputx('S_AE1', SUBJID);
    if _N_ = 30 then call symputx('S_AE2', SUBJID);
    if _N_ = 50 then call symputx('S_AE3', SUBJID);
run;

/*--- Two defects require a subject with specific characteristics ---*/
proc sql noprint;
    /* A placebo subject, for the dose-versus-arm mismatch */
    select SUBJID into :S_EX2 trimmed
        from raw.subjects
        where ARMCD = 'PBO'
          and SUBJID not in ("&S_VS1","&S_VS2","&S_VS3","&S_VS4","&S_VS5",
                             "&S_LB1","&S_LB2","&S_DM1","&S_DM2","&S_EX1",
                             "&S_AE1","&S_AE2","&S_AE3")
        order by SUBJID;

    /* An early discontinuation, for the false 'completed' disposition */
    select SUBJID into :S_DS1 trimmed
        from raw.subjects
        where DISCONT = 1 and LASTVIS <= 4
        order by SUBJID;
quit;

%put NOTE: Seed targets -> VS &S_VS1 &S_VS2 &S_VS3 &S_VS4 &S_VS5;
%put NOTE: Seed targets -> LB &S_LB1 &S_LB2 | DM &S_DM1 &S_DM2;
%put NOTE: Seed targets -> AE &S_AE1 &S_AE2 &S_AE3;
%put NOTE: Seed targets -> EX &S_EX1 &S_EX2 | DS &S_DS1;


/*===========================================================================
  STEP 2: Vital signs defects
  SEED-01  Systolic blood pressure of 310 mmHg (physiologically implausible)
  SEED-02  Systolic below diastolic (values transposed at data entry)
  SEED-03  Pulse rate of 250 beats/min (implausible)
  SEED-04  Week 8 visit 21 days late (outside the +/- 5 day window)
  SEED-05  Week 2 visit 10 days early (outside the +/- 3 day window)
===========================================================================*/

data raw.vitals;
    set raw.vitals;

    if SUBJID = "&S_VS1" and VISITNUM = 4 then SYSBP = 310;

    if SUBJID = "&S_VS2" and VISITNUM = 5 then do;
        SYSBP = 78;
        DIABP = 120;
    end;

    if SUBJID = "&S_VS3" and VISITNUM = 3 then PULSE = 250;

    if SUBJID = "&S_VS4" and VISITNUM = 5 then VSDT = VSDT + 21;

    if SUBJID = "&S_VS5" and VISITNUM = 3 then VSDT = VSDT - 10;
run;


/*===========================================================================
  STEP 3: Laboratory defects
  SEED-06  Potassium of 12.5 mmol/L (upper limit of normal is 5.1)
  SEED-07  Negative glucose result
===========================================================================*/

data raw.labs;
    set raw.labs;

    if SUBJID = "&S_LB1" and LBTESTCD = 'K'    and VISITNUM = 6
        then LBSTRESN = 12.5;

    if SUBJID = "&S_LB2" and LBTESTCD = 'GLUC' and VISITNUM = 4
        then LBSTRESN = -3;
run;


/*===========================================================================
  STEP 4: Adverse event defects
  SEED-08  Event end date precedes the event start date
  SEED-09  Severe event with no action taken on study drug
  SEED-10  Event onset 10 days before the first dose
===========================================================================*/

data raw.ae;
    set raw.ae;

    if SUBJID = "&S_AE1" and AESEQ = 1 then AEENDT = AESTDT - 5;

    if SUBJID = "&S_AE2" and AESEQ = 1 then do;
        AESEV = 'SEVERE';
        AEACN = 'DOSE NOT CHANGED';
    end;

    if SUBJID = "&S_AE3" and AESEQ = 1 then do;
        AESTDT = RANDDT - 10;
        AEENDT = RANDDT -  3;
    end;
run;


/*===========================================================================
  STEP 5: Demographic defects
  SEED-11  Age of 82, above the protocol maximum of 75
  SEED-12  Race missing on a required field
===========================================================================*/

data raw.subjects;
    set raw.subjects;

    if SUBJID = "&S_DM1" then AGE  = 82;
    if SUBJID = "&S_DM2" then RACE = '';
run;


/*===========================================================================
  STEP 6: Exposure defects
  SEED-13  Last dose date precedes the first dose date
  SEED-14  Placebo subject recorded as receiving 25 mg
===========================================================================*/

data raw.dosing;
    set raw.dosing;

    if SUBJID = "&S_EX1" then do;
        EXENDT  = EXSTDT - 2;
        TRTDURD = EXENDT - EXSTDT + 1;
    end;

    if SUBJID = "&S_EX2" then EXDOSE = 25;
run;


/*===========================================================================
  STEP 7: Disposition defect
  SEED-15  Recorded as having completed the study, but the subject's last
           attended visit was Visit 4
===========================================================================*/

data raw.disp;
    set raw.disp;

    if SUBJID = "&S_DS1" then do;
        DSDECOD = 'COMPLETED';
        DSTERM  = 'COMPLETED STUDY';
    end;
run;


/*===========================================================================
  STEP 8: Answer key
  One record per seeded defect. 03_edit_checks.sas reconciles its findings
  against this dataset, so that any defect the checks fail to detect is
  reported explicitly rather than passing unnoticed.
===========================================================================*/

data raw.seeded_issues;
    length ISSUEID $10 SUBJID $10 SEEDDOM $8 ISSUE_DESC $120 EXPECT_CHK $10;

    ISSUEID='SEED-01'; SUBJID="&S_VS1"; SEEDDOM='VS'; EXPECT_CHK='VS01';
        ISSUE_DESC='Systolic BP of 310 mmHg at Week 4'; output;
    ISSUEID='SEED-02'; SUBJID="&S_VS2"; SEEDDOM='VS'; EXPECT_CHK='VS03';
        ISSUE_DESC='Systolic BP below diastolic BP at Week 8'; output;
    ISSUEID='SEED-03'; SUBJID="&S_VS3"; SEEDDOM='VS'; EXPECT_CHK='VS02';
        ISSUE_DESC='Pulse rate of 250 beats/min at Week 2'; output;
    ISSUEID='SEED-04'; SUBJID="&S_VS4"; SEEDDOM='SV'; EXPECT_CHK='SV01';
        ISSUE_DESC='Week 8 visit 21 days outside the protocol window'; output;
    ISSUEID='SEED-05'; SUBJID="&S_VS5"; SEEDDOM='SV'; EXPECT_CHK='SV01';
        ISSUE_DESC='Week 2 visit 10 days outside the protocol window'; output;
    ISSUEID='SEED-06'; SUBJID="&S_LB1"; SEEDDOM='LB'; EXPECT_CHK='LB01';
        ISSUE_DESC='Potassium of 12.5 mmol/L at Week 12'; output;
    ISSUEID='SEED-07'; SUBJID="&S_LB2"; SEEDDOM='LB'; EXPECT_CHK='LB02';
        ISSUE_DESC='Negative glucose result at Week 4'; output;
    ISSUEID='SEED-08'; SUBJID="&S_AE1"; SEEDDOM='AE'; EXPECT_CHK='AE01';
        ISSUE_DESC='Adverse event end date precedes start date'; output;
    ISSUEID='SEED-09'; SUBJID="&S_AE2"; SEEDDOM='AE'; EXPECT_CHK='AE03';
        ISSUE_DESC='Severe adverse event with no action taken on study drug'; output;
    ISSUEID='SEED-10'; SUBJID="&S_AE3"; SEEDDOM='AE'; EXPECT_CHK='AE02';
        ISSUE_DESC='Adverse event onset 10 days before first dose'; output;
    ISSUEID='SEED-11'; SUBJID="&S_DM1"; SEEDDOM='DM'; EXPECT_CHK='DM02';
        ISSUE_DESC='Age of 82 exceeds the protocol maximum of 75'; output;
    ISSUEID='SEED-12'; SUBJID="&S_DM2"; SEEDDOM='DM'; EXPECT_CHK='DM01';
        ISSUE_DESC='Race missing on a required demographic field'; output;
    ISSUEID='SEED-13'; SUBJID="&S_EX1"; SEEDDOM='EX'; EXPECT_CHK='EX01';
        ISSUE_DESC='Last dose date precedes first dose date'; output;
    ISSUEID='SEED-14'; SUBJID="&S_EX2"; SEEDDOM='EX'; EXPECT_CHK='EX02';
        ISSUE_DESC='Placebo subject recorded as receiving 25 mg'; output;
    ISSUEID='SEED-15'; SUBJID="&S_DS1"; SEEDDOM='DS'; EXPECT_CHK='DS01';
        ISSUE_DESC='Disposition of COMPLETED with last attended visit of 4'; output;

    label ISSUEID    = 'Seeded Issue Identifier'
          SUBJID     = 'Subject Identifier'
          SEEDDOM    = 'Domain Affected'
          ISSUE_DESC = 'Description of Seeded Issue'
          EXPECT_CHK = 'Edit Check Expected to Detect It';
run;


/*===========================================================================
  STEP 9: Confirmation
===========================================================================*/

title "Seeded Data Issues: Answer key for edit-check validation";
proc print data=raw.seeded_issues noobs label;
    var ISSUEID SUBJID SEEDDOM EXPECT_CHK ISSUE_DESC;
run;

title "Verification: the seeded values are present in the raw data";
proc sql;
    select "&S_VS1" as SUBJID length=10, 'VS: SYSBP at Visit 4' as Field length=28,
           put(max(SYSBP), 8.) as Value length=10
        from raw.vitals where SUBJID = "&S_VS1" and VISITNUM = 4
    union all
    select "&S_VS3", 'VS: PULSE at Visit 3', put(max(PULSE), 8.)
        from raw.vitals where SUBJID = "&S_VS3" and VISITNUM = 3
    union all
    select "&S_LB1", 'LB: Potassium at Visit 6', put(max(LBSTRESN), 8.1)
        from raw.labs where SUBJID = "&S_LB1" and LBTESTCD = 'K' and VISITNUM = 6
    union all
    select "&S_DM1", 'DM: AGE', put(max(AGE), 8.)
        from raw.subjects where SUBJID = "&S_DM1"
    union all
    select "&S_EX2", 'EX: EXDOSE (placebo arm)', put(max(EXDOSE), 8.)
        from raw.dosing where SUBJID = "&S_EX2";
quit;

title;


/*****************************************************************************
* End of program
*****************************************************************************/
