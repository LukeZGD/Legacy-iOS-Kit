#!/usr/bin/env python3
"""Select the latest physical restore attempt for a standalone jump-start retry.

Reads journals only. This never restores, boots, or connects to a device.
"""
import argparse
from pathlib import Path
import re

from macho import ImageError
from session import Session


def restore_started(session):
    return max((item.get('time', 0) for item in session.data.get('history', [])
                if item.get('to') == 'restore-running'), default=0)


def require_pending_restore(session):
    if session.data.get('restorer_exit_code') != 0 or session.data.get('phase') != 'awaiting-jumpstart':
        raise ImageError('Jump-start retry requires a successful custom restore still awaiting jump-start')
    if not restore_started(session):
        raise ImageError('No recorded physical restore attempt for this session')
    session.verify_boot_artifacts()


def candidates(parent, ecid=None):
    # A newer failed/in-progress restore can have replaced the older filesystem.
    # Do not silently offer an older successful attempt for that same device.
    latest = {}
    for folder in Path(parent).glob('*'):
        if not re.fullmatch(r'[1-9][0-9]*-[a-f0-9-]{36}', folder.name):
            continue
        try:
            session = Session(folder)
            device = session.data.get('ecid')
            if not isinstance(device, str) or not re.fullmatch(r'[1-9][0-9]*', device):
                continue
            if ecid and device != ecid:
                continue
            started = restore_started(session)
            if not started:
                continue
            rank = (started, folder.name)
            if device not in latest or rank > latest[device][0]:
                latest[device] = (rank, session)
        except (ImageError, OSError, ValueError, KeyError, TypeError):
            continue
    result = []
    for rank, session in latest.values():
        try:
            require_pending_restore(session)
            result.append((rank, session))
        except (ImageError, OSError, ValueError, KeyError, TypeError):
            continue
    return [s for _, s in sorted(result, key=lambda item: item[0], reverse=True)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('list', 'identity'))
    parser.add_argument('--directory', required=True)
    parser.add_argument('--ecid')
    args = parser.parse_args()
    if args.action == 'list':
        for session in candidates(args.directory, args.ecid):
            d = session.data
            print(str(session.directory) + '\t' + d['product'] + ' / iOS ' + d['version'] + ' / ECID ' + d['ecid'])
    else:
        session = Session(args.directory)
        require_pending_restore(session)
        print('\t'.join(session.data[k] for k in ('product', 'board', 'version', 'build', 'ecid')))


if __name__ == '__main__':
    try:
        main()
    except (ImageError, OSError, ValueError, KeyError, TypeError) as exc:
        raise SystemExit(str(exc))
