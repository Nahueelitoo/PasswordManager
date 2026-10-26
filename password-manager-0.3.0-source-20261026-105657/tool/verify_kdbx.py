"""Verify only the public fictitious fixture created by tool/interop.dart."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / 'build' / 'verification_deps'))
from pykeepass import PyKeePass

source = Path((root / 'build' / 'interop' / 'latest-path.txt').read_text())
assert source.resolve().is_relative_to((root / 'build' / 'interop').resolve())
vault = PyKeePass(str(source), password='public fixture password for interoperability')
assert vault.version == (4, 0)
assert vault.encryption_algorithm == 'aes256'
assert vault.entries[0].title == 'Interoperability fixture'
assert vault.entries[0].username == 'demo@example.org'
assert vault.entries[0].password == 'fictional-entry-password'
assert vault.entries[0].url == 'https://example.org'
vault.entries[0].notes = 'Updated by independent implementation'
vault.save(str(root / 'build' / 'interop' / 'from-python.kdbx'))
print('Independent implementation opened KDBX 4 / AES-256 and verified fixture fields.')
