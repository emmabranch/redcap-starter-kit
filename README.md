# REDCap starter kit

A small, reusable pipeline for REDCap projects: pull the data, clean it using the project's own data dictionary, run quality checks, and produce a polished status report automatically.

**Live site:** https://emmabranch.github.io/redcap-starter-kit/ · **More projects:** [github.com/emmabranch](https://github.com/emmabranch)

![Preview of the Coastal Beginnings report](images/report-preview.png)

> It is demonstrated on the **Coastal Beginnings Study**, a fictional pregnancy cohort. **All data are simulated. No real people are represented.**

## What it does

1. **Defines a realistic REDCap project.** A longitudinal data dictionary with three events, required fields, range validation, branching logic, calculated fields (BMI, gestational age, a preterm flag), cross-event references, and identifier flags on dates.
2. **Pulls the data** live from the REDCap API with [REDCapR](https://ouhscbbmc.github.io/REDCapR/), or from a local REDCap-format export when no credentials are set.
3. **Cleans it using the data dictionary.** Field types and labels come from the dictionary, not hard-coded rules, so the same code adapts to other projects.
4. **Runs six quality checks** and writes a list of issues a study coordinator can work through.
5. **Renders a Quarto report** with recruitment, follow-up, data quality, baseline characteristics, and outcome graphics.

## The quality checks

| Check | What it finds | Driven by |
|---|---|---|
| Out of range | Values outside the allowed minimum and maximum | Data dictionary |
| Missing required field | Required questions left blank, only where they should have been shown | Data dictionary and branching logic |
| Branching logic violation | Values in questions that should be hidden | Data dictionary |
| Date order | Dates across events in an impossible order | Study rules |
| Implausible gestational age | Gestational age at birth outside 22 to 44 weeks | Study rules |
| Possible duplicate | The same person enrolled under two record IDs | Study rules |

REDCap's range checks and required fields only warn at data entry, and values stay behind when branching logic changes, so these problems are common in real projects. The simulated data has 18 problems planted on purpose, and the checks catch all 18.

## Data and licences

- **Data:** every record in `data/` is simulated by `R/01_simulate_data.R` for the fictional Coastal Beginnings Study. `data/raw/seeded_issues.csv` lists the 18 problems planted on purpose.
- **Code:** MIT licence (see [`LICENSE`](LICENSE)).

## Repository structure

```
redcap-starter-kit/
├── data-dictionary/        REDCap data dictionary, events, and instrument mapping
├── data/
│   ├── raw/                Synthetic REDCap export and the list of planted issues
│   └── processed/          Cleaned, typed, and labelled data
├── R/
│   ├── 00_functions.R      Shared helpers (dictionary parsing, branching logic, data access)
│   ├── 01_simulate_data.R  Simulates the fictional cohort
│   ├── 02_pull_and_clean.R Pulls and cleans the data
│   └── 03_quality_checks.R Runs the quality checks
├── report/                 Quarto sample report (renders on its own to report/index.html)
├── outputs/                Issue list and summaries (CSV)
├── images/                 Motif, browser tab icon, and report preview
├── docs/                   Published website for GitHub Pages
├── index.qmd, how-it-works.qmd, about.qmd   Website pages
└── run_all.R               Runs everything in order
```

## How to reproduce

You need R (4.3 or later), [Quarto](https://quarto.org/), and these packages:

```r
install.packages(c("tidyverse", "REDCapR", "here", "gt", "glue", "scales",
                   "quarto", "reactable"))
```

Then open `redcap-starter-kit.Rproj` in RStudio and run:

```r
source("run_all.R")
```

The report is saved to `report/index.html`, and the website, with the report inside it, to `docs/`.

### Using it with a real REDCap project

1. Ask your REDCap administrator for API access to the project, and generate a token.
2. Create a file called `.Renviron` in the project folder (it is already excluded from Git) containing:

   ```
   REDCAP_URI=https://your-institution.ca/redcap/api/
   REDCAP_TOKEN=your-token-here
   ```

3. Restart R and run `source("run_all.R")`. The simulation step is skipped and the data are pulled live.

The cleaning and the first three quality checks work on any project. The date rules, gestational age check, duplicate check, and report sections are specific to this study and are the parts to adapt.

**Never commit an API token, and never publish a report built from real participant data.**

## Limitations

- Tested on simulated data only. The 18 planted problems were written alongside the checks, so catching all 18 shows the checks work as designed, not how many problems a real project will have.
- The branching logic translator handles simple logic (`=`, `<>`, `and`, `or`, and fields in a single event). More complex REDCap logic, such as functions or cross-event references, would need extending it.
- Checkbox fields, repeating instruments, and projects with more than one arm have not been tested.
- The date rules, gestational age check, duplicate check, and report sections are specific to this study.

## About me

I'm Emma Branch, an epidemiologist and data analyst in British Columbia, and a PhD candidate in Population and Public Health at the University of British Columbia. I've spent about 10 years working with health research data, including registry analytics, REDCap database design, data governance, and performance measurement. I mostly work in R, SAS, and SQL, and build reports and tools with Quarto, Shiny, leaflet, and Power BI. Lately I've been applying the same habits to environmental and ocean data, mostly because I like maps and fish.

[More projects](https://github.com/emmabranch) · [LinkedIn](https://www.linkedin.com/in/embranch/) · emma.branch@gmail.com
