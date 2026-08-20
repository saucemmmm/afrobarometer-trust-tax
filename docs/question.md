# Phase 0 — Question, estimand, and frozen variable list

**Project:** Afrobarometer relational database → institutional-trust panel
**Option chosen:** B — institutional trust, with a coverage-limited tax extension
**Frozen:** 2026-08-18 · **Revised:** 2026-08-19 after Phase 1.3 inventory

> **Revision note.** This document originally specified Option A (tax
> legitimacy). The Phase 1.3 inventory of the four `.sav` files showed the tax
> compliance item exists cleanly in R6 and R7 only — R8 asks a differently
> framed question and R9 carries no tax-attitude item at all. Break condition
> #1 fired as written. See `docs/phase1_inventory_findings.md`. The tax theme
> is retained as an explicitly coverage-limited extension (§7), not as the
> outcome.

**Code status.** Variable codes below are **extracted from the `.sav` files**
via SPSS metadata attributes — not guessed, not carried over between rounds.
Exact question wording and the label for the corruption `0` category are still
**pending codebook confirmation** (§8).

---

## 1. The question

> How does trust in the state institutions that enforce law and compliance —
> the police and the courts — co-move with perceived corruption in government
> and with perceived government economic performance, across African countries
> and across Afrobarometer rounds 6–9?

---

## 2. Estimand — one paragraph

Among adult residents of the African countries surveyed by Afrobarometer in
rounds 6 through 9, I estimate the association between a respondent's
**trust in state enforcement institutions** — an index of trust in the police
and trust in the courts of law — and two perceptual measures: **how widespread
the respondent believes corruption is among government officials**, and **how
well the respondent judges the government to be handling the economy**. The
comparison is made at two levels. The primary comparison is *within country,
across rounds*: country fixed effects absorb time-invariant country
characteristics (colonial and legal legacy, ethnic fractionalization,
constitutional structure, baseline state capacity), and round fixed effects
absorb shocks common to all countries in a wave, so the estimate is driven by
countries whose perceptions moved between rounds. The secondary comparison is
*across countries within a round*, reported descriptively only. All means are
weighted by the Afrobarometer within-country survey weight — `withinwt` in
R6/R7 and `withinwt_ea` in R8/R9, which is the definition continuous with the
earlier rounds — and standard errors are clustered at the country level, which
is the level at which both sampling design and the shocks of interest vary.
This design supports a statement of the form: *in country-rounds where
perceived corruption among government officials is higher, or perceived
government economic performance lower, the weighted mean trust in police and
courts is on average lower by X, conditional on the observables in §5 and net
of country and round fixed effects.* It does not support any statement about
what would happen to institutional trust if corruption or government
performance were changed.

### The five bullets, stated explicitly

- **Population.** Adult respondents (the Afrobarometer sampling frame:
  citizens of voting age, nationally representative, urban and rural) in every
  country fielded in rounds 6, 7, 8 and 9 — 201,286 respondent records in
  total. Countries are **not** subset by hand; the panel is unbalanced by
  construction and the imbalance is reported, not hidden.
- **Outcome.** `trust_enforcement_index` — the mean of the harmonized
  trust-in-police and trust-in-courts items (each 0–3), computed only where
  both items are non-missing. Analyzed at the individual level and as the
  survey-weighted country-round mean. The two component items are also
  reported separately as a robustness check.
- **Comparison.** Primary: within country, across rounds (two-way fixed
  effects, country × round). Secondary: across countries within a round,
  descriptive only. A balanced-panel version — countries present in all four
  rounds — is reported alongside the full panel.
- **What this can support.** A descriptive association, conditional on the
  observables in §5 and on country and round fixed effects. A statement that
  two things move together within countries over time.
- **What this cannot support.** A causal effect. Trust in institutions,
  perceived corruption, and perceived economic performance are plausibly all
  responding to the same unobserved shocks, and reverse causation is entirely
  live — people who trust the police may report lower perceived corruption
  precisely *because* they trust institutions, rather than the other way round.
  There is no exogenous variation here, no instrument, and no discontinuity.
  **Two-way fixed effects on observational cross-country survey data does not
  identify a causal parameter.** This sentence goes into the README verbatim.

---

## 3. Why this outcome

**Police and courts, not the president.** These are the coercive and legal arms
of the state — the institutions that actually enforce law and compliance, and
the ones whose perceived legitimacy is theorised to underpin voluntary
cooperation with the state. Trust in the president is available in all four
rounds but is heavily driven by incumbent partisanship and election timing,
which would import a political-cycle story this design cannot adjudicate.

**Why an index rather than one item.** The two items are conceptually paired
(enforcement and adjudication), share an identical 0–3 scale in all four
rounds, and averaging reduces item-specific measurement noise. The cost — that
an index obscures divergence between the two — is addressed by reporting both
items separately.

**Continuity.** Afrobarometer trust outcomes are the same family used in
Nunn–Wantchekon, which the MA essay already re-estimates. That is real
interview depth rather than portfolio-project familiarity.

---

## 4. Why these covariates — and the one Phase 0 got wrong

**Perceived corruption among government officials.**
Phase 0 designated *corruption of tax officials* as the covariate and
explicitly **cut** general government corruption as collinear. The inventory
reversed that: the tax-officials item is **absent from R7**, while the
general government-officials item is present in all four rounds. Coverage
decided this, not preference. The tax-specific item moves to §7.

**Perceived government handling of the economy.**
Retained unchanged. Present in all four rounds on a stable 1–4 scale, it is
the closest available proxy for what citizens believe they receive from the
state, and it is not a restatement of the outcome.

**Why only two.** Every additional concept is another codebook confirmation,
another `question_map` row per round, and another block of `response_values`
mappings. Two covariates of interest, one two-item outcome, and a small
control block is the whole budget.

---

## 5. Covariate candidates — keep / cut

| # | Candidate | Role | Verdict | Reasoning |
|---|---|---|---|---|
| 1 | Corruption: **government officials** | covariate of interest | **KEEP** | Only corruption item present in all four rounds. Promoted from "cut" after inventory. |
| 2 | Government handling of **the economy** | covariate of interest | **KEEP** | Fiscal-exchange proxy. All four rounds, stable scale. |
| 3 | **Urban/rural, age, gender, education** | demographic block | **KEEP** | Cheap, present every round, and they shift the composition of the weighted mean. ⚠️ R9 renumbered gender (`Q100`) and education (`Q94`); urban/rural categories are not harmonized — see §6.2. |
| 4 | **Lived Poverty Index** | control | **KEEP, with a construction decision** | Ability-to-pay / material-deprivation confound. Pre-built `LivedPoverty` exists in R7/R8/R9 but **not R6**. See §6.3. |
| 5 | Corruption: **tax officials** | covariate | **MOVED to §7** | Absent from R7. Cannot serve as a four-round covariate. |
| 6 | **Trust in the tax authority** | — | **MOVED to §7** | Absent from R7 **and** R9. Also note: as an *outcome* it would have been near-tautological against a trust index; as an extension outcome it is fine. |
| 7 | Corruption: **office of the Presidency** | covariate | **CUT** | Present all four rounds but highly correlated with #1; including both invites a collinearity argument without adding information. Available as a robustness swap. |
| 8 | **Personal bribe experience** | covariate | **CUT** | Experience, not perception — a different construct needing its own theory. Batteries vary across rounds; high item non-response. |
| 9 | **Trust in the president** | covariate | **CUT** | Partisanship and election timing dominate; imports a story the design cannot adjudicate. |
| 10 | **Access to public services** | covariate | **CUT** | Option C's question. Importing it changes what the project is about and doubles the crosswalk. |

---

## 6. Frozen variable list

**Rounds:** 6, 7, 8, 9. **Round 5 excluded** — on disk, but a fifth codebook
read and the most instrument drift.

### 6.1 Core — codes extracted from the `.sav` files

| `canonical_code` | Role | Scale | R6 | R7 | R8 | R9 |
|---|---|---|---|---|---|---|
| `trust_police` | outcome component | 0–3 | `Q52H` | `Q43G` | `Q41G` | `Q37G` |
| `trust_courts` | outcome component | 0–3 | `Q52J` | `Q43I` | `Q41I` | `Q37I` |
| `corruption_govt_officials` | covariate | 0–3 | `Q53C` | `Q44C` | `Q42C` | `Q38C` |
| `govt_perf_economy` | covariate | 1–4 | `Q66A` | `Q56A` | `Q50A` | `Q46A` |
| `urban_rural` | demographic | categorical | `URBRUR` | `URBRUR` | `URBRUR` | `URBRUR` |
| `age` | demographic | numeric | `Q1` | `Q1` | `Q1` | `Q1` |
| `gender` | demographic | binary | `Q101` | `Q101` | `Q101` | **`Q100`** |
| `education_level` | demographic | ordinal | `Q97` | `Q97` | `Q97` | **`Q94`** |
| `lived_poverty` | control | continuous | *see §6.3* | `LivedPoverty` | `LivedPoverty` | `LivedPoverty` |
| `within_weight` | **weight** | continuous | `withinwt` | `withinwt` | **`withinwt_ea`** | **`withinwt_ea`** |

**Structural:** `RESPNO` (unique *within* round only — must be round-prefixed),
`COUNTRY`, `REGION`, `DATEINTR`.

### 6.2 Harmonization decisions required — decide before `03_build_crosswalk.sql`

**a. Missing codes differ by round.** R6 codes Refused as **98**; R7–R9 use
**8**. All rounds use `−1 = Missing` and `9 = Don't know`. R6 additionally
carries `99 = Not asked in this country` on performance items. Every one of
these maps to `value_harmonized = NULL`, `is_missing = TRUE`, **per round**.
No round-invariant missing rule is correct.

**b. Urban/rural categories are not harmonized.**

| Round | Categories |
|---|---|
| R6, R7 | 1 Urban · 2 Rural · 3 Semi-Urban · **460 Peri-Urban** |
| R8 | 1 Urban · 2 Rural · 3 Semi-Urban |
| R9 | 1 Urban · 2 Rural · 3 Peri-urban |

**Decision: collapse to binary — Urban = {1, 3, 460}, Rural = {2}** — and
document it. The stray `460` code in R6/R7 is a data-quality finding for the
README; check the codebook before assuming it means what its label says.

**c. The survey weight changed definition at R8.** R8/R9 split the
within-country weight into `withinwt_ea` ("old AB withinwt", enumeration-area
level) and `withinwt_hh` ("new", household level). **Use `withinwt_ea`** — it
is the definition continuous with R6/R7's `withinwt`. Using `withinwt_hh`
would make weighted means non-comparable across the R7/R8 boundary. State this
in the memo; it is a substantive choice, not a formality.

**d. Gender label wording changed** (R6 "Male/Female" → R9 "Man/Woman") on
identical codes 1/2. Harmless, but record it rather than silently unifying.

### 6.3 The one open construction decision — Lived Poverty in R6

`LivedPoverty` (documented as the average of five deprivation items) is
pre-built in R7, R8 and R9 but **not in R6**. R6 carries the five components
(`Q8A`–`Q8E`: food, water, medical care, cooking fuel, cash income), as do the
later rounds (`Q7A`–`Q7E` in R8, `Q6A`–`Q6E` in R9).

- **Recommended:** construct R6's index from `Q8A`–`Q8E` using the same
  averaging formula, after confirming the formula in the R7 codebook. Cost:
  five extra `questions` rows and their value mappings, R6 only — roughly
  30–45 minutes.
- **Fallback if time is tight:** cut `lived_poverty` entirely. Do **not**
  include it for R7–R9 only; that silently changes the estimation sample
  across rounds.

> ⚠️ **This list is FROZEN.** Adding a variable is traded directly against
> finishing. If a new variable is proposed, answer first which one it replaces.

---

## 7. The tax extension — explicitly coverage-limited

The public-finance theme is retained as a secondary analysis, reported with
its coverage stated on the face of every table and figure. It is **not** part
of the main estimand and no four-round claim is made from it.

| `canonical_code` | Scale | R6 | R7 | R8 | R9 |
|---|---|---|---|---|---|
| `trust_tax_authority` | 0–3 | `Q52D` | — | `Q41J` | — |
| `corruption_tax_officials` | 0–3 | `Q53F` | — | `Q42G` | `Q38G` |

**What this can support:** a two-round (R6, R8) comparison of trust in the
revenue authority against trust in police and courts, and a three-round
(R6, R8, R9) look at whether perceived corruption of tax officials tracks
perceived corruption of government officials generally.

**What it cannot support:** any trend statement, any use of `LAG` across
adjacent rounds, or any claim that the tax pattern generalizes to R7 or R9.

**Why it earns its place.** These gaps are the substantive content of the
`LEFT JOIN` coverage query (outline §8.4) — the NULLs are the finding, and
"which countries and which items enter and leave the panel" is the question
that determines whether any cross-round comparison is balanced.

---

## 8. What still requires the codebook PDFs

1. **The label for `value_raw = 0` on every corruption item.** It exists in all
   four rounds with an **empty** label in the `.sav`; values 1–3 are Some /
   Most / All. Almost certainly "None", but the file does not say so.
   **Blocking** — this cannot be extracted and must be read.
2. **Verbatim question wording** for every item in §6.1 and §7.
3. **The `LivedPoverty` averaging formula** (§6.3).
4. **The meaning of `URBRUR = 460`** in R6/R7 (§6.2b).
5. **Country coverage notes** for any item not asked in all countries.

---

## 9. Inference notes fixed in advance

- **Weights are mandatory.** Every mean, every regression, using the §6.2c
  choice consistently.
- **Cluster at country level** — but rounds 6–9 give roughly 34–39 countries,
  so the cluster count is **small enough that asymptotic cluster-robust
  standard errors are optimistic**. Report a wild cluster bootstrap alongside,
  or at minimum state the small-cluster caveat in the memo. Do not report a
  conventional cluster-robust p-value as though 35 clusters were plenty.
- **Balanced panel reported alongside** the full unbalanced panel.
- **Multiple comparisons.** One outcome index × two covariates of interest.
  The family is small *by design* and was fixed here, before estimation. The
  tax extension in §7 is reported as exploratory and labelled as such.
- **Language discipline.** No "effect", "impact", "drives", "leads to",
  "causes", or "explains" in the memo, README, figures, or resume bullets.
  Permitted: "is associated with", "co-moves with", "is higher/lower in
  country-rounds where".
