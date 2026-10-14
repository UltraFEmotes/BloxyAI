"""Deterministic provider, HTTP, queue and audio tests; no paid API calls."""
import io
import json
from pathlib import Path
import struct
import sys
import threading
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
import wave

sys.path.insert(0, str(Path(__file__).parent))
import bridge


def settings(**changes):
    result = {"provider": "custom", "endpoint": "http://127.0.0.1:1234/v1", "model": "kokoro", "voice": "af_bella", "device": "Test :: Cable", "key": "private-key"}
    result.update(changes)
    return result


def payload(identifier="1", **changes):
    result = {"id": identifier, "session": "test-session", "generation": 0, "settings": settings(), "text": "Hello!"}
    result.update(changes)
    return result


def wav_bytes(width=2, rate=24000, channels=1):
    raw = b"\0" * (width * channels * rate // 20)
    with io.BytesIO() as output:
        with wave.open(output, "wb") as wav:
            wav.setnchannels(channels)
            wav.setsampwidth(width)
            wav.setframerate(rate)
            wav.writeframes(raw)
        return output.getvalue()


class Sink:
    def __init__(self):
        self.played = []
        self.gate = None

    def resolve(self, device):
        if device != "Test :: Cable":
            raise bridge.VoiceError("Device missing", 503)
        return {"index": 0}

    def devices(self):
        return [{"id": "Test :: Cable", "name": "Cable", "virtual": True}]

    def play(self, data, fmt, rate, settings, cancelled, on_playing):
        on_playing()
        if self.gate:
            while not self.gate.is_set():
                if cancelled():
                    return False
                time.sleep(0.002)
        if cancelled():
            return False
        self.played.append(data)
        return True


def wait_for(check, timeout=2):
    deadline = time.monotonic() + timeout
    while not check():
        if time.monotonic() > deadline:
            raise AssertionError("Timed out waiting for worker")
        time.sleep(0.002)


class CatalogTests(unittest.TestCase):
    def test_tts_filter_excludes_chat_stt_voice_conversion_and_audio_chat(self):
        data = {"data": [
            {"id": "gpt-4o-mini-tts"}, {"id": "tts-1-hd"}, {"id": "custom-speech", "capabilities": {"tts": True}},
            {"id": "speech-model", "task": "text-to-speech"}, {"id": "only-conversion", "can_do_voice_conversion": True},
            {"id": "whisper-1"}, {"id": "gpt-4o-audio-preview", "output_modalities": ["audio"]},
            {"id": "gemma4:e2b"}, {"id": "tts-1", "can_do_text_to_speech": False}, {"id": "gpt-4o-mini-tts"},
        ]}
        self.assertEqual([m["id"] for m in bridge.parse_models(data)], ["custom-speech", "gpt-4o-mini-tts", "speech-model", "tts-1-hd"])
        self.assertEqual(bridge.parse_models({"data": ["chat-model", "kokoro", "vendor/piper-en"]}), [{"id": "kokoro", "name": "kokoro"}, {"id": "vendor/piper-en", "name": "vendor/piper-en"}])

    def test_model_metadata_and_voice_shapes(self):
        self.assertEqual(bridge.parse_models([{"model_id": "eleven_v3", "name": "Eleven v3", "can_do_text_to_speech": True}])[0]["id"], "eleven_v3")
        voices = bridge.parse_voices({"voices": [{"voice_id": "v1", "name": "One"}, "v2", {"id": "v1", "name": "One"}]})
        self.assertEqual([v["id"] for v in voices], ["v1", "v2"])
        with self.assertRaises(bridge.VoiceError):
            bridge.parse_models({"data": {"not": "a list"}})

    def test_endpoint_resolution_and_overrides(self):
        speech, models, voices = bridge.endpoints("https://example.test/v1/audio/speech?tenant=x", "/catalog/models", "voice-list")
        self.assertEqual(speech, "https://example.test/v1/audio/speech?tenant=x")
        self.assertEqual(models, ["https://example.test/catalog/models"])
        self.assertEqual(voices, ["https://example.test/v1/voice-list"])
        self.assertEqual(bridge.endpoints("https://example.test/audio/speech")[0], "https://example.test/audio/speech")
        self.assertEqual(bridge.endpoints("http://localhost:1234")[1], ["http://localhost:1234/v1/models", "http://localhost:1234/models"])
        for value in ("https://user:key@example.test/v1", "file:///tmp/audio", "https://example.test/v1/chat/completions"):
            with self.assertRaises(bridge.VoiceError):
                bridge.endpoints(value)

    def test_elevenlabs_filters_models_and_fetches_every_voice_page(self):
        calls = []
        def request(url, *args):
            calls.append(url)
            if url.endswith("/v1/models"):
                return [{"model_id": "eleven_v3", "can_do_text_to_speech": True}, {"model_id": "conversion", "can_do_voice_conversion": True}]
            if "next_page_token" in url:
                return {"voices": [{"voice_id": "second", "name": "Second"}], "has_more": False}
            return {"voices": [{"voice_id": "first", "name": "First"}], "has_more": True, "next_page_token": "page 2"}
        with patch.object(bridge, "fetch_json", request):
            result = bridge.catalog(bridge.Settings.read(settings(provider="elevenlabs")))
        self.assertEqual([m["id"] for m in result["models"]], ["eleven_v3"])
        self.assertEqual([v["id"] for v in result["voices"]], ["first", "second"])
        self.assertEqual(len(calls), 3)
        self.assertIn("next_page_token=page+2", calls[-1])

    def test_missing_custom_voice_endpoint_preserves_manual_voice_flow(self):
        def request(urls, *args):
            if "models" in urls[0]:
                return {"data": [{"id": "kokoro"}, {"id": "chat"}]}
            raise bridge.VoiceError("No voices endpoint")
        with patch.object(bridge, "fetch_list", request):
            result = bridge.catalog(bridge.Settings.read(settings()))
        self.assertEqual([m["id"] for m in result["models"]], ["kokoro"])
        self.assertEqual(result["voices"], [])
        self.assertIn("manually", result["note"])

    def test_openai_voice_compatibility_and_payload(self):
        with self.assertRaises(bridge.VoiceError):
            bridge.Settings.read(settings(provider="openai", model="tts-1", voice="cedar"), speech=True)
        config = bridge.Settings.read(settings(provider="openai", model="gpt-4o-mini-tts", voice="cedar"), speech=True)
        with patch.object(bridge, "fetch", return_value=b"audio") as request:
            bridge.synthesize(config, "Hello")
        args = request.call_args.args
        self.assertEqual(args[0], "https://api.openai.com/v1/audio/speech")
        self.assertEqual(args[3], {"model": "gpt-4o-mini-tts", "voice": "cedar", "input": "Hello", "response_format": "wav"})
        self.assertNotIn("reasoning_effort", args[3])

    def test_elevenlabs_speech_uses_voice_id_and_raw_pcm(self):
        config = bridge.Settings.read(settings(provider="elevenlabs", model="eleven_v3", voice="voice/id"), speech=True)
        with patch.object(bridge, "fetch", return_value=b"audio") as request:
            data, fmt, rate = bridge.synthesize(config, "Hello")
        self.assertIn("voice%2Fid?output_format=pcm_24000", request.call_args.args[0])
        self.assertEqual(request.call_args.args[3], {"text": "Hello", "model_id": "eleven_v3"})
        self.assertEqual((fmt, rate), ("pcm", 24000))

    def test_error_credentials_redacted(self):
        self.assertNotIn("private-key", bridge.redact("provider rejected private-key Bearer extra-secret", "private-key"))
        self.assertNotIn("extra-secret", bridge.redact("provider rejected private-key Bearer extra-secret", "private-key"))


class QueueTests(unittest.TestCase):
    def setUp(self):
        self.sink, self.inputs = Sink(), []
        def synth(config, text):
            self.inputs.append(text)
            return text.encode(), "pcm", 24000
        self.bridge = bridge.Bridge(self.sink, synth)

    def tearDown(self):
        self.bridge.close()
        self.bridge.worker.join(timeout=2)

    def test_ordered_playback_and_duplicate_jobs(self):
        self.bridge.submit(payload("1", text="One"))
        self.bridge.submit(payload("2", text="Two"))
        duplicate = self.bridge.submit(payload("1", text="One"))
        wait_for(lambda: self.bridge.stats["played"] == 2)
        self.assertTrue(duplicate["duplicate"])
        self.assertEqual(self.sink.played, [b"One", b"Two"])

    def test_missing_device_rejected_before_paid_synthesis(self):
        with self.assertRaises(bridge.VoiceError):
            self.bridge.submit(payload(settings=settings(device="missing")))
        self.assertEqual(self.inputs, [])

    def test_cancel_active_and_queued_jobs_and_reject_late_requests(self):
        self.sink.gate = threading.Event()
        self.bridge.submit(payload("1"))
        wait_for(lambda: self.bridge.status()["jobs"][0]["state"] == "playing")
        self.bridge.submit(payload("2"))
        self.bridge.cancel("test-session", 1)
        wait_for(lambda: not self.bridge.status()["active"])
        self.assertEqual(self.sink.played, [])
        self.assertEqual([j["state"] for j in self.bridge.status()["jobs"]], ["cancelled", "cancelled"])
        with self.assertRaises(bridge.VoiceError) as error:
            self.bridge.submit(payload("late"))
        self.assertEqual(error.exception.status, 409)

    def test_cancel_during_synthesis_discards_late_audio(self):
        started, finish = threading.Event(), threading.Event()
        def synth(config, text):
            started.set(); finish.wait(timeout=2)
            return b"late", "pcm", 24000
        self.bridge.synthesizer = synth
        self.bridge.submit(payload())
        self.assertTrue(started.wait(timeout=2))
        self.bridge.cancel("test-session", 1); finish.set()
        wait_for(lambda: not self.bridge.status()["active"])
        self.assertEqual(self.sink.played, [])

    def test_bounded_queue_and_expired_jobs(self):
        self.sink.gate = threading.Event()
        self.bridge.queue_limit = 1; self.bridge.lifetime = 0.03
        self.bridge.submit(payload("1"))
        wait_for(lambda: self.bridge.status()["active"])
        self.bridge.submit(payload("2"))
        with self.assertRaises(bridge.VoiceError) as error:
            self.bridge.submit(payload("3"))
        self.assertEqual(error.exception.status, 429)
        time.sleep(0.04); self.sink.gate.set()
        wait_for(lambda: not self.bridge.status()["active"] and not self.bridge.pending)
        self.assertEqual(self.bridge.status()["jobs"][-1]["state"], "expired")

    def test_errors_are_reported_without_leaking_keys_or_text(self):
        self.bridge.synthesizer = lambda config, text: (_ for _ in ()).throw(bridge.VoiceError("Provider rejected private-key"))
        self.bridge.submit(payload())
        wait_for(lambda: self.bridge.stats["errors"] == 1)
        status = self.bridge.status()
        self.assertNotIn("private-key", json.dumps(status))
        self.assertNotIn("Hello!", json.dumps(status))
        self.assertEqual(status["jobs"][-1]["state"], "failed")

    def test_public_ai_voice_disclosure_once_and_private_test_stays_exact(self):
        self.bridge.submit(payload("1", disclose=False, text="Private test"))
        self.bridge.submit(payload("2", disclose=True, text="One"))
        self.bridge.submit(payload("3", disclose=True, text="Two"))
        wait_for(lambda: self.bridge.stats["played"] == 3)
        self.assertEqual(self.inputs, ["Private test", "This is an AI-generated voice. One", "Two"])


class HttpTests(unittest.TestCase):
    def setUp(self):
        self.sink = Sink()
        self.bridge = bridge.Bridge(self.sink, lambda config, text: (b"audio", "pcm", 24000))
        self.server = bridge.Server(("127.0.0.1", 0), "test-pair-key", self.bridge)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.bridge.close(); self.server.shutdown(); self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, route, data=None, key="test-pair-key", **headers):
        headers.update({"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        body = json.dumps(data).encode() if data is not None else None
        try:
            with urllib.request.urlopen(urllib.request.Request(self.url + route, data=body, headers=headers), timeout=2) as response:
                return response.status, json.load(response)
        except urllib.error.HTTPError as error:
            error.close()
            raise

    def test_pairing_authentication_device_list_and_service_identity(self):
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request("/v1/status", key="wrong")
        self.assertEqual(error.exception.code, 401)
        self.assertEqual(self.request("/v1/status")[1]["service"], bridge.SERVICE)
        self.assertEqual(self.request("/v1/devices")[1]["devices"][0]["id"], "Test :: Cable")

    def test_http_speech_enqueue_cancel_and_status(self):
        self.sink.gate = threading.Event()
        self.assertEqual(self.request("/v1/speak", payload())[0], 202)
        wait_for(lambda: self.bridge.status()["active"])
        self.assertTrue(self.request("/v1/cancel", {"session": "test-session", "generation": 1})[1]["cancelled"])
        wait_for(lambda: not self.bridge.status()["active"])
        self.assertEqual(self.request("/v1/status?session=test-session")[1]["jobs"][-1]["state"], "cancelled")

    def test_http_catalog_and_invalid_requests(self):
        with patch.object(bridge, "catalog", return_value={"models": [{"id": "kokoro"}], "voices": [{"id": "af_bella"}]}):
            self.assertEqual(self.request("/v1/catalog", {"settings": settings()})[1]["models"][0]["id"], "kokoro")
        for data in ([], {"settings": {}}, {"settings": settings(), "text": ""}):
            with self.assertRaises(urllib.error.HTTPError):
                self.request("/v1/speak", data)
        with self.assertRaises(urllib.error.HTTPError) as error:
            self.request("/v1/status", Origin="https://example.test")
        self.assertEqual(error.exception.code, 403)


class AudioTests(unittest.TestCase):
    def test_wav_widths_raw_pcm_and_invalid_audio(self):
        try:
            bridge.AudioBackend.modules()
        except bridge.VoiceError:
            self.skipTest("Install voice/requirements.txt to exercise audio decoding")
        backend = bridge.AudioBackend()
        for width in (1, 2, 3, 4):
            samples, rate = backend.decode(wav_bytes(width), "wav", 48000)
            self.assertEqual(rate, 24000)
            self.assertEqual(len(samples), 1200)
        samples, rate = backend.decode(struct.pack("<hhh", -32768, 0, 32767), "pcm", 24000)
        self.assertEqual(rate, 24000)
        self.assertEqual(samples[0], -1)
        for data, fmt in ((b"ID3fake mp3", "wav"), (b"{\"error\":true}", "pcm"), (b"\0", "pcm")):
            with self.assertRaises(bridge.VoiceError):
                backend.decode(data, fmt, 24000)

    def test_resampling_selected_device_stereo_and_cancellation(self):
        try:
            np, _ = bridge.AudioBackend.modules()
        except bridge.VoiceError:
            self.skipTest("Install voice/requirements.txt to exercise playback conversion")
        class Stream:
            blocks = []; instances = []; aborted = False
            def __init__(self, **kwargs): self.kwargs = kwargs; self.instances.append(self)
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def write(self, data): self.blocks.append(data.copy())
            def abort(self): self.aborted = True
        class Device:
            OutputStream = Stream
        backend = bridge.AudioBackend()
        with patch.object(backend, "modules", return_value=(np, Device)), patch.object(backend, "resolve", return_value={"index": 3, "sample_rate": 48000, "channels": 2}):
            self.assertTrue(backend.play(wav_bytes(), "wav", 24000, bridge.Settings.read(settings(), speech=True), lambda: False, lambda: None))
        self.assertEqual(sum(len(block) for block in Stream.blocks), 2400)
        self.assertTrue(all(block.shape[1] == 2 for block in Stream.blocks))
        Stream.blocks = []
        with patch.object(backend, "modules", return_value=(np, Device)), patch.object(backend, "resolve", return_value={"index": 3, "sample_rate": 48000, "channels": 2}):
            self.assertFalse(backend.play(wav_bytes(), "wav", 24000, bridge.Settings.read(settings(), speech=True), lambda: len(Stream.blocks) > 0, lambda: None))
        self.assertTrue(Stream.instances[-1].aborted)
        self.assertEqual(len(Stream.blocks), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
