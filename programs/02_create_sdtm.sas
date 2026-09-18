/*****************************************************************************
* Program:     02_create_sdtm.sas
* Study:       MHT-2026-001
*              A Phase 2, Randomized, Double-Blind, Placebo-Controlled Study
*              of MHT-101 in Adults with Stage 1-2 Hypertension
*
* Purpose:     Map the simulated raw source datasets created by
*              01_simulate_source.sas into CDISC SDTM v3.2 domains.
*
* Input:       RAW.SUBJECTS, RAW.SCREENFAIL, RAW.VITALS, RAW.AE,
*              RAW.LABS, RAW.DOSING, RAW.DISP
*
* Output:      SDTM.DM      Demographics              (one record per subject)
*              SDTM.SUPPDM  Supplemental Qualifiers   (stratification factor)
*              SDTM.SV      Subject Visits            (one per subject/visit)
*              SDTM.VS      Vital Signs               (one per measurement)
*              SDTM.LB      Laboratory Test Results   (one per test)
*              SDTM.AE      Adverse Events            (one per event)
*              SDTM.EX      Exposure                  (one per subject)
*              SDTM.DS      Disposition               (one per subject)
*
* Conventions applied:
*   - USUBJID is unique across the study: STUDYID prefix + SUBJID
*   - All dates are ISO 8601 character strings (--DTC), never numeric
*   - Study day (--DY) is relative to RFSTDTC, with no Day 0
*   - --SEQ is unique and sequential within USUBJID
*   - Baseline flag (--BLFL) marks the last non-missing assessment
*     on or before the first dose date
*   - Variable order is controlled by RETAIN so domains match the
*     order published in the SDTM Implementation Guide
*
* Author:      Aleksandr Mikhailov
* Date:        September 2026
*****************************************************************************/

options notes source dlcreatedir;

/*--- Libraries -----------------------------------------------------------*/
libname raw  "/home/u63064984/md-hypertension-trial/data/raw";
libname sdtm "/home/u63064984/md-hypertension-trial/data/sdtm";

/*--- Study-level constants ----------------------------------------------*/
%let studyid = MHT-2026-001;
%let country = USA;


/*===========================================================================
  UTILITY MACRO: Study day
  SDTM study day is counted from the reference start date (RFSTDTC, here the
  first dose date). There is no Day 0: the reference date itself is Day 1,
  and the day before it is Day -1.
===========================================================================*/

%macro studyday(dt=, ref=, dy=);
    if not missing(&dt) and not missing(&ref) then do;
        if &dt >= &ref then &dy = &dt - &ref + 1;
        else                &dy = &dt - &ref;
    end;
    else &dy = .;
%mend studyday;


/*===========================================================================
  STEP 1: Reference dates
  RFSTDTC (first dose) and RFENDTC (end of participation) are needed by every
  other domain to derive study day, so they are built first and carried
  forward on a small lookup dataset.
===========================================================================*/

proc sort data=raw.subjects  out=work.sub_s;  by SUBJID; run;
proc sort data=raw.dosing    out=work.dos_s(keep=SUBJID EXSTDT EXENDT);
    by SUBJID;
run;
proc sort data=raw.disp      out=work.dis_s(keep=SUBJID DSSTDT DSDECOD DSTERM);
    by SUBJID;
run;

data work.refdates;
    merge work.sub_s(in=a keep=SUBJID SCRNDT RANDDT)
          work.dos_s
          work.dis_s(keep=SUBJID DSSTDT);
    by SUBJID;
    if a;

    length USUBJID $30;
    USUBJID = catx('-', "&studyid", SUBJID);

    RFSTDT = EXSTDT;    /* first dose  */
    RFENDT = DSSTDT;    /* last visit  */

    keep SUBJID USUBJID SCRNDT RANDDT RFSTDT RFENDT EXSTDT EXENDT;
    format SCRNDT RANDDT RFSTDT RFENDT EXSTDT EXENDT yymmdd10.;
run;


/*===========================================================================
  STEP 2: DM - Demographics
  One record per subject. Randomized subjects and screen failures are both
  represented; screen failures carry ARMCD = 'SCRNFAIL' and have no
  treatment reference dates.
===========================================================================*/

/*--- Randomized subjects ---*/
data work.dm_rand;
    merge work.sub_s(in=a) work.refdates(keep=SUBJID RFSTDT RFENDT EXSTDT EXENDT);
    by SUBJID;
    if a;

    length STUDYID $20 DOMAIN $2 USUBJID $30 SUBJID $10
           RFSTDTC RFENDTC RFXSTDTC RFXENDTC RFICDTC DMDTC $10
           SITEID $3 AGEU $10 SEX $1 RACE $45 ETHNIC $30
           ARMCD $8 ARM $20 ACTARMCD $8 ACTARM $20 COUNTRY $3;

    STUDYID  = "&studyid";
    DOMAIN   = 'DM';
    USUBJID  = catx('-', "&studyid", SUBJID);

    RFSTDTC  = put(RFSTDT, e8601da.);
    RFENDTC  = put(RFENDT, e8601da.);
    RFXSTDTC = put(EXSTDT, e8601da.);
    RFXENDTC = put(EXENDT, e8601da.);
    RFICDTC  = put(SCRNDT, e8601da.);
    DMDTC    = put(SCRNDT, e8601da.);

    AGEU     = 'YEARS';
    ACTARMCD = ARMCD;       /* no treatment switching in this study */
    ACTARM   = ARM;
    COUNTRY  = "&country";

    %studyday(dt=SCRNDT, ref=RFSTDT, dy=DMDY);

    keep STUDYID DOMAIN USUBJID SUBJID RFSTDTC RFENDTC RFXSTDTC RFXENDTC
         RFICDTC SITEID AGE AGEU SEX RACE ETHNIC ARMCD ARM ACTARMCD ACTARM
         COUNTRY DMDTC DMDY;
run;

/*--- Screen failures ---*/
data work.dm_sf;
    set raw.screenfail;

    length STUDYID $20 DOMAIN $2 USUBJID $30 SUBJID $10
           RFSTDTC RFENDTC RFXSTDTC RFXENDTC RFICDTC DMDTC $10
           SITEID $3 AGEU $10 SEX $1 RACE $45 ETHNIC $30
           ARMCD $8 ARM $20 ACTARMCD $8 ACTARM $20 COUNTRY $3;

    STUDYID  = "&studyid";
    DOMAIN   = 'DM';
    USUBJID  = catx('-', "&studyid", SUBJID);

    /*--- Never treated: reference dates stay null ---*/
    RFSTDTC  = '';
    RFENDTC  = '';
    RFXSTDTC = '';
    RFXENDTC = '';
    RFICDTC  = put(SCRNDT, e8601da.);
    DMDTC    = put(SCRNDT, e8601da.);

    AGEU     = 'YEARS';
    ARMCD    = 'SCRNFAIL';
    ARM      = 'Screen Failure';
    ACTARMCD = 'SCRNFAIL';
    ACTARM   = 'Screen Failure';
    COUNTRY  = "&country";
    DMDY     = .;

    keep STUDYID DOMAIN USUBJID SUBJID RFSTDTC RFENDTC RFXSTDTC RFXENDTC
         RFICDTC SITEID AGE AGEU SEX RACE ETHNIC ARMCD ARM ACTARMCD ACTARM
         COUNTRY DMDTC DMDY;
run;

data sdtm.dm;
    set work.dm_rand work.dm_sf;

    /*--- SDTMIG variable order ---*/
    retain STUDYID DOMAIN USUBJID SUBJID RFSTDTC RFENDTC RFXSTDTC RFXENDTC
           RFICDTC SITEID AGE AGEU SEX RACE ETHNIC ARMCD ARM ACTARMCD ACTARM
           COUNTRY DMDTC DMDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          SUBJID   = 'Subject Identifier for the Study'
          RFSTDTC  = 'Subject Reference Start Date/Time'
          RFENDTC  = 'Subject Reference End Date/Time'
          RFXSTDTC = 'Date/Time of First Study Treatment'
          RFXENDTC = 'Date/Time of Last Study Treatment'
          RFICDTC  = 'Date/Time of Informed Consent'
          SITEID   = 'Study Site Identifier'
          AGE      = 'Age'
          AGEU     = 'Age Units'
          SEX      = 'Sex'
          RACE     = 'Race'
          ETHNIC   = 'Ethnicity'
          ARMCD    = 'Planned Arm Code'
          ARM      = 'Description of Planned Arm'
          ACTARMCD = 'Actual Arm Code'
          ACTARM   = 'Description of Actual Arm'
          COUNTRY  = 'Country'
          DMDTC    = 'Date/Time of Collection'
          DMDY     = 'Study Day of Collection';
run;

proc sort data=sdtm.dm; by USUBJID; run;


/*===========================================================================
  STEP 3: SUPPDM - Supplemental Qualifiers for DM
  Hypertension stage at screening is a randomization stratification factor.
  It is not a standard DM variable, so it is carried as a supplemental
  qualifier, which is how non-standard collected data is represented in SDTM.
===========================================================================*/

data sdtm.suppdm;
    set raw.subjects(keep=SUBJID HTNSTAGE)
        raw.screenfail(keep=SUBJID HTNSTAGE);

    length STUDYID $20 RDOMAIN $2 USUBJID $30 IDVAR $8 IDVARVAL $20
           QNAM $8 QLABEL $40 QVAL $200 QORIG $20 QEVAL $40;

    STUDYID  = "&studyid";
    RDOMAIN  = 'DM';
    USUBJID  = catx('-', "&studyid", SUBJID);
    IDVAR    = '';          /* DM is one record per subject: no key needed */
    IDVARVAL = '';
    QNAM     = 'HTNSTAGE';
    QLABEL   = 'Hypertension Stage at Screening';
    QVAL     = strip(HTNSTAGE);
    QORIG    = 'CRF';
    QEVAL    = '';

    keep STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;
    retain STUDYID RDOMAIN USUBJID IDVAR IDVARVAL QNAM QLABEL QVAL QORIG QEVAL;

    label STUDYID  = 'Study Identifier'
          RDOMAIN  = 'Related Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          IDVAR    = 'Identifying Variable'
          IDVARVAL = 'Identifying Variable Value'
          QNAM     = 'Qualifier Variable Name'
          QLABEL   = 'Qualifier Variable Label'
          QVAL     = 'Data Value'
          QORIG    = 'Origin'
          QEVAL    = 'Evaluator';
run;

proc sort data=sdtm.suppdm; by USUBJID QNAM; run;


/*===========================================================================
  STEP 4: SV - Subject Visits
  One record per subject per attended visit. Derived from the vital signs
  source, which contains a record for every visit the subject attended.
===========================================================================*/

proc sort data=raw.vitals(keep=SUBJID VISITNUM VISITNAM VSDT)
          out=work.sv_pre nodupkey;
    by SUBJID VISITNUM;
run;

data sdtm.sv;
    merge work.sv_pre(in=a) work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;

    length STUDYID $20 DOMAIN $2 USUBJID $30 VISIT $30 SVSTDTC $10;

    STUDYID = "&studyid";
    DOMAIN  = 'SV';
    VISIT   = VISITNAM;
    SVSTDTC = put(VSDT, e8601da.);

    %studyday(dt=VSDT, ref=RFSTDT, dy=SVSTDY);

    keep STUDYID DOMAIN USUBJID VISITNUM VISIT SVSTDTC SVSTDY;
    retain STUDYID DOMAIN USUBJID VISITNUM VISIT SVSTDTC SVSTDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          VISITNUM = 'Visit Number'
          VISIT    = 'Visit Name'
          SVSTDTC  = 'Start Date/Time of Visit'
          SVSTDY   = 'Study Day of Start of Visit';
run;

proc sort data=sdtm.sv; by USUBJID VISITNUM; run;


/*===========================================================================
  STEP 5: VS - Vital Signs
  The source holds one wide record per subject per visit. SDTM findings
  domains are vertical: one record per measurement. The transposition below
  also drops measurements that were not collected (weight is only taken at
  three visits, and a small share of BP readings are missing).
===========================================================================*/

data work.vs_long;
    set raw.vitals(keep=SUBJID VISITNUM VISITNAM VSDT
                        SYSBP DIABP PULSE TEMP WEIGHTV);

    length VSTESTCD $8 VSTEST $40 VSORRESU $10;

    array _v{5} SYSBP DIABP PULSE TEMP WEIGHTV;

    do _i = 1 to 5;
        select (_i);
            when (1) do;
                VSTESTCD='SYSBP';  VSTEST='Systolic Blood Pressure';
                VSORRESU='mmHg';
            end;
            when (2) do;
                VSTESTCD='DIABP';  VSTEST='Diastolic Blood Pressure';
                VSORRESU='mmHg';
            end;
            when (3) do;
                VSTESTCD='PULSE';  VSTEST='Pulse Rate';
                VSORRESU='beats/min';
            end;
            when (4) do;
                VSTESTCD='TEMP';   VSTEST='Temperature';
                VSORRESU='C';
            end;
            when (5) do;
                VSTESTCD='WEIGHT'; VSTEST='Weight';
                VSORRESU='kg';
            end;
            otherwise;
        end;

        VSSTRESN = _v{_i};

        /*--- Only measurements that were actually taken become records ---*/
        if not missing(VSSTRESN) then output;
    end;

    keep SUBJID VISITNUM VISITNAM VSDT VSTESTCD VSTEST VSORRESU VSSTRESN;
run;

/*--- Attach reference dates ---*/
proc sort data=work.vs_long; by SUBJID; run;

data work.vs_ref;
    merge work.vs_long(in=a) work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;
run;

/*--- Baseline: last non-missing result on or before first dose, per test ---*/
proc sort data=work.vs_ref out=work.vs_cand
          (where=(not missing(RFSTDT) and VSDT <= RFSTDT));
    by USUBJID VSTESTCD VSDT VISITNUM;
run;

data work.vs_blfl(keep=USUBJID VSTESTCD VISITNUM _BLFL);
    set work.vs_cand;
    by USUBJID VSTESTCD;
    length _BLFL $1;
    if last.VSTESTCD then do;
        _BLFL = 'Y';
        output;
    end;
run;

proc sort data=work.vs_ref;  by USUBJID VSTESTCD VISITNUM; run;
proc sort data=work.vs_blfl; by USUBJID VSTESTCD VISITNUM; run;

data work.vs_flagged;
    merge work.vs_ref(in=a) work.vs_blfl;
    by USUBJID VSTESTCD VISITNUM;
    if a;
run;

/*--- Assign VSSEQ within subject, ordered by visit then test ---*/
proc sort data=work.vs_flagged; by USUBJID VISITNUM VSTESTCD; run;

data sdtm.vs;
    set work.vs_flagged;
    by USUBJID;

    length STUDYID $20 DOMAIN $2 VISIT $30
           VSORRES VSSTRESC $20 VSSTRESU $10 VSBLFL $1 VSDTC $10;
    retain VSSEQ;

    STUDYID = "&studyid";
    DOMAIN  = 'VS';
    VISIT   = VISITNAM;

    if first.USUBJID then VSSEQ = 0;
    VSSEQ + 1;

    /*--- Collected result and standardized result are identical here:
          a single unit is used for each test across all sites ---*/
    VSORRES  = strip(put(VSSTRESN, best12.));
    VSSTRESC = VSORRES;
    VSSTRESU = VSORRESU;

    VSBLFL = _BLFL;
    VSDTC  = put(VSDT, e8601da.);

    %studyday(dt=VSDT, ref=RFSTDT, dy=VSDY);

    keep STUDYID DOMAIN USUBJID VSSEQ VSTESTCD VSTEST VSORRES VSORRESU
         VSSTRESC VSSTRESN VSSTRESU VSBLFL VISITNUM VISIT VSDTC VSDY;
    retain STUDYID DOMAIN USUBJID VSSEQ VSTESTCD VSTEST VSORRES VSORRESU
           VSSTRESC VSSTRESN VSSTRESU VSBLFL VISITNUM VISIT VSDTC VSDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          VSSEQ    = 'Sequence Number'
          VSTESTCD = 'Vital Signs Test Short Name'
          VSTEST   = 'Vital Signs Test Name'
          VSORRES  = 'Result or Finding in Original Units'
          VSORRESU = 'Original Units'
          VSSTRESC = 'Character Result/Finding in Std Format'
          VSSTRESN = 'Numeric Result/Finding in Standard Units'
          VSSTRESU = 'Standard Units'
          VSBLFL   = 'Baseline Flag'
          VISITNUM = 'Visit Number'
          VISIT    = 'Visit Name'
          VSDTC    = 'Date/Time of Measurements'
          VSDY     = 'Study Day of Vital Signs';
run;


/*===========================================================================
  STEP 6: LB - Laboratory Test Results
  The source is already vertical. Derivation adds the reference range
  indicator (LBNRIND), the baseline flag, and study day.
===========================================================================*/

proc sort data=raw.labs(keep=SUBJID VISITNUM VISITNAM LBDT LBTESTCD LBTEST
                             LBCAT LBSTRESN LBSTRESU LBSTNRLO LBSTNRHI)
          out=work.lb_pre;
    by SUBJID;
run;

data work.lb_ref;
    merge work.lb_pre(in=a) work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;
run;

/*--- Baseline: last non-missing result on or before first dose, per test ---*/
proc sort data=work.lb_ref out=work.lb_cand
          (where=(not missing(LBSTRESN) and not missing(RFSTDT)
                  and LBDT <= RFSTDT));
    by USUBJID LBTESTCD LBDT VISITNUM;
run;

data work.lb_blfl(keep=USUBJID LBTESTCD VISITNUM _BLFL);
    set work.lb_cand;
    by USUBJID LBTESTCD;
    length _BLFL $1;
    if last.LBTESTCD then do;
        _BLFL = 'Y';
        output;
    end;
run;

proc sort data=work.lb_ref;  by USUBJID LBTESTCD VISITNUM; run;
proc sort data=work.lb_blfl; by USUBJID LBTESTCD VISITNUM; run;

data work.lb_flagged;
    merge work.lb_ref(in=a) work.lb_blfl;
    by USUBJID LBTESTCD VISITNUM;
    if a;
run;

proc sort data=work.lb_flagged; by USUBJID VISITNUM LBCAT LBTESTCD; run;

data sdtm.lb;
    set work.lb_flagged;
    by USUBJID;

    length STUDYID $20 DOMAIN $2 VISIT $30
           LBORRES LBSTRESC $20 LBORRESU $20 LBNRIND $10 LBBLFL $1 LBDTC $10;
    retain LBSEQ;

    STUDYID = "&studyid";
    DOMAIN  = 'LB';
    VISIT   = VISITNAM;

    if first.USUBJID then LBSEQ = 0;
    LBSEQ + 1;

    LBORRES  = strip(put(LBSTRESN, best12.));
    LBORRESU = LBSTRESU;
    LBSTRESC = LBORRES;

    /*--- Reference range indicator ---*/
    if missing(LBSTRESN) then LBNRIND = '';
    else if LBSTRESN < LBSTNRLO then LBNRIND = 'LOW';
    else if LBSTRESN > LBSTNRHI then LBNRIND = 'HIGH';
    else                             LBNRIND = 'NORMAL';

    LBBLFL = _BLFL;
    LBDTC  = put(LBDT, e8601da.);

    %studyday(dt=LBDT, ref=RFSTDT, dy=LBDY);

    keep STUDYID DOMAIN USUBJID LBSEQ LBTESTCD LBTEST LBCAT LBORRES LBORRESU
         LBSTRESC LBSTRESN LBSTRESU LBSTNRLO LBSTNRHI LBNRIND LBBLFL
         VISITNUM VISIT LBDTC LBDY;
    retain STUDYID DOMAIN USUBJID LBSEQ LBTESTCD LBTEST LBCAT LBORRES LBORRESU
           LBSTRESC LBSTRESN LBSTRESU LBSTNRLO LBSTNRHI LBNRIND LBBLFL
           VISITNUM VISIT LBDTC LBDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          LBSEQ    = 'Sequence Number'
          LBTESTCD = 'Lab Test or Examination Short Name'
          LBTEST   = 'Lab Test or Examination Name'
          LBCAT    = 'Category for Lab Test'
          LBORRES  = 'Result or Finding in Original Units'
          LBORRESU = 'Original Units'
          LBSTRESC = 'Character Result/Finding in Std Format'
          LBSTRESN = 'Numeric Result/Finding in Standard Units'
          LBSTRESU = 'Standard Units'
          LBSTNRLO = 'Reference Range Lower Limit in Std Units'
          LBSTNRHI = 'Reference Range Upper Limit in Std Units'
          LBNRIND  = 'Reference Range Indicator'
          LBBLFL   = 'Baseline Flag'
          VISITNUM = 'Visit Number'
          VISIT    = 'Visit Name'
          LBDTC    = 'Date/Time of Specimen Collection'
          LBDY     = 'Study Day of Specimen Collection';
run;


/*===========================================================================
  STEP 7: AE - Adverse Events
  One record per event. AESEQ is re-derived after sorting by onset date so
  that sequence numbers follow the order in which events occurred.
===========================================================================*/

proc sort data=raw.ae(keep=SUBJID AETERM AEDECOD AEBODSYS AESEV AEREL AESER
                           AEACN AEOUT AESTDT AEENDT)
          out=work.ae_pre;
    by SUBJID;
run;

data work.ae_ref;
    merge work.ae_pre(in=a) work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;
run;

proc sort data=work.ae_ref; by USUBJID AESTDT AEDECOD; run;

data sdtm.ae;
    set work.ae_ref;
    by USUBJID;

    length STUDYID $20 DOMAIN $2 AESTDTC AEENDTC $10;
    retain AESEQ;

    STUDYID = "&studyid";
    DOMAIN  = 'AE';

    if first.USUBJID then AESEQ = 0;
    AESEQ + 1;

    AESTDTC = put(AESTDT, e8601da.);
    AEENDTC = put(AEENDT, e8601da.);

    %studyday(dt=AESTDT, ref=RFSTDT, dy=AESTDY);
    %studyday(dt=AEENDT, ref=RFSTDT, dy=AEENDY);

    keep STUDYID DOMAIN USUBJID AESEQ AETERM AEDECOD AEBODSYS AESEV AESER
         AEREL AEACN AEOUT AESTDTC AEENDTC AESTDY AEENDY;
    retain STUDYID DOMAIN USUBJID AESEQ AETERM AEDECOD AEBODSYS AESEV AESER
           AEREL AEACN AEOUT AESTDTC AEENDTC AESTDY AEENDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          AESEQ    = 'Sequence Number'
          AETERM   = 'Reported Term for the Adverse Event'
          AEDECOD  = 'Dictionary-Derived Term'
          AEBODSYS = 'Body System or Organ Class'
          AESEV    = 'Severity/Intensity'
          AESER    = 'Serious Event'
          AEREL    = 'Causality'
          AEACN    = 'Action Taken with Study Treatment'
          AEOUT    = 'Outcome of Adverse Event'
          AESTDTC  = 'Start Date/Time of Adverse Event'
          AEENDTC  = 'End Date/Time of Adverse Event'
          AESTDY   = 'Study Day of Start of Adverse Event'
          AEENDY   = 'Study Day of End of Adverse Event';
run;


/*===========================================================================
  STEP 8: EX - Exposure
  One record per subject covering the continuous dosing period. A study with
  dose interruptions would require one record per constant-dose interval.
===========================================================================*/

proc sort data=raw.dosing out=work.ex_pre; by SUBJID; run;

data sdtm.ex;
    merge work.ex_pre(in=a) work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;

    length STUDYID $20 DOMAIN $2 EXTRT $30 EXDOSU $10 EXDOSFRM $20
           EXROUTE $20 EXSTDTC EXENDTC $10;

    STUDYID = "&studyid";
    DOMAIN  = 'EX';
    EXSEQ   = 1;

    EXSTDTC = put(EXSTDT, e8601da.);
    EXENDTC = put(EXENDT, e8601da.);

    %studyday(dt=EXSTDT, ref=RFSTDT, dy=EXSTDY);
    %studyday(dt=EXENDT, ref=RFSTDT, dy=EXENDY);

    keep STUDYID DOMAIN USUBJID EXSEQ EXTRT EXDOSE EXDOSU EXDOSFRM EXROUTE
         EXSTDTC EXENDTC EXSTDY EXENDY;
    retain STUDYID DOMAIN USUBJID EXSEQ EXTRT EXDOSE EXDOSU EXDOSFRM EXROUTE
           EXSTDTC EXENDTC EXSTDY EXENDY;

    label STUDYID  = 'Study Identifier'
          DOMAIN   = 'Domain Abbreviation'
          USUBJID  = 'Unique Subject Identifier'
          EXSEQ    = 'Sequence Number'
          EXTRT    = 'Name of Treatment'
          EXDOSE   = 'Dose per Administration'
          EXDOSU   = 'Dose Units'
          EXDOSFRM = 'Dose Form'
          EXROUTE  = 'Route of Administration'
          EXSTDTC  = 'Start Date/Time of Treatment'
          EXENDTC  = 'End Date/Time of Treatment'
          EXSTDY   = 'Study Day of Start of Treatment'
          EXENDY   = 'Study Day of End of Treatment';
run;

proc sort data=sdtm.ex; by USUBJID; run;


/*===========================================================================
  STEP 9: DS - Disposition
  One record per randomized subject describing study completion or the
  reason for discontinuation, plus one record per screen failure.
===========================================================================*/

data work.ds_rand;
    merge raw.disp(in=a keep=SUBJID DSDECOD DSTERM DSSTDT)
          work.refdates(keep=SUBJID USUBJID RFSTDT);
    by SUBJID;
    if a;

    length DSCAT $30;
    DSCAT  = 'DISPOSITION EVENT';
    DSSTDT2 = DSSTDT;
run;

data work.ds_sf;
    set raw.screenfail(keep=SUBJID SCRNDT);

    length USUBJID $30 DSCAT $30 DSDECOD $40 DSTERM $60;
    USUBJID = catx('-', "&studyid", SUBJID);
    DSCAT   = 'DISPOSITION EVENT';
    DSDECOD = 'SCREEN FAILURE';
    DSTERM  = 'SCREEN FAILURE - ELIGIBILITY CRITERIA NOT MET';
    DSSTDT2 = SCRNDT;
    RFSTDT  = .;

    keep SUBJID USUBJID DSCAT DSDECOD DSTERM DSSTDT2 RFSTDT;
run;

data sdtm.ds;
    set work.ds_rand work.ds_sf;

    length STUDYID $20 DOMAIN $2 DSSTDTC $10;

    STUDYID = "&studyid";
    DOMAIN  = 'DS';
    DSSEQ   = 1;

    DSSTDTC = put(DSSTDT2, e8601da.);
    %studyday(dt=DSSTDT2, ref=RFSTDT, dy=DSSTDY);

    keep STUDYID DOMAIN USUBJID DSSEQ DSTERM DSDECOD DSCAT DSSTDTC DSSTDY;
    retain STUDYID DOMAIN USUBJID DSSEQ DSTERM DSDECOD DSCAT DSSTDTC DSSTDY;

    label STUDYID = 'Study Identifier'
          DOMAIN  = 'Domain Abbreviation'
          USUBJID = 'Unique Subject Identifier'
          DSSEQ   = 'Sequence Number'
          DSTERM  = 'Reported Term for the Disposition Event'
          DSDECOD = 'Standardized Disposition Term'
          DSCAT   = 'Category for Disposition Event'
          DSSTDTC = 'Start Date/Time of Disposition Event'
          DSSTDY  = 'Study Day of Start of Disposition Event';
run;

proc sort data=sdtm.ds; by USUBJID; run;


/*===========================================================================
  STEP 10: SDTM build summary
  Record counts and the structural checks that every domain must satisfy
  before edit checks are run in the next program.
===========================================================================*/

title "SDTM Build Summary 1: Record counts by domain";
proc sql;
    select 'DM'     as Domain length=8, count(*) as Records from sdtm.dm
    union all
    select 'SUPPDM' as Domain length=8, count(*) as Records from sdtm.suppdm
    union all
    select 'SV'     as Domain length=8, count(*) as Records from sdtm.sv
    union all
    select 'VS'     as Domain length=8, count(*) as Records from sdtm.vs
    union all
    select 'LB'     as Domain length=8, count(*) as Records from sdtm.lb
    union all
    select 'AE'     as Domain length=8, count(*) as Records from sdtm.ae
    union all
    select 'EX'     as Domain length=8, count(*) as Records from sdtm.ex
    union all
    select 'DS'     as Domain length=8, count(*) as Records from sdtm.ds;
quit;

title "SDTM Build Summary 2: DM subject accounting by arm";
proc freq data=sdtm.dm;
    tables ARM / nocum;
run;

title "SDTM Build Summary 3: Orphan USUBJIDs (must return zero rows)";
proc sql;
    select 'VS' as Domain length=8, USUBJID
        from sdtm.vs where USUBJID not in (select USUBJID from sdtm.dm)
    union all
    select 'LB' as Domain length=8, USUBJID
        from sdtm.lb where USUBJID not in (select USUBJID from sdtm.dm)
    union all
    select 'AE' as Domain length=8, USUBJID
        from sdtm.ae where USUBJID not in (select USUBJID from sdtm.dm)
    union all
    select 'EX' as Domain length=8, USUBJID
        from sdtm.ex where USUBJID not in (select USUBJID from sdtm.dm)
    union all
    select 'DS' as Domain length=8, USUBJID
        from sdtm.ds where USUBJID not in (select USUBJID from sdtm.dm);
quit;

title "SDTM Build Summary 4: Duplicate --SEQ keys (must return zero rows)";
proc sql;
    select 'VS' as Domain length=8, USUBJID, VSSEQ as Seq
        from sdtm.vs group by USUBJID, VSSEQ having count(*) > 1
    union all
    select 'LB' as Domain length=8, USUBJID, LBSEQ as Seq
        from sdtm.lb group by USUBJID, LBSEQ having count(*) > 1
    union all
    select 'AE' as Domain length=8, USUBJID, AESEQ as Seq
        from sdtm.ae group by USUBJID, AESEQ having count(*) > 1;
quit;

title "SDTM Build Summary 5: Baseline flag counts (one per subject per test)";
proc sql;
    select 'VS' as Domain length=8, VSTESTCD as Testcd length=8,
           count(*) as Baseline_Records
        from sdtm.vs where VSBLFL = 'Y'
        group by VSTESTCD
    union all
    select 'LB' as Domain length=8, LBTESTCD as Testcd length=8,
           count(*) as Baseline_Records
        from sdtm.lb where LBBLFL = 'Y'
        group by LBTESTCD;
quit;

title "SDTM Build Summary 6: Study day range check (no Day 0 permitted)";
proc sql;
    select min(VSDY) as Min_VSDY, max(VSDY) as Max_VSDY,
           sum(case when VSDY = 0 then 1 else 0 end) as Day_Zero_Count
        from sdtm.vs;
quit;

title "SDTM Build Summary 7: DM structure";
proc contents data=sdtm.dm varnum;
run;

title;


/*****************************************************************************
* End of program
*****************************************************************************/
