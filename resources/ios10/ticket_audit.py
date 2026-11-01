#!/usr/bin/env python3
"""Summarize ticket evidence without inferring causation from a nonce alone."""
import argparse
import base64
import hashlib
from pathlib import Path
import re

from prepare import write_json


def audit(text):
    text = re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', text.replace('\r', '\n'))
    device_hashes = re.findall(r'device tree ticket_hash:\s*([0-9A-Fa-f]{40,96})', text)
    supplied_hashes = re.findall(r'computed ticket_hash\s*:\s*([0-9A-Fa-f]{40,96})', text)
    nonces = re.findall(r'(?:Getting ApNonce[^\n]*?\.\.\.|^Nonce:)\s*((?:[0-9a-fA-F]{2}[ \t]+){19}[0-9a-fA-F]{2})', text, re.M)
    tickets = []
    for encoded in re.findall(r'<key>APTicket</key>\s*<data>(.*?)</data>', text, re.S):
        try:
            data = base64.b64decode(re.sub(r'\s', '', encoded), validate=True)
            sha = hashlib.sha1(data).hexdigest()
            if sha not in tickets:
                tickets.append(sha)
        except ValueError:
            pass
    rejected = 'ramrod_ticket_update: invalid ticket' in text
    accepted = 'received valid ticket' in text
    asr_killed = '/usr/sbin/asr was terminated by signal 9' in text
    amfi_rejected = 'AMFI: code signature validation failed.' in text
    return dict(device_nonces=[re.sub(r'\s', '', n).lower() for n in nonces],
                tss_ticket_sha1=tickets, device_tree_ticket_hashes=[h.lower() for h in device_hashes],
                supplied_root_ticket_hashes=[h.lower() for h in supplied_hashes],
                ticket_rejected=rejected, ticket_accepted=accepted,
                ticket_hashes_match=(device_hashes[-1].lower() == supplied_hashes[-1].lower())
                    if device_hashes and supplied_hashes else None,
                cached_shsh_used='Using cached SHSH' in text,
                asr_killed_signal_9=asr_killed, amfi_signature_rejection=amfi_rejected,
                reached_partition_nand=bool(re.search(r'CHECKPOINT BEGIN:[^\n]* partition_nand', text)),
                interpretation='Explicit ticket rejection recorded' if rejected else
                    'Explicit ticket acceptance recorded' if accepted else 'Ticket outcome not established by this log',
                limits='Nonce differences alone do not prove the cause. Missing evidence is not success.')


def audit_logs(log, serial=None):
    text = Path(log).read_text(errors='replace')
    sources = [str(log)]
    if serial:
        # Raw receive bytes avoid timestamp insertions splitting kernel lines.
        text += '\n' + Path(serial).read_bytes().decode('utf-8', errors='replace')
        sources.append(str(serial))
    return dict(audit(text), evidence_sources=sources)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--log', required=True)
    p.add_argument('--output', required=True)
    p.add_argument('--serial-log')
    a = p.parse_args()
    write_json(a.output, audit_logs(a.log, a.serial_log))
