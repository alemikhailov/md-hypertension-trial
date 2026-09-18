# Simulated Phase 2 Hypertension Trial. CDISC SDTM Build and Data Management

An end-to-end clinical data pipeline built in SAS on a **simulated** Phase 2
trial: source data generation, CDISC SDTM domain mapping, and a validated
suite of programmed edit checks.

The study, the drug, and the sites are fictitious. No real patient data is
used anywhere in this repository. The purpose is to demonstrate the
programming and data management workflow that supports a clinical trial
database, not to produce a scientific finding.

**Status:** Stage 1 complete (SDTM + edit checks). ADaM datasets and TFLs in progress.

---

## Study design

| | |
|---|---|
| Protocol | MHT-2026-001 |
| Design | Phase 2, randomized, double-blind, placebo-controlled |
| Arms | Placebo, MHT-101 25 mg, MHT-101 50 mg |
| Randomization | Stratified permuted-block, blocks of 6, stratified by site x hypertension stage |
| Sites | 3 |
| Subjects | 220 screened, 205 randomized, 182 completed |
| Visits | 7 (Screening, Baseline, Weeks 2/4/8/12, Follow-up Week 14) |
| Primary endpoint | Change from baseline in seated systolic blood pressure at Week 12 |


---

## Repository structure

```
programs/    SAS programs, run in numerical order
data/raw/    Simulated source datasets
data/sdtm/   CDISC SDTM v3.2 domains
docs/        Protocol synopsis
output/      Data management query log
```

## Programs

| Program | Purpose |
|---|---|
| `01_simulate_source.sas` | Generates 7 raw source datasets: demographics, randomization, vital signs, adverse events, labs, exposure, disposition |
| `01b_seed_data_issues.sas` | Introduces 15 known data defects and writes an answer key used to validate the edit checks |
| `02_create_sdtm.sas` | Maps raw source data into 8 SDTM domains |
| `03_edit_checks.sas` | Runs 21 programmed edit checks and produces the query log |

Run in order. `01b` must follow `01` directly, as two of its defects shift
dates relative to their current values.

---

## SDTM domains

| Domain | Structure | Records |
|---|---|---|
| DM | One per subject, including screen failures | 220 |
| SUPPDM | Stratification factor as a supplemental qualifier | 220 |
| SV | One per subject per attended visit | 1,386 |
| VS | One per vital sign measurement | 6,074 |
| LB | One per laboratory result | 7,800 |
| AE | One per adverse event | 266 |
| EX | One per subject | 205 |
| DS | One per subject, including screen failures | 220 |

Conventions applied: ISO 8601 character dates (`--DTC`), study day relative
to first dose with no Day 0 (`--DY`), sequence numbers unique within
`USUBJID` (`--SEQ`), baseline flags set to the last non-missing assessment
on or before first dose (`--BLFL`), and SDTMIG variable ordering.

Screen failures are retained in DM with `ARMCD = 'SCRNFAIL'` and null
treatment reference dates.

---

## Edit checks

21 checks across seven domains, executed through a single reusable macro so
that every finding lands in one query dataset with a consistent structure:
subject, check identifier, severity, query text written for a site
coordinator, and the values that triggered it.

| Domain | Checks |
|---|---|
| DM | Missing required fields, age outside eligibility range, missing first dose date, end date before start |
| VS | Systolic range, pulse range, systolic not greater than diastolic, diastolic range, temperature range, missing expected measurement |
| SV | Visit outside the protocol window |
| LB | Grossly out of reference range, negative result, no baseline available |
| AE | End before start, onset before first dose, severe event with no action taken, ongoing event, serious event |
| EX | Dose date logic, recorded dose inconsistent with randomized arm |
| DS | Disposition inconsistent with visit history, missing records |

**Result:** 132 queries raised across 17 checks. Output is written to
`output/MHT-2026-001_Query_Log.xlsx` with three sheets — query log, check
summary, and validation.

### Validating the checks

An edit check program that has only been run against clean data has not been
tested. `01b_seed_data_issues.sas` plants 15 defects — one for each check
type — and records them in an answer key. `03_edit_checks.sas` reconciles
its findings against that key and reports any seeded defect it failed to
catch.

**Detection rate: 15 of 15 (100%).**

This mirrors how edit check specifications are qualified before database
go-live: seed defects of each type the checks are meant to catch, run the
checks, and confirm every one is reported.

---

## Reproducibility

Every DATA step that draws random numbers calls `streaminit` with a fixed
seed, so the simulated data regenerates identically on every run. Seeding
only the first DATA step is not sufficient — later steps fall back to a
clock-based seed.

Edit check targets in `01b` are selected by position in a sorted list rather
than at random, so the answer key stays valid across runs.

---

## Environment

SAS 9.4 (SAS OnDemand for Academics). No external dependencies.

## Author

Aleksandr Mikhailov
