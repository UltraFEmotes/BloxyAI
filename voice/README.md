# AI Chat Bot v3 — voice output helper

The script sends completed AI replies to this local helper. The helper synthesizes speech using your selected provider and plays it into a virtual audio device. Roblox captures that device as your microphone. Keep the helper running while using voice output.

## macOS

1. Install [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole) and [Python 3.10 or newer](https://www.python.org/downloads/macos/).
2. Open `start-macos.command`. It creates a local `.venv` and installs the audio dependencies on first use. If needed, run `bash voice/start-macos.command` from the project folder in Terminal.
3. The terminal prints a helper URL and pairing key. In the script's **Voice Output** tab, enter those values and click **Check helper / Refresh output devices**.
4. Choose **Core Audio :: BlackHole 2ch** as **Speech output device**. In Roblox's audio settings, choose **BlackHole 2ch** as the microphone input and unmute VC. Keep Roblox's audio output on your headphones/speakers.
5. Choose your TTS provider, API key if needed, model and voice. Click **Test selected voice**, then enable **Speak public AI replies**.

An installed VB-CABLE device on macOS also works as a virtual route: select its playback device in the helper and the matching recording device in Roblox. The helper marks known virtual devices in the picker, but never automatically switches the system's default audio devices.

## Windows

1. Install [VB-CABLE](https://vb-audio.com/Cable/) and restart Windows. Install [Python 3.10 or newer](https://www.python.org/downloads/windows/) with its `py` launcher.
2. Open `start-windows.cmd`. It creates a local `.venv` and installs the audio dependencies on first use.
3. Paste the terminal's URL and pairing key into **Voice Output**, then check the helper.
4. Select a **CABLE Input** playback device as **Speech output device**. Select **CABLE Output** as Roblox's microphone input and unmute VC. Keep Roblox's audio output on your normal headphones/speakers.
5. Select a provider/model/voice, test it, then enable spoken replies.

Windows can expose the cable through several host APIs such as MME or WASAPI. Pick one that successfully plays the voice test. The device selection stores its name and host API, so changing an unrelated device index does not route audio to another speaker.

If you want to mix your real microphone with the AI voice, [Voicemeeter](https://vb-audio.com/Voicemeeter/) provides that routing. The script also supports selecting its virtual playback inputs.

## Speech providers

- **OpenAI:** Enter an OpenAI API key. **Fetch / Refresh TTS models and voices** filters the account's model list to dedicated TTS IDs. The current speech API documents `gpt-4o-mini-tts`, its `2025-12-15` snapshot, `tts-1` and `tts-1-hd`. Voice options change with the model; legacy models have fewer voices. [Speech API](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create), [voice compatibility](https://developers.openai.com/api/docs/guides/text-to-speech).
- **ElevenLabs:** Enter an ElevenLabs API key. Models must declare `can_do_text_to_speech=true`; voice-conversion-only models are excluded. The helper retrieves your available voices, following every voice-list page, and sends the selected voice ID to the speech API. Audio uses 24 kHz PCM. [Models](https://elevenlabs.io/docs/api-reference/models/list), [voices](https://elevenlabs.io/docs/api-reference/voices/search), [speech](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).
- **Custom (OpenAI-compatible):** Enter a server root, versioned base URL, or full `/audio/speech` URL. API keys are optional. Model and voice list paths can be overridden independently. Speech uses an OpenAI-style POST body with `model`, `voice`, `input` and `response_format`. The response must be binary uncompressed PCM WAV or 16-bit little-endian PCM. MP3-only or provider-specific JSON/SSML APIs need an OpenAI-compatible proxy.

Chat, vision and TTS connections are independent. Each TTS provider has its own key. Switching TTS providers disables automatic speech so you can configure and test the new route first.

Custom lists accept arrays or `data`/`models` and `voices` containers. TTS recognition uses explicit capability fields (`can_do_text_to_speech`, `supports_tts`, `capabilities.tts`, `capabilities.text_to_speech`), explicit TTS task labels, or recognizable dedicated TTS families. Audio-output capability alone is insufficient because it can describe an audio-chat model. Unknown IDs stay out of the dropdown. If your server omits useful metadata, enter its actual TTS model ID and voice ID manually and test them. A missing voice-list endpoint leaves the manual voice flow usable.

Default discovery tries `/v1/models` and `/v1/voices`, then the corresponding unversioned path only on HTTP 404/405. An endpoint already containing a prefix keeps that prefix. Overrides can be relative paths or full HTTP(S) URLs. Custom PCM output requires the correct sample rate; OpenAI PCM is fixed at 24 kHz. WAV carries its own rate. The helper converts audio to the selected output device's rate and channels.

## Playback behavior

Voice output starts disabled. Public speech follows accepted text replies, uses the same truncated message without the chat prefix, and strips emote/thinking tags. Private panel replies and local previews remain silent unless **Also speak private / local-preview replies** is explicitly enabled. A voice test is audible through the selected device but sends no game-chat message.

The first public speech for a script session includes “This is an AI-generated voice.” Later replies speak the reply text. [OpenAI's disclosure requirement](https://developers.openai.com/api/docs/guides/text-to-speech).

The helper queues speech in order and plays one clip at a time. It bounds queued jobs, deduplicates job IDs, expires old queued work and limits clips to 60 seconds. Stop, pause, chat/model invalidation, voice-setting changes and unload cancel queued/current speech for that script session. A provider request already in progress may finish remotely; its late audio is discarded after cancellation. Speech failures do not remove successful chat replies. Pending speech is polled so later synthesis/playback failures reach the panel automatically; **Refresh speech status** also shows the latest result.

The helper binds only to `127.0.0.1` and requires its pairing key. Provider keys and speech text are kept in memory and are not logged or saved by the helper. Script key persistence follows **Remember API keys on this device**. Without saved keys, a new script run starts voice disabled until you pair and configure it again. Restarting the helper generates a new pairing key unless `AICHATBOT_VOICE_TOKEN` is set in its environment.

Roblox must have voice chat available and use the virtual microphone for other players to hear the audio. A successful helper playback confirms local playback, not that Roblox or another player received it.

## Manual startup and diagnostics

Run these from the project folder if you prefer a terminal:

```sh
python3 -m venv voice/.venv
voice/.venv/bin/python -m pip install -r voice/requirements.txt
voice/.venv/bin/python voice/bridge.py
```

On Windows:

```bat
py -3 -m venv voice\.venv
voice\.venv\Scripts\python.exe -m pip install -r voice\requirements.txt
voice\.venv\Scripts\python.exe voice\bridge.py
```

Pass `--port 8766` if needed, then change **Voice helper URL** to match. Pass `--list-devices` to inspect output devices without starting the server. A missing device never falls back to an unrelated default speaker.

Run `python voice/test_bridge.py` to exercise provider adapters, catalog filtering, pagination, pairing, queue order, cancellation, errors and audio conversion. Install the requirements to include the WAV/PCM decoding and playback-conversion checks; no paid API calls are made. [Audio backend documentation](https://python-sounddevice.readthedocs.io/en/latest/api/streams.html).
