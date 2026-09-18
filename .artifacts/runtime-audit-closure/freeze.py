import importlib.util,pathlib,subprocess,shutil,json,os
root=pathlib.Path.cwd();out=root/'.artifacts/runtime-audit-closure';dest=out/'candidate'
s=importlib.util.spec_from_file_location('runner',root/'scripts/local-ios-build.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);workspace=m.Workspace(root)
before=workspace.audit_source_identity()
subprocess.run(['git','clone','--shared','--no-hardlinks','--quiet',str(root),str(dest)],check=True)
paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=root,text=True).split('\0')
for name in paths:
 if not name:continue
 source=root/name;target=dest/name
 if source.is_symlink():
  target.parent.mkdir(parents=True,exist_ok=True)
  if target.exists() or target.is_symlink():target.unlink()
  target.symlink_to(os.readlink(source))
 elif source.is_file():
  target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
 elif not source.exists() and target.exists():target.unlink()
after=workspace.audit_source_identity();frozen=m.Workspace(dest).audit_source_identity()
(out/'snapshot-origin.json').write_text(json.dumps({'before':before,'after':after,'frozen':frozen,'stable':before==after,'matches_frozen':after==frozen},indent=2)+'\n')
assert before==after==frozen,'Source changed during snapshot; do not validate this copy'
cache=dest/'.build/local-ios';cache.mkdir(parents=True,exist_ok=True)
for name in ['packages','package-cache']:
 source=root/'.build/local-ios'/name
 if source.exists():subprocess.run(['cp','-cR',str(source),str(cache/name)],check=True)
print('FROZEN',frozen['source_fingerprint'],flush=True)
