from pathlib import Path
root=Path('/var/minis/workspace/Venera-3.0.0-custom')
for fn,mode in {
 'lib/foundation/history.dart':'ours',
 'lib/foundation/res.dart':'ours',
}.items():
 p=root/fn; lines=p.read_text().splitlines(keepends=True); out=[]; i=0
 while i<len(lines):
  if lines[i].startswith('<<<<<<<'):
   l=[]; r=[]; i+=1; t=l
   while i<len(lines) and not lines[i].startswith('>>>>>>>'):
    if lines[i].startswith('======='): t=r
    else: t.append(lines[i])
    i+=1
   out += l if mode=='ours' else r; i+=1
  else: out.append(lines[i]); i+=1
 p.write_text(''.join(out))
print('done')
