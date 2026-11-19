# =============================================================================
# 02_pull_and_clean.R
# Coastal Beginnings Study (fictional): pull and clean the data
#
# 1. Gets the data from the REDCap API, or from the local synthetic export.
# 2. Converts each field to the right type, using the data dictionary.
# 3. Builds one row per participant, with readable labels.
#
# Outputs (in data/processed/):
#   export_typed.rds  one row per participant per event, coded values,
#                     typed; used by the quality checks
#   participants.rds  one row per participant, labelled; used for analysis
#   participants.csv  the same, for use outside R
#   dictionary.rds    the data dictionary in a tidy form
# =============================================================================

source(here::here("R", "00_functions.R"))

# --- 1. Get the data ---------------------------------------------------------

redcap  <- get_redcap_data()
raw     <- redcap$data
dict    <- redcap$dict
mapping <- redcap$mapping

# --- 2. Work out each field's type from the dictionary -----------------------

field_types <- dict |>
  transmute(
    field_name,
    form_name,
    type = case_when(
      text_validation_type_or_show_slider_number == "date_ymd"        ~ "date",
      text_validation_type_or_show_slider_number %in%
        c("integer", "number", "number_1dp")                          ~ "number",
      field_type == "calc"                                            ~ "number",
      field_type %in% c("radio", "dropdown", "yesno")                 ~ "categorical",
      TRUE                                                            ~ "text"
    )
  )

fields_of <- function(type_wanted) {
  field_types |>
    filter(type == type_wanted, field_name %in% names(raw)) |>
    pull(field_name)
}

complete_fields <- str_subset(names(raw), "_complete$")

# --- 3. Typed long data (one row per participant per event) ------------------

export_typed <- raw |>
  mutate(
    across(all_of(fields_of("date")),        as.Date),
    across(all_of(fields_of("number")),      as.numeric),
    across(all_of(fields_of("categorical")), as.integer),
    across(all_of(complete_fields),          as.integer)
  )

# --- 4. One row per participant ----------------------------------------------

# For each event, keep only the fields of the instrument collected there,
# then join the events side by side.
event_tables <- mapping |>
  select(unique_event_name, form) |>
  pmap(\(unique_event_name, form) {
    keep <- c(dict$field_name[dict$form_name == form], paste0(form, "_complete"))
    export_typed |>
      filter(redcap_event_name == unique_event_name) |>
      select(record_id, any_of(setdiff(keep, "record_id")))
  })

participants <- reduce(event_tables, full_join, by = "record_id")

# --- 5. Replace codes with labels --------------------------------------------

categorical <- dict |> filter(field_type %in% c("radio", "dropdown", "yesno"))

for (i in seq_len(nrow(categorical))) {
  f       <- categorical$field_name[i]
  choices <- field_choices(categorical[i, ])
  participants[[f]] <- factor(as.character(participants[[f]]),
                              levels = choices$code, labels = choices$label)
}

completion_labels <- c("Incomplete", "Unverified", "Complete")
participants <- participants |>
  mutate(
    across(ends_with("_complete"),
           \(x) factor(x, levels = 0:2, labels = completion_labels)),
    preterm   = factor(preterm, levels = 0:1, labels = c("Term", "Preterm")),
    has_third_trimester = record_id %in%
      raw$record_id[raw$redcap_event_name == "third_trimester_arm_1"],
    has_birth = record_id %in%
      raw$record_id[raw$redcap_event_name == "birth_arm_1"]
  ) |>
  arrange(as.integer(record_id))

# --- 6. Tidy dictionary for later scripts ------------------------------------

dictionary <- dict |>
  left_join(select(field_types, field_name, type), by = "field_name")

# --- 7. Save -----------------------------------------------------------------

dir.create(here("data", "processed"), showWarnings = FALSE)
saveRDS(export_typed, here("data", "processed", "export_typed.rds"))
saveRDS(participants, here("data", "processed", "participants.rds"))
saveRDS(dictionary,   here("data", "processed", "dictionary.rds"))
write_csv(participants, here("data", "processed", "participants.csv"), na = "")

message(
  "Source: ", redcap$source, "\n",
  "Participants: ", nrow(participants), "\n",
  "With third trimester survey: ", sum(participants$has_third_trimester), "\n",
  "With birth outcome: ", sum(participants$has_birth)
)
