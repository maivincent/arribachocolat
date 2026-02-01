#!/usr/bin/env python3
import os,json
fr=[]
for root,_,files in os.walk("_i18n/fr"):
  for f in files:
    if f.endswith('.md'):
      p=os.path.join(root,f)
      rel=os.path.relpath(p,'_i18n/fr')
      fr.append(rel.replace(os.sep,'/'))
fr=sorted(fr)
en_missing=[]
es_missing=[]
for rel in fr:
  if not os.path.exists(os.path.join('_i18n/en',rel)):
    en_missing.append(rel)
  if not os.path.exists(os.path.join('_i18n/es',rel)):
    es_missing.append(rel)
result={'count_fr':len(fr),'en_missing':en_missing,'es_missing':es_missing}
print(json.dumps(result,ensure_ascii=False,indent=2))
