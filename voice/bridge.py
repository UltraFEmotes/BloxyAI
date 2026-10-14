#!/usr/bin/env python3
"""Local speech playback bridge for AI Chat Bot v3 (macOS / Windows)."""
from __future__ import annotations

import argparse
from collections import OrderedDict, deque
from dataclasses import dataclass
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
import re
import secrets
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import wave

SERVICE = "aichatbot-voice"
OPENAI_MODELS = {"tts-1", "tts-1-hd", "gpt-4o-mini-tts", "gpt-4o-mini-tts-2025-12-15"}
OPENAI_VOICES = ["alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse", "marin", "cedar"]
LEGACY_VOICES = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
MAX_AUDIO = 20 * 1024 * 1024


class VoiceError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def clean_string(value, limit=2048):
    if not isinstance(value, str):
        raise VoiceError("Expected a text value.")
    value = value.strip()
    if len(value) > limit or any(ord(char) < 32 for char in value):
        raise VoiceError("Setting is too long or contains control characters.")
    return value


def validate_url(value):
    value = clean_string(value)
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password or parsed.fragment or any(char.isspace() for char in value):
        raise VoiceError("Use an HTTP(S) URL without credentials or fragments.")
    try:
        parsed.port
    except ValueError as error:
        raise VoiceError("Invalid endpoint port.") from error
    return parsed


def endpoints(endpoint, models_path="", voices_path=""):
    parsed = validate_url(endpoint)
    path = parsed.path.rstrip("/")
    if path.endswith("/chat/completions"):
        raise VoiceError("Use your TTS server base URL or /audio/speech URL, not /chat/completions.")
    explicit_route = False
    for suffix in ("/audio/speech", "/models", "/voices"):
        if path.endswith(suffix):
            path = path[:-len(suffix)]
            explicit_route = True
            break
    path = path if path or explicit_route else "/v1"
    origin = urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, "", "", ""))
    base = origin + path
    query = "?" + parsed.query if parsed.query else ""

    def resolve(override, suffix):
        if override:
            override = clean_string(override)
            url = origin + override if override.startswith("/") else override if re.match(r"^https?://", override) else base + "/" + override
            validate_url(url)
            return [url]
        result = [base + suffix + query]
        if path.endswith("/v1"):
            result.append(origin + path[:-3] + suffix + query)
        return result

    return base + "/audio/speech" + query, resolve(models_path, "/models"), resolve(voices_path, "/voices")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def redact(message, key=""):
    message = str(message)
    if key:
        message = message.replace(key, "[redacted]")
    return re.sub(r"(?i)Bearer\s+[^\s\"']+", "Bearer [redacted]", message)[:400]


def fetch(url, key="", provider="custom", data=None, limit=MAX_AUDIO):
    validate_url(url)
    headers = {"Accept": "application/json" if data is None else "audio/wav,application/octet-stream", "User-Agent": "AIChatBot-Voice/1"}
    if key:
        headers["xi-api-key" if provider == "elevenlabs" else "Authorization"] = key if provider == "elevenlabs" else "Bearer " + key
    body = None
    if data is not None:
        headers["Content-Type"] = "application/json"
        body = json.dumps(data).encode()
    request = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
            mime = response.headers.get("Content-Type", "").lower()
            if data is not None and any(codec in mime for codec in ("mpeg", "mp3", "opus", "aac", "flac", "application/json", "image/", "text/")):
                raise VoiceError("Speech endpoint returned a compressed/JSON response. Configure WAV or 16-bit PCM audio.")
            result = response.read(limit + 1)
            if len(result) > limit:
                raise VoiceError("Provider response exceeds the audio/JSON size limit.")
            return result
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            payload = json.loads(error.read(8192))
            detail = payload.get("error", payload.get("detail", payload.get("message", "")))
            if isinstance(detail, dict):
                detail = detail.get("message", detail.get("detail", ""))
        except (ValueError, AttributeError):
            pass
        raise VoiceError(redact(f"TTS provider HTTP {error.code}: {detail or error.reason}", key), 502) from None
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise VoiceError(redact(f"TTS provider connection failed: {error}", key), 502) from None


def fetch_json(url, key="", provider="custom"):
    try:
        return json.loads(fetch(url, key, provider, limit=2 * 1024 * 1024))
    except (ValueError, UnicodeError):
        raise VoiceError("Provider returned invalid model/voice JSON.", 502) from None


def fetch_list(urls, key, provider):
    for index, url in enumerate(urls):
        try:
            return fetch_json(url, key, provider)
        except VoiceError as error:
            if index + 1 < len(urls) and re.search(r"HTTP (404|405):", str(error)):
                continue
            raise
    raise VoiceError("Catalog endpoint was not found.")


def rows(data, fields):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for field in fields:
            if isinstance(data.get(field), list):
                return data[field]
    raise VoiceError("Catalog must contain an array of models or voices.")


def tts_capable(entry, identifier):
    if isinstance(entry, dict):
        caps = entry.get("capabilities", {})
        flags = (entry.get("can_do_text_to_speech"), entry.get("supports_tts"), caps.get("text_to_speech") if isinstance(caps, dict) else None, caps.get("tts") if isinstance(caps, dict) else None)
        if any(flag is False for flag in flags):
            return False
        if any(flag is True for flag in flags):
            return True
        tasks = [entry.get("task"), entry.get("type"), entry.get("pipeline_tag")]
        for field in ("tasks", "supported_tasks", "capabilities"):
            if isinstance(entry.get(field), list):
                tasks.extend(entry[field])
        if any(isinstance(task, str) and task.lower().replace("_", "-") in ("tts", "text-to-speech") for task in tasks):
            return True
    # Names are used only for dedicated, recognizable TTS families. Audio chat/STT
    # models are deliberately excluded; audio output alone does not prove TTS.
    return bool(re.search(r"(?:^|/)(?:tts-1(?:-hd)?|gpt-4o-mini-tts(?:-\d{4}-\d{2}-\d{2})?|kokoro(?:[-:].*)?|piper(?:[-:].*)?|chatterbox(?:[-:].*)?|f5-tts(?:[-:].*)?|qwen3-tts(?:[-:].*)?|xtts(?:[-:].*)?|orpheus(?:[-:].*)?)$", identifier, re.I))


def parse_models(data):
    result = {}
    for entry in rows(data, ("data", "models")):
        identifier = entry if isinstance(entry, str) else entry.get("id", entry.get("model_id", entry.get("name", ""))) if isinstance(entry, dict) else ""
        if not isinstance(identifier, str) or not identifier.strip():
            continue
        identifier = clean_string(identifier, 256)
        if tts_capable(entry, identifier):
            name = entry.get("display_name", entry.get("name", identifier)) if isinstance(entry, dict) else identifier
            result[identifier] = {"id": identifier, "name": str(name or identifier)[:160]}
    return sorted(result.values(), key=lambda item: item["id"].lower())


def parse_voices(data):
    result = {}
    for entry in rows(data, ("voices", "data")):
        identifier = entry if isinstance(entry, str) else entry.get("voice_id", entry.get("id", entry.get("name", ""))) if isinstance(entry, dict) else ""
        if not isinstance(identifier, str) or not identifier.strip():
            continue
        identifier = clean_string(identifier, 256)
        name = entry.get("name", identifier) if isinstance(entry, dict) else identifier
        result[identifier] = {"id": identifier, "name": str(name or identifier)[:160]}
    return sorted(result.values(), key=lambda item: (item["name"].lower(), item["id"]))


@dataclass(frozen=True)
class Settings:
    provider: str
    endpoint: str
    key: str
    model: str
    voice: str
    models_path: str
    voices_path: str
    audio_format: str
    pcm_rate: int
    device: str
    volume: float

    @classmethod
    def read(cls, data, speech=False):
        if not isinstance(data, dict):
            raise VoiceError("Provide a settings object.")
        provider = clean_string(data.get("provider", "custom"), 20)
        if provider not in ("openai", "elevenlabs", "custom"):
            raise VoiceError("Unknown TTS provider.")
        key = clean_string(data.get("key", ""), 4096)
        if provider != "custom" and (not key or key.startswith("YOUR_")):
            raise VoiceError("Enter the selected TTS provider's API key.")
        endpoint = {"openai": "https://api.openai.com/v1", "elevenlabs": "https://api.elevenlabs.io"}.get(provider, clean_string(data.get("endpoint", "")))
        model, voice = clean_string(data.get("model", ""), 256), clean_string(data.get("voice", ""), 256)
        if speech and (not model or not voice):
            raise VoiceError("Select a TTS model and voice first.")
        if provider == "openai" and speech:
            if not tts_capable({}, model):
                raise VoiceError("Select a dedicated OpenAI TTS model.")
            voices = LEGACY_VOICES if model in ("tts-1", "tts-1-hd") else OPENAI_VOICES
            if voice not in voices:
                raise VoiceError("This voice is not supported by the selected OpenAI model.")
        audio_format = clean_string(data.get("audio_format", "wav"), 10)
        if audio_format not in ("wav", "pcm"):
            raise VoiceError("Choose WAV or PCM output.")
        try:
            rate, volume = int(data.get("pcm_rate", 24000)), float(data.get("volume", 0.8))
        except (TypeError, ValueError):
            raise VoiceError("Invalid sample rate or volume.") from None
        if rate not in (16000, 22050, 24000, 44100, 48000) or not 0 <= volume <= 1:
            raise VoiceError("Unsupported PCM rate or volume.")
        device = clean_string(data.get("device", ""))
        if speech and not device:
            raise VoiceError("Choose the helper's audio output device first.")
        models_path = clean_string(data.get("models_path", ""))
        voices_path = clean_string(data.get("voices_path", ""))
        if provider == "custom":
            endpoints(endpoint, models_path, voices_path)
        return cls(provider, endpoint, key, model, voice, models_path, voices_path, audio_format, rate, device, volume)


def catalog(settings):
    if settings.provider == "elevenlabs":
        models = parse_models(fetch_json(settings.endpoint + "/v1/models", settings.key, settings.provider))
        voices, seen, token = [], set(), None
        for _ in range(100):
            query = {"page_size": 100, "include_total_count": "false"}
            if token:
                query["next_page_token"] = token
            data = fetch_json(settings.endpoint + "/v2/voices?" + urllib.parse.urlencode(query), settings.key, settings.provider)
            voices.extend(parse_voices(data))
            if not data.get("has_more"):
                break
            token = data.get("next_page_token")
            if not isinstance(token, str) or not token or token in seen:
                raise VoiceError("Voice-list pagination returned an invalid/repeated token.")
            seen.add(token)
        else:
            raise VoiceError("Voice catalog exceeded the pagination limit.")
        voices = parse_voices(voices)
        note = "Only models declaring text-to-speech capability are listed."
    else:
        _, model_urls, voice_urls = endpoints(settings.endpoint, settings.models_path, settings.voices_path)
        models = parse_models(fetch_list(model_urls, settings.key, settings.provider))
        note = "Only TTS capability metadata or dedicated TTS model families are listed."
        if settings.provider == "openai":
            voices = [{"id": voice, "name": voice} for voice in (LEGACY_VOICES if settings.model in ("tts-1", "tts-1-hd") else OPENAI_VOICES)]
        else:
            try:
                voices = parse_voices(fetch_list(voice_urls, settings.key, settings.provider))
            except VoiceError as error:
                voices = []
                note += " Voices could not be listed: " + str(error) + " Enter a voice ID manually."
    if not models:
        note = "No identifiable TTS models were returned. Enter your TTS model ID manually and test it. " + note
    return {"models": models, "voices": voices, "note": note}


def synthesize(settings, text):
    if settings.provider == "elevenlabs":
        url = settings.endpoint + "/v1/text-to-speech/" + urllib.parse.quote(settings.voice, safe="") + "?output_format=pcm_24000"
        payload = {"text": text, "model_id": settings.model}
        return fetch(url, settings.key, settings.provider, payload), "pcm", 24000
    url, _, _ = endpoints(settings.endpoint, settings.models_path, settings.voices_path)
    payload = {"model": settings.model, "voice": settings.voice, "input": text, "response_format": settings.audio_format}
    # Speech APIs synthesize supplied text; chat reasoning parameters aren't part
    # of their schemas. Chat/vision still enforce the bot's thinking-off policy.
    return fetch(url, settings.key, settings.provider, payload), settings.audio_format, 24000 if settings.provider == "openai" else settings.pcm_rate


class AudioBackend:
    @staticmethod
    def modules():
        try:
            import numpy as np
            import sounddevice as sd
            return np, sd
        except (ImportError, OSError):
            raise VoiceError("Audio dependencies unavailable. Run the helper launcher to install requirements.", 503) from None

    def devices(self):
        _, sd = self.modules()
        try:
            apis, devices = sd.query_hostapis(), sd.query_devices()
        except Exception:
            raise VoiceError("Could not enumerate output devices. Check your audio driver.", 503) from None
        result = []
        for index, device in enumerate(devices):
            if device["max_output_channels"] < 1:
                continue
            api, name = apis[device["hostapi"]]["name"], device["name"]
            result.append({"id": api + " :: " + name, "name": name, "hostapi": api, "index": index,
                           "channels": device["max_output_channels"], "sample_rate": device["default_samplerate"],
                           "virtual": bool(re.search(r"blackhole|vb-cable|cable input|voicemeeter.*input", name, re.I))})
        return sorted(result, key=lambda row: (not row["virtual"], row["name"].lower(), row["hostapi"]))

    def resolve(self, identifier):
        matches = [device for device in self.devices() if device["id"] == identifier]
        if not matches:
            raise VoiceError("Selected output device is unavailable. Refresh devices and choose BlackHole or CABLE Input.", 503)
        device = matches[0]
        _, sd = self.modules()
        try:
            sd.check_output_settings(device=device["index"], samplerate=device["sample_rate"], channels=min(2, device["channels"]), dtype="float32")
        except Exception:
            raise VoiceError("Output device cannot play audio at its configured sample rate.", 503) from None
        return device

    def decode(self, data, audio_format, pcm_rate):
        np, _ = self.modules()
        if data.startswith(b"RIFF") and data[8:12] == b"WAVE":
            try:
                with wave.open(io.BytesIO(data), "rb") as wav:
                    rate, channels, width = wav.getframerate(), wav.getnchannels(), wav.getsampwidth()
                    if not 1 <= channels <= 8 or not 8000 <= rate <= 192000 or wav.getnframes() > rate * 60:
                        raise VoiceError("Speech WAV dimensions exceed the playback limits.")
                    raw = wav.readframes(wav.getnframes())
            except (wave.Error, EOFError):
                raise VoiceError("Speech endpoint returned an invalid/uncompressed PCM WAV file.") from None
        elif audio_format == "pcm" and not data.startswith((b"ID3", b"{", b"<")):
            rate, channels, width, raw = pcm_rate, 1, 2, data
        else:
            raise VoiceError("Speech endpoint did not return WAV or PCM audio. Configure WAV, or 16-bit little-endian PCM with its sample rate.")
        if not raw or len(raw) % (channels * width):
            raise VoiceError("Speech audio is empty or has incomplete samples.")
        if len(raw) // (channels * width) > rate * 60:
            raise VoiceError("Speech audio exceeds the 60-second playback limit.")
        if width == 1:
            samples = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128) / 128
        elif width == 2:
            samples = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768
        elif width == 3:
            packed = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
            integers = packed[:, 0] | packed[:, 1] << 8 | packed[:, 2] << 16
            integers = np.where(integers & 0x800000, integers - 0x1000000, integers)
            samples = integers.astype(np.float32) / 8388608
        elif width == 4:
            samples = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648
        else:
            raise VoiceError("Unsupported WAV sample width.")
        return samples.reshape(-1, channels).mean(axis=1), rate

    def play(self, data, audio_format, pcm_rate, settings, cancelled, on_playing):
        np, sd = self.modules()
        samples, rate = self.decode(data, audio_format, pcm_rate)
        if cancelled():
            return False
        device = self.resolve(settings.device)
        target_rate = int(device["sample_rate"])
        if rate != target_rate:
            frames = max(1, round(len(samples) * target_rate / rate))
            samples = np.interp(np.arange(frames) * rate / target_rate, np.arange(len(samples)), samples).astype(np.float32)
        samples = np.clip(samples * settings.volume, -1, 1).astype(np.float32)
        channels = min(2, device["channels"])
        samples = np.repeat(samples[:, None], channels, axis=1)
        try:
            with sd.OutputStream(device=device["index"], samplerate=target_rate, channels=channels, dtype="float32") as stream:
                on_playing()
                for index in range(0, len(samples), 1024):
                    if cancelled():
                        stream.abort()
                        return False
                    stream.write(samples[index:index + 1024])
            return not cancelled()
        except Exception as error:
            raise VoiceError("Audio playback failed. Refresh devices and check the virtual audio driver.", 503) from error


class Bridge:
    def __init__(self, audio=None, synthesizer=None, queue_limit=8, lifetime=45):
        self.audio = audio or AudioBackend()
        self.synthesizer = synthesizer or synthesize
        self.queue_limit, self.lifetime = queue_limit, lifetime
        self.lock = threading.Condition()
        self.pending, self.jobs, self.epochs = deque(), OrderedDict(), {}
        self.active = None
        self.disclosed = set()
        self.closed = False
        self.stats = {"played": 0, "errors": 0, "cancelled": 0, "last_error": ""}
        self.worker = threading.Thread(target=self.run, daemon=True, name="speech-playback")
        self.worker.start()

    def submit(self, payload):
        settings = Settings.read(payload.get("settings"), speech=True)
        text = payload.get("text")
        if not isinstance(text, str) or not text.strip() or len(text) > 4096:
            raise VoiceError("Speech text must contain 1–4096 characters.")
        session, identifier = clean_string(payload.get("session", ""), 128), clean_string(payload.get("id", ""), 180)
        epoch = payload.get("generation")
        if not session or not identifier or type(epoch) is not int or epoch < 0:
            raise VoiceError("Invalid speech session/job identity.")
        self.audio.resolve(settings.device)  # Reject missing devices before paid synthesis.
        key = session + ":" + identifier
        with self.lock:
            if self.closed:
                raise VoiceError("Speech helper is shutting down.", 503)
            if key in self.jobs:
                return {"id": identifier, "state": self.jobs[key]["state"], "duplicate": True}
            if epoch < self.epochs.get(session, 0):
                raise VoiceError("Speech request was cancelled before it arrived.", 409)
            if len(self.pending) >= self.queue_limit:
                raise VoiceError("Speech queue is full. Wait or stop speech.", 429)
            self.epochs[session] = max(epoch, self.epochs.get(session, 0))
            job = {"session": session, "id": identifier, "generation": epoch, "key": key, "settings": settings,
                   "text": text.strip(), "disclose": payload.get("disclose") is True, "created": time.monotonic()}
            self.jobs[key] = {"id": identifier, "session": session, "state": "queued"}
            self.pending.append(job)
            while len(self.jobs) > 256:
                oldest, record = next(iter(self.jobs.items()))
                if record["state"] in ("queued", "synthesizing", "playing"):
                    break
                self.jobs.pop(oldest)
            self.lock.notify_all()
            return {"id": identifier, "state": "queued", "duplicate": False}

    def cancelled(self, job):
        with self.lock:
            return self.closed or job["generation"] < self.epochs.get(job["session"], 0)

    def state(self, job, state):
        with self.lock:
            record = self.jobs[job["key"]]
            if state == "cancelled" and record["state"] != "cancelled":
                self.stats["cancelled"] += 1
            record["state"] = state

    def cancel(self, session, generation):
        session = clean_string(session, 128)
        if not session or type(generation) is not int or generation < 0:
            raise VoiceError("Invalid cancellation identity.")
        with self.lock:
            self.epochs[session] = max(generation, self.epochs.get(session, 0))
            remaining = deque()
            for job in self.pending:
                if job["session"] == session and job["generation"] < generation:
                    self.jobs[job["key"]]["state"] = "cancelled"
                    self.stats["cancelled"] += 1
                else:
                    remaining.append(job)
            self.pending = remaining
            self.lock.notify_all()
        return {"cancelled": True}

    def run(self):
        while True:
            with self.lock:
                self.lock.wait_for(lambda: self.closed or self.pending)
                if self.closed:
                    return
                job = self.pending.popleft()
                self.active = job["key"]
            try:
                if time.monotonic() - job["created"] > self.lifetime:
                    self.state(job, "expired")
                    continue
                if self.cancelled(job):
                    self.state(job, "cancelled")
                    continue
                self.state(job, "synthesizing")
                announcement = job["disclose"] and job["session"] not in self.disclosed
                prefix = "This is an AI-generated voice. " if announcement else ""
                text = prefix + job["text"][:4096 - len(prefix)]
                data, audio_format, rate = self.synthesizer(job["settings"], text)
                if self.cancelled(job):
                    self.state(job, "cancelled")
                    continue
                finished = self.audio.play(data, audio_format, rate, job["settings"], lambda: self.cancelled(job), lambda: self.state(job, "playing"))
                self.state(job, "done" if finished else "cancelled")
                with self.lock:
                    if finished:
                        self.stats["played"] += 1
                    if finished and announcement:
                        self.disclosed.add(job["session"])
            except Exception as error:
                if self.cancelled(job):
                    self.state(job, "cancelled")
                else:
                    self.state(job, "failed")
                    with self.lock:
                        self.stats["errors"] += 1
                        self.stats["last_error"] = redact(error, job["settings"].key) if isinstance(error, VoiceError) else "Unexpected speech helper failure. Check the audio driver and provider settings."
            finally:
                with self.lock:
                    self.active = None
                    self.lock.notify_all()

    def status(self, session=""):
        with self.lock:
            jobs = [dict(value) for value in self.jobs.values() if not session or value["session"] == session][-20:]
            return {"service": SERVICE, "version": 1, "platform": "macos" if sys.platform == "darwin" else "windows" if sys.platform == "win32" else sys.platform,
                    "queue": len(self.pending), "active": self.active is not None, "stats": dict(self.stats), "jobs": jobs}

    def close(self):
        with self.lock:
            self.closed = True
            self.pending.clear()
            self.lock.notify_all()


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, token, bridge):
        self.token, self.bridge = token, bridge
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    server: Server
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # Never log provider keys or spoken/private text.

    def reply(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def dispatch(self, method):
        self.connection.settimeout(10)
        if not hmac.compare_digest(self.headers.get("Authorization", "").encode("utf-8"), ("Bearer " + self.server.token).encode("utf-8")):
            self.close_connection = True
            self.reply(401, {"error": "Paste the helper's pairing key into Voice Output → Helper pairing key."})
            return
        if self.headers.get("Origin"):
            self.close_connection = True
            self.reply(403, {"error": "Browser-origin requests are not supported."})
            return
        try:
            if method == "POST":
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 32768:
                    raise VoiceError("Request body exceeds the allowed size.", 413)
                if not self.headers.get("Content-Type", "").startswith("application/json"):
                    raise VoiceError("Use an application/json body.", 415)
                payload = json.loads(self.rfile.read(size))
                if not isinstance(payload, dict):
                    raise VoiceError("Expected a JSON object.")
            else:
                payload = {}
            url = urllib.parse.urlsplit(self.path)
            if method == "GET" and url.path == "/v1/status":
                query = urllib.parse.parse_qs(url.query)
                self.reply(200, self.server.bridge.status(query.get("session", [""])[0]))
            elif method == "GET" and url.path == "/v1/devices":
                self.reply(200, {"devices": self.server.bridge.audio.devices()})
            elif method == "POST" and url.path == "/v1/catalog":
                self.reply(200, catalog(Settings.read(payload.get("settings"))))
            elif method == "POST" and url.path == "/v1/speak":
                self.reply(202, self.server.bridge.submit(payload))
            elif method == "POST" and url.path == "/v1/cancel":
                self.reply(200, self.server.bridge.cancel(payload.get("session", ""), payload.get("generation")))
            else:
                self.reply(404, {"error": "Unknown helper endpoint."})
        except VoiceError as error:
            self.reply(error.status, {"error": str(error)})
        except (ValueError, TypeError, UnicodeError):
            self.close_connection = True
            self.reply(400, {"error": "Invalid JSON request."})
        except Exception:
            self.close_connection = True
            self.reply(500, {"error": "Helper request failed. Check provider settings and audio dependencies."})

    def do_GET(self):
        self.dispatch("GET")

    def do_POST(self):
        self.dispatch("POST")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--list-devices", action="store_true")
    args = parser.parse_args()
    if args.list_devices:
        print(json.dumps(AudioBackend().devices(), indent=2))
        return
    if not 1 <= args.port <= 65535:
        parser.error("Port must be between 1 and 65535.")
    token = os.environ.get("AICHATBOT_VOICE_TOKEN") or secrets.token_urlsafe(32)
    bridge = Bridge()
    server = Server(("127.0.0.1", args.port), token, bridge)
    print(f"AI Chat Bot voice helper: http://127.0.0.1:{args.port}", flush=True)
    print(f"Pairing key: {token}", flush=True)
    print("Keep this window open. In Voice Output, paste the key, check the helper, then choose an output device.", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        bridge.close()
        server.server_close()


if __name__ == "__main__":
    main()
