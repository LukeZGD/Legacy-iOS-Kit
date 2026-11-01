#!/usr/bin/env python3
"""Require the late-restore finalizer success marker in an available DCSD trace."""
import json,sys
from pathlib import Path

def audit(text):
    text=text.replace('\r','')
    start=text.rfind('[LIK-AIO] FINAL_MOUNTED_STAGE:')
    done=text.rfind('[LIK-AIO] INSTALLATION_COMPLETE:')
    failure=text.rfind('[LIK-AIO] INSTALLATION_FAILED')
    return dict(trigger_observed=start>=0,installation_verified=done>start>=0 and failure<start,
                installation_failed=failure>=0 and failure>=start,
                hardware_boot_verified=False)
if __name__=='__main__':
    result=audit(Path(sys.argv[1]).read_bytes().decode('utf-8', errors='replace'))
    (Path(sys.argv[2])/'allinone-restore-audit.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Restore-stage untether verification: '+('passed' if result['installation_verified'] else 'failed' if result['installation_failed'] else 'not confirmed'))
    sys.exit(0 if result['installation_verified'] else 3 if result['installation_failed'] else 2)
