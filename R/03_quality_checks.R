# =============================================================================
# 03_quality_checks.R
# Coastal Beginnings Study (fictional): data quality checks
#
# Runs six kinds of check, most of them driven by the data dictionary so they
# work on any REDCap project:
#   1. Out-of-range values (dictionary min and max)
#   2. Missing required fields (only where the field should be shown)
#   3. Branching logic violations (a value in a field that should be hidden)
#   4. Dates in the wrong order across events
#   5. Implausible gestational age at birth
#   6. Possible duplicate participants
#
# Outputs (in outputs/):
#   qc_issues.csv          every issue found, one row each
#   qc_summary.csv         counts by check
#   qc_seeded_scorecard.csv  which seeded issues were caught (synthetic data only)
# =============================================================================

source(here::here("R", "00_functions.R"))

export_typed <- readRDS(here("data", "processed", "export_typed.rds"))
participants <- readRDS(here("data", "processed", "participants.rds"))
dictionary   <- readRDS(here("data", "processed", "dictionary.rds"))
mapping      <- read_csv(here("data-dictionary", "instrument_event_mapping.csv"),
                         col_types = cols(.default = col_character()))

# Which event each field is collected at
field_events <- dictionary |>
  select(field_name, form_name, type, field_label) |>
  left_join(select(mapping, form, unique_event_name),
            by = c("form_name" = "form"))

# Rows of the export for the event where a field is collected
rows_for <- function(field) {
  ev <- field_events$unique_event_name[field_events$field_name == field]
  export_typed |> filter(redcap_event_name %in% ev)
}

# Standard shape for every issue
issue <- function(df, field, check, detail, value) {
  if (nrow(df) == 0) return(NULL)
  tibble(
    record_id = df$record_id,
    event     = df$redcap_event_name,
    field     = field,
    value     = as.character(value),
    check     = check,
    detail    = detail
  )
}

# Is each row's branching logic met? Fields without logic are always shown.
is_shown <- function(df, logic) {
  if (is.na(logic) || logic == "") return(rep(TRUE, nrow(df)))
  expr  <- rlang::parse_expr(redcap_logic_to_r(logic))
  shown <- rlang::eval_tidy(expr, data = mutate(df, across(everything(), as.character)))
  coalesce(shown, FALSE)
}

issues <- list()

# --- 1. Out-of-range values --------------------------------------------------

range_fields <- dictionary |>
  filter(!is.na(text_validation_min) | !is.na(text_validation_max),
         type %in% c("number", "date"))

for (i in seq_len(nrow(range_fields))) {
  f   <- range_fields$field_name[i]
  typ <- range_fields$type[i]
  to_value <- function(x) {
    if (is.na(x)) return(NA)
    if (x == "today") return(Sys.Date())
    if (typ == "date") as.Date(x) else as.numeric(x)
  }
  mn <- to_value(range_fields$text_validation_min[i])
  mx <- to_value(range_fields$text_validation_max[i])

  df  <- rows_for(f)
  bad <- df |> filter(!is.na(.data[[f]]) &
                      ((!is.na(mn) & .data[[f]] < mn) | (!is.na(mx) & .data[[f]] > mx)))
  issues[[length(issues) + 1]] <- issue(
    bad, f, "Out of range",
    glue::glue("Allowed range {range_fields$text_validation_min[i]} to {range_fields$text_validation_max[i]}"),
    bad[[f]]
  )
}

# --- 2. Missing required fields ----------------------------------------------

required <- dictionary |> filter(required_field == "y", field_type != "calc")

for (i in seq_len(nrow(required))) {
  f  <- required$field_name[i]
  df <- rows_for(f)
  df <- df[is_shown(df, required$branching_logic[i]), ]
  bad <- df |> filter(is.na(.data[[f]]))
  issues[[length(issues) + 1]] <- issue(
    bad, f, "Missing required field", "Required field is blank", NA
  )
}

# --- 3. Branching logic violations -------------------------------------------

branching <- dictionary |> filter(!is.na(branching_logic))

for (i in seq_len(nrow(branching))) {
  f     <- branching$field_name[i]
  logic <- branching$branching_logic[i]
  df    <- rows_for(f)
  bad   <- df[!is_shown(df, logic) & !is.na(df[[f]]), ]
  issues[[length(issues) + 1]] <- issue(
    bad, f, "Branching logic violation",
    glue::glue("Has a value but should be hidden (shown only if {logic})"),
    bad[[f]]
  )
}

# --- 4. Dates in the wrong order ---------------------------------------------

date_rules <- tribble(
  ~earlier,     ~later,       ~later_event,
  "lmp_date",   "enrol_date", "enrolment_arm_1",
  "enrol_date", "tt_date",    "third_trimester_arm_1",
  "enrol_date", "birth_date", "birth_arm_1",
  "tt_date",    "birth_date", "third_trimester_arm_1"
)

for (i in seq_len(nrow(date_rules))) {
  e <- date_rules$earlier[i]
  l <- date_rules$later[i]
  bad <- participants |>
    filter(!is.na(.data[[e]]), !is.na(.data[[l]]), .data[[l]] < .data[[e]]) |>
    mutate(redcap_event_name = date_rules$later_event[i])
  # When a survey is dated after the birth, the survey date is the suspect field
  flag_field <- if (e == "tt_date") "tt_date" else l
  issues[[length(issues) + 1]] <- issue(
    bad, flag_field, "Date order",
    glue::glue("{l} is before {e}"),
    glue::glue("{bad[[e]]} then {bad[[l]]}")
  )
}

# --- 5. Implausible gestational age at birth ---------------------------------

bad <- participants |>
  filter(!is.na(ga_birth_weeks), ga_birth_weeks < 22 | ga_birth_weeks > 44) |>
  mutate(redcap_event_name = "birth_arm_1")
issues[[length(issues) + 1]] <- issue(
  bad, "ga_birth_weeks", "Implausible gestational age",
  "Gestational age at birth outside 22 to 44 weeks; check the LMP and birth dates",
  bad$ga_birth_weeks
)

# --- 6. Possible duplicate participants --------------------------------------

dupes <- participants |>
  filter(!is.na(lmp_date)) |>
  group_by(age, lmp_date, height_cm, weight_kg) |>
  filter(n() > 1) |>
  arrange(as.integer(record_id), .by_group = TRUE) |>
  mutate(first_record = first(record_id)) |>
  filter(record_id != first_record) |>
  ungroup() |>
  mutate(redcap_event_name = "enrolment_arm_1")
issues[[length(issues) + 1]] <- issue(
  dupes, "record_id", "Possible duplicate",
  glue::glue("Same age, LMP date, height, and weight as record {dupes$first_record}"),
  dupes$record_id
)

# --- Combine and save --------------------------------------------------------

qc_issues <- bind_rows(issues) |>
  left_join(select(dictionary, field_name, field_label), by = c("field" = "field_name")) |>
  relocate(field_label, .after = field) |>
  arrange(as.integer(record_id), event, field)

check_order <- c("Out of range", "Missing required field", "Branching logic violation",
                 "Date order", "Implausible gestational age", "Possible duplicate")

qc_summary <- qc_issues |>
  count(check, name = "issues") |>
  right_join(tibble(check = check_order), by = "check") |>
  mutate(issues = coalesce(issues, 0L)) |>
  arrange(match(check, check_order))

dir.create(here("outputs"), showWarnings = FALSE)
write_csv(qc_issues,  here("outputs", "qc_issues.csv"), na = "")
write_csv(qc_summary, here("outputs", "qc_summary.csv"))
saveRDS(qc_issues, here("data", "processed", "qc_issues.rds"))

# --- Score against the seeded issues (synthetic data only) -------------------

seeded_path <- here("data", "raw", "seeded_issues.csv")
if (file.exists(seeded_path)) {
  seeded <- read_csv(seeded_path, col_types = cols(.default = col_character()))

  # A seeded issue counts as caught if any check flagged that record at that
  # event, on the same field or (for implausible dates) the related GA field.
  scorecard <- seeded |>
    rowwise() |>
    mutate(caught = any(
      qc_issues$record_id == record_id &
      qc_issues$event == event &
      (qc_issues$field == field |
         (field == "birth_date" & qc_issues$field == "ga_birth_weeks"))
    )) |>
    ungroup()

  write_csv(scorecard, here("outputs", "qc_seeded_scorecard.csv"))
  saveRDS(scorecard, here("data", "processed", "qc_scorecard.rds"))

  message("Seeded issues caught: ", sum(scorecard$caught), " of ", nrow(scorecard))
}

message("Total issues flagged: ", nrow(qc_issues))
print(qc_summary)
