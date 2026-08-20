# Phase 1.3 — Inventory findings (machine-extracted from the .sav files)

**Run:** 2026-08-19, from `data/raw/Merge{6,7,8,9}.sav` via SPSS metadata attributes.
**Source of truth:** the `.sav` files themselves. Full question wording still
requires the codebook PDFs — variable labels below are abbreviations.

| Round | Respondents | Columns |
|---|---|---|
| R6 | 53,935 | 364 |
| R7 | 45,823 | 366 |
| R8 | 48,084 | 425 |
| R9 | 53,444 | 421 |

**Total: 201,286 respondent records.**

---

## 1. ⛔ Break condition #1 has fired — the Option A outcome does not survive

`tax_compliance_norm` was to be the outcome. What actually exists:

| Round | Variable | Label | Battery it sits in |
|---|---|---|---|
| R6 | `Q42C` | People must pay taxes | Q42a courts binding · Q42b obey law · **Q42c pay taxes** |
| R7 | `Q38C` | People must pay taxes | Q38a courts binding · Q38b obey law · **Q38c pay taxes** · … |
| R8 | `Q39A` | Tax authorities have right to enforce taxes | Q39a **enforce** · Q39b govt information official use |
| R9 | — | **absent** | — |

R6 `Q42C` and R7 `Q38C` are the same item: the state-legitimacy triad
(binding courts / obey the law / pay taxes), identical 1–5 agree-disagree scale.

**R8 `Q39A` is a different item.** Its battery-mate (`Q39B`, "Government
information for official use only") matches R7's `Q38G`, not R7's tax item.
The R8 question is framed as the *authority's right to enforce*, not the
*citizen's obligation to pay*. Treating them as one concept would be an
assertion, not a harmonization.

**R9 contains no tax-attitude item of any kind** — a search of all 421 variable
labels returns exactly one tax hit: `Q38G`, corruption of tax officials.

**Verdict: Option A has 2 clean rounds, not 4.** A two-round panel does not
justify a crosswalk, does not support `LAG` over a meaningful series, and
removes the cross-round harmonization problem that is the project's entire
reason to exist.

---

## 2. ✅ Option B (institutional trust) is fully viable across all four rounds

The trust battery is present in every round, with stable item wording:

| Concept | R6 | R7 | R8 | R9 |
|---|---|---|---|---|
| Trust president | `Q52A` | `Q43A` | `Q41A` | `Q37A` |
| Trust parliament | `Q52B` | `Q43B` | `Q41B` | `Q37B` |
| Trust police | `Q52H` | `Q43G` | `Q41G` | `Q37G` |
| Trust courts of law | `Q52J` | `Q43I` | `Q41I` | `Q37I` |
| Trust electoral commission | `Q52C` | `Q43C` | `Q41C` | `Q37C` |
| **Trust tax department / revenue office** | `Q52D` | **absent** | `Q41J` | **absent** |

Note the code drift — `Q52H → Q43G → Q41G → Q37G` for the same police item.
This is exactly the instability the `question_map` table exists to record.

---

## 3. ✅ Both covariates of interest survive — one with a substitution

**Government handling of the economy — all four rounds:**
`Q66A` (R6) → `Q56A` (R7) → `Q50A` (R8) → `Q46A` (R9). Scale stable at 1–4
(Very badly / Fairly badly / Fairly well / Very well).

**Corruption — the battery is in all four rounds, but the tax-official item is not:**

| Item | R6 | R7 | R8 | R9 |
|---|---|---|---|---|
| Corruption: tax officials | `Q53F` | **absent** | `Q42G` | `Q38G` |
| Corruption: govt officials / civil servants | `Q53C` | `Q44C` | `Q42C` | `Q38C` |
| Corruption: office of the Presidency | `Q53A` | `Q44A` | `Q42A` | `Q38A` |
| Corruption: police | `Q53E` | `Q44E` | `Q42E` | `Q38E` |

Scale stable at 0–3 (None / Some of them / Most of them / All of them).

**Consequence:** the Phase 0 cut of "general government corruption" (candidate
#5) must be reversed. `corruption_govt_officials` is the only corruption item
with full four-round coverage, so it becomes the primary covariate;
`corruption_tax_officials` drops to a three-round sub-analysis.

---

## 4. Controls and structural fields — all present

| Concept | R6 | R7 | R8 | R9 | Note |
|---|---|---|---|---|---|
| Respondent id | `RESPNO` | `RESPNO` | `RESPNO` | `RESPNO` | unique **within** round only |
| Country | `COUNTRY` | `COUNTRY` | `COUNTRY` | `COUNTRY` | |
| Region | `REGION` | `REGION` | `REGION` | `REGION` | |
| Interview date | `DATEINTR` | `DATEINTR` | `DATEINTR` | `DATEINTR` | |
| Urban/rural | `URBRUR` | `URBRUR` | `URBRUR` | `URBRUR` | ⚠️ R8 `URBRUR` is **3-category**; use `URBRUR_COND` for a 2-category series |
| Age | `Q1` | `Q1` | `Q1` | `Q1` | stable |
| Gender | `Q101` | `Q101` | `Q101` | **`Q100`** | R9 renumbered |
| Education | `Q97` | `Q97` | `Q97` | **`Q94`** | R9 renumbered |
| Lived Poverty Index | **absent** | `LivedPoverty` | `LivedPoverty` | `LivedPoverty` | R6 has the 5 components (`Q8A`–`Q8E`) but no pre-built index |

---

## 5. ⚠️ Three harmonization problems found that Phase 0 did not anticipate

### 5.1 The survey weight changed definition between R7 and R8

| Round | Weight variables |
|---|---|
| R6 | `withinwt`, `Combinwt` |
| R7 | `withinwt`, `Combinwt` |
| R8 | `withinwt_ea`, `withinwt_hh`, `Combinwt_old_ea`, `Combinwt_new_hh` |
| R9 | `withinwt_ea`, `withinwt_hh`, `Combinwt_old_ea`, `Combinwt_new_hh` |

R8 and R9 split the within-country weight into an enumeration-area version
(labelled "old AB withinwt") and a household version ("new AB withinwt").

**Decision required, and it must be stated in the memo:** use `withinwt_ea` for
R8/R9, because it is the definition continuous with R6/R7's `withinwt`.
Choosing `withinwt_hh` would make the weighted means non-comparable across the
R7/R8 boundary. This is a genuine harmonization decision, not a formality.

### 5.2 Missing-value codes are NOT constant across rounds

| Round | "Refused" | "Don't know" | Other |
|---|---|---|---|
| R6 | **98** | 9 | −1 Missing; **99 = Not asked in this country** |
| R7 | **8** | 9 | −1 Missing |
| R8 | **8** | 9 | −1 Missing |
| R9 | **8** | 9 | −1 Missing |

R6 codes Refused as **98** where later rounds use **8**. On the 0–3 corruption
scale and the 1–5 agree scale, 8 is out of range and harmless; but any
round-invariant rule of the form "8 is always Refused" is wrong for R6, and
R6's `99 = Not asked in this country` is a fourth missing type that later
rounds do not carry. Every mapping goes in `response_values` per round.

### 5.3 The corruption scale's zero category has no label in the .sav

For every corruption item in every round, `value_raw = 0` exists but carries an
**empty** value label. Values 1–3 are Some / Most / All. The 0 category is
almost certainly "None", but the `.sav` does not say so.

**This must be read off the codebook PDF and cannot be extracted.** It is the
clearest case in the project of why the codebook and the `.sav` are both
required: the file has the codes, the codebook has their meaning.

---

### 5.4 Merge6.sav declares LATIN1 and carries non-UTF-8 bytes

`Merge6.sav` sets its file encoding to **LATIN1** in the header and contains
Latin-1 byte sequences that are not valid UTF-8 - row 39,619 holds `VOTACAO`
(with cedilla and tilde) in the verbatim field `Q29B`, from the Lusophone
samples. A default `haven::read_sav()` of the whole file fails with *"Unable to
convert string to the requested encoding"*.

Two things hide this until late:

- a truncated read (`n_max = 1`) succeeds, because the offending rows are ~39k
  rows in;
- a `col_select` read succeeds, because only the selected columns are decoded.

So the inventory and crosswalk scripts run clean on this file and only the full
staging conversion fails. Every `.sav` read now goes through `read_sav_safe()`
in `R/00_utils.R`, which retries with `encoding = "latin1"` and says so. The
encoding actually used is recorded per round in `docs/staging_manifest.csv`.
R7-R9 read cleanly by default; only R6 needs the fallback.

---

## 6. What still requires the codebook PDFs

1. **The label for corruption `value_raw = 0`** (§5.3) — blocking.
2. **Full question wording** for every item entering the crosswalk. Variable
   labels above are abbreviations, and `question_text` must be verbatim.
3. **Confirmation that R8 `Q39A` differs from R6 `Q42C` / R7 `Q38C`** — the
   battery evidence is strong but the wording is decisive.
4. **Country coverage notes** for any item not asked in all countries.
