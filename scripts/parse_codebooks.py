import pdfplumber, re, pandas as pd
U="/mnt/user-data/uploads/afrobarometer-trust-tax/data/raw"
FIELDS=["Question","Variable Label","Values","Value Labels","Source","Note"]
rows=[]
for rnd in (6,7,8,9):
    text=""; bounds=[]
    with pdfplumber.open(f"{U}/Merge{rnd}_Codebook.pdf") as pdf:
        for i,pg in enumerate(pdf.pages,1):
            t=(pg.extract_text() or "")
            t=re.sub(r"\n?\s*Copyright Afrobarometer\s*\d*\s*$","",t)   # strip page footer
            t=re.sub(r"\n\s*Copyright Afrobarometer\s*\d*\s*\n","\n",t)
            t=t+"\n"
            bounds.append((len(text),len(text)+len(t),i)); text+=t
    def page_of(pos):
        for a,b,i in bounds:
            if a<=pos<b: return i
        return None
    text=re.sub(r"-\n","",text)                      # de-hyphenate line breaks
    hits=list(re.finditer(r"Question Number:\s*([^\s\n]+)", text))
    for k,h in enumerate(hits):
        chunk=text[h.end(): hits[k+1].start() if k+1<len(hits) else len(text)]
        rec={"round_number":rnd,"question_number":h.group(1).strip(),
             "codebook_page":page_of(h.start())}
        for j,f in enumerate(FIELDS):
            m=re.search(rf"(?:^|\n)\s*{re.escape(f)}:\s*(.*?)(?=\n\s*(?:{'|'.join(re.escape(x) for x in FIELDS)}):|\Z)",
                        chunk, re.S)
            rec[f.lower().replace(" ","_")]=re.sub(r"\s+"," ",m.group(1)).strip() if m else ""
        rows.append(rec)
E=pd.DataFrame(rows); E.to_csv("out/codebook_entries.csv",index=False)
print("entries parsed per round:", E.groupby("round_number").size().to_dict())
print("\nsample:")
print(E[(E.round_number==9)&(E.question_number=="Q37G")].T.to_string())
