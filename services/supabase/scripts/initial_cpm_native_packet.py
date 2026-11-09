"""Closed synthetic native fixture input; never accepts private backend configuration.

The native test retains its actual acquisition input and owner-read derivatives.
Canonical candidate bytes are carried verbatim, not rebuilt from parsed fields.
This is test IPC, not an upload or original-media export API.
"""
import base64
import hashlib
import json
import re

MAX_PACKET = 2 * 1024 * 1024
MAX_ROLE = 256 * 1024
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")


def closed_json(raw):
    def pairs(entries):
        result = {}
        for key, value in entries:
            if key in result:
                raise ValueError("duplicate fixture key")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite fixture number")))


def validate_packet(raw, nonce, execution):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= MAX_PACKET:
        raise ValueError("fixture packet bound")
    value = closed_json(raw.decode("utf-8", errors="strict"))
    if not isinstance(value, dict) or set(value) != {"version", "nonce", "owner_id", "candidate_canonical", "candidate_sha256", "roles", "execution"}:
        raise ValueError("fixture envelope")
    if type(value["version"]) is not int or value["version"] != 1 or value["nonce"] != nonce:
        raise ValueError("fixture binding")
    if not isinstance(value["owner_id"], str) or not UUID.fullmatch(value["owner_id"]):
        raise ValueError("synthetic owner")
    if (not isinstance(value["execution"], dict) or value["execution"] != execution
            or set(execution) != {"source_sha256", "app_sha256", "tests_sha256"}
            or any(not isinstance(h, str) or not re.fullmatch(r"[0-9a-f]{64}", h) for h in execution.values())):
        raise ValueError("exact execution binding")
    canonical = value["candidate_canonical"]
    if not isinstance(canonical, str) or not 0 < len(canonical.encode()) <= 131072:
        raise ValueError("candidate bound")
    if hashlib.sha256(canonical.encode()).hexdigest() != value["candidate_sha256"]:
        raise ValueError("candidate byte identity")
    candidate = closed_json(canonical)
    if set(candidate) != {"version", "variant", "content_canonical", "admission"}:
        raise ValueError("candidate shape")
    content = closed_json(candidate["content_canonical"])
    if not UUID.fullmatch(content["scan_id"]) or len(content["photos"]) != 2:
        raise ValueError("two-photo fixture identity")
    roles = value["roles"]
    if not isinstance(roles, list) or len(roles) != 6:
        raise ValueError("complete fixture roster")
    roster, content_types = [], []
    for index, role in enumerate(roles):
        ordinal, name = index // 3, ["source", "ai", "display"][index % 3]
        if not isinstance(role, dict) or set(role) != {"ordinal", "role", "bytes_base64"}:
            raise ValueError("fixture role shape")
        if type(role["ordinal"]) is not int or role["ordinal"] != ordinal or role["role"] != name:
            raise ValueError("ordered fixture roles")
        encoded = role["bytes_base64"]
        if not isinstance(encoded, str) or len(encoded) > (MAX_ROLE + 2) // 3 * 4:
            raise ValueError("fixture role bound")
        data = base64.b64decode(encoded, validate=True)
        if not 0 < len(data) <= MAX_ROLE or base64.b64encode(data).decode() != encoded:
            raise ValueError("fixture role encoding")
        photo = content["photos"][ordinal]
        declaration = photo[name]
        if (photo["ordinal"] != ordinal or type(declaration["byte_count"]) is not int
                or declaration["byte_count"] != len(data)
                or declaration["sha256"] != hashlib.sha256(data).hexdigest()
                or declaration["declared_content_type"] not in ("image/jpeg", "image/png")
                or (name != "source" and declaration["declared_content_type"] != "image/jpeg")):
            raise ValueError("original prepared bytes differ")
        roster.append(data)
        content_types.append(declaration["declared_content_type"])
    return {"owner": value["owner_id"], "scan": content["scan_id"], "canonical": canonical,
            "sha256": value["candidate_sha256"], "candidate": candidate,
            "roster": roster, "content_types": content_types, "execution": dict(execution)}


def bind_fixture_identity(prefix, packet):
    """Bind only trusted fixture SQL fragments, never submitted canonical text."""
    prefix = prefix.replace("00000000-0000-4000-8000-00000000f001", packet["owner"])
    return prefix.replace("00000000-0000-4000-8000-00000000f101", packet["scan"])


def bind_fixture_prefix(prefix, packet):
    """Reuse existing disposable seeding; the actual create call receives literal bytes."""
    from initial_cpm_admission_bridge_races import literal
    prefix = bind_fixture_identity(prefix, packet)
    pattern = r"CREATE FUNCTION pg_temp\.cpm_candidate\(scan UUID\) RETURNS TEXT LANGUAGE SQL AS \$\$.*?\$\$;"
    replacement = "CREATE FUNCTION pg_temp.cpm_candidate(scan UUID) RETURNS TEXT LANGUAGE SQL AS $$ SELECT " + literal(packet["canonical"]) + "; $$;"
    # A fixed literal SQL function body must never contain its enclosing delimiter.
    # Native canonical metadata may legitimately contain '$$'; use a fresh tag.
    tag = "$native_" + packet["sha256"] + "$"
    if tag in packet["canonical"]:
        raise ValueError("fixture SQL delimiter")
    replacement = replacement.replace("AS $$ SELECT", "AS " + tag + " SELECT").removesuffix(" $$;") + " " + tag + ";"
    result, count = re.subn(pattern, lambda _: replacement, prefix, flags=re.S)
    if count != 1:
        raise ValueError("unique fixture candidate owner required")
    return result
