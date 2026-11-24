# =============================================================================
# run_all.R
# Runs the whole Coastal Beginnings pipeline from start to finish:
#   simulate (only when no REDCap credentials are set), pull and clean,
#   quality checks, render the sample report, then render the website
#   (which copies the report in) to docs/ for GitHub Pages.
# =============================================================================

library(here)

using_api <- nzchar(Sys.getenv("REDCAP_URI")) && nzchar(Sys.getenv("REDCAP_TOKEN"))

if (!using_api) source(here("R", "01_simulate_data.R"))
source(here("R", "02_pull_and_clean.R"))
source(here("R", "03_quality_checks.R"))

# 1. The sample report: one self-contained file, report/index.html
quarto::quarto_render(here("report", "coastal_beginnings_report.qmd"))

# 2. The website: Overview, How it works, and About pages, plus a copy of the
#    report at docs/report/index.html
quarto::quarto_render(here())

message("Done. Report saved to report/index.html, and the website to docs/")
