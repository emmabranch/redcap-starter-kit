# =============================================================================
# 00_functions.R
# Helper functions shared by the Coastal Beginnings scripts.
# Other scripts load this with: source(here("R", "00_functions.R"))
# =============================================================================

library(tidyverse)
library(here)

# --- Data dictionary ---------------------------------------------------------

# The REDCap API names for the 18 dictionary columns, in order. The CSV you
# download from REDCap uses longer headers; renaming makes both sources match.
dictionary_names <- c(
  "field_name", "form_name", "section_header", "field_type", "field_label",
  "select_choices_or_calculations", "field_note",
  "text_validation_type_or_show_slider_number", "text_validation_min",
  "text_validation_max", "identifier", "branching_logic", "required_field",
  "custom_alignment", "question_number", "matrix_group_name",
  "matrix_ranking", "field_annotation"
)

# Read a data dictionary CSV downloaded from REDCap
read_dictionary_csv <- function(path) {
  read_csv(path, col_types = cols(.default = col_character())) |>
    set_names(dictionary_names)
}

# Turn "1, Female | 2, Male" into a two-column table of codes and labels
parse_choices <- function(choices) {
  if (is.na(choices) || choices == "") {
    return(tibble(code = character(), label = character()))
  }
  str_split(choices, "\\s*\\|\\s*")[[1]] |>
    str_match("^\\s*([^,]+),\\s*(.*)$") |>
    as_tibble(.name_repair = "minimal") |>
    set_names(c("whole", "code", "label")) |>
    transmute(code = str_trim(code), label = str_trim(label))
}

# Codes and labels for a categorical field, including REDCap's built-in yes/no
field_choices <- function(dict_row) {
  if (dict_row$field_type == "yesno") {
    return(tibble(code = c("0", "1"), label = c("No", "Yes")))
  }
  parse_choices(dict_row$select_choices_or_calculations)
}

# --- REDCap logic ------------------------------------------------------------

# Translate simple REDCap branching logic into an R expression, for example
# "[smoking] = '2'" becomes "smoking == '2'". Handles =, <>, and, or, and
# comparisons of single-event fields, which covers this project. Comparisons
# are made on text, the way REDCap stores values.
redcap_logic_to_r <- function(logic) {
  logic |>
    str_replace_all("\\[([a-z0-9_]+)\\]", "\\1") |>
    str_replace_all("<>", "!=") |>
    str_replace_all("(?<![<>!=])=(?!=)", "==") |>
    str_replace_all("\\band\\b", "&") |>
    str_replace_all("\\bor\\b", "|")
}

# --- Getting the data --------------------------------------------------------

# Returns a list with the raw export (all text), the dictionary, and the
# event-to-instrument mapping. Uses the REDCap API when REDCAP_URI and
# REDCAP_TOKEN are set (for example in a .Renviron file), and the local
# synthetic export otherwise.
get_redcap_data <- function() {
  uri   <- Sys.getenv("REDCAP_URI")
  token <- Sys.getenv("REDCAP_TOKEN")

  if (nzchar(uri) && nzchar(token)) {
    message("Pulling data from the REDCap API at ", uri)
    data <- REDCapR::redcap_read(redcap_uri = uri, token = token)$data
    dict <- REDCapR::redcap_metadata_read(redcap_uri = uri, token = token)$data |>
      mutate(across(everything(), as.character))
    mapping <- REDCapR::redcap_event_instruments(redcap_uri = uri, token = token)$data
    source <- "REDCap API"
  } else {
    message("No REDCap credentials found: using the local synthetic export")
    data <- read_csv(here("data", "raw", "coastal_beginnings_export.csv"),
                     col_types = cols(.default = col_character()))
    dict <- read_dictionary_csv(here("data-dictionary",
                                     "coastal_beginnings_data_dictionary.csv"))
    mapping <- read_csv(here("data-dictionary", "instrument_event_mapping.csv"),
                        col_types = cols(.default = col_character()))
    source <- "local synthetic export"
  }

  list(
    data    = mutate(data, across(everything(), as.character)),
    dict    = dict,
    mapping = mutate(mapping, across(everything(), as.character)),
    source  = source
  )
}
