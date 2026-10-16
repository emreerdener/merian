"""Persistent trusted fixture composer for successive, independently identified admissions."""
from dataclasses import dataclass
import hashlib
import uuid
from initial_atomic_admission_sessions import BASE, Session


@dataclass(frozen=True)
class Admission:
    owner_id: str
    scan_id: str
    receipt_id: str


class AdmissionFixture:
    """Keep pg_temp composers on one connection; never reinstall shared rows."""

    def __init__(self, qualification, held=True):
        self.qualification = qualification
        self.session = Session(qualification, 'synthetic_fixture_owner', statement_seconds=45, marker_seconds=55)
        self.count = 0
        self.pending_admission = None
        try:
            prefix, self.owner, self.foreign = qualification.fixture_prefix(held)
            self.bound_owner = self.owner
            self.owners = {self.owner, self.foreign}
            prefix += 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;COMMIT;'
            qualification.record['fixture_setup_sha256'] = hashlib.sha256(prefix.encode()).hexdigest()
            qualification.save()
            self.session.run('install_fixture_once', prefix)
        except Exception:
            self.session.close()
            raise

    def ensure_owner(self, owner_id):
        if self.pending_admission is not None:
            raise ValueError('finish the prepared admission before installing owners')
        if str(uuid.UUID(owner_id)) != owner_id:
            raise ValueError('canonical synthetic owner UUID required')
        if owner_id in self.owners:
            return
        if len(self.owners) >= 4:
            raise ValueError('at most four synthetic owners per fixture')
        self.session.run('install_additional_owner', BASE +
            "SELECT pg_temp.admission_owner('" + owner_id + "');"
            "DO $$ BEGIN IF (SELECT count(*) FROM public.users WHERE id='" + owner_id +
            "')<>1 THEN RAISE EXCEPTION USING ERRCODE='ZX599';END IF;END $$;COMMIT;")
        self.owners.add(owner_id)

    def bind_owner(self, owner_id):
        if self.pending_admission is not None:
            raise ValueError('finish the prepared admission before rebinding')
        if owner_id not in self.owners:
            raise ValueError('only installed synthetic owners allowed')
        if owner_id != self.bound_owner:
            # The catalog helper embeds one synthetic owner. Rebind only this
            # connection-local definition, retaining the archived fixture seam.
            self.session.run('rebind_media_owner',
                "DO $$ DECLARE definition TEXT;BEGIN "
                "definition:=pg_get_functiondef('pg_temp.media_create(uuid,bigint)'::REGPROCEDURE);"
                "IF (length(definition)-length(replace(definition,'" + self.bound_owner + "','')))/36<>1 "
                "THEN RAISE EXCEPTION USING ERRCODE='ZX598';END IF;"
                "EXECUTE replace(definition,'" + self.bound_owner + "','" + owner_id + "');END $$;")
            self.bound_owner = owner_id

    def prepare_admission(self, owner_id, scan, ip_identity='a', *, commit=True):
        if self.pending_admission is not None or not isinstance(commit, bool):
            raise ValueError('only one prepared admission at a time')
        if owner_id not in self.owners or ip_identity not in ('a', 'c'):
            raise ValueError('only installed synthetic owners and IP identities allowed')
        if str(uuid.UUID(scan)) != scan or self.bound_owner != owner_id:
            raise ValueError('canonical scan and matching bound owner required')
        self.count += 1
        sql = self.qualification.admission_sql(owner_id, scan)
        if sql.count("repeat('a',64)") != 1:
            raise ValueError('one synthetic quota IP identity required')
        sql = sql.replace("repeat('a',64)", "repeat('" + ip_identity + "',64)")
        ending = 'END; $admit$;\nCOMMIT;'
        if sql.count(ending) != 1:
            raise ValueError('one admission commit boundary required')
        sql = sql.replace(ending, 'END; $admit$;\nUPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=FALSE;\n' + ('COMMIT;' if commit else ''))
        sql = 'UPDATE internal.initial_analysis_rollout SET initial_analysis_lifecycle_enabled=TRUE;' + sql
        self.qualification.record.setdefault('fixture_admission_sha256', []).append(hashlib.sha256(sql.encode()).hexdigest())
        self.qualification.save()
        if not commit:
            self.pending_admission = (owner_id, scan)
        return sql

    def read_identity(self, owner, scan):
        rows = self.session.run('identity_' + str(self.count),
            "SELECT owner_id::TEXT||':'||scan_id::TEXT||':'||admission_receipt_id::TEXT "
            "FROM internal.initial_preparation_admission_receipts WHERE scan_id='" + scan + "';")
        if len(rows) != 1:
            raise RuntimeError('one exact admission identity required')
        owner_id, scan_id, receipt_id = rows[0].split(':')
        if owner_id != owner or scan_id != scan:
            raise RuntimeError('admission identity mismatch')
        uuid.UUID(receipt_id)
        return Admission(owner_id, scan_id, receipt_id)

    def commit_prepared(self):
        if self.pending_admission is None:
            raise ValueError('a prepared admission is required')
        identity = self.read_identity(*self.pending_admission)
        self.session.run('admission_commit', 'COMMIT;')
        self.pending_admission = None
        return identity

    def admit_one(self, owner_id=None, ip_identity='a'):
        owner_id = self.owner if owner_id is None else owner_id
        self.bind_owner(owner_id)
        scan = str(uuid.uuid4())
        sql = self.prepare_admission(owner_id, scan, ip_identity)
        self.session.run('admit_' + str(self.count), BASE + sql)
        return self.read_identity(owner_id, scan)

    def close(self):
        self.session.close()
