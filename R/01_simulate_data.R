# =============================================================================
# 01_simulate_data.R
# Coastal Beginnings Study (fictional): simulate a REDCap-style export
#
# Creates synthetic records for a fictional pregnancy cohort, in the same
# "flat" format REDCap produces for a longitudinal project: one row per
# participant per event, with raw coded values.
#
# A small number of realistic data problems are deliberately added, and
# listed in data/raw/seeded_issues.csv, so the quality checks can be tested.
#
# All data are simulated. No real people are represented.
# =============================================================================

library(tidyverse)
library(here)

set.seed(2026)

n          <- 300                    # participants
export_day <- as.Date("2026-11-15")  # pretend export date

# --- Helpers -----------------------------------------------------------------

# REDCap's rounddown(x, 1): round down to one decimal place
rounddown1 <- function(x) floor(x * 10) / 10

# Weeks between two dates, the way the dictionary's calc fields do it
weeks_between <- function(start, end) {
  rounddown1(as.numeric(end - start) / 7)
}

# --- Enrolment ---------------------------------------------------------------

enrol <- tibble(
  record_id = as.character(1001:(1000 + n)),
  site      = sample(1:3, n, replace = TRUE, prob = c(0.45, 0.35, 0.20)),
  consent   = 1L,
  age       = pmin(pmax(round(rnorm(n, 31, 5)), 17), 45),
  education = sample(c(1, 2, 3, 4, 99), n, replace = TRUE,
                     prob = c(0.15, 0.30, 0.35, 0.17, 0.03)),
  parity    = pmin(rpois(n, 0.8), 6),
  height_cm = round(rnorm(n, 164, 7), 1),
  weight_kg = round(exp(rnorm(n, log(68), 0.18)), 1),
  smoking   = sample(0:2, n, replace = TRUE, prob = c(0.80, 0.12, 0.08)),
  lmp_date  = as.Date("2025-01-01") + sample(0:270, n, replace = TRUE)
) |>
  mutate(
    cigs_per_day   = if_else(smoking == 2,
                             as.numeric(sample(1:20, n, replace = TRUE)),
                             NA_real_),
    enrol_date     = lmp_date + sample((8 * 7):(20 * 7), n, replace = TRUE),
    bmi            = round(weight_kg / (height_cm / 100)^2, 1),
    ga_enrol_weeks = weeks_between(lmp_date, enrol_date)
  )

# --- Third trimester survey (about 92% complete it) --------------------------

tt <- enrol |>
  select(record_id, lmp_date, smoking) |>
  slice_sample(prop = 0.92) |>
  mutate(
    tt_date       = lmp_date + sample((28 * 7):(34 * 7), n(), replace = TRUE),
    tt_ga_weeks   = weeks_between(lmp_date, tt_date),
    sleep_hours   = round(pmin(pmax(rnorm(n(), 7, 1.2), 3), 11), 1),
    stress        = sample(0:4, n(), replace = TRUE,
                           prob = c(0.15, 0.35, 0.30, 0.15, 0.05)),
    activity_days = sample(0:7, n(), replace = TRUE,
                           prob = c(0.10, 0.10, 0.15, 0.20, 0.15, 0.12, 0.08, 0.10)),
    gdm           = rbinom(n(), 1, 0.10),
    gdm_treatment = if_else(gdm == 1,
                            as.numeric(sample(1:4, n(), replace = TRUE,
                                              prob = c(0.50, 0.25, 0.20, 0.05))),
                            NA_real_),
    bp_sys        = round(rnorm(n(), 114, 11)),
    bp_dia        = round(rnorm(n(), 72, 8))
  )

# --- Birth outcome (about 97% have one recorded) -----------------------------

birth <- enrol |>
  select(record_id, lmp_date, smoking) |>
  left_join(select(tt, record_id, gdm), by = "record_id") |>
  slice_sample(prop = 0.97) |>
  mutate(
    preterm_draw   = rbinom(n(), 1, 0.08),
    ga_days        = if_else(preterm_draw == 1,
                             round(runif(n(), 28, 36.9) * 7),
                             round(pmin(pmax(rnorm(n(), 39.4, 1.1), 37), 42) * 7)),
    birth_date     = lmp_date + ga_days,
    ga_birth_weeks = weeks_between(lmp_date, birth_date),
    preterm        = if_else(ga_birth_weeks < 37, 1, 0),
    infant_sex     = sample(1:3, n(), replace = TRUE, prob = c(0.49, 0.507, 0.003)),
    birth_weight_g = round(3400 + 180 * (ga_birth_weeks - 39.5)
                           - 200 * (smoking == 2) + rnorm(n(), 0, 400)),
    birth_weight_g = pmin(pmax(birth_weight_g, 500), 5200),
    p_caesarean    = 0.28 + 0.10 * coalesce(gdm, 0L),
    delivery_mode  = map_dbl(p_caesarean, \(p) sample(1:4, 1,
                     prob = c(0.72 - p + 0.08, 0.08, p * 0.5, p * 0.5))),
    apgar5         = if_else(preterm == 1,
                             as.numeric(sample(5:9, n(), replace = TRUE)),
                             as.numeric(sample(7:10, n(), replace = TRUE,
                                               prob = c(0.03, 0.10, 0.70, 0.17)))),
    nicu           = rbinom(n(), 1, if_else(preterm == 1, 0.70, 0.06)),
    nicu_days      = if_else(nicu == 1,
                             round(exp(rnorm(n(), if_else(preterm == 1, 2.8, 1.2), 0.6))),
                             NA_real_)
  ) |>
  select(-preterm_draw, -ga_days, -p_caesarean, -gdm, -smoking, -lmp_date)

# A survey can only happen before the birth: participants who gave birth
# before their third trimester survey date never got the survey.
tt <- tt |>
  left_join(select(birth, record_id, birth_date), by = "record_id") |>
  filter(is.na(birth_date) | tt_date < birth_date) |>
  select(-birth_date)

# --- Seed deliberate data problems -------------------------------------------
# Each problem is something REDCap would allow to be saved (range checks and
# required fields only warn), or that can happen when branching logic changes.

issues <- list()
log_issue <- function(record_id, event, field, issue_type, detail) {
  issues[[length(issues) + 1]] <<- tibble(record_id, event, field,
                                          issue_type, detail)
}

# Pool of records to damage: only those with all three events, no repeats
ids <- sample(intersect(tt$record_id, birth$record_id), 40)

# 1. Out-of-range values (typos)
birth$birth_weight_g[birth$record_id == ids[1]] <- 34500
log_issue(ids[1], "birth_arm_1", "birth_weight_g", "out_of_range", "Extra digit typed")
enrol$age[enrol$record_id == ids[2]] <- 52
log_issue(ids[2], "enrolment_arm_1", "age", "out_of_range", "Age above study maximum")
tt$bp_sys[tt$record_id == ids[3]] <- 260
log_issue(ids[3], "third_trimester_arm_1", "bp_sys", "out_of_range", "Implausible systolic BP")
enrol$height_cm[enrol$record_id == ids[4]] <- 16.4
enrol$bmi[enrol$record_id == ids[4]] <- round(enrol$weight_kg[enrol$record_id == ids[4]] / 0.164^2, 1)
log_issue(ids[4], "enrolment_arm_1", "height_cm", "out_of_range", "Height entered without a digit")

# 2. Missing required fields
for (i in 5:7) {
  enrol$parity[enrol$record_id == ids[i]] <- NA
  log_issue(ids[i], "enrolment_arm_1", "parity", "missing_required", "Required field left blank")
}
for (i in 8:9) {
  birth$birth_weight_g[birth$record_id == ids[i]] <- NA
  log_issue(ids[i], "birth_arm_1", "birth_weight_g", "missing_required", "Required field left blank")
}
tt$gdm[tt$record_id == ids[10]] <- NA
tt$gdm_treatment[tt$record_id == ids[10]] <- NA
log_issue(ids[10], "third_trimester_arm_1", "gdm", "missing_required", "Required field left blank")

# 3. Branching logic violations (value in a field that should be hidden)
for (i in 11:12) {
  r <- enrol$record_id == ids[i]
  enrol$smoking[r] <- 0
  enrol$cigs_per_day[r] <- 5
  log_issue(ids[i], "enrolment_arm_1", "cigs_per_day", "branching_violation",
            "Value present but smoking is not 'current'")
}
r <- birth$record_id == ids[13]
birth$nicu[r] <- 0
birth$nicu_days[r] <- 3
log_issue(ids[13], "birth_arm_1", "nicu_days", "branching_violation",
          "Value present but infant not admitted to NICU")

# 4. Date sequence errors
r <- birth$record_id == ids[14]
birth$birth_date[r] <- enrol$enrol_date[enrol$record_id == ids[14]] - 10
log_issue(ids[14], "birth_arm_1", "birth_date", "date_sequence", "Birth date before enrolment date")
r <- tt$record_id == ids[15]
tt$tt_date[r] <- birth$birth_date[birth$record_id == ids[15]] + 14
log_issue(ids[15], "third_trimester_arm_1", "tt_date", "date_sequence", "Third trimester survey dated after birth")

# 5. Implausible gestational age at birth (LMP date likely mistyped)
for (i in 16:17) {
  r <- birth$record_id == ids[i]
  birth$birth_date[r] <- enrol$lmp_date[enrol$record_id == ids[i]] + 46 * 7
  log_issue(ids[i], "birth_arm_1", "birth_date", "implausible_ga", "Gestational age at birth over 44 weeks")
}

# Keep calculated fields consistent with the damaged dates, as REDCap would
recalc <- function() {
  lmp <- select(enrol, record_id, lmp_date)
  tt <<- tt |> select(-lmp_date) |> left_join(lmp, by = "record_id") |>
    mutate(tt_ga_weeks = weeks_between(lmp_date, tt_date))
  birth <<- birth |> left_join(lmp, by = "record_id") |>
    mutate(ga_birth_weeks = weeks_between(lmp_date, birth_date),
           preterm = if_else(ga_birth_weeks < 37, 1, 0)) |>
    select(-lmp_date)
}
recalc()

# 6. A duplicate participant (same person enrolled twice at another site)
dup_source <- enrol |> filter(record_id == ids[18])
dup <- dup_source |>
  mutate(record_id  = as.character(1000 + n + 1),
         site       = if_else(site == 1, 2, 1),
         enrol_date = enrol_date + 9,
         ga_enrol_weeks = weeks_between(lmp_date, enrol_date))
enrol <- bind_rows(enrol, dup)
log_issue(dup$record_id, "enrolment_arm_1", "record_id", "possible_duplicate",
          glue::glue("Same age, LMP date, height, and weight as record {ids[18]}"))

seeded <- bind_rows(issues)

# --- Form completion status (0 = Incomplete, 1 = Unverified, 2 = Complete) ---

status <- function(has_missing) {
  if_else(has_missing, 0, sample(c(1, 2), length(has_missing),
                                 replace = TRUE, prob = c(0.15, 0.85)))
}
enrol <- enrol |> mutate(enrolment_complete = status(is.na(parity)))
tt    <- tt    |> mutate(third_trimester_survey_complete = status(is.na(gdm)))
birth <- birth |> mutate(birth_outcome_complete = status(is.na(birth_weight_g)))

# --- Assemble the flat REDCap export -----------------------------------------

dd <- read_csv(here("data-dictionary", "coastal_beginnings_data_dictionary.csv"),
               show_col_types = FALSE)
fields <- function(form) dd$`Variable / Field Name`[dd$`Form Name` == form]

enrol_fields <- setdiff(fields("enrolment"), "record_id")
tt_fields    <- fields("third_trimester_survey")
birth_fields <- fields("birth_outcome")

fmt <- function(df) mutate(df, across(where(is.Date), \(x) format(x, "%Y-%m-%d")))

rows_enrol <- enrol |>
  fmt() |>
  transmute(record_id, redcap_event_name = "enrolment_arm_1",
            across(all_of(enrol_fields)), enrolment_complete)
rows_tt <- tt |>
  fmt() |>
  transmute(record_id, redcap_event_name = "third_trimester_arm_1",
            across(all_of(tt_fields)), third_trimester_survey_complete)
rows_birth <- birth |>
  fmt() |>
  transmute(record_id, redcap_event_name = "birth_arm_1",
            across(all_of(birth_fields)), birth_outcome_complete)

event_order <- c("enrolment_arm_1", "third_trimester_arm_1", "birth_arm_1")

export <- bind_rows(
  mutate(rows_enrol, across(-c(record_id, redcap_event_name), as.character)),
  mutate(rows_tt,    across(-c(record_id, redcap_event_name), as.character)),
  mutate(rows_birth, across(-c(record_id, redcap_event_name), as.character))
) |>
  relocate(record_id, redcap_event_name, all_of(enrol_fields), enrolment_complete,
           all_of(tt_fields), third_trimester_survey_complete,
           all_of(birth_fields), birth_outcome_complete) |>
  arrange(as.integer(record_id), match(redcap_event_name, event_order))

# --- Save --------------------------------------------------------------------

write_csv(export, here("data", "raw", "coastal_beginnings_export.csv"), na = "")
write_csv(seeded, here("data", "raw", "seeded_issues.csv"))

message("Saved ", nrow(export), " rows for ", n_distinct(export$record_id),
        " participants, with ", nrow(seeded), " seeded issues.")
