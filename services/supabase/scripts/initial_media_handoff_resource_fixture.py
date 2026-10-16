"""Synthetic byte-transport cohorts for current installed local test profiles.

These deterministic buffers qualify transport size/hash and resource behavior,
not media structure or the preparation transform. Everything is bound before
fresh admission; no admitted document or original deadline is rewritten.
"""
import copy
import hashlib
import json
from initial_atomic_admission_test_support import Qualification, ROOT, STAGE


def byte_spec(size, fill):
    return {'byte_count': size, 'fill': fill,
            'sha256': hashlib.sha256(bytes([fill]) * size).hexdigest()}


def resource_fixture(shape):
    if shape not in ('photo_audio', 'photo_audio_images', 'video_audio'):
        raise ValueError('fixed local profile shape required')
    text = (ROOT / STAGE).read_text()
    if text.count('$vectors$') != 2:
        raise ValueError('unique archived fixture vector block required')
    vectors = json.loads(text.split('$vectors$')[1])
    is_video = shape == 'video_audio'
    vector = 6 if is_video else 4
    image_count = 2 if shape == 'photo_audio' else 3
    audio_count = 2 if shape == 'photo_audio' else 1
    original = vectors[vector - 1]
    candidate = copy.deepcopy(original['candidate'])
    plan = candidate['source_plan']
    image = next(s for s in plan['sources'] if s['kind'] == 'image')
    audio = next(s for s in plan['sources'] if s['kind'] == 'audio')
    # The matcher reserves each image rule's full output limit. With a 20 MiB
    # aggregate reservation, photo/audio admits (2,2) or (3,1), video (3,1,1).
    # Actual images still jointly reach the separate 5 MiB input cap.
    image_sizes = [5242880 // image_count] * image_count
    image_sizes[-1] += 5242880 % image_count
    image_specs = [byte_spec(size, 3) for size in image_sizes]
    audio_bytes = byte_spec(2700000, 7)
    prepared_bytes = byte_spec(2700000, 8)
    video_bytes = byte_spec(12582912, 5)
    sources = []

    def bind(s, spec):
        s['source_byte_count'] = spec['byte_count']
        s['source_sha256'] = spec['sha256']
        return s

    for index in range(image_count):
        s = copy.deepcopy(image)
        s['input_index'] = index
        if not is_video:
            s['source_index'] = index
        else:
            s['frame_index'] = index
        sources.append(bind(s, image_specs[index]))
    for index in range(audio_count):
        s = copy.deepcopy(audio)
        s['input_index'] = index
        if not is_video:
            s['source_index'] = index
        sources.append(bind(s, audio_bytes))
    if is_video:
        s = copy.deepcopy(next(s for s in plan['sources'] if s['kind'] == 'video'))
        sources.append(bind(s, video_bytes))
        plan['capture']['declared_video_frame_count'] = image_count
        plan['capture']['video_inference_frame_count'] = image_count
    plan['sources'] = sources
    plan['owner_timeline'] = [
        {'kind': 'description', 'index': i}
        for i in range(len(plan['ordered_descriptions']))
    ] + [{'kind': 'media', 'index': i}
         for i, s in enumerate(sources) if s['kind'] == 'video' or s['clip_index'] is None]
    specs = list({s['sha256']: s for s in image_specs}.values()) + [audio_bytes, prepared_bytes]
    if is_video:
        specs.append(video_bytes)
    return {'shape': shape, 'vector': vector, 'candidate': candidate,
            'input_profile': original['profile']['spec']['input_profile'],
            'profile_canonical': original['profile_canonical'],
            'specs': specs, 'prepared': prepared_bytes, 'source_count': len(sources),
            'object_count': len(sources) + audio_count,
            'alias_count': 2 * image_count + 2 * audio_count + int(is_video),
            'unique_bytes': 5242880 + 5400000 * audio_count + 12582912 * int(is_video)}


class ResourceQualification(Qualification):
    resource = None

    def admission_sql(self, owner, scan):
        if self.resource is None:
            raise ValueError('select original resource profile before admission')
        sql = super().admission_sql(owner, scan)
        old = "pg_temp.media_create('" + scan + "',1)"
        assert sql.count(old) == 1 and sql.count("'vision_compat_v1'") == 1
        return sql.replace(old, "pg_temp.media_create('" + scan + "'," + str(self.resource['vector']) + ')').replace(
            "'vision_compat_v1'", "'" + self.resource['input_profile'] + "'")


def install_before_admission(fixture, spec):
    # Amend only the connection-local synthetic composer. Both audio outputs
    # still have distinct allocated IDs; the bytes are deliberately identical.
    prepared = spec['prepared']
    canonical = json.dumps(spec['candidate'], separators=(',', ':'))
    assert '$resource$' not in canonical
    sql = "UPDATE media_vectors SET v=jsonb_set(v,'{candidate}',$resource$" + canonical + "$resource$::JSONB) WHERE i=" + str(spec['vector']) + ';'
    sql += "DO $$ DECLARE definition TEXT;BEGIN definition:=pg_get_functiondef('pg_temp.execution_advance(uuid,integer)'::REGPROCEDURE);"
    sql += "IF position('THEN ''32''::JSONB' IN definition)=0 OR position('THEN repeat(''7'',64)' IN definition)=0 THEN RAISE EXCEPTION USING ERRCODE='ZX870';END IF;"
    sql += "definition:=replace(definition,'THEN ''32''::JSONB','THEN ''" + str(prepared['byte_count']) + "''::JSONB');"
    sql += "definition:=replace(definition,'THEN repeat(''7'',64)','THEN ''" + prepared['sha256'] + "''');EXECUTE definition;END $$;"
    fixture.session.run('resource_bytes_bound_before_admission', sql)
