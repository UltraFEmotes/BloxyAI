# AI Chat Bot v3

A single-file Roblox client chatbot with a setup wizard, provider adapters, personalities, nearby-player replies, and a control panel. The chatbot implementation remains in `main.lua`; optional voice output uses the local helper in `voice/`.

## Running

Run `main.lua` in the same client environment used for the original script. This is not a standalone Lua program or an ordinary Studio LocalScript: it relies on the existing environment's HTTP request function, `loadstring`, CoreGui access, and optionally `readfile` / `writefile`. The panel loads the stable [Rayfield Gen2](https://docs.sirius.menu/rayfield-gen2) library from `https://sirius.menu/gen2`. Native Gen2 controls, notification handles, dropdown refresh/selection, themes, and unload methods replace WindUI. Bot settings use the existing typed configuration; Rayfield does not save API keys or duplicate bot settings.

1. Choose a provider in the searchable tile grid. Filters include cloud, local, no-key and vision services.
2. Enter connection details. Required keys are masked, with a Show/Hide button. Custom keys are optional; LM Studio uses its server port. Choose whether to remember keys on this device.
3. Choose a model, search suggestions, or enter an exact ID. Custom and local servers fetch model lists here. Endpoints accept a server root, a `/v1` base URL, or a complete `/chat/completions` URL.
4. Select a personality and edit its prompt and identity.
5. In the optional **Voice Output** step, pair the local helper, choose an output device, and select a speech provider, TTS model and voice. Test playback and enable spoken replies, or press **Start bot · text only** to skip speech. Voice settings stay in the setup draft until launch; Back preserves them, and Close discards them and cancels test audio.
6. Use **Provider → Test Connection (private)** before enabling public conversation. This makes a real provider request using your account. **K** is Rayfield's default panel key; its Settings tab can rebind it.

The provider catalog retains the original integrations and model suggestions. It is not a verified list of currently available models or account entitlements. Enter a current model ID from your provider if a preset has been retired. Pollinations now uses its authenticated API; add a key in the Provider tab when migrating an existing configuration.

## Changes

- Rebuilt setup with a charcoal/mint palette, horizontal step navigation, searchable provider tiles, masked connection fields, ID-based model selection, an editable personality prompt, and an optional fifth Voice Output step. The layout adapts to narrow screens and scrolls on shorter displays. Provider buttons support pointer, touch, and gamepad activation. Changes stay in a draft until launch.
- Fixed false chat-delivery errors for `Enum.TextChatMessageStatus.Sending`. Pending sends are accepted without retries, while terminal failures still return errors and chat-filter tracking remains active.
- Fixed memory persistence, notification scope, Groq key storage, owner-command handling, model selection, personality clicks, literal search, local-model refresh, and setup transitions.
- Added a bounded queue shared by automatic replies, greetings, introductions, and private tests. Requests have a global cooldown, expiration, timeout, backoff, and rate-limit handling.
- Pausing, clearing memory, changing models, unloading, and re-executing invalidate pending replies. A transport already in progress may finish internally; its result is discarded after cancellation or timeout.
- Added isolated public/private conversation histories, configurable memory limits, and a persistence toggle. Public exports exclude private panel chats.
- Added diagnostics, pending-reply cancellation, direct model editing, custom endpoint controls, and truthful file-save results.
- Rebuilt the status billboard as a fixed-size charcoal badge with a persistent bot name, labeled activity, color-coded paused/error states, and staggered activity dots. It tracks generation, avatar inspection, sending and cooldowns, hides beyond 120 studs, and restores after respawn. Hidden/idle badges stop animation; cancellation clears activity immediately.
- Added UTF-8-safe truncation and local preview escaping. Local Preview is visible only to you; it does not send a whisper to another player.
- Removed per-frame setup selection polling. The wizard reflows to the viewport, retains selections when navigating back, ignores stale model-list responses, and disconnects listeners during cleanup.
- Added an Avatar Vision tab with opt-in main-model or separate custom-model routing, independent connection settings, model discovery, a private avatar test, and a two-minute description cache.
- Downloaded avatar images are validated and sent as inline base64, fixing servers that reject remote image URLs. API errors expose the provider's message with saved credentials redacted.
- Added `describe_avatar` function calling with a real model capability probe, automatic-caption fallback, and bounded tool exchanges.
- Added a guided Voice Output tab and a macOS/Windows speech helper, independent TTS providers/keys/models/voices, speech-only catalog filtering, virtual-device selection, voice tests, ordered playback, private-reply opt-in and cancellation.
- Only the local operator can issue control commands. Blacklist entries take precedence over whitelist entries. Private/team channels do not trigger public responses.

## Custom model discovery

In setup, select **Custom Proxy / Endpoint**, enter the endpoint and optional API key, and continue. The next step fetches the model list and includes a **Refresh models** button. You can search the results, select a model, or enter an ID manually if the endpoint does not provide a list.

The Provider tab also has **Fetch / Refresh Custom Models** and a **Discovered custom models** dropdown. Fetching a list does not change the active model. Selecting a result applies it when the active provider is Custom. Refresh preserves an existing selection when it is still available.

| Chat endpoint input | Default model-list request |
| --- | --- |
| `https://proxy.example` | `https://proxy.example/v1/models` |
| `https://proxy.example/v1` | `https://proxy.example/v1/models` |
| `https://proxy.example/v1/chat/completions` | `https://proxy.example/v1/models` |
| `https://proxy.example/api/v2` | `https://proxy.example/api/v2/models` |

For a missing `/v1/models` route (HTTP 404/405), discovery tries the corresponding `/models` route. Authentication failures and rate limits are reported without probing another route.

Set **Custom model-list URL / path (optional)** to override discovery. An absolute path such as `/api/tags` is resolved against the endpoint's origin. A full URL is used directly. The optional bearer key is included in discovery requests. Common OpenAI lists (`data`), Ollama lists (`models`), and plain arrays of model IDs are accepted. Duplicate IDs are removed and results are sorted.

Connection changes clear cached choices, and late responses from an old connection are discarded. Model-list overrides affect discovery only; chat continues using the normalized chat-completions endpoint.

## Separate avatar vision

Open **Avatar Vision** in the panel:

1. Enter your **Vision endpoint / base URL**, optional **Vision API key**, and an image-capable **Vision model ID**. These are independent of the chat provider's settings.
2. Optionally use **Fetch / Refresh Vision Models** and choose a result. A **Vision model-list URL / path** override works like custom chat model discovery. Lists can include text-only models, so discovery does not establish that a model accepts images.
3. Use **Test custom vision on my avatar** to check the configuration privately. The test displays the description in a notification without sending a game-chat message or modifying conversation history.
4. Turn on **Enable avatar vision** and **Use separate custom vision provider**.

With both toggles on, the flow is:

```text
Roblox avatar headshot → custom vision model → short appearance description → selected chat model → reply
```

The vision model receives the static headshot and a description prompt, not your conversation history. The main chat model receives the description as text alongside the current message. This lets a text-only chat model use avatar context. The main provider, model, endpoint, and API key are not changed.

With **Use separate custom vision provider** off, the existing direct image route remains available for Pollinations and Gemini: the selected chat model receives the headshot and must support images. With **Enable avatar vision** off, automatic replies make no avatar-image or vision-model requests.

Avatar headshots are downloaded and sent as `data:image/...;base64,...` rather than remote image URLs. PNG, JPEG and WebP signatures are accepted, with a 4 MB download limit.

Custom descriptions are cached in memory for up to two minutes per player and thumbnail. A different thumbnail, model, endpoint, or key causes a new description request. **Clear cached avatar descriptions** requests a fresh description next time. Cache entries are removed when a player leaves, and the cache is cleared on unload. Descriptions are not saved separately to disk; vision keys follow **Remember API keys on this device**.

Both vision and chat requests apply the fixed thinking-off policy. A failed vision request stops that reply and reports the error instead of sending the avatar to another provider. Cancelled requests cannot cache late descriptions or produce a stale chat reply. Diagnostics shows vision-request and cache-hit counts.

## Avatar vision as a tool

With **Enable avatar vision**, **Use separate custom vision provider**, and **Let the chat model call avatar vision** on, the chat model can request `describe_avatar(user_id)` when appearance matters. Ordinary conversation can finish without downloading an avatar. The tool routes images to your separate vision model and returns its description to the chat model as a tool result.

The script probes the chat model with a real function-call request and caches the result for ten minutes per connection/model. **Check chat model tool support** forces a fresh check. Model-list metadata alone does not prove tool support. A valid avatar call confirms support; an unsupported-tools error or a text-only probe response falls back to automatic descriptions. Other errors are reported rather than silently changing the thinking policy.

Only current-game players can be inspected. Unknown tools, malformed arguments, missing players, vision errors, and reported reasoning abort the reply. Tool conversations allow at most three calls and then require a final text response. Intermediate tool messages are not saved in conversation history. Pausing, changing settings, or unloading prevents cancelled work from continuing to a new vision request or final reply. Diagnostics includes tool-call counts.

Live checks against the supplied no-key gateway with `gemma4:e2b` accepted plain chat, base64 avatar vision, an avatar function call, and a tool-result follow-up. The URL and model are not hardcoded into the bot.

## Voice output through VC

Use the fifth **Voice Output** step in initial provider setup, or open **Voice Output** in the panel after launch. Both use the same controls for macOS/BlackHole and Windows/VB-CABLE setup instructions, helper pairing, output-device selection, OpenAI/ElevenLabs/custom provider choices, TTS-only model discovery, voice selection, a voice test and automatic speech. Speech is optional and can be configured later.

Download and extract the [voice helper ZIP](https://github.com/UltraFEmotes/BloxyAI/raw/refs/heads/main/voice-helper.zip), or use the `voice/` folder in a checkout of this repository.

Start `voice/start-macos.command` or `voice/start-windows.cmd`, paste its pairing key, and use **Check helper / Refresh output devices**. Choose the virtual playback device in the script and its recording/input device in Roblox. Then select your speech provider/model/voice, test it, and enable **Speak public AI replies**.

The helper must stay open. Public speech matches the accepted chat text without its prefix. Private and local-preview replies stay silent by default. Speech uses its own API credentials and queue; a speech failure leaves the text reply intact. Chat and vision thinking-off controls remain in force; speech requests use the dedicated speech endpoint's schema.

See [voice/README.md](voice/README.md) for full installation, custom API requirements, voice compatibility, cancellation behavior, and troubleshooting. No documented Roblox API injects audio into the VC microphone directly; this feature plays through the selected OS virtual audio device.

## Model thinking

Every chat and vision generation request explicitly forces thinking off, including ordinary models, unknown model aliases, local servers, and custom endpoints. OpenRouter uses `reasoning: {enabled: false, effort: "none", exclude: true}`; Together uses `reasoning: {enabled: false}`; all other adapters send `reasoning_effort: "none"`. Model-name checks no longer prevent attempts to request off.

Caller-supplied thinking controls are overwritten before requests are encoded. The bot never retries with low, default, or enabled reasoning. If a provider rejects the off setting, the request fails and you receive an error. This strict policy may cause providers that do not accept these parameters to reject a request, including some otherwise non-thinking models.

Responses reporting reasoning tokens, nonempty reasoning fields, or thinking content are discarded even if they also contain a final answer. Empty thinking delimiters and zero reasoning tokens are accepted. Discarded responses do not enter chat or conversation memory.

A client cannot change a remote model's implementation or detect internal reasoning that a server conceals. The script forces the off request and rejects evidence that it was ignored; it cannot guarantee that every remote server honors it. The **brief pause before replying** setting controls a cosmetic delay only. Status text now says **Generating** to avoid confusing that delay with model reasoning.

## Commands

Where the game's chat forwards local slash commands:

| Command | Action |
| --- | --- |
| `/ai on` | Enable automatic replies |
| `/ai off` | Pause and cancel pending replies |
| `/ai clear` | Clear both histories and cancel pending replies |
| `/ai model MODEL_ID` | Change model and clear conversation context |
| `/ai status` | Display current configuration and queue statistics |

The panel provides equivalent controls if the game consumes slash commands.

## Storage

Configuration uses `aichatbot_cfg_v3.json`; memory uses `aichatbot_memory_v3.json` in the environment's file workspace. Existing v2 configuration and flat history files are accepted and validated. Legacy memory cannot distinguish old private conversations from public ones; clear memory once if you previously used the old private panel for sensitive discussions.

New installations keep API keys in memory unless **Remember API keys on this device** is enabled. Enabling it stores keys as plain text in the configuration file. Existing configurations retain their previous key-saving behavior during migration. Disabling it rewrites the configuration without keys. Disabling conversation persistence clears the on-disk memory on a successful save while retaining the current conversation in memory.

Use **Diagnostics → Save Settings Now** to check whether file writing is available. Unloading preserves settings and saved history. **Reset Setup for Next Run** unloads the bot; execute `main.lua` again to reopen setup.

## Verification

Run:

```sh
python3 tests/run.py
```

Requires `luau` and `luau-compile` on PATH. Tests compile the complete production script, exercise the actual core against deterministic transport/chat/storage mocks, and run the full wizard and panel against simulated GUI objects. They make no network calls and send no Roblox messages.

Coverage includes UTF-8, malformed configuration/memory, key persistence, queue limits, public/private isolation, rate limits, timeouts, retry recovery, cancellation, unload, local commands, file errors, literal searches, filtered model selection, personality selection, panel launch, custom model discovery, authentication, route fallback, refresh selection, stale responses, independent vision routing, image payloads, caption caching, vision failures, and cancellation.

The current suite passes 70 core regressions plus the full setup/panel smoke checks, including native Gen2 property/method contracts, compact layouts, masked-key behavior, keyless setup, tool exchanges, fallback, cancellation, image encoding, credential redaction, billboard identity/activity/respawn/unload lifecycle, and speech routing/privacy/error/cancellation/key persistence. Voice Output UI checks cover setup, pairing, devices, filtered catalogs, model/voice choice, compatibility and stale responses. Mocked GUI renders were inspected for the provider, connection, model and personality pages. The added voice setup page is covered by simulated UI checks for draft isolation, pairing, masked keys, device and catalog selection, testing, launch, back navigation, compact layout, stale responses and cancellation. These checks do not establish in-game visual correctness or executor compatibility; live checks cover only the supplied gateway/model. The helper has 20 additional tests (`python voice/test_bridge.py`; install its requirements for audio conversion checks). A real local helper/provider HTTP fixture and an installed macOS virtual output device were validated, without playing a test tone into an active Roblox session. Paid TTS providers and end-to-end VC transmission still require your provider key and an in-game voice test. For in-game verification, complete setup, use a private connection test, check the panel at your display size, then test one public reply, pause during a request, respawn, and unload/re-execute.

Provider/reference documentation used for this update:

- [Rayfield Gen2](https://docs.sirius.menu/rayfield-gen2)
- [Roblox BillboardGui](https://create.roblox.com/docs/reference/engine/classes/BillboardGui)
- [Roblox TextChannel](https://create.roblox.com/docs/reference/engine/classes/TextChannel)
- [Pollinations API](https://gen.pollinations.ai/docs)
- [Hugging Face Inference Providers](https://huggingface.co/docs/inference-providers/en/index)
- [OpenRouter reasoning controls](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
- [Groq reasoning controls](https://console.groq.com/docs/api-reference)
- [Gemini OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai)
- [Cerebras reasoning controls](https://inference-docs.cerebras.ai/capabilities/reasoning)
- [Together reasoning controls](https://docs.together.ai/docs/inference/chat/reasoning)
