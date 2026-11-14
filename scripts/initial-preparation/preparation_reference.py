"""Immutable identity for local evidence; never a runtime or dispatch grant."""
import json

from artifact import VALIDATED, select_version, sha

DOMAIN = b'merian.initial-analysis.preparation-profile.v1\n'
MAX_REFERENCE_BYTES = 16384


def preparation_reference(version):
    """Return canonical immutable bytes from the finite registry authority."""
    if type(version) is not str or version != VALIDATED:
        raise ValueError('unsupported_preparation_profile')
    entry = select_version(version)
    if entry['artifact_sha256'] is None or entry['artifact_bytes'] is None:
        raise ValueError('unregistered_artifact')
    value = dict(version=1, profile_id=VALIDATED, scope='local_synthetic_only',
                 platform='darwin-arm64', protocol_version=2,
                 validator_id='initial-wav-structure-v1',
                 transform_id='initial_audio_v1',
                 options=dict(target_sample_rate=16000,
                              fallback_rule='clip_index_not_null'),
                 registry_entry=entry)
    raw = json.dumps(value, sort_keys=True, separators=(',', ':'),
                     ensure_ascii=False, allow_nan=False).encode('utf-8')
    if not raw.isascii() or len(raw) > MAX_REFERENCE_BYTES:
        raise ValueError('preparation_reference_bound')
    return raw


def decode_preparation_reference(candidate):
    """Do not parse untrusted JSON: only the exact authority bytes can match.

    This rejects duplicate keys at any depth, type/number aliases, whitespace,
    BOM, extra fields and altered tuple/order values before they gain meaning.
    """
    if type(candidate) is not bytes or not 0 < len(candidate) <= MAX_REFERENCE_BYTES:
        raise ValueError('preparation_reference_bound')
    expected = preparation_reference(VALIDATED)
    if candidate != expected:
        raise ValueError('preparation_reference_identity')
    return expected


def preparation_reference_digest(candidate):
    return sha(DOMAIN + decode_preparation_reference(candidate))


def preparation_reference_edge_eligible(candidate):
    decode_preparation_reference(candidate)
    # Qualified local synthetic Darwin evidence cannot select Edge execution.
    return False
