# Generic citation checks.
#
# NOTHING IN THIS FILE IS SPECIFIC TO distsamp. It is written to be copied, or
# lifted into a shared repo, unchanged. Everything project-specific lives in
# tools/citation-hooks.R.
#
# The interface between the two is deliberately small:
#
#   * a registry CSV with the columns documented in `citation_registry()`
#   * `citation_hooks()` in the hooks file, returning a list of extra checks
#
# Each check is a function taking (registry, ctx) and returning a list with
# `failures` and `notes`, both character vectors. That is the whole contract.

# --- reporting --------------------------------------------------------------

cc_say <- function(...) cat(..., "\n", sep = "")
cc_rule <- function(title) {
  cc_say("\n== ", title, " ", strrep("=", max(0, 60 - nchar(title))))
}
cc_result <- function(failures = character(), notes = character()) {
  list(failures = failures, notes = notes)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# Normalise a title or journal for comparison: lowercase, strip markup, collapse
# punctuation. Publishers are inconsistent about dashes, JATS markup in titles,
# and trailing periods.
cc_norm <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("<[^>]+>", " ", x)
  x <- gsub("[‐-―]", "-", x)
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
}

# --- registry ---------------------------------------------------------------

#' Read a citation registry.
#'
#' Columns: key, doi, url, first_author, year, title, container, volume, pages,
#' checks, note. `checks` is a semicolon-separated list naming which checks apply
#' to the row: "crossref", "url", "none", plus any hook-defined names.
citation_registry <- function(path) {
  reg <- utils::read.csv(path, stringsAsFactors = FALSE, na.strings = "")
  required <- c("key", "doi", "url", "first_author", "year", "title", "checks")
  missing <- setdiff(required, names(reg))
  if (length(missing)) {
    stop("Registry is missing column(s): ", paste(missing, collapse = ", "))
  }
  reg
}

# Every DOI mentioned anywhere in the project sources.
cc_scan_dois <- function(paths) {
  paths <- paths[file.exists(paths)]
  if (!length(paths)) return(character())
  text <- unlist(lapply(paths, readLines, warn = FALSE))
  found <- regmatches(
    text,
    gregexpr("10\\.[0-9]{4,9}/[^\\s\"'<>)\\]},;`*_]+", text, perl = TRUE)
  )
  found <- unique(sub("[.,;:>`)\\]]+$", "", unlist(found)))
  # Documentation shows citation *templates* as well as citations: "DOI:
  # 10.48670/moi-xxxxx (Accessed on DD MMM YYYY)" is an instruction to the
  # reader, not a reference. An ellipsis or a run of x's marks the difference.
  found[!grepl("[.]{3}|x{4,}|X{4,}", found)]
}

# --- check 1: registry coverage --------------------------------------------

check_registry_coverage <- function(registry, ctx) {
  found <- cc_scan_dois(ctx$sources)
  reg_dois <- stats::na.omit(registry$doi)

  failures <- character()
  notes <- character()

  unregistered <- setdiff(tolower(found), tolower(reg_dois))
  if (length(unregistered)) {
    failures <- paste0(
      "DOI cited but not in the registry: ",
      paste(unregistered, collapse = ", ")
    )
  } else {
    cc_say("  all ", length(found), " cited DOIs are registered")
  }

  unused <- setdiff(tolower(reg_dois), tolower(found))
  if (length(unused)) {
    notes <- paste0(
      "Registry DOI never cited in the project: ",
      paste(unused, collapse = ", ")
    )
  }

  cc_result(failures, notes)
}

# --- check 2: CrossRef metadata --------------------------------------------

cc_crossref <- function(doi) {
  url <- paste0("https://api.crossref.org/works/", utils::URLencode(doi, TRUE))
  out <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE),
                  error = function(e) NULL)
  out$message
}

# Dataset DOIs - Copernicus Marine (10.48670), NOAA NCEI (10.25921), BODC
# (10.5285) - are registered with DataCite, not CrossRef, so a CrossRef lookup
# returns nothing for them. That is not a dead DOI, and treating it as one would
# make the check useless in exactly the repositories that cite the most data.
cc_datacite <- function(doi) {
  url <- paste0("https://api.datacite.org/dois/", utils::URLencode(doi, TRUE))
  out <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE),
                  error = function(e) NULL)
  a <- out$data$attributes
  if (is.null(a)) return(NULL)
  list(
    registrar = "DataCite",
    author = if (length(a$creators)) {
      a$creators[[1]]$familyName %||% a$creators[[1]]$name %||% ""
    } else "",
    year = a$publicationYear %||% "",
    title = if (length(a$titles)) a$titles[[1]]$title else "",
    container = a$publisher %||% ""
  )
}

# Does the DOI resolve at all? Used for dataset DOIs, where the registrar may
# be neither CrossRef nor DataCite, and where "it still points somewhere" is
# the question worth asking.
cc_doi_resolves <- function(doi) {
  cc_url_ok(paste0("https://doi.org/", doi))
}

check_crossref_metadata <- function(registry, ctx) {
  rows <- registry[!is.na(registry$doi) & grepl("crossref", registry$checks), ,
                   drop = FALSE]
  failures <- character()

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    m <- cc_crossref(r$doi)

    if (is.null(m)) {
      # Not a CrossRef work. Try DataCite, then bare resolution, before
      # concluding anything is wrong.
      dc <- cc_datacite(r$doi)
      if (!is.null(dc)) {
        prob <- character()
        if (nzchar(dc$author) && nzchar(r$first_author) &&
            cc_norm(dc$author) != cc_norm(r$first_author)) {
          prob <- c(prob, sprintf("first creator '%s' vs registry '%s'",
                                  dc$author, r$first_author))
        }
        if (length(prob)) {
          failures <- c(failures, paste0(r$key, " (DataCite ", r$doi, "):\n      - ",
                                         paste(prob, collapse = "\n      - ")))
        } else {
          cc_say("  ok  ", r$key, "  ", r$doi, "  (DataCite)")
        }
      } else if (cc_doi_resolves(r$doi)) {
        cc_say("  ok  ", r$key, "  ", r$doi,
               "  (resolves; not indexed by CrossRef or DataCite)")
      } else {
        failures <- c(failures,
                      paste0(r$key, ": DOI does not resolve (", r$doi, ")"))
      }
      next
    }

    problems <- character()

    fam <- if (length(m$author)) m$author[[1]]$family else NA_character_
    if (!is.na(fam) && cc_norm(fam) != cc_norm(r$first_author)) {
      problems <- c(problems, sprintf("first author '%s' vs registry '%s'",
                                      fam, r$first_author))
    }

    yr <- m$issued$`date-parts`[[1]][[1]]
    # Online-first publication can predate the issue year we cite by one.
    if (!is.null(yr) && !(yr %in% c(r$year, r$year - 1L))) {
      problems <- c(problems, sprintf("year %s vs registry %s", yr, r$year))
    }

    ti <- if (length(m$title)) m$title[[1]] else NA_character_
    if (!is.na(ti) && cc_norm(ti) != cc_norm(r$title)) {
      problems <- c(problems, sprintf(
        "title\n        CrossRef: %s\n        registry: %s", ti, r$title))
    }

    ct <- if (length(m$`container-title`)) m$`container-title`[[1]] else NA_character_
    if (!is.na(ct) && !is.na(r$container) && cc_norm(ct) != cc_norm(r$container)) {
      problems <- c(problems, sprintf("journal '%s' vs registry '%s'",
                                      ct, r$container))
    }

    if (!is.na(r$volume) && !is.null(m$volume) &&
        trimws(m$volume) != trimws(as.character(r$volume))) {
      problems <- c(problems, sprintf("volume '%s' vs registry '%s'",
                                      m$volume, r$volume))
    }

    if (length(problems)) {
      failures <- c(failures, paste0(
        r$key, " (", r$doi, "):\n      - ",
        paste(problems, collapse = "\n      - ")))
    } else {
      cc_say("  ok  ", r$key, "  ", r$doi)
    }
  }

  cc_unreachable_guard(failures, nrow(rows), "DOI",
                       "doi.org, CrossRef and DataCite")
}

# Every reference failing at once is not every reference rotting at once; it is
# the network being down. Reporting it as a note rather than a wall of failures
# is derivoce's idea, and the reason it gives is the right one: an issue listing
# the entire bibliography is an issue nobody reads.
#
# Applies only when there was more than one thing to check - with a single
# reference, "all of them failed" carries no information.
cc_unreachable_guard <- function(failures, n_checked, what, service) {
  if (n_checked > 1 && length(failures) == n_checked) {
    return(cc_result(notes = paste0(
      "Every ", what, " check failed (", n_checked, " of ", n_checked, "). That ",
      "means ", service, " could not be reached, not that every reference ",
      "rotted at once. Drawing no conclusion.")))
  }
  cc_result(failures)
}

# --- check 3: URL liveness --------------------------------------------------

cc_url_ok <- function(u) {
  code <- tryCatch({
    con <- url(u, open = "rb")
    on.exit(close(con), add = TRUE)
    readBin(con, "raw", 1L)
    200L
  }, error = function(e) {
    st <- suppressWarnings(system2(
      "curl", c("-sIL", "-o", "/dev/null", "-w", "%{http_code}",
                "--max-time", "30", shQuote(u)),
      stdout = TRUE, stderr = FALSE
    ))
    suppressWarnings(as.integer(st[length(st)]))
  })
  isTRUE(!is.na(code) && code >= 200 && code < 400)
}

check_url_liveness <- function(registry, ctx) {
  rows <- registry[!is.na(registry$url) & grepl("url", registry$checks), ,
                   drop = FALSE]
  failures <- character()

  for (i in seq_len(nrow(rows))) {
    r <- rows[i, ]
    if (cc_url_ok(r$url)) {
      cc_say("  ok  ", r$key, "  ", r$url)
    } else {
      failures <- c(failures,
                    paste0(r$key, ": URL did not resolve (", r$url, ")"))
    }
  }

  cc_unreachable_guard(failures, nrow(rows), "URL", "the network")
}

# --- check 4: the package's own citation ------------------------------------

# Read a DESCRIPTION field without needing the package installed.
cc_desc <- function(root, field) {
  d <- file.path(root, "DESCRIPTION")
  if (!file.exists(d)) return(NA_character_)
  val <- tryCatch(read.dcf(d, fields = field)[1, 1], error = function(e) NA_character_)
  if (is.na(val)) NA_character_ else trimws(gsub("\\s+", " ", val))
}

#' Does the project say how to cite itself, consistently?
#'
#' Three failure modes, all common and all silent:
#'
#'   * no `inst/CITATION`, so `citation("pkg")` falls back to an auto-generated
#'     entry that names no author and no URL;
#'   * `inst/CITATION` exists but its version has drifted from DESCRIPTION, so
#'     users cite a version that was never released;
#'   * the README never tells anyone how to cite the thing at all.
check_self_citation <- function(registry, ctx) {
  root <- ctx$root %||% "."
  pkg <- cc_desc(root, "Package")
  ver <- cc_desc(root, "Version")

  failures <- character()
  notes <- character()

  if (is.na(pkg)) {
    return(cc_result(notes = "No DESCRIPTION; skipping the self-citation check."))
  }

  # --- inst/CITATION ---
  cit_path <- file.path(root, "inst", "CITATION")
  if (!file.exists(cit_path)) {
    failures <- c(failures, paste0(
      "No inst/CITATION. Without it, citation(\"", pkg, "\") falls back to an ",
      "auto-generated entry with no author and no URL."))
  } else {
    cit <- tryCatch(
      utils::readCitationFile(cit_path, meta = list(Package = pkg, Version = ver)),
      error = function(e) e
    )
    if (inherits(cit, "error")) {
      failures <- c(failures, paste0("inst/CITATION does not parse: ",
                                     conditionMessage(cit)))
    } else {
      cc_say("  ok  inst/CITATION parses (", length(cit), " entry/entries)")

      # Version drift: the classic one. A hard-coded version in CITATION goes
      # stale the moment DESCRIPTION is bumped.
      txt <- paste(readLines(cit_path, warn = FALSE), collapse = " ")
      hard <- regmatches(txt, gregexpr("[0-9]+[.][0-9]+[.][0-9]+", txt))[[1]]
      stale <- setdiff(unique(hard), ver)
      if (length(stale)) {
        failures <- c(failures, paste0(
          "inst/CITATION hard-codes version(s) ", paste(stale, collapse = ", "),
          " but DESCRIPTION says ", ver,
          ". Use meta$Version so it cannot drift."))
      }
    }
  }

  # --- README ---
  readme <- file.path(root, "README.md")
  if (!file.exists(readme)) {
    notes <- c(notes, "No README.md; skipping the README citation check.")
  } else {
    rd <- paste(readLines(readme, warn = FALSE), collapse = "\n")
    has_heading <- grepl("(?i)#+\\s*(how to )?cit(e|ing|ation)", rd, perl = TRUE)
    names_pkg <- grepl(paste0("(?i)\\b", pkg, "\\b"), rd, perl = TRUE)

    if (!has_heading) {
      failures <- c(failures, paste0(
        "README.md has no citation section. Add a heading such as ",
        "\"## Citing ", pkg, "\" showing users how to cite the package."))
    } else if (!names_pkg) {
      failures <- c(failures, "README.md has a citation section that never names the package.")
    } else {
      cc_say("  ok  README.md tells users how to cite ", pkg)
    }

    # If the README hard-codes a version, it must be the current one.
    rd_vers <- regmatches(rd, gregexpr("(?i)version\\s+[0-9]+[.][0-9]+[.][0-9]+", rd, perl = TRUE))[[1]]
    rd_vers <- unique(gsub("(?i)version\\s+", "", rd_vers, perl = TRUE))
    stale_rd <- setdiff(rd_vers, ver)
    if (length(stale_rd)) {
      failures <- c(failures, paste0(
        "README.md cites version(s) ", paste(stale_rd, collapse = ", "),
        " but DESCRIPTION says ", ver, "."))
    }
  }

  cc_result(failures, notes)
}

# --- check 5: the reference list and the prose agree ------------------------

# Adapted from derivoce's check_citations.R, which is where this idea and most
# of these regexes come from. Generalised to handle both reference styles in
# use across these repositories: "- Surname, A. (2009) ..." bullets, and
# "Surname, A. (2009) ..." paragraphs.

# Surnames used in running text: "Belkin and O'Reilly (2009)", "Ross et al. 2023"
cc_cited_names <- function(text) {
  hits <- unlist(regmatches(text, gregexpr(
    "\\b[A-Z][a-zA-Z'\u2019]+(?:\\s+et al\\.|\\s+and\\s+[A-Z][a-zA-Z'\u2019]+)\\s*\\(?[0-9]{4}",
    text)))
  unique(sub("\\s+(et al\\.|and\\s+[A-Z][a-zA-Z'\u2019]+)\\s*\\(?[0-9]{4}$", "", hits))
}

# Leading surname of each entry in a reference list, in either style.
cc_list_entries <- function(refs) {
  bullets <- unlist(regmatches(refs, gregexpr(
    "(?m)^[-*] ([A-Z][A-Za-z'\u2019]+)", refs, perl = TRUE)))
  bullets <- sub("^[-*] ", "", bullets)
  paras <- unlist(regmatches(refs, gregexpr(
    "(?m)^([A-Z][A-Za-z'\u2019]+),\\s+[A-Z]", refs, perl = TRUE)))
  paras <- sub(",\\s+[A-Z]$", "", paras)
  unique(c(bullets, paras))
}

#' Does every name cited in prose appear in the reference list, and vice versa?
#'
#' Two silent failures. A reference added to the list and never cited leaves a
#' reader wondering what it was for. A name cited in prose and missing from the
#' list leaves them unable to follow it up. Neither shows up in R CMD check.
check_reference_list <- function(registry, ctx) {
  root <- ctx$root %||% "."
  readme_path <- file.path(root, "README.md")
  if (!file.exists(readme_path)) {
    return(cc_result(notes = "No README.md; skipping the reference-list check."))
  }

  readme <- paste(readLines(readme_path, warn = FALSE), collapse = "\n")
  at <- regexpr("(?m)^#+ *References?\\b", readme, perl = TRUE)
  if (at < 0) {
    return(cc_result(notes = paste0(
      "README has no References section; skipping the reference-list check. ",
      "Add one if this package cites anything.")))
  }

  refs <- substring(readme, at)
  body <- substring(readme, 1, at - 1)

  # A long-form document anywhere in the project may carry its own reference
  # list, and a work cited only there is properly referenced - just not in the
  # top-level README. Treat every reference section in the project as one pool,
  # or the check reports a false positive every time a sub-document is added.
  #
  # "Reference" as well as "References": a section listing one work is usually
  # titled in the singular, and that is exactly the sub-document case.
  others <- setdiff(
    list.files(root, "[.]md$", full.names = TRUE, recursive = TRUE),
    readme_path
  )
  others <- others[!grepl("/(\\.git|node_modules|renv|packrat)/", others)]
  for (f in others) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    a2 <- regexpr("(?m)^#+ *References?\\b", txt, perl = TRUE)
    if (a2 > 0) refs <- paste(refs, substring(txt, a2), sep = "\n")
  }

  # A "Data sources" or "Software" subsection lists things a *user* should
  # cite, not things this documentation refers to, so its entries are not
  # orphans. Cut them off before looking.
  cut <- regexpr("(?m)^#+ *(Data sources|Software|Datasets)", refs, perl = TRUE)
  papers <- if (cut > 0) substring(refs, 1, cut - 1) else refs

  prose <- paste(c(
    body,
    unlist(lapply(list.files(file.path(root, "R"), "[.]R$", full.names = TRUE),
                  readLines, warn = FALSE)),
    unlist(lapply(list.files(file.path(root, "docs"), "[.]md$", full.names = TRUE),
                  readLines, warn = FALSE))
  ), collapse = "\n")

  failures <- character()
  notes <- character()

  for (name in cc_cited_names(prose)) {
    if (!grepl(name, refs, fixed = TRUE)) {
      notes <- c(notes, paste0(
        "`", name, "` is cited in the documentation but is not in the ",
        "README reference list."))
    }
  }

  entries <- cc_list_entries(papers)
  for (entry in entries) {
    if (!grepl(entry, prose, fixed = TRUE)) {
      notes <- c(notes, paste0(
        "`", entry, "` is in the reference list but cited nowhere."))
    }
  }

  if (!length(notes)) {
    cc_say("  ok  ", length(entries), " reference-list entries all cited, and ",
           "every cited name is listed")
  }

  # Reported as notes rather than failures: name matching from prose is
  # necessarily approximate, and a check that cries wolf gets ignored.
  cc_result(notes = notes)
}

# --- driver -----------------------------------------------------------------

#' Run a set of checks and report.
#'
#' @param registry_path Path to the registry CSV.
#' @param sources Files to scan for cited DOIs.
#' @param root Project root, used by the self-citation check.
#' @param hooks Named list of extra check functions, each `(registry, ctx)`.
#' @return `TRUE` if everything passed.
run_citation_checks <- function(registry_path, sources, root = ".",
                                hooks = list()) {
  registry <- citation_registry(registry_path)
  ctx <- list(sources = sources, registry_path = registry_path, root = root)

  checks <- c(
    list(
      "1. Registry coverage" = check_registry_coverage,
      "2. CrossRef metadata" = check_crossref_metadata,
      "3. URL liveness"      = check_url_liveness,
      "4. Package self-citation" = check_self_citation,
      "5. Reference list" = check_reference_list
    ),
    hooks
  )

  failures <- character()
  notes <- character()

  for (nm in names(checks)) {
    cc_rule(nm)
    res <- checks[[nm]](registry, ctx)
    failures <- c(failures, res$failures %||% character())
    notes <- c(notes, res$notes %||% character())
  }

  cc_rule("Summary")
  for (n in notes) cc_say("  note: ", n)

  if (length(failures)) {
    cc_say("")
    for (f in failures) cc_say("  FAIL: ", f)
    cc_say("\n", length(failures), " citation check(s) failed.")
    return(FALSE)
  }

  cc_say("  all citation checks passed",
         if (length(notes)) " (with notes above)" else "")
  TRUE
}
