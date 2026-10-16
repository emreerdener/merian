"""Closed synthetic fixture pipe correlation. No process is launched here."""
import json
from artifact import compact, read_regular, select_version, sha, VALIDATED, validated_request, validate_validated_answer, wav


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def digest(domain, value):
    return sha(domain.encode() + b'\n' + canonical(value))


class OwnerExchange:
    def __init__(self, args, cwd, cache, inputs, fixture):
        self.args, self.cwd, self.cache, self.inputs = tuple(args), cwd, cache, dict(inputs)
        self.vector = json.loads(read_regular(fixture, 65536))
        v = self.vector
        entry = select_version(VALIDATED)
        p = v['profile']
        spec = p['spec']
        limits = dict(source_bytes=192000, output_bytes=192000, cpu_ms=15000, heap_bytes=268435456, wall_ms=15000)
        if (v['synthetic_only'] is not True or v['edge_eligible'] is not False or
                v['resource_status'] != 'sampled_local_only' or spec['profile_id'] != 'local_validated_wav_fixture' or
                spec['runtime'] != dict(engine='deno', version='2.9.4', platform='darwin_arm64', abi='local_synthetic_only', protocol=2) or
                spec['artifact'] != dict(sha256=entry['artifact_sha256'], byte_count=entry['artifact_bytes']) or
                spec['identities'] != dict(source=sha(canonical(entry)), validator=entry['validator']['sha256'],
                                           transform=sha(canonical(entry['inputs'][:6])), configuration=entry['configuration_digest']) or
                spec['max_sources'] != 1 or spec['limits'] != limits or
                spec['rules'] != [dict(role='recording', source_types=['audio/wav'], transform='initial_audio_v1',
                                      target_sample_rate=16000, preserve_short_video_context=False, max_count=1, limits=limits)] or
                p['qualification']['spec_digest'] != digest('merian.initial-analysis.media.profile_spec.v1', spec)):
            raise ValueError('local_fixture_profile')
        self.source = wav(32000, [8192] * 32000)
        self.inner = validated_request(self.source)
        if len(self.source) > 192000 or len(self.inner) > 262144:
            raise ValueError('local_fixture_envelope')
        a, candidate = v['assignment'], v['candidate']
        source = candidate['source_plan']['sources']
        if (len(source) != 1 or source[0]['source_byte_count'] != len(self.source) or source[0]['source_sha256'] != sha(self.source) or
                source[0]['clip_index'] is not None or source[0]['frame_index'] is not None or source[0]['transform'] != 'initial_audio_v1' or
                source[0]['transform_parameters'] != dict(target_sample_rate=16000, preserve_short_video_context=False) or
                a['candidate_digest'] != digest('merian.initial-analysis.preparation-candidate.v2', candidate) or
                a['source_plan_digest'] != digest('merian.initial-analysis.media.source_plan.v1', candidate['source_plan']) or
                v['assignment_digest'] != digest('merian.initial-analysis.assignment.v2', a) or
                a['preparation']['profile_digest'] != digest('merian.initial-analysis.media.profile.v1', p) or
                len(a['preparation']['source_mapping']) != 1 or a['preparation']['source_mapping'][0]['source'] != source[0]):
            raise ValueError('local_fixture_source')
        self.identity = dict(version=1, scan_id=v['scan'], assignment_digest=v['assignment_digest'])
        self.source_receipt = dict(self.identity, profile_digest=a['preparation']['profile_digest'],
                                   backend_generation=a['preparation']['backend_generation'], validator_identity=spec['identities']['validator'],
                                   entries=[dict(ordinal=0, object_id=a['preparation']['source_mapping'][0]['object_id'],
                                                 bytes=dict(byte_count=len(self.source), sha256=sha(self.source), content_type='audio/wav'),
                                                 facts=dict(image=None, wav=dict(format='pcm16', sample_rate=32000, channels=1, frames=32000), mp4=None))])
        self.source_digest = digest('merian.initial-analysis.preparation-execution.source_verification.v1', self.source_receipt)
        self.grant = dict(self.identity, grant_id=v['grant_id'], source_digest=self.source_digest,
                          profile_digest=a['preparation']['profile_digest'], artifact_digest=spec['artifact']['sha256'],
                          issued_at_ms=1000000, execution_deadline_ms=1020000, registration_deadline_ms=1025000, outcome_deadline_ms=1060000)
        self.expected = compact(dict(version=1, kind='execute', scan_id=v['scan'], assignment_digest=v['assignment_digest'],
                                     grant_id=v['grant_id'], source_digest=self.source_digest, profile_digest=self.grant['profile_digest'],
                                     ordinal=0, request=json.loads(self.inner))) + b'\n'
        self.consumed = self.finished = False
        self.output = self.outcome_digest = self.stage = None

    def accept(self, frame):
        if not isinstance(frame, bytes) or len(frame) > 280000:
            raise ValueError('local_fixture_frame')
        if frame == self.expected and not self.consumed and not self.finished:
            self.consumed = True
            return self.inner
        # Final summaries contain only fixed scalar fields; no process output/media.
        if not self.consumed or self.finished or self.output is None:
            raise ValueError('local_fixture_unexpected_frame')
        expected = compact(dict(version=1, kind='summary', outcome='outcome_ready', replay='outcome_ready',
                                runtime=1, issues=1, reads=1, retains=1, outcome_digest=self.outcome_digest)) + b'\n'
        if frame != expected:
            raise ValueError('local_fixture_summary')
        self.finished = True
        return None

    def answer(self, code, raw, stderr):
        if not self.consumed or self.output is not None or self.stage is not None:
            raise ValueError('local_fixture_answer')
        header = dict(version=1, kind='prepared', grant_id=self.vector['grant_id'], source_digest=self.source_digest, ordinal=0)
        if code in (2, 3):
            stage = 'validation' if code == 2 else 'transform'
            if raw or stderr != compact(dict(version=2, status='rejected', stage=stage, transform_started=stage == 'transform')) + b'\n':
                raise ValueError('local_fixture_rejection')
            self.stage = stage
            header['kind'] = 'rejected'
            return compact(dict(header, stage=stage)) + b'\n'
        if code != 0 or stderr:
            raise ValueError('local_fixture_process')
        output = validate_validated_answer(raw, self.source, False)
        if len(output) > 192000:
            raise ValueError('local_fixture_output')
        self.output = output
        request = dict(self.identity, grant_id=self.grant['grant_id'], source_digest=self.source_digest,
                       entries=[dict(ordinal=0, prepared=dict(bytes=dict(byte_count=len(output), sha256=sha(output), content_type='audio/wav'),
                                                              transform='initial_audio_v1', parameters=dict(target_sample_rate=16000, preserve_short_video_context=False), source_identity=output == self.source))])
        resolved = dict(self.identity, grant_id=self.grant['grant_id'], request_digest=digest('merian.initial-analysis.preparation-execution.output_manifest.v1', request),
                        entries=[dict(ordinal=0, object_id=self.vector['output_id'])])
        outcome = dict(self.identity, grant=self.grant, source_verification=self.source_receipt, output_manifest=request,
                       resolved_manifest=resolved, profile=self.vector['profile'],
                       retained=[dict(ordinal=0, object_id=self.vector['output_id'], bytes=request['entries'][0]['prepared']['bytes'])])
        self.outcome_digest = digest('merian.initial-analysis.preparation-execution.outcome.v1', outcome)
        return compact(dict(header, answer=json.loads(raw))) + b'\n'
