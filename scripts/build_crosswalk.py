import pandas as pd, numpy as np
INV_V=pd.read_csv("out/inventory_variables.csv"); INV_L=pd.read_csv("out/inventory_values.csv")

Q={ # canonical_code: (concept, role, scale, higher_means, valid_range, question_text, per-round var)
"trust_police":("institutional_trust","outcome_component","likert_0_3","more trust",range(0,4),
  "How much do you trust each of the following, or haven't you heard enough about them to say: The Police?",
  {6:"Q52H",7:"Q43G",8:"Q41G",9:"Q37G"}),
"trust_courts":("institutional_trust","outcome_component","likert_0_3","more trust",range(0,4),
  "How much do you trust each of the following, or haven’t you heard enough about them to say: Courts of law?",
  {6:"Q52J",7:"Q43I",8:"Q41I",9:"Q37I"}),
"corruption_govt_officials":("corruption_perception","covariate","likert_0_3","more perceived corruption",range(0,4),
  "How many of the following people do you think are involved in corruption, or haven’t you heard enough about them to say: Government Officials?",
  {6:"Q53C",7:"Q44C",8:"Q42C",9:"Q38C"}),
"govt_perf_economy":("govt_performance","covariate","likert_1_4","better perceived performance",range(1,5),
  "Now let’s speak about the present government of this country. How well or badly would you say the current government is handling the following matters, or haven’t you heard enough to say: Managing the economy?",
  {6:"Q66A",7:"Q56A",8:"Q50A",9:"Q46A"}),
"urban_rural":("demographic","demographic","categorical","n/a (1=Urban, 2=Rural)",[1,2,3,460],
  "PSU/EA",{6:"URBRUR",7:"URBRUR",8:"URBRUR",9:"URBRUR"}),
"age":("demographic","demographic","numeric","older",None,
  "How old are you?",{6:"Q1",7:"Q1",8:"Q1",9:"Q1"}),
"gender":("demographic","demographic","categorical","n/a (1=Male, 2=Female)",[1,2],
  "Respondent's gender",{6:"Q101",7:"Q101",8:"Q101",9:"Q100"}),
"education_level":("demographic","demographic","ordinal_0_9","more education",range(0,10),
  "What is your highest level of education?",{6:"Q97",7:"Q97",8:"Q97",9:"Q94"}),
"lived_poverty":("material_deprivation","control","continuous_0_4","more deprivation",None,
  "",{6:None,7:"LivedPoverty",8:"LivedPoverty",9:"LivedPoverty"}),
"within_weight":("survey_design","weight","continuous","n/a",None,
  "",{6:"withinwt",7:"withinwt",8:"withinwt_ea",9:"withinwt_ea"}),
"trust_tax_authority":("institutional_trust","extension","likert_0_3","more trust",range(0,4),
  "How much do you trust each of the following, or haven't you heard enough about them to say: The [Tax Department]?",
  {6:"Q52D",7:None,8:"Q41J",9:None}),
"corruption_tax_officials":("corruption_perception","extension","likert_0_3","more perceived corruption",range(0,4),
  "How many of the following people do you think are involved in corruption, or haven’t you heard enough about them to say: Tax Officials (e.g. Ministry of Finance officials or Local Government tax collectors)?",
  {6:"Q53F",7:None,8:"Q42G",9:"Q38G"}),
}
LP_STEM="Over the past year, how often, if ever, have you or anyone in your family: "
LP={"food":"Gone without enough food to eat?","water":"Gone without enough clean water for home use?",
    "medical":"Gone without medicines or medical treatment?",
    "fuel":"Gone without enough fuel to cook your food?","cash":"Gone without a cash income?"}
for sfx,lt in [("food","A"),("water","B"),("medical","C"),("fuel","D"),("cash","E")]:
    Q[f"lp_{sfx}"]=("material_deprivation","lpi_component","likert_0_4","more deprivation",range(0,5),
      LP_STEM+LP[sfx],{6:f"Q8{lt}",7:f"Q8{lt}",8:f"Q7{lt}",9:f"Q6{lt}"})

CORR0={"corruption_govt_officials","corruption_tax_officials"}
vrows,lrows=[],[]
for code,(concept,role,scale,hm,valid,qtext,vmap) in Q.items():
    for rnd in (6,7,8,9):
        var=vmap[rnd]
        if var is None:
            note=("constructed from lp_* components; see docs/question.md 6.3"
                  if code=="lived_poverty" else "item not asked in this round")
            vrows.append(dict(canonical_code=code,concept=concept,role=role,round_number=rnd,
                present=False,round_variable="",variable_label="",question_text="",
                codebook_source="",codebook_note="",codebook_page="",raw_scale_type="",
                n_substantive_categories="",higher_means=hm,asked_all_countries="",
                countries_excluded="",verified=True,notes=note)); continue
        meta=INV_V[(INV_V.round_number==rnd)&(INV_V.variable_name==var)]
        vlab=meta.variable_label.iloc[0] if len(meta) else ""
        labs=INV_L[(INV_L.round_number==rnd)&(INV_L.variable_name==var)]
        subs=[]
        for _,x in labs.iterrows():
            raw=int(x.value_raw); lab=x.value_label
            if code in CORR0 and raw==0 and (pd.isna(lab) or str(lab)=="nan"):
                lab="None"                      # confirmed from codebook, absent from .sav
            miss = valid is None or raw not in list(valid)
            if not miss: subs.append(raw)
            lrows.append(dict(canonical_code=code,round_number=rnd,value_raw=raw,
                value_label=lab,
                value_harmonized=("" if miss else (1 if (code=="urban_rural" and raw in (1,3,460))
                                                   else 2 if code=="urban_rural" else raw)),
                is_missing=miss,
                harmonization_rule=("missing" if miss else
                    "collapsed to binary: urban={1,3,460}, rural={2}" if code=="urban_rural" else "direct"),
                codebook_page="",notes=""))
        vrows.append(dict(canonical_code=code,concept=concept,role=role,round_number=rnd,
            present=True,round_variable=var,variable_label=vlab,question_text=qtext,
            codebook_source="",codebook_note="",codebook_page="",raw_scale_type=scale,
            n_substantive_categories=(len(subs) if valid is not None else ""),
            higher_means=hm,asked_all_countries="",countries_excluded="",
            verified=(bool(qtext) or code in ("lived_poverty","within_weight")) and not (role=="lpi_component" and rnd in (8,9)),
            notes=("wording carried from the R6/R7 Q8x battery; spot-check against this round's codebook"
                   if role=="lpi_component" and rnd in (8,9)
                   else "constructed/design variable; no codebook question exists"
                   if code in ("lived_poverty","within_weight") else "")))
V=pd.DataFrame(vrows); L=pd.DataFrame(lrows)
V.to_csv("out/crosswalk_variables.csv",index=False)
L.to_csv("out/crosswalk_values.csv",index=False)
print("variable rows:",len(V),"| present:",int(V.present.sum()),"| absent:",int((~V.present).sum()))
print("value rows:",len(L),"| missing-coded:",int(L.is_missing.sum()),"| substantive:",int((~L.is_missing).sum()))
print("\nunverified wording:",sorted(V[V.notes.str.contains('wording',na=False)].canonical_code.unique()))
print("\ncoverage matrix (present):")
print(V.pivot_table(index="canonical_code",columns="round_number",values="present",aggfunc="first")
       .replace({True:"Y",False:"."}).to_string())
