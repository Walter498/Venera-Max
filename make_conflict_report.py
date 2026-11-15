from pathlib import Path
import subprocess
root=Path('/var/minis/workspace/Venera-3.0.0-custom')
files=subprocess.check_output(['git','diff','--name-only','--diff-filter=U'],cwd=root,text=True).splitlines()
out=[]
for fn in files:
    p=root/fn
    lines=p.read_text(errors='replace').splitlines()
    out.append(f'\n===== {fn} =====')
    i=0
    while i<len(lines):
        if lines[i].startswith('<<<<<<<'):
            start=max(0,i-5); j=i+1
            while j<len(lines) and not lines[j].startswith('>>>>>>>'): j+=1
            end=min(len(lines),j+6)
            out.append(f'--- conflict at lines {i+1}-{j+1} ---')
            for n in range(start,end): out.append(f'{n+1:5}: {lines[n]}')
            i=j
        i+=1
Path('/var/minis/workspace/Venera-3.0.0-custom/conflict-report.txt').write_text('\n'.join(out))
print('files',len(files),'bytes',len('\n'.join(out)))
