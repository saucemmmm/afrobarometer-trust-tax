# Phase 0 — Question, estimand, and frozen variable list

**Project:** Afrobarometer relational database → tax-legitimacy panel
**Option chosen:** A — tax legitimacy
**Frozen:** 2026-08-18
**Code status:** ⚠️ every round-specific variable code and value label in this
document is **UNVERIFIED**. Codes and missing-value conventions differ between
rounds and must be read out of each round's codebook in Phase 1.3 before any
of this is treated as real. Concepts are frozen here; *codes are not asserted here.*

---

## 1. The question

> How does stated willingness to pay taxes co-move with perceived government
> performance and perceived corruption, across African countries and across
> Afrobarometer rounds 6–9?

---

## 2. Estimand — one paragraph

Among adult residents of the African countries surveyed by Afrobarometer in
rounds 6 through 9, I estimate the association between a respondent's stated
**tax-compliance norm** — endorsement of the obligation to pay taxes owed — and
two perceptual measures: **how well the respondent judges the government to be
handling the economy**, and **how widespread the respondent believes corruption
is among tax officials**. The comparison is made at two levels. The primary
comparison is *within country, across rounds*: country fixed effects absorb
time-invariant country characteristics (colonial and legal legacy, ethnic
fractionalization, statutory tax structure, enforcement capacity), and round
fixed effects absorb shocks common to all countries in a wave, so the estimate
is driven by countries whose perceptions moved between rounds. The secondary
comparison is *across countries within a round*, reported descriptively only.
All means are weighted by the Afrobarometer within-country survey weight, and
standard errors are clustered at the country level, which is the level at which
both sampling design and the shocks of interest vary. This design supports a
statement of the form: *in country-rounds where perceived government economic
performance is higher, or perceived corruption of tax officials lower, the
weighted mean tax-compliance norm is on average higher by X, conditional on the
observables listed in §5 and net of country and round fixed effects.* It does
not support any statement about what would happen to tax attitudes if
government performance or corruption were changed.

### The five bullets, stated explicitly

- **Population.** Adult respondents (the Afrobarometer sampling frame:
  citizens of voting age, nationally representative, both urban and rural) in
  every country fielded in Afrobarometer rounds 6, 7, 8 and 9. Countries are
  **not** subset by hand; the panel is unbalanced by construction and the
  imbalance is reported, not hidden.
- **Outcome.** The harmonized tax-compliance-norm item (canonical code
  `tax_compliance_norm`), analyzed at two levels: the individual response, and
  the survey-weighted country-round mean.
- **Comparison.** Primary: within country, across rounds (two-way fixed
  effects, country × round). Secondary: across countries within a round,
  descriptive only. A balanced-panel version — restricted to countries present
  in all four rounds — is reported alongside the full panel.
- **What this can support.** A descriptive association, conditional on the
  observables in §5 and on country and round fixed effects. A statement that
  two things move together within countries over time.
- **What this cannot support.** A causal effect. Perceived government
  performance, perceived corruption, and tax attitudes are plausibly all
  responding to the same unobserved shocks, and reverse causation is entirely
  live — people who feel obliged to pay taxes may rate government more
  favourably rather than the other way round. There is no exogenous variation
  here, no instrument, and no discontinuity. **Two-way fixed effects on
  observational cross-country survey data does not identify a causal
  parameter.** This sentence goes into the README verbatim.

---

## 3. Why *these* two covariates of interest

The question names two constructs. Each is included because it carries a
distinct, pre-stated reason, not because it was available.

**Perceived government performance (economy).**
The fiscal-exchange account of tax compliance holds that willingness to pay is
a function of what citizens believe they receive in return. Perceived
government economic performance is the closest available survey proxy for that
return. It is asked in a consistent battery across rounds, is not a direct
restatement of the outcome, and it is the covariate a public-finance reader
will expect to see first.

**Perceived corruption among tax officials.**
The complementary account: compliance falls when citizens believe the revenue
is captured rather than spent. The *tax-official* item is chosen deliberately
over generic corruption because it is the corruption perception most
proximate to the tax-payment decision itself, and because using a
tax-specific measure rather than a general one is a defensible choice that a
reviewer can interrogate. It is also the item most at risk of not being asked
in every round — see §6.

**Why only two.** The variable list is the top scope risk in this project.
Every additional concept is another codebook read, another `question_map` row
per round, and another block of `response_values` mappings to verify by hand.
Two covariates of interest, one outcome, and a small demographic block is the
whole budget.

---

## 4. Covariate candidates considered — keep / cut

Nine candidates were considered. Four are kept, five are cut. The cuts are
recorded here so that "why didn't you control for X" has an answer that was
written before the results existed.

| # | Candidate concept | Role | Verdict | Reasoning |
|---|---|---|---|---|
| 1 | Government handling of **the economy** | covariate of interest | **KEEP** | The fiscal-exchange proxy. Core to the question. Asked as part of a stable performance battery. |
| 2 | Perceived corruption of **tax officials** | covariate of interest | **KEEP** | The capture proxy, and the corruption item closest to the tax decision. Core to the question. |
| 3 | **Urban/rural, age, gender, education** | demographic block | **KEEP** | Cheap: four items, near-certainly present every round, minimal crosswalk cost. They shift the composition of the weighted mean and their absence would be noticed. Treated as one block. |
| 4 | **Lived Poverty Index** (going without cash income, food, water, medical care) | control | **KEEP, conditionally** | Ability to pay is the obvious omitted variable — poorer respondents may report lower compliance norms for reasons unrelated to legitimacy. **Condition:** keep only if the merged file carries a pre-constructed LPI variable. If it must be built from 4–5 component items, that is 4–5 extra crosswalk rows *per round* and it is **cut** instead. Verify in Phase 1.3. |
| 5 | Perceived corruption of the **Presidency / government officials generally** | covariate | **CUT** | Almost certainly highly correlated with #2, so including both invites a collinearity argument and muddies which corruption perception is doing the work. Retain as a **robustness swap**: re-run substituting general for tax-official corruption, report both. Costs one extra concept only if the robustness check is run. |
| 6 | **Personal bribe experience** (paid a bribe for a permit, to police, etc.) | covariate | **CUT** | Different construct — experience, not perception — and would need its own theory of why experience should move a stated norm. Typically high item non-response and asked with varying batteries across rounds. High crosswalk cost, low marginal information. |
| 7 | **Trust in the tax authority / revenue authority** | covariate | **CUT — and note why** | This is the strongest cut. Trust in the tax authority and the obligation to pay taxes are plausibly the *same latent construct* measured twice. Regressing one on the other produces a large coefficient that means nothing. Including it would be a genuine methodological error, not merely a scope cost. |
| 8 | **Presidential approval** | covariate | **CUT** | Redundant with #1 and more politically volatile; adds noise and a partisanship story the design cannot adjudicate. |
| 9 | **Access to public services** (water, electricity, clinic) | covariate | **CUT** | This is Option C's question, not Option A's. Importing it changes what the project is about and doubles the crosswalk. Out of scope. |

---

## 5. Frozen variable list

**Rounds:** 6, 7, 8, 9. **Round 5 is excluded** — it is on disk but adds a fifth
codebook read and carries the most instrument drift of the five.

**Structural fields** (identifiers, not analysis variables):

| Field | Purpose |
|---|---|
| respondent id (`respno`) | Unique **within** a round only — must be round-prefixed. |
| country | Joins to `countries`. |
| round | Joins to `rounds`. |

**Analysis variables** — 6 concepts (7 if LPI survives), plus one weight:

| # | `canonical_code` | Concept | Role | Scale | R6 | R7 | R8 | R9 |
|---|---|---|---|---|---|---|---|---|
| 1 | `tax_compliance_norm` | Obligation to pay taxes owed | **outcome** | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 2 | `govt_perf_economy` | Govt handling of the economy | covariate | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 3 | `corruption_tax_officials` | Corruption among tax officials | covariate | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 4 | `urban_rural` | Settlement type | demographic | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 5 | `age` | Age in years | demographic | numeric | ❓ | ❓ | ❓ | ❓ |
| 6 | `gender` | Respondent gender | demographic | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 7 | `education_level` | Highest level completed | demographic | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 8 | `lived_poverty` | Lived Poverty Index | control — **conditional** | UNVERIFIED | ❓ | ❓ | ❓ | ❓ |
| 9 | `within_weight` | Within-country survey weight | **weight — mandatory** | numeric | ❓ | ❓ | ❓ | ❓ |

❓ = round-specific code to be filled from the codebook in Phase 1.3. Do not
populate these cells from memory, from another round, or from any secondary
source.

**Missing-value handling.** Afrobarometer commonly uses codes in the family
8 / 9 / 98 / 99 / 998 for refused, don't know, and missing — but the exact
convention **differs by round and by item**. Every such code maps to
`value_harmonized = NULL` with `is_missing = TRUE` in `response_values`.
A missing code is never mapped onto a valid response value. Verify per round,
per item.

> ⚠️ **This list is FROZEN.** Adding a variable is traded directly against
> finishing the project. If a new variable is proposed, the question to answer
> first is which existing one it replaces.

---

## 6. Conditions that would break this freeze

This is written down now so that discovering it in Phase 1 is a planned
contingency rather than a crisis.

1. **The outcome is not asked in at least 3 of the 4 rounds.** This is the
   single largest risk to Option A — tax-attitude items are less stable across
   Afrobarometer rounds than trust or performance items. If the compliance-norm
   item appears in fewer than three rounds, **switch to Option B (institutional
   trust)**, which uses more stable instrumentation. Check this *first* in
   Phase 1.3, before extracting anything else.
2. **`corruption_tax_officials` is missing from a round.** Fall back to
   candidate #5 (general government corruption) as the primary covariate and
   document the substitution.
3. **The outcome's response scale changes across rounds.** Resolve per outline
   §5.3 — restrict to rounds sharing a scale, or collapse to a common coarser
   scale. Record which and why. Do not standardize within round without
   restating what the outcome then means.
4. **An item is not asked in all countries within a round.** Record it in
   `question_map.asked_all_countries` and exclude those country-rounds from the
   panel rather than treating them as zero.

---

## 7. Inference notes fixed in advance

- **Weights are mandatory.** Every mean, every regression. Unweighted means
  from a stratified sample are wrong.
- **Clustering at country level.** But note: rounds 6–9 give roughly 34–39
  countries, so the cluster count is **small enough that asymptotic
  cluster-robust standard errors are optimistic**. Report a wild cluster
  bootstrap alongside, or at minimum state the small-cluster caveat in the memo.
  Do not report a conventional cluster-robust p-value as though 35 clusters
  were plenty.
- **Balanced panel reported alongside.** Countries enter and leave; the result
  must be shown for countries present in all four rounds as well as for the
  full unbalanced panel.
- **Multiple comparisons.** One outcome × two covariates of interest. The
  family is small *by design*, and it was fixed here, on 2026-08-18, before any
  estimation. That is the reason for freezing the list at Phase 0 rather than
  after seeing the data.
- **Language discipline.** No "effect", "impact", "drives", "leads to",
  "causes", or "explains" in the memo, README, figures, or resume bullets.
  Permitted: "is associated with", "co-moves with", "is higher/lower in
  country-rounds where".
