# =============================================================================
# run_all.R
# Runs the whole Coastal Beginnings pipeline from start to finish:
#   simulate (only when no REDCap credentials are set), pull and clean,
#   quality checks, then render the report and copy it to docs/ for
#   GitHub Pages.
# =============================================================================

library(here)

using_api <- nzchar(Sys.getenv("REDCAP_URI")) && nzchar(Sys.getenv("REDCAP_TOKEN"))

if (!using_api) source(here("R", "01_simulate_data.R"))
source(here("R", "02_pull_and_clean.R"))
source(here("R", "03_quality_checks.R"))

quarto::quarto_render(here("report", "coastal_beginnings_report.qmd"))

dir.create(here("docs"), showWarnings = FALSE)
file.copy(here("report", "coastal_beginnings_report.html"),
          here("docs", "index.html"), overwrite = TRUE)

message("Done. Report saved to docs/index.html")
