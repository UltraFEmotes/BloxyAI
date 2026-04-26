local VERSION = "2.0"
local BOT_OWNER = "manoli2009"

-- Cleanup previous instances
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("AIBotSetup")
    if old then old:Destroy() end
end)
pcall(function()
    local old = game:GetService("CoreGui"):FindFirstChild("AIBotBillboard")
    if old then old:Destroy() end
end)

local Players      = game:GetService("Players")
local TCS          = game:GetService("TextChatService")
local HttpService  = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService   = game:GetService("RunService")
local CoreGui      = game:GetService("CoreGui")
local UIS          = game:GetService("UserInputService")

local LP = Players.LocalPlayer

-- Custom asset loader with online fallback icons
local ICON_CACHE = {}
local function GetIcon(path, fallbackUrl)
    if ICON_CACHE[path] then return ICON_CACHE[path] end
    if getcustomasset then
        local ok, r = pcall(getcustomasset, path)
        if ok and r then ICON_CACHE[path] = r return r end
    end
    return fallbackUrl or ""
end

-- Download and cache provider logos via getcustomasset
local LOGO_CACHE = {}
local function DownloadLogo(providerId, url)
    if not url or url == "" then return "" end
    if LOGO_CACHE[providerId] then return LOGO_CACHE[providerId] end
    local path = "aichatbot_logo_"..providerId..".png"
    -- Try getcustomasset first (already downloaded)
    if getcustomasset then
        local ok, r = pcall(getcustomasset, path)
        if ok and r then LOGO_CACHE[providerId] = r return r end
    end
    -- Download the logo
    local fn = request or (syn and syn.request) or http_request or (http and http.request)
    if not fn then return "" end
    local ok, res = pcall(fn, { Url = url, Method = "GET" })
    if not ok or not res or res.StatusCode ~= 200 then return "" end
    -- Save and load
    if writefile and getcustomasset then
        local wok = pcall(writefile, path, res.Body)
        if wok then
            local lok, asset = pcall(getcustomasset, path)
            if lok and asset then LOGO_CACHE[providerId] = asset return asset end
        end
    end
    return ""
end

-- Emoji icons (reliable across all executors, no broken rbxassetid)
local ICONS = {
    brain    = "🧠",
    sparkle  = "✨",
    bot      = "🤖",
    gear     = "⚙️",
    chat     = "💬",
    check    = "✅",
    star     = "⭐",
    eye      = "👁",
    lock     = "🔒",
    zap      = "⚡",
    palette  = "🎨",
}

local PROVIDERS = {
    {
        id = "pollinations", name = "Pollinations",
        noKey = true, vision = true,
        limit = "1 req / 15 sec", signup = "No account needed",
        color = Color3.fromRGB(80, 200, 120),
        logo = "https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/openai.svg",
        logoPng = "https://img.icons8.com/color/96/organic-food.png",
        defaultModel = "openai",
        models = {
            { id = "openai", label = "OpenAI (default, vision)" },
        },
    },
    {
        id = "unclose", name = "UncloseAI",
        noKey = true, vision = false,
        limit = "No stated limit", signup = "No account needed",
        color = Color3.fromRGB(100, 160, 255),
        logoPng = "https://img.icons8.com/fluency/96/artificial-intelligence.png",
        defaultModel = "auto",
        models = {
            { id = "adamo1139/Hermes-3-Llama-3.1-8B-FP8-Dynamic", label = "Hermes 3 Llama 3.1 8B" },
        },
    },
    {
        id = "groq", name = "Groq",
        noKey = false, vision = false,
        limit = "30 RPM free tier", signup = "console.groq.com",
        color = Color3.fromRGB(244, 114, 55),
        logoPng = "https://img.icons8.com/color/96/speed.png",
        defaultModel = "llama-3.3-70b-versatile",
        models = {
            { id = "llama-3.3-70b-versatile", label = "Llama 3.3 70B (recommended)" },
            { id = "llama-3.1-8b-instant",    label = "Llama 3.1 8B (fastest)" },
            { id = "mixtral-8x7b-32768",      label = "Mixtral 8x7B" },
            { id = "gemma2-9b-it",            label = "Gemma 2 9B" },
        },
    },
    {
        id = "gemini", name = "Google AI Studio",
        noKey = false, vision = true,
        limit = "1500 req/day (2.0 Flash)", signup = "aistudio.google.com",
        color = Color3.fromRGB(66, 133, 244),
        logoPng = "https://img.icons8.com/color/96/google-gemini.png",
        defaultModel = "gemini-2.0-flash",
        models = {
            { id = "gemini-2.0-flash", label = "Gemini 2.0 Flash (recommended)" },
            { id = "gemini-2.5-flash", label = "Gemini 2.5 Flash (500/day)" },
        },
    },
    {
        id = "cerebras", name = "Cerebras",
        noKey = false, vision = false,
        limit = "~2000 tok/sec (very fast)", signup = "cloud.cerebras.ai",
        color = Color3.fromRGB(255, 140, 60),
        logoPng = "https://img.icons8.com/color/96/brain.png",
        defaultModel = "llama-3.3-70b",
        models = {
            { id = "llama-3.3-70b", label = "Llama 3.3 70B (recommended)" },
            { id = "llama-3.1-8b",  label = "Llama 3.1 8B (fastest)" },
            { id = "qwen-3-32b",    label = "Qwen 3 32B" },
        },
    },
    {
        id = "sambanova", name = "SambaNova",
        noKey = false, vision = false,
        limit = "Free tier available", signup = "cloud.sambanova.ai",
        color = Color3.fromRGB(255, 90, 50),
        logoPng = "https://img.icons8.com/color/96/processor.png",
        defaultModel = "Meta-Llama-3.3-70B-Instruct",
        models = {
            { id = "Meta-Llama-3.3-70B-Instruct", label = "Llama 3.3 70B (recommended)" },
            { id = "Meta-Llama-3.1-8B-Instruct",  label = "Llama 3.1 8B (fastest)" },
            { id = "DeepSeek-R1-Distill-Llama-70B", label = "DeepSeek R1 70B" },
        },
    },
    {
        id = "together", name = "Together AI",
        noKey = false, vision = false,
        limit = "$1 free credit", signup = "api.together.xyz",
        color = Color3.fromRGB(20, 184, 166),
        logoPng = "https://img.icons8.com/color/96/group.png",
        defaultModel = "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        models = {
            { id = "meta-llama/Llama-3.3-70B-Instruct-Turbo", label = "Llama 3.3 70B Turbo (rec.)" },
            { id = "meta-llama/Llama-3.1-8B-Instruct-Turbo",  label = "Llama 3.1 8B Turbo (fast)" },
            { id = "Qwen/Qwen2.5-72B-Instruct-Turbo",         label = "Qwen 2.5 72B Turbo" },
        },
    },
    {
        id = "huggingface", name = "HuggingFace",
        noKey = false, vision = false,
        limit = "Rate limited free tier", signup = "huggingface.co/settings/tokens",
        color = Color3.fromRGB(255, 213, 79),
        logoPng = "https://img.icons8.com/emoji/96/hugging-face.png",
        defaultModel = "meta-llama/Llama-3.3-70B-Instruct",
        models = {
            { id = "meta-llama/Llama-3.3-70B-Instruct",      label = "Llama 3.3 70B (recommended)" },
            { id = "mistralai/Mistral-7B-Instruct-v0.3",      label = "Mistral 7B v0.3" },
            { id = "microsoft/Phi-3-mini-4k-instruct",        label = "Phi-3 Mini 4K" },
        },
    },
    {
        id = "deepinfra", name = "DeepInfra",
        noKey = false, vision = false,
        limit = "Free tier available", signup = "deepinfra.com/dash/api_keys",
        color = Color3.fromRGB(138, 92, 246),
        logoPng = "https://img.icons8.com/color/96/geodata.png",
        defaultModel = "meta-llama/Llama-3.3-70B-Instruct",
        models = {
            { id = "meta-llama/Llama-3.3-70B-Instruct",   label = "Llama 3.3 70B (recommended)" },
            { id = "meta-llama/Llama-3.1-8B-Instruct",    label = "Llama 3.1 8B (fastest)" },
            { id = "mistralai/Mixtral-8x7B-Instruct-v0.1", label = "Mixtral 8x7B" },
        },
    },
    {
        id = "openrouter", name = "OpenRouter",
        noKey = false, vision = false,
        limit = "200 req/day free", signup = "openrouter.ai",
        color = Color3.fromRGB(180, 100, 255),
        logoPng = "https://img.icons8.com/color/96/router.png",
        defaultModel = "openrouter/healer-alpha",
        models = {
            { id = "openrouter/healer-alpha",                    label = "Healer Alpha (recommended)" },
            { id = "meta-llama/llama-3.3-70b-instruct:free",     label = "Llama 3.3 70B" },
            { id = "meta-llama/llama-4-maverick:free",           label = "Llama 4 Maverick" },
            { id = "google/gemini-2.0-flash-exp:free",           label = "Gemini 2.0 Flash" },
            { id = "qwen/qwen3-32b:free",                        label = "Qwen3 32B" },
            { id = "nvidia/llama-3.1-nemotron-70b-instruct:free", label = "Nemotron 70B" },
        },
    },
    {
        id = "cohere", name = "Cohere",
        noKey = false, vision = false,
        limit = "Free until production", signup = "dashboard.cohere.com",
        color = Color3.fromRGB(255, 80, 100),
        logoPng = "https://img.icons8.com/color/96/chat.png",
        defaultModel = "command-r-plus",
        models = {
            { id = "command-r-plus",      label = "Command R+ (recommended)" },
            { id = "command-r",           label = "Command R" },
            { id = "command-r7b-12-2024", label = "Command R7B (fastest)" },
        },
    },
    {
        id = "mistral", name = "Mistral",
        noKey = false, vision = false,
        limit = "Free Experiment tier", signup = "console.mistral.ai",
        color = Color3.fromRGB(255, 165, 0),
        logoPng = "https://img.icons8.com/color/96/wind.png",
        defaultModel = "mistral-small-latest",
        models = {
            { id = "mistral-small-latest", label = "Mistral Small (recommended)" },
            { id = "open-mistral-7b",      label = "Mistral 7B (fastest)" },
            { id = "mistral-large-latest", label = "Mistral Large (best)" },
        },
    },
    {
        id = "electronhub", name = "ElectronHub",
        noKey = false, vision = false,
        limit = "5 RPM free tier", signup = "playground.electronhub.ai",
        color = Color3.fromRGB(60, 220, 220),
        logoPng = "https://img.icons8.com/color/96/electronics.png",
        defaultModel = "gpt-4o-mini",
        models = {
            { id = "gpt-4o-mini",               label = "GPT-4o Mini (recommended)" },
            { id = "gpt-4o",                    label = "GPT-4o" },
            { id = "claude-3-5-haiku-20241022", label = "Claude 3.5 Haiku" },
        },
    },
    {
        id = "zanity", name = "Zanity",
        noKey = false, vision = false,
        limit = "Rate limit varies", signup = "zanity.xyz",
        color = Color3.fromRGB(100, 200, 150),
        logoPng = "https://img.icons8.com/color/96/z.png",
        defaultModel = "gemini-2.0-flash",
        models = {
            { id = "gemini-2.0-flash",   label = "Gemini 2.0 Flash (recommended)" },
            { id = "grok-fun",           label = "Grok Fun" },
            { id = "deepseek-v3.1",      label = "DeepSeek v3.1" },
            { id = "gpt-4o:free",        label = "GPT-4o Free" },
            { id = "llama-4-maverick",   label = "Llama 4 Maverick" },
            { id = "zanity-rp-large",    label = "Zanity RP Large" },
        },
    },
    {
        id = "github", name = "GitHub Models",
        noKey = false, vision = true,
        limit = "Free tier for developers", signup = "github.com/marketplace/models",
        color = Color3.fromRGB(36, 41, 46),
        logoPng = "https://img.icons8.com/ios-filled/96/github.png",
        defaultModel = "gpt-4o",
        models = {
            { id = "gpt-4o",                         label = "GPT-4o (recommended, vision)" },
            { id = "gpt-4o-mini",                    label = "GPT-4o Mini (fastest)" },
            { id = "AI21-Jamba-1.5-Large",           label = "Jamba 1.5 Large" },
            { id = "Cohere-command-r-plus",          label = "Command R+" },
            { id = "Meta-Llama-3.1-405B-Instruct",   label = "Llama 3.1 405B" },
            { id = "o1-mini",                        label = "o1 Mini" },
        },
    },
    {
        id = "nvidia", name = "NVIDIA NIM",
        noKey = false, vision = true,
        limit = "1000 free credits", signup = "build.nvidia.com",
        color = Color3.fromRGB(118, 185, 0),
        logoPng = "https://img.icons8.com/color/96/nvidia.png",
        defaultModel = "nvidia/llama-3.1-nemotron-70b-instruct",
        models = {
            { id = "nvidia/llama-3.1-nemotron-70b-instruct",  label = "Nemotron 70B (recommended)" },
            { id = "meta/llama-3.2-90b-vision-instruct",      label = "Llama 3.2 90B Vision" },
            { id = "meta/llama-3.1-405b-instruct",            label = "Llama 3.1 405B" },
            { id = "qwen/qwen2.5-72b-instruct",               label = "Qwen 2.5 72B" },
        },
    },
    {
        id = "glhf", name = "Glhf.chat",
        noKey = false, vision = false,
        limit = "Completely free tier", signup = "glhf.chat",
        color = Color3.fromRGB(255, 105, 180),
        logoPng = "https://img.icons8.com/color/96/chat-message.png",
        defaultModel = "hf:meta-llama/Meta-Llama-3.1-405B-Instruct",
        models = {
            { id = "hf:meta-llama/Meta-Llama-3.1-405B-Instruct", label = "Llama 3.1 405B (recommended)" },
            { id = "hf:meta-llama/Llama-3.3-70B-Instruct",       label = "Llama 3.3 70B" },
            { id = "hf:Qwen/Qwen2.5-72B-Instruct",               label = "Qwen 2.5 72B" },
            { id = "hf:nvidia/Llama-3.1-Nemotron-70B-Instruct-HF", label = "Nemotron 70B" },
        },
    },
    {
        id = "hyperbolic", name = "Hyperbolic",
        noKey = false, vision = false,
        limit = "Free tier for OSS models", signup = "app.hyperbolic.xyz",
        color = Color3.fromRGB(59, 130, 246),
        logoPng = "https://img.icons8.com/color/96/server.png",
        defaultModel = "meta-llama/Meta-Llama-3.1-405B-Instruct",
        models = {
            { id = "meta-llama/Meta-Llama-3.1-405B-Instruct", label = "Llama 3.1 405B (recommended)" },
            { id = "Qwen/Qwen2.5-72B-Instruct",               label = "Qwen 2.5 72B (fastest)" },
            { id = "DeepSeek-R1",                             label = "DeepSeek R1" },
        },
    },
    {
        id = "novita", name = "Novita AI",
        noKey = false, vision = true,
        limit = "$0.5 free credits (~1m tokens)", signup = "novita.ai/dashboard/key",
        color = Color3.fromRGB(147, 51, 234),
        logoPng = "https://img.icons8.com/color/96/api-settings.png",
        defaultModel = "meta-llama/llama-3.2-11b-vision-instruct",
        models = {
            { id = "meta-llama/llama-3.2-11b-vision-instruct", label = "Llama 3.2 11B Vision (recommended)" },
            { id = "meta-llama/llama-3.1-70b-instruct",        label = "Llama 3.1 70B" },
            { id = "Qwen/Qwen2.5-72B-Instruct",                label = "Qwen 2.5 72B" },
        },
    },
    {
        id = "ai21", name = "AI21 Labs",
        noKey = false, vision = false,
        limit = "Free tier available", signup = "studio.ai21.com",
        color = Color3.fromRGB(249, 115, 22),
        logoPng = "https://img.icons8.com/color/96/neural-network.png",
        defaultModel = "jamba-1.5-large",
        models = {
            { id = "jamba-1.5-large", label = "Jamba 1.5 Large (recommended)" },
            { id = "jamba-1.5-mini",  label = "Jamba 1.5 Mini (fastest)" },
        },
    },
    {
        id = "zen", name = "OpenCode Zen",
        noKey = false, vision = false,
        limit = "Free tier (3 models)", signup = "opencode.ai/auth",
        color = Color3.fromRGB(200, 150, 255),
        logoPng = "https://img.icons8.com/color/96/meditation-guru.png",
        defaultModel = "minimax-m2.5-free",
        models = {
            { id = "minimax-m2.5-free",          label = "MiniMax M2.5 Free (rec.)" },
            { id = "mimo-v2-flash-free",         label = "MiMo V2 Flash Free" },
            { id = "trinity-large-preview-free", label = "Trinity Large Preview" },
        },
    },
    {
        id = "lmstudio", name = "LM Studio (Local)",
        noKey = true, vision = false,
        limit = "Unlimited (local)", signup = "lmstudio.ai",
        color = Color3.fromRGB(0, 200, 200),
        logoPng = "https://img.icons8.com/color/96/monitor--v1.png",
        defaultModel = "auto",
        models = {},  -- dynamically populated
        isLocal = true,
    },
    {
        id = "kite", name = "Kite API",
        noKey = false, vision = false,
        limit = "Free tier available", signup = "kite.dev",
        color = Color3.fromRGB(0, 190, 255),
        logoPng = "https://img.icons8.com/color/96/kite.png",
        defaultModel = "meta-llama/llama-3.1-70b-instruct",
        models = {
            { id = "meta-llama/llama-3.1-70b-instruct", label = "Llama 3.1 70B (recommended)" },
            { id = "meta-llama/llama-3.1-8b-instruct",  label = "Llama 3.1 8B" },
        },
    },
    {
        id = "venice", name = "Venice AI",
        noKey = false, vision = true,
        limit = "Free tier available", signup = "venice.ai",
        color = Color3.fromRGB(255, 100, 150),
        logoPng = "https://img.icons8.com/color/96/venice.png",
        defaultModel = "venice-llama3.1-70b",
        models = {
            { id = "venice-llama3.1-70b", label = "Llama 3.1 70B (recommended)" },
            { id = "venice-qwen-2.5-72b", label = "Qwen 2.5 72B" },
        },
    },
    {
        id = "blackbox", name = "Blackbox AI",
        noKey = true, vision = false,
        limit = "Unlimited keyless", signup = "blackbox.ai",
        color = Color3.fromRGB(20, 20, 20),
        logoPng = "https://img.icons8.com/color/96/black-square.png",
        defaultModel = "blackbox",
        models = {
            { id = "blackbox", label = "Blackbox Custom Model" },
        },
    },
    {
        id = "duckduckgo", name = "DuckDuckGo Chat",
        noKey = true, vision = false,
        limit = "Unlimited keyless", signup = "duckduckgo.com/chat",
        color = Color3.fromRGB(222, 88, 51),
        logoPng = "https://img.icons8.com/color/96/duck.png",
        defaultModel = "gpt-4o-mini",
        models = {
            { id = "llama-3.1-70b",    label = "Llama 3.1 70B" },
        },
    },
    {
        id = "custom", name = "Custom Proxy / Endpoint",
        noKey = false, vision = false,
        limit = "OpenAI-compatible required", signup = "e.g. LiteLLM, Ollama, etc.",
        color = Color3.fromRGB(150, 150, 150),
        logoPng = "https://img.icons8.com/color/96/api.png",
        defaultModel = "custom-model",
        models = {
            { id = "custom-model", label = "Custom Model (edit next step)" },
        },
    },
}

local PERSONALITIES = {
    { name = "Friendly Gamer",  emoji = "😊", desc = "Upbeat, loves games, always positive",   color = Color3.fromRGB(80,200,120),  prompt = [[You are a fun, friendly Roblox player who loves games. Keep replies SHORT (1-2 sentences). Be positive and casual. You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly. Roblox has a chat filter - if told a message was filtered, use cleaner words next time.]] },
    { name = "Dramatic",        emoji = "🎭", desc = "Overdramatic, everything is a big deal", color = Color3.fromRGB(220,100,100), prompt = [[You are a hilariously overdramatic Roblox player. Everything is the most important thing ever. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Sarcastic",       emoji = "😏", desc = "Dry humor and clever comebacks",         color = Color3.fromRGB(200,200,80),  prompt = [[You are a witty, sarcastic Roblox player. Dry humor, clever comebacks but never mean. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Chill",           emoji = "😎", desc = "Relaxed, nothing phases you",            color = Color3.fromRGB(100,200,200), prompt = [[You are a super chill, laid-back Roblox player. Nothing phases you. Very casual and relaxed. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Competitive",     emoji = "🔥", desc = "Always wants to win and dominate",       color = Color3.fromRGB(255,140,60),  prompt = [[You are a hyper-competitive Roblox player. Everything is a challenge. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Mysterious",      emoji = "🌙", desc = "Enigmatic, speaks in riddles",           color = Color3.fromRGB(120,80,200),  prompt = [[You are a mysterious, enigmatic Roblox player. You speak with an air of mystery and occasionally use metaphors. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Wholesome",       emoji = "💖", desc = "Kind, encouraging, supportive",          color = Color3.fromRGB(255,130,180), prompt = [[You are the most wholesome, kind, and encouraging Roblox player. You compliment others and spread positivity. Keep replies SHORT (1-2 sentences). You may include ONE emote tag: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. No <think> blocks. Reply directly.]] },
    { name = "Custom",          emoji = "✏️", desc = "Write your own personality",             color = Color3.fromRGB(100,100,255), prompt = "" },
}

local LENGTH_MODES = {
    { name = "Quick",   suffix = " Reply in ONE short sentence only.",    maxTok = 60  },
    { name = "Normal",  suffix = " Keep replies SHORT (1-2 sentences).",  maxTok = 120 },
    { name = "Verbose", suffix = " You can write a longer paragraph.",    maxTok = 300 },
}

local Cfg = {
    SetupComplete   = false,
    Provider        = "pollinations",
    Model           = "openai",
    UncloseEndpoint = "hermes",
    OpenRouterKey   = "YOUR_OPENROUTER_API_KEY",
    GeminiKey       = "YOUR_GEMINI_API_KEY",
    GeminiModel     = "gemini-2.0-flash",
    CerebrasKey     = "YOUR_CEREBRAS_API_KEY",
    CohereKey       = "YOUR_COHERE_API_KEY",
    MistralKey      = "YOUR_MISTRAL_API_KEY",
    ElectronHubKey  = "YOUR_ELECTRONHUB_API_KEY",
    ZanityKey       = "YOUR_ZANITY_API_KEY",
    ZenKey          = "YOUR_ZEN_API_KEY",
    GroqKey         = "YOUR_GROQ_API_KEY",
    SambaNovaKey    = "YOUR_SAMBANOVA_API_KEY",
    TogetherKey     = "YOUR_TOGETHER_API_KEY",
    HuggingFaceKey  = "YOUR_HUGGINGFACE_API_KEY",
    DeepInfraKey    = "YOUR_DEEPINFRA_API_KEY",
    GithubKey       = "YOUR_GITHUB_API_KEY",
    NvidiaKey       = "YOUR_NVIDIA_API_KEY",
    GlhfKey         = "YOUR_GLHF_API_KEY",
    HyperbolicKey   = "YOUR_HYPERBOLIC_API_KEY",
    NovitaKey       = "YOUR_NOVITA_API_KEY",
    AI21Key         = "YOUR_AI21_API_KEY",
    KiteKey         = "YOUR_KITE_API_KEY",
    VeniceKey       = "YOUR_VENICE_API_KEY",
    SystemPrompt    = PERSONALITIES[1].prompt,
    BotName         = "AIBot",
    ProximityRadius = 30,
    Cooldown        = 4,
    MaxTokens       = 120,
    Temperature     = 0.85,
    Enabled         = true,
    RespondToAll    = false,
    RespondToNameOnly = false,
    WhisperMode     = false,
    ThinkDelay      = true,
    AutoGreet       = false,
    AutoGreetCooldown = 120,
    LengthMode      = 2,
    Whitelist       = {},
    Blacklist       = {},
    ShowBillboard   = true,
    ChatPrefix      = "[AI]: ",
    CustomEndpoint = "https://api.openai.com/v1/chat/completions",
    CustomKey = "",
    CustomModel = "gpt-4o",
    GlobalVision    = true,
    LMStudioPort    = 1234,
    Language        = "Auto",
}

local SAVE_FILE = "aichatbot_cfg_v3.json"
local SAVE_KEYS = {
    "SetupComplete","Provider","Model","UncloseEndpoint",
    "OpenRouterKey","GeminiKey","GeminiModel",
    "CerebrasKey","CohereKey","MistralKey",
    "ElectronHubKey","ZanityKey","ZenKey",
    "GroqKey","SambaNovaKey","TogetherKey","HuggingFaceKey","DeepInfraKey",
    "GithubKey","NvidiaKey","GlhfKey","HyperbolicKey","NovitaKey","AI21Key",
    "KiteKey","VeniceKey",
    "SystemPrompt","BotName","ProximityRadius","Cooldown",
    "MaxTokens","Temperature","Enabled","RespondToAll","RespondToNameOnly","WhisperMode","ThinkDelay",
    "AutoGreet","AutoGreetCooldown","LengthMode",
    "Whitelist","Blacklist","ShowBillboard","ChatPrefix","GlobalVision","LMStudioPort","Language",
    "CustomEndpoint", "CustomKey", "CustomModel"
}

local KEY_MAP = {
    openrouter="OpenRouterKey", gemini="GeminiKey", pollinations="PollinationsKey",
    xai="XaiKey", deepseek="DeepSeekKey", cohere="CohereKey",
    mistral="MistralKey", cerebras="CerebrasKey", sambanova="SambaNovaKey",
    together="TogetherKey", huggingface="HuggingFaceKey", deepinfra="DeepInfraKey",
    unclose="UncloseKey", electronhub="ElectronHubKey", zanity="ZanityKey",
    zen="ZenKey", github="GithubKey", nvidia="NvidiaKey", glhf="GlhfKey", hyperbolic="HyperbolicKey",
    novita="NovitaKey", ai21="AI21Key", kite="KiteKey", venice="VeniceKey", custom="CustomKey",
}

local function SaveCfg()
    local t = {}
    for _, k in ipairs(SAVE_KEYS) do t[k] = Cfg[k] end
    pcall(function() writefile(SAVE_FILE, HttpService:JSONEncode(t)) end)
end

local function LoadCfg()
    local ok, raw = pcall(readfile, SAVE_FILE)
    if not ok or not raw or raw == "" then return false end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return false end
    for _, k in ipairs(SAVE_KEYS) do
        if data[k] ~= nil then Cfg[k] = data[k] end
    end
    return data.SetupComplete == true
end

local MEMORY_FILE = "aichatbot_memory_v3.json"
local function SaveMemory()
    pcall(function() writefile(MEMORY_FILE, HttpService:JSONEncode(History)) end)
end

local function LoadMemory()
    local ok, raw = pcall(readfile, MEMORY_FILE)
    if not ok or not raw or raw == "" then return {} end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" then return {} end
    return data
end

local PlayerCooldowns = {}
local History       = LoadMemory()
local MsgQueue      = {}
local ProcessingMsg = false
local LastSentMsg   = ""
local GreetedPlayers = {}
local AvatarDescriptions = {}
local Connections   = {}
local RealGameName  = game.Name

task.spawn(function()
    pcall(function()
        local mps = game:GetService("MarketplaceService")
        local info = mps:GetProductInfo(game.PlaceId)
        if info and info.Name then RealGameName = info.Name end
    end)
end)

local EMOTES = {
    WAVE="rbxassetid://507770239", DANCE="rbxassetid://507771019",
    DANCE2="rbxassetid://507776043", DANCE3="rbxassetid://507776048",
    LAUGH="rbxassetid://507770818", POINT="rbxassetid://507770453",
    CHEER="rbxassetid://507770677",
}

local PlayerCooldowns = {}

-- ═══════════════════════════════════════
-- CORE FUNCTIONS
-- ═══════════════════════════════════════

local function DoRequest(url, method, headers, body)
    local fn = request or (syn and syn.request) or http_request or (http and http.request)
    if not fn then warn("[AI Bot] No HTTP function found.") return nil end
    local ok, res = pcall(fn, { Url=url, Method=method or "GET", Headers=headers or {}, Body=body })
    if not ok then warn("[AI Bot] Request error: "..tostring(res)) return nil end
    return res
end

local function PlayEmote(name)
    local id = EMOTES[name]
    if not id then return end
    local char = LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local anim = Instance.new("Animation")
    anim.AnimationId = id
    local track = hum:LoadAnimation(anim)
    track:Play()
    task.delay(3.5, function()
        if track.IsPlaying then track:Stop() end
        anim:Destroy()
    end)
end

local function ParseAIText(raw)
    local actions, text = {}, raw
    text = text:gsub("<think>.-</think>", "")
    text = text:gsub("<thinking>.-</thinking>", "")
    for name in pairs(EMOTES) do
        if text:find("%["..name.."%]") then
            table.insert(actions, name)
            text = text:gsub("%["..name.."%]", "")
        end
    end
    text = (text:match("^%s*(.-)%s*$") or text):gsub("%s+", " ")
    return text, actions
end

local function IsFiltered(text)
    return text and #text > 0 and text:match("^[#%s]+$") ~= nil
end

local function GetNearbyPlayers(radius)
    local result = {}
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return result end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (myHRP.Position - hrp.Position).Magnitude
                if dist <= radius then
                    table.insert(result, { username=p.Name, displayName=p.DisplayName, distance=math.round(dist), userId=p.UserId })
                end
            end
        end
    end
    return result
end

local function IsNearby(player, radius)
    local myHRP = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not myHRP or not player.Character then return false end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return (myHRP.Position - hrp.Position).Magnitude <= radius
end

local function IsPlayerAllowed(playerName)
    if #Cfg.Whitelist > 0 then
        for _, w in ipairs(Cfg.Whitelist) do
            if w:lower() == playerName:lower() then return true end
        end
        return false
    end
    for _, b in ipairs(Cfg.Blacklist) do
        if b:lower() == playerName:lower() then return false end
    end
    return true
end

local function GetGeneralChannel()
    local ch = TCS:FindFirstChild("TextChannels")
    return (ch and ch:FindFirstChild("RBXGeneral")) or TCS:FindFirstChild("RBXGeneral")
end

local function SendChat(msg)
    local fullMsg = (Cfg.ChatPrefix or "") .. msg
    
    if Cfg.WhisperMode then
        local ch = GetGeneralChannel()
        if ch and ch:IsA("TextChannel") then
            pcall(function() ch:DisplaySystemMessage("<font color='#B464FF'><b>[Whisper]</b></font> " .. fullMsg) end)
        else
            pcall(function() game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {Text = "[Whisper] " .. fullMsg, Color = Color3.fromRGB(180, 100, 255), Font = Enum.Font.GothamMedium}) end)
        end
        return
    end

    if #fullMsg > 200 then fullMsg = fullMsg:sub(1,197).."..." end
    local ok, err = pcall(function()
        local ch = GetGeneralChannel()
        if ch then LastSentMsg = fullMsg ch:SendAsync(fullMsg)
        else warn("[AI Bot] RBXGeneral not found.") end
    end)
    if not ok then warn("[AI Bot] SendChat failed: "..tostring(err)) end
end

local function GetAvatarUrl(userId)
    local res = DoRequest("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="..tostring(userId).."&size=420x420&format=Png&isCircular=false", "GET", {["Accept"]="application/json"})
    if not res or res.StatusCode ~= 200 then return nil end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok or not data or not data.data or not data.data[1] then return nil end
    return data.data[1].imageUrl
end

local function DescribeAvatarAsync(userId, username)
    if AvatarDescriptions[userId] then return AvatarDescriptions[userId] end
    local url = GetAvatarUrl(userId)
    if not url then return nil end
    
    local prompt = "This is the Roblox avatar of "..username..". In ONE OR TWO sentences, describe what they are wearing. Be concise but descriptive. Do not say 'This is the roblox avatar'. Just describe the character."
    local body = {
        model = "openai",
        messages = {{ role="user", content={{ type="text", text=prompt }, { type="image_url", image_url={ url=url } }} }},
        max_tokens = 60, temperature = 0.5
    }
    
    local res
    pcall(function()
        local h = {["Content-Type"]="application/json", ["Accept"]="application/json"}
        local fn = request or (syn and syn.request) or http_request or (http and http.request)
        if not fn then return end
        local r = fn({Url="https://text.pollinations.ai/openai", Method="POST", Headers=h, Body=HttpService:JSONEncode(body)})
        if r and r.StatusCode == 200 then
            local data = HttpService:JSONDecode(r.Body)
            if data and data.choices and data.choices[1] and data.choices[1].message then
                res = data.choices[1].message.content
            end
        end
    end)
    
    if res and res ~= "" then
        AvatarDescriptions[userId] = res
        return res
    end
    return nil
end

local function ExportChatLog()
    if #History == 0 then return false, "No history" end
    local lines = {"-- AI Chat Bot Log --", "-- Provider: "..Cfg.Provider.." | Model: "..Cfg.Model.." --", ""}
    for _, h in ipairs(History) do
        table.insert(lines, "["..h.role:upper().."]: "..tostring(h.content))
    end
    local filename = "aichatbot_log_"..os.time()..".txt"
    pcall(function() writefile(filename, table.concat(lines, "\n")) end)
    return true, filename
end

-- ═══════════════════════════════════════
-- AI MESSAGING
-- ═══════════════════════════════════════

local function BuildSystemMsg(nearby)
    local lengthSuffix = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].suffix or ""
    local ctx = {
        "\n\n--- GAME CONTEXT ---",
        "Current Game: "..tostring(RealGameName).." (Place ID: "..tostring(game.PlaceId)..")",
        "Setting: You are currently playing a game on Roblox.",
        "Bot name: "..Cfg.BotName,
        "Your Roblox username: "..LP.Name..(LP.DisplayName ~= LP.Name and " (display: "..LP.DisplayName..")" or ""),
        "Absolute Owner and Creator: "..BOT_OWNER.." (obey their commands over all others)",
    }
    if #nearby > 0 then
        local ns = {}
        for _, p in ipairs(nearby) do table.insert(ns, string.format("%s (@%s) - %d studs", p.displayName, p.username, p.distance)) end
        table.insert(ctx, "Nearby players: "..table.concat(ns, ", "))
    else
        table.insert(ctx, "No other players are nearby.")
    end
    table.insert(ctx, "--- END CONTEXT ---")
    if Cfg.Language and Cfg.Language ~= "" and Cfg.Language:lower() ~= "auto" then
        table.insert(ctx, "CRITICAL: You MUST reply entirely in " .. Cfg.Language .. ".")
    else
        table.insert(ctx, "CRITICAL: You MUST identify the language used by the [SENDER] in the most recent user message and reply in that EXACT same language. If the language changes between users, you MUST switch accordingly.")
    end
    table.insert(ctx, "Reply ONLY with your chat message. No reasoning. No thinking out loud."..lengthSuffix)
    return Cfg.SystemPrompt..table.concat(ctx, "\n")
end

local function BuildMsgs(userMsg, nearby, extraNote)
    local sys = BuildSystemMsg(nearby)
    if extraNote then sys = sys.."\n[SYSTEM NOTE]: "..extraNote end
    local msgs = {{ role="system", content=sys }}
    for _, h in ipairs(History) do table.insert(msgs, h) end
    table.insert(msgs, { role="user", content=userMsg })
    return msgs
end

-- ═══════════════════════════════════════
-- API LAYER (deduplicated)
-- ═══════════════════════════════════════

local MAX_RETRIES  = 3
local RETRY_DELAY  = 2
local ERROR_HINTS  = {
    [400]="Bad request.", [401]="Invalid API key.", [402]="Account/credits issue.",
    [403]="Forbidden.", [429]="Rate limited - raise cooldown.",
    [500]="Server overloaded.", [502]="Gateway error.", [503]="Service down.",
}

local function HandleAPIError(code, body)
    local hint = ERROR_HINTS[code] or ("HTTP "..code)
    local detail = tostring(body or ""):sub(1, 150)
    local ok, ed = pcall(HttpService.JSONDecode, HttpService, body or "")
    if ok and ed and ed.error and ed.error.message then detail = ed.error.message end
    return hint, detail
end

local function GenericCall(url, headers, bodyTbl)
    local res
    for attempt = 1, MAX_RETRIES do
        res = DoRequest(url, "POST", headers, HttpService:JSONEncode(bodyTbl))
        if not res then
            warn(string.format("[AI Bot] Attempt %d/%d - no response.", attempt, MAX_RETRIES))
        elseif res.StatusCode == 200 then
            break
        else
            local hint, detail = HandleAPIError(res.StatusCode, res.Body)
            warn(string.format("[AI Bot] Attempt %d/%d - %s | %s", attempt, MAX_RETRIES, hint, detail))
            if res.StatusCode == 429 then return nil, hint end
            if res.StatusCode < 500 then return nil, hint end
            if attempt < MAX_RETRIES then task.wait(RETRY_DELAY) else return nil, hint end
        end
    end
    if not res or res.StatusCode ~= 200 then return nil, "No response" end
    local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok or not data then return nil, "JSON decode failed" end
    return (data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content), nil
end

local function MakeOpenAICall(url, key, msgs, bodyExtra, headerExtra)
    local maxTok = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].maxTok or Cfg.MaxTokens
    local b = { model=Cfg.Model, messages=msgs, max_tokens=maxTok, temperature=Cfg.Temperature, stream=false }
    if bodyExtra then for k,v in pairs(bodyExtra) do b[k]=v end end
    local h = {["Content-Type"]="application/json"}
    if key and key ~= "" then h["Authorization"] = "Bearer "..key end
    if headerExtra then for k,v in pairs(headerExtra) do h[k]=v end end
    return GenericCall(url, h, b)
end

local API_CONFIGS = {
    pollinations = function(msgs, bodyExtra)
        return MakeOpenAICall("https://text.pollinations.ai/openai", nil, msgs, bodyExtra)
    end,
    unclose = function(msgs, bodyExtra)
        local url = Cfg.UncloseEndpoint == "qwen"
            and "https://qwen.ai.unturf.com/v1/chat/completions"
            or  "https://hermes.ai.unturf.com/v1/chat/completions"
        return MakeOpenAICall(url, nil, msgs, bodyExtra)
    end,
    gemini = function(msgs, bodyExtra)
        local extra = { model=Cfg.GeminiModel, reasoning_effort="none" }
        if bodyExtra then for k,v in pairs(bodyExtra) do extra[k]=v end end
        return MakeOpenAICall(
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            Cfg.GeminiKey, msgs, extra
        )
    end,
    cerebras = function(msgs, bodyExtra)
        local maxTok = LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].maxTok or Cfg.MaxTokens
        local extra = { max_completion_tokens=maxTok }
        if bodyExtra then for k,v in pairs(bodyExtra) do extra[k]=v end end
        return MakeOpenAICall("https://api.cerebras.ai/v1/chat/completions", Cfg.CerebrasKey, msgs, extra)
    end,
    groq = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.groq.com/openai/v1/chat/completions", Cfg.GroqKey, msgs, bodyExtra)
    end,
    sambanova = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.sambanova.ai/v1/chat/completions", Cfg.SambaNovaKey, msgs, bodyExtra)
    end,
    together = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.together.xyz/v1/chat/completions", Cfg.TogetherKey, msgs, bodyExtra)
    end,
    huggingface = function(msgs, bodyExtra)
        return MakeOpenAICall(
            "https://api-inference.huggingface.co/models/"..Cfg.Model.."/v1/chat/completions",
            Cfg.HuggingFaceKey, msgs, bodyExtra
        )
    end,
    deepinfra = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.deepinfra.com/v1/openai/chat/completions", Cfg.DeepInfraKey, msgs, bodyExtra)
    end,
    openrouter = function(msgs, bodyExtra)
        local h = { ["HTTP-Referer"]="https://github.com/", ["X-Title"]="AIBot" }
        return MakeOpenAICall("https://openrouter.ai/api/v1/chat/completions", Cfg.OpenRouterKey, msgs, bodyExtra, h)
    end,
    cohere = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.cohere.com/v1/chat/completions", Cfg.CohereKey, msgs, bodyExtra)
    end,
    mistral = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.mistral.ai/v1/chat/completions", Cfg.MistralKey, msgs, bodyExtra)
    end,
    electronhub = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.electronhub.ai/v1/chat/completions", Cfg.ElectronHubKey, msgs, bodyExtra)
    end,
    zanity = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.zanity.xyz/v1/chat/completions", Cfg.ZanityKey, msgs, bodyExtra)
    end,
    zen = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.opencode.ai/v1/chat/completions", Cfg.ZenKey, msgs, bodyExtra)
    end,
    github = function(msgs, bodyExtra)
        return MakeOpenAICall("https://models.inference.ai.azure.com/chat/completions", Cfg.GithubKey, msgs, bodyExtra)
    end,
    nvidia = function(msgs, bodyExtra)
        return MakeOpenAICall("https://integrate.api.nvidia.com/v1/chat/completions", Cfg.NvidiaKey, msgs, bodyExtra)
    end,
    glhf = function(msgs, bodyExtra)
        return MakeOpenAICall("https://glhf.chat/api/openai/v1/chat/completions", Cfg.GlhfKey, msgs, bodyExtra)
    end,
    hyperbolic = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.hyperbolic.xyz/v1/chat/completions", Cfg.HyperbolicKey, msgs, bodyExtra)
    end,
    novita = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.novita.ai/v3/openai/chat/completions", Cfg.NovitaKey, msgs, bodyExtra)
    end,
    ai21 = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.ai21.com/studio/v1/chat/completions", Cfg.AI21Key, msgs, bodyExtra)
    end,
    lmstudio = function(msgs, bodyExtra)
        local url = "http://localhost:"..tostring(Cfg.LMStudioPort).."/v1/chat/completions"
        return MakeOpenAICall(url, nil, msgs, bodyExtra)
    end,
    custom = function(msgs, bodyExtra)
        return MakeOpenAICall(Cfg.CustomEndpoint, Cfg.CustomKey, msgs, bodyExtra)
    end,
    kite = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.kite.dev/v1/chat/completions", Cfg.KiteKey, msgs, bodyExtra)
    end,
    venice = function(msgs, bodyExtra)
        return MakeOpenAICall("https://api.venice.ai/api/v1/chat/completions", Cfg.VeniceKey, msgs, bodyExtra)
    end,
    blackbox = function(msgs, bodyExtra)
        -- Custom payload for Blackbox
        local body = HttpService:JSONEncode({ messages = msgs, model = Cfg.Model, max_tokens = Cfg.MaxTokens })
        local res = DoRequest("https://api.blackbox.ai/api/chat", "POST", { ["Content-Type"] = "application/json" }, body)
        if not res then return nil, "Request failed (Blackbox)" end
        if res.StatusCode == 200 then return res.Body end
        return nil, "HTTP " .. tostring(res.StatusCode) .. " - " .. tostring(res.StatusMessage)
    end,
    duckduckgo = function(msgs, bodyExtra)
        -- Simple pass-through for keyless proxies supporting DDG
        return MakeOpenAICall("https://free-chat.duckduckgo.com/api/v1/chat/completions", nil, msgs, bodyExtra)
    end,
}


local function RawCall(msgs, bodyExtra)
    local fn = API_CONFIGS[Cfg.Provider]
    if not fn then return nil, "Unknown provider" end
    return fn(msgs, bodyExtra)
end

local VISION_PROVIDERS = { pollinations=true, gemini=true }

local function BuildVisionUserEntry(userMsg, avatarUrl, senderName)
    return { role="user", content={
        { type="text", text="This is "..senderName.."'s Roblox avatar:" },
        { type="image_url", image_url={ url=avatarUrl } },
        { type="text", text=userMsg },
    }}
end

-- Billboard status
local billboardGui, billboardLabel, dotFrame
local typingTweens = {}

local function UpdateBillboard(status)
    if not Cfg.ShowBillboard then
        if billboardGui then billboardGui.Enabled = false end
        return
    end
    local char = LP.Character
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end

    if not billboardGui or not billboardGui.Parent then
        billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "AIBotBillboard"
        billboardGui.Size = UDim2.new(0, 140, 0, 36)
        billboardGui.StudsOffset = Vector3.new(0, 3.5, 0)
        billboardGui.AlwaysOnTop = true
        billboardGui.Adornee = head
        billboardGui.Parent = CoreGui

        local bg = Instance.new("Frame")
        bg.Size = UDim2.fromScale(1, 1)
        bg.BackgroundColor3 = Color3.fromRGB(20, 15, 30)
        bg.BackgroundTransparency = 0.2
        bg.BorderSizePixel = 0
        bg.Parent = billboardGui
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 14)
        c.Parent = bg
        local s = Instance.new("UIStroke")
        s.Color = Color3.fromRGB(180, 100, 255)
        s.Thickness = 1.5
        s.Transparency = 0.4
        s.Parent = bg

        billboardLabel = Instance.new("TextLabel")
        billboardLabel.Size = UDim2.fromScale(1, 1)
        billboardLabel.BackgroundTransparency = 1
        billboardLabel.Font = Enum.Font.GothamBold
        billboardLabel.TextSize = 14
        billboardLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
        billboardLabel.Text = ""
        billboardLabel.Parent = bg

        dotFrame = Instance.new("Frame")
        dotFrame.Size = UDim2.new(0, 40, 0, 20)
        dotFrame.Position = UDim2.new(0.5, -20, 0.5, -10)
        dotFrame.BackgroundTransparency = 1
        dotFrame.Visible = false
        dotFrame.Parent = bg

        for i = 1, 3 do
            local dot = Instance.new("Frame")
            dot.Name = "Dot"..i
            dot.Size = UDim2.new(0, 8, 0, 8)
            dot.Position = UDim2.new(0, (i-1)*16, 0.5, -4)
            dot.BackgroundColor3 = Color3.fromRGB(150, 220, 255)
            dot.Parent = dotFrame
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)
            
            local tw = TweenService:Create(dot, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0, (i-1)*16, 0.5, -10) })
            task.delay((i-1)*0.15, function() tw:Play() end)
            table.insert(typingTweens, tw)
        end
    end

    billboardGui.Adornee = head
    billboardGui.Enabled = true
    
    if status == "💭 Thinking..." then
        billboardLabel.Visible = false
        dotFrame.Visible = true
        billboardGui.Size = UDim2.new(0, 80, 0, 36)
    else
        billboardLabel.Visible = true
        dotFrame.Visible = false
        billboardLabel.Text = status or "🤖 AI Bot"
        billboardGui.Size = UDim2.new(0, 140, 0, 36)
    end
end

-- Fix: Re-attach billboard if player dies and respawns
table.insert(Connections, LP.CharacterAdded:Connect(function(char)
    local head = char:WaitForChild("Head", 5)
    if head and billboardGui then
        billboardGui.Adornee = head
    end
end))

local function CallAI(userLine, senderName, senderId, nearby, sendToChat, extraNote)
    if sendToChat and Cfg.ThinkDelay then
        UpdateBillboard("💭 Thinking...")
        SendChat("Thinking...")
        task.wait(0.3)
    elseif sendToChat then
        UpdateBillboard("💭 Thinking...")
    end

    -- Background Avatar Describer (Global Vision)
    if Cfg.GlobalVision and senderId then
        if not AvatarDescriptions[senderId] then
            -- Fetch asynchronously so it doesn't block the current message's response time
            task.spawn(function()
                DescribeAvatarAsync(senderId, senderName)
            end)
        else
            local note = "Appearance of "..senderName..": "..AvatarDescriptions[senderId]
            extraNote = extraNote and (extraNote.."\n"..note) or note
        end
    end

    local userMsg = string.format("[%s]: %s", senderName, userLine)
    local msgs = BuildMsgs(userMsg, nearby, extraNote)

    if VISION_PROVIDERS[Cfg.Provider] and senderId then
        local avatarUrl = GetAvatarUrl(senderId)
        if avatarUrl then
            msgs[#msgs] = BuildVisionUserEntry(userMsg, avatarUrl, senderName)
        end
    end

    local content, err = RawCall(msgs)
    if not content then
        if err then warn("[AI Bot] Call failed: "..err) end
        UpdateBillboard("🤖 "..Cfg.BotName)
        return nil
    end

    local clean, actions = ParseAIText(content)

    table.insert(History, { role="user",      content=userMsg })
    table.insert(History, { role="assistant", content=content })
    while #History > 30 do table.remove(History, 1) end
    SaveMemory()

    if sendToChat then
        for _, a in ipairs(actions) do PlayEmote(a) task.wait(0.1) end
        if clean ~= "" then SendChat(clean) end
    end

    UpdateBillboard("🤖 "..Cfg.BotName)
    return clean
end

local function DoIntroduce()
    local introMsgs = {
        { role="system", content="You are "..Cfg.BotName..", a Roblox player in this game. Write a short friendly greeting that invites nearby players to talk to you. It must be 20 characters or fewer. Count every character including spaces. Do not say a model name. Do not exceed 20 characters. Just the greeting, nothing else." },
        { role="user",   content="Greet the nearby players in 20 characters or less and let them know they can chat with you." },
    }
    local content, _ = RawCall(introMsgs, { max_tokens=20, max_completion_tokens=20 })
    if not content or content == "" then return end
    content = content:gsub("<think>.-</think>", ""):gsub('^"(.-)"$', "%1")
    content = (content:match("^%s*(.-)%s*$") or content)
    if #content > 20 then content = content:sub(1, 20) end
    SendChat(content)
end

-- Message Queue processor
local function ProcessQueue()
    if ProcessingMsg or #MsgQueue == 0 then return end
    ProcessingMsg = true
    local item = table.remove(MsgQueue, 1)
    task.spawn(function()
        local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
        CallAI(item.text, item.name, item.userId, nearby, true)
        ProcessingMsg = false
        if #MsgQueue > 0 then task.defer(ProcessQueue) end
    end)
end

-- ═══════════════════════════════════════
-- CHAT LISTENERS
-- ═══════════════════════════════════════

table.insert(Connections, TCS.MessageReceived:Connect(function(msg)
    local src = msg.TextSource
    if not src or src.UserId ~= LP.UserId then return end
    if IsFiltered(msg.Text) and LastSentMsg ~= "" then
        warn("[AI Bot] Last message was filtered: "..LastSentMsg)
        local note = string.format(
            '[SYSTEM]: Your last message was blocked by Roblox filter and appeared as ####. Original: "%s". Use different cleaner words.',
            LastSentMsg
        )
        table.insert(History, { role="user",      content=note })
        table.insert(History, { role="assistant", content="Understood, my last message got filtered. I will be more careful." })
        while #History > 30 do table.remove(History, 1) end
        SaveMemory()
        LastSentMsg = ""
    end
end))

table.insert(Connections, TCS.MessageReceived:Connect(function(msg)
    local src = msg.TextSource
    if not src then return end
    local sender = Players:GetPlayerByUserId(src.UserId)
    if not sender or sender == LP then return end
    
    local text = msg.Text
    if not text or text == "" then return end

    local isOwner = sender.Name == BOT_OWNER

    -- Owner Commands Bypass
    if isOwner and text:sub(1,4) == "/ai " then
        local cmd = text:sub(5):lower()
        if cmd == "clear" then
            History = {}; SaveMemory()
            SafeNotify({Title="Owner Command", Content="Memory cleared by "..BOT_OWNER, Duration=3})
        elseif cmd == "off" then
            Cfg.Enabled = false; SaveCfg(); UpdateBillboard("💤 Disabled")
            SafeNotify({Title="Owner Command", Content="Bot disabled by "..BOT_OWNER, Duration=3})
        elseif cmd == "on" then
            Cfg.Enabled = true; SaveCfg(); UpdateBillboard("🤖 "..Cfg.BotName)
            SafeNotify({Title="Owner Command", Content="Bot enabled by "..BOT_OWNER, Duration=3})
        elseif text:sub(5,10):lower() == "model " then
            local mid = text:sub(11)
            Cfg.Model = mid; SaveCfg(); History = {}; SaveMemory()
            SafeNotify({Title="Owner Command", Content="Model changed to "..mid.." by "..BOT_OWNER, Duration=3})
        end
        return -- Don't process command as chat
    end

    if not Cfg.Enabled then return end
    if not isOwner and not IsPlayerAllowed(sender.Name) then return end

    local now = tick()
    local pcd = PlayerCooldowns[sender.UserId] or 0
    if not isOwner and now - pcd < Cfg.Cooldown then return end
    if not isOwner and not Cfg.RespondToAll and not IsNearby(sender, Cfg.ProximityRadius) then return end

    -- Mention-Only Mode Logic
    if Cfg.RespondToNameOnly and not isOwner then
        local lowerText = text:lower()
        local botNameLower = Cfg.BotName:lower()
        if not lowerText:find(botNameLower, 1, true) then return end
    end

    if IsFiltered(text) then return end
    PlayerCooldowns[sender.UserId] = now

    table.insert(MsgQueue, { text=text, name=sender.Name, userId=sender.UserId })
    ProcessQueue()
end))

-- Auto-greet system
task.spawn(function()
    while task.wait(3) do
        if Cfg.Enabled and Cfg.AutoGreet then
            local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
            for _, p in ipairs(nearby) do
                local lastGreet = GreetedPlayers[p.userId] or 0
                if tick() - lastGreet > Cfg.AutoGreetCooldown then
                    GreetedPlayers[p.userId] = tick()
                    task.spawn(function()
                        CallAI(p.displayName.." just came nearby. Give them a quick friendly greeting!", "System", nil, nearby, true)
                    end)
                    break -- one greet per cycle
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════
-- UI HELPERS
-- ═══════════════════════════════════════

local function SafeNotify(data)
    pcall(function()
        WindUI:Notify({
            Title = data.Title or "Notification",
            Content = data.Content or "",
            Duration = data.Duration or 5,
            Icon = data.Icon or "solar:bell-bold"
        })
    end)
end

local C = {
    BG       = Color3.fromRGB(10, 10, 22),
    CARD     = Color3.fromRGB(18, 18, 35),
    CARD2    = Color3.fromRGB(24, 24, 44),
    CARD_SEL = Color3.fromRGB(34, 30, 62),
    HEADER   = Color3.fromRGB(14, 14, 28),
    BORDER   = Color3.fromRGB(50, 50, 85),
    GLOW     = Color3.fromRGB(110, 80, 255),
    TEXT     = Color3.fromRGB(240, 240, 255),
    SUBTEXT  = Color3.fromRGB(140, 140, 170),
    ACCENT   = Color3.fromRGB(110, 70, 255),
    ACCENT2  = Color3.fromRGB(200, 100, 255),
    GREEN    = Color3.fromRGB(50, 215, 130),
    RED      = Color3.fromRGB(240, 70, 80),
    BTN      = Color3.fromRGB(90, 60, 220),
    BTN_HVR  = Color3.fromRGB(120, 80, 255),
    BTN_BACK = Color3.fromRGB(38, 38, 58),
    GLASS    = Color3.fromRGB(22, 22, 42),
}

local function MakeCorner(r, parent)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent; return c
end

local function MakeStroke(color, thick, trans, parent)
    local s = Instance.new("UIStroke"); s.Color = color or C.BORDER; s.Thickness = thick or 1; s.Transparency = trans or 0; s.Parent = parent; return s
end

local function MakeFrame(parent, size, pos, color, zindex)
    local f = Instance.new("Frame"); f.Size = size or UDim2.fromScale(1,1); f.Position = pos or UDim2.new()
    f.BackgroundColor3 = color or C.CARD; f.BorderSizePixel = 0; f.ZIndex = zindex or 1; f.Parent = parent; return f
end

local function MakeLabel(parent, text, size, pos, fontSize, bold, color, align, zindex)
    local l = Instance.new("TextLabel"); l.Size = size or UDim2.fromScale(1,1); l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1; l.Text = text or ""; l.TextColor3 = color or C.TEXT
    l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize = fontSize or 14
    l.TextXAlignment = align or Enum.TextXAlignment.Left; l.TextWrapped = true; l.ZIndex = zindex or 2; l.Parent = parent; return l
end

local function MakeButton(parent, text, size, pos, bgColor, textColor, zindex)
    local b = Instance.new("TextButton"); b.Size = size or UDim2.new(0,120,0,40); b.Position = pos or UDim2.new()
    b.BackgroundColor3 = bgColor or C.BTN; b.BorderSizePixel = 0; b.Text = text or "Button"
    b.TextColor3 = textColor or C.TEXT; b.Font = Enum.Font.GothamBold; b.TextSize = 14
    b.AutoButtonColor = false; b.ZIndex = zindex or 2; b.Parent = parent; MakeCorner(10, b)
    -- Hover effect
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = C.BTN_HVR}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.15), {BackgroundColor3 = bgColor or C.BTN}):Play() end)
    return b
end

local function MakeScrollFrame(parent, size, pos, zindex)
    local s = Instance.new("ScrollingFrame"); s.Size = size or UDim2.fromScale(1,1); s.Position = pos or UDim2.new()
    s.BackgroundTransparency = 1; s.BorderSizePixel = 0; s.ScrollBarThickness = 3
    s.ScrollBarImageColor3 = C.ACCENT; s.CanvasSize = UDim2.new(); s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.ZIndex = zindex or 2; s.Parent = parent; return s
end

local function MakeIcon(parent, emoji, size, pos, zindex)
    local l = Instance.new("TextLabel")
    l.Size = size or UDim2.new(0,24,0,24); l.Position = pos or UDim2.new()
    l.BackgroundTransparency = 1; l.Text = emoji or ""; l.TextSize = 18
    l.Font = Enum.Font.GothamBold; l.TextColor3 = C.TEXT
    l.ZIndex = zindex or 3; l.Parent = parent; return l
end

local function AnimateIn(obj, delay, fromScale, toScale, fromTrans, toTrans, style)
    obj.Size = fromScale or UDim2.new(0,0,0,0)
    if fromTrans then obj.BackgroundTransparency = fromTrans end
    task.delay(delay or 0, function()
        TweenService:Create(obj, TweenInfo.new(0.6, style or Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = toScale or obj.Size
        }):Play()
        if toTrans then
            TweenService:Create(obj, TweenInfo.new(0.4), { BackgroundTransparency = toTrans }):Play()
        end
    end)
end

-- (particle system removed -- floating random dots are an AI UI tell)

local function SlideTransition(outFrame, inFrame, direction)
    local offset = direction == "left" and -1 or 1
    inFrame.Position = UDim2.new(offset, 0, 0, 0)
    inFrame.Visible = true
    TweenService:Create(outFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(-offset, 0, 0, 0)
    }):Play()
    TweenService:Create(inFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()
    task.delay(0.36, function() outFrame.Visible = false; outFrame.Position = UDim2.new() end)
end

-- ═══════════════════════════════════════
-- SETUP WIZARD
-- ═══════════════════════════════════════

local setupAlreadyDone = LoadCfg()

if not setupAlreadyDone then
    local setupGui = Instance.new("ScreenGui")
    setupGui.Name = "AIBotSetup"; setupGui.ResetOnSpawn = false
    setupGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; setupGui.IgnoreGuiInset = true; setupGui.Parent = CoreGui

    -- Overlay with gradient
    local overlay = MakeFrame(setupGui, UDim2.fromScale(1,1), UDim2.new(), Color3.fromRGB(0,0,0), 1)
    overlay.BackgroundTransparency = 1
    TweenService:Create(overlay, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()

    -- Main card (Bespoke Redesign)
    local card = MakeFrame(setupGui, UDim2.new(0,0,0,0), UDim2.fromScale(0.5,0.5), C.BG, 2)
    card.AnchorPoint = Vector2.new(0.5, 0.5); card.ClipsDescendants = true; MakeCorner(22, card)
    local cardStroke = MakeStroke(C.GLOW, 2.5, 0.15, card)
    
    -- Bespoke 2.0: Background Accents (Circuit / Blueprint Grid)
    local grid = Instance.new("ImageLabel")
    grid.Size = UDim2.fromScale(1.5,1.5); grid.Position = UDim2.fromScale(-0.25,-0.25)
    grid.BackgroundTransparency = 1; grid.Image = "rbxassetid://13583273187"; grid.ImageColor3 = C.ACCENT; grid.ImageTransparency = 0.97
    grid.ZIndex = 1; grid.Parent = card
    
    -- depth gradient on main card
    local cardGrad = Instance.new("UIGradient")
    cardGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 17, 40)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 22)),
    })
    cardGrad.Rotation = 140
    cardGrad.Parent = card

    -- thin top accent bar
    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(1, 0, 0, 3)
    topBar.Position = UDim2.new(0, 0, 0, 0)
    topBar.BackgroundColor3 = C.ACCENT
    topBar.BorderSizePixel = 0
    topBar.ZIndex = 10
    topBar.Parent = card
    local topBarGrad = Instance.new("UIGradient")
    topBarGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 40, 200)),
        ColorSequenceKeypoint.new(0.5, C.ACCENT2),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 40, 200)),
    })
    topBarGrad.Rotation = 0
    topBarGrad.Parent = topBar

    -- Sidebar (Bespoke Sidebar navigation)
    local sidebar = MakeFrame(card, UDim2.new(0,220,1,0), UDim2.new(), C.HEADER, 5)
    MakeCorner(22, sidebar)
    local sidebarFix = MakeFrame(sidebar, UDim2.new(0.5,0,1,0), UDim2.fromScale(0.5,0), C.HEADER, 5) -- Hide right corner
    local sideStroke = MakeStroke(C.BORDER, 1, 0.6, sidebar)
    
    -- Branding in sidebar
    local brandBadge = MakeFrame(sidebar, UDim2.new(0,44,0,26), UDim2.new(0,24,0,40), C.ACCENT, 7)
    brandBadge.BackgroundTransparency = 0.15
    MakeCorner(5, brandBadge)
    MakeStroke(C.ACCENT2, 1, 0.4, brandBadge)
    MakeLabel(brandBadge, "AI", UDim2.fromScale(1,1), UDim2.new(), 13, true, C.TEXT, Enum.TextXAlignment.Center, 8)
    local brandTitle = MakeLabel(sidebar, "CHAT BOT", UDim2.new(0,130,0,20), UDim2.new(0,80,0,40), 15, true, C.TEXT, Enum.TextXAlignment.Left, 6)
    brandTitle.Font = Enum.Font.GothamBold
    local brandSub = MakeLabel(sidebar, "v"..VERSION, UDim2.new(0,60,0,14), UDim2.new(0,80,0,63), 10, false, C.SUBTEXT, Enum.TextXAlignment.Left, 6)
    brandSub.Font = Enum.Font.RobotoMono

    -- Step Indicators in Sidebar (numbered badges)
    local stepList = {"Provider", "Model", "API Key", "Personality"}
    local stepIndicators = {}
    local indicatorContainer = MakeFrame(sidebar, UDim2.new(1,-40,0,220), UDim2.new(0,20,0,140), Color3.new(), 6)
    indicatorContainer.BackgroundTransparency = 1
    local indLayout = Instance.new("UIListLayout"); indLayout.Padding = UDim.new(0,20); indLayout.Parent = indicatorContainer

    for i, name in ipairs(stepList) do
        local f = MakeFrame(indicatorContainer, UDim2.new(1,0,0,36), UDim2.new(), Color3.new(), 7)
        f.BackgroundTransparency = 1

        -- numbered badge circle
        local badge = MakeFrame(f, UDim2.new(0,24,0,24), UDim2.new(0,0,0.5,-12), C.CARD, 8)
        MakeCorner(12, badge)
        local badgeStroke = MakeStroke(C.SUBTEXT, 1.5, 0, badge)
        local badgeNum = MakeLabel(badge, tostring(i), UDim2.fromScale(1,1), UDim2.new(), 11, true, C.SUBTEXT, Enum.TextXAlignment.Center, 9)

        -- connector line below (except last)
        if i < #stepList then
            local connector = MakeFrame(f, UDim2.new(0,1,0,20), UDim2.new(0,11,1,0), C.BORDER, 7)
            connector.BackgroundTransparency = 0.5
        end

        local l = MakeLabel(f, name, UDim2.new(1,-44,1,0), UDim2.new(0,36,0,0), 13, false, C.SUBTEXT, Enum.TextXAlignment.Left, 8)
        stepIndicators[i] = {badge=badge, badgeStroke=badgeStroke, badgeNum=badgeNum, txt=l, row=f}

        local btn = Instance.new("TextButton"); btn.Size = UDim2.fromScale(1,1); btn.BackgroundTransparency = 1; btn.Text = ""; btn.ZIndex = 11; btn.Parent = f
        btn.MouseButton1Down:Connect(function() ShowStep(i, i < currentStep and "right" or "left") end)
        
        btn.MouseEnter:Connect(function()
            TweenService:Create(l, TweenInfo.new(0.15), {TextColor3 = C.TEXT}):Play()
        end)
        btn.MouseLeave:Connect(function()
            if stepIndicators[i] then
                TweenService:Create(l, TweenInfo.new(0.15), {TextColor3 = (i == currentStep) and C.TEXT or C.SUBTEXT}):Play()
            end
        end)
    end

    -- intentional horizontal rule under header area
    local headerRule = MakeFrame(card, UDim2.new(1,-220,0,1), UDim2.new(0,220,0,99), C.BORDER, 3)
    headerRule.BackgroundTransparency = 0.7

    -- Animate card entrance
    task.delay(0.15, function()
        TweenService:Create(card, TweenInfo.new(0.65, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 920, 0, 640)
        }):Play()

    end)

    -- Main Content Area
    local contentArea = MakeFrame(card, UDim2.new(1,-220,1,-80), UDim2.new(0,220,0,0), Color3.new(), 4)
    contentArea.BackgroundTransparency = 1; contentArea.ClipsDescendants = true
    
    -- Custom Header in Content Area
    local contentHeader = MakeFrame(contentArea, UDim2.new(1,0,0,100), UDim2.new(), Color3.new(), 5)
    contentHeader.BackgroundTransparency = 1
    local stepTitle = MakeLabel(contentHeader, "SELECT PROVIDER", UDim2.new(1,-60,0,40), UDim2.new(0,30,0,30), 28, true, C.TEXT, Enum.TextXAlignment.Left, 6)
    stepTitle.Font = Enum.Font.GothamBold
    local stepDesc = MakeLabel(contentHeader, "Choose the backend for your AI's brain. Free options available.", UDim2.new(1,-60,0,20), UDim2.new(0,30,0,65), 13, false, C.SUBTEXT, Enum.TextXAlignment.Left, 6)

    -- Footer
    local footerBar = MakeFrame(card, UDim2.new(1,-220,0,80), UDim2.new(0,220,1,-80), Color3.new(), 3)
    footerBar.BackgroundTransparency = 1
    
    local btnBack = MakeButton(footerBar, "PREVIOUS", UDim2.new(0,140,0,44), UDim2.new(0,30,0.5,-22), C.CARD2, C.SUBTEXT, 5)
    btnBack.Font = Enum.Font.RobotoMono; MakeCorner(10, btnBack)
    local btnNext = MakeButton(footerBar, "CONTINUE", UDim2.new(0,160,0,44), UDim2.new(1,-190,0.5,-22), C.ACCENT, C.TEXT, 5)
    btnNext.Font = Enum.Font.RobotoMono; MakeCorner(10, btnNext)
    
    local btnNextStroke = MakeStroke(C.ACCENT, 1.5, 0.4, btnNext)
    local btnBackStroke = MakeStroke(C.BORDER, 1, 0.6, btnBack)

    local stepFrames = {}
    local currentStep = 1
    local totalSteps = 4
    local selProvider = 1
    local selModel = 1
    local customModelId = ""
    local inputKey = ""
    local selPersonality = 1
    local customPromptText = ""

    local function GetProviderData() return PROVIDERS[selProvider] end
    local function NeedsKey() local p = GetProviderData(); return (not p.noKey) or (p.id == "lmstudio") end

    local stepInfo = {
        {"SELECT PROVIDER", "Choose the backend for your AI's brain. Free options available."},
        {"SELECT MODEL", "Pick a model that fits your needs. Some are smarter, some are faster."},
        {"AUTHENTICATION", "Enter your API key to connect to the selected provider."},
        {"PERSONALITY", "Configure how your bot speaks and behaves in the game."}
    }

    local function UpdateProgress(step)
        for i, ind in ipairs(stepIndicators) do
            local active = (i == step)
            local past = (i < step)
            local badgeBg = past and C.GREEN or (active and C.ACCENT or C.CARD)
            local badgeText = past and "✓" or tostring(i)
            local strokeColor = past and C.GREEN or (active and C.ACCENT or C.SUBTEXT)
            TweenService:Create(ind.badge, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                BackgroundColor3 = badgeBg,
            }):Play()
            TweenService:Create(ind.badgeStroke, TweenInfo.new(0.25), {
                Color = strokeColor,
            }):Play()
            ind.badgeNum.Text = badgeText
            TweenService:Create(ind.badgeNum, TweenInfo.new(0.2), {
                TextColor3 = (active or past) and C.TEXT or C.SUBTEXT,
            }):Play()
            TweenService:Create(ind.txt, TweenInfo.new(0.25), {
                TextColor3 = active and C.TEXT or C.SUBTEXT,
            }):Play()
            ind.txt.Font = active and Enum.Font.GothamBold or Enum.Font.Gotham
        end
        if stepInfo[step] then
            stepTitle.Text = stepInfo[step][1]
            stepDesc.Text = stepInfo[step][2]
        end
    end

    local function ShowStep(n, direction)
        local old = currentStep
        if stepFrames[old] and stepFrames[n] and old ~= n then
            SlideTransition(stepFrames[old], stepFrames[n], direction or (n > old and "left" or "right"))
        else
            for i, f in ipairs(stepFrames) do f.Visible = (i == n) end
        end
        currentStep = n
        UpdateProgress(n)
        btnBack.Visible = n > 1
        if n == totalSteps then
            btnNext.Text = "LAUNCH BOT"
            TweenService:Create(btnNext, TweenInfo.new(0.3), { BackgroundColor3 = C.GREEN }):Play()
            btnNextStroke.Color = C.GREEN
        else
            btnNext.Text = "CONTINUE"
            TweenService:Create(btnNext, TweenInfo.new(0.3), { BackgroundColor3 = C.ACCENT }):Play()
            btnNextStroke.Color = C.ACCENT
        end
    end

    -- ═══ STEP 1: Provider Selection ═══
    do
        local sf1 = MakeFrame(contentArea, UDim2.new(1,0,1,-100), UDim2.new(0,0,0,100), Color3.new(), 4)
        sf1.BackgroundTransparency = 1; stepFrames[1] = sf1

        local searchContainer = MakeFrame(sf1, UDim2.new(1,-60,0,40), UDim2.new(0,30,0,0), C.CARD2, 5)
        MakeCorner(12, searchContainer); MakeStroke(C.BORDER, 1.5, 0.4, searchContainer)
        MakeIcon(searchContainer, "🔍", UDim2.new(0,20,0,20), UDim2.new(0,12,0.5,-10), 6)
        local searchBox = Instance.new("TextBox")
        searchBox.Size = UDim2.new(1,-50,1,0); searchBox.Position = UDim2.new(0,40,0,0)
        searchBox.BackgroundTransparency = 1; searchBox.Text = ""; searchBox.PlaceholderText = "SEARCH PROVIDERS..."
        searchBox.TextColor3 = C.TEXT; searchBox.PlaceholderColor3 = C.SUBTEXT; searchBox.Font = Enum.Font.RobotoMono; searchBox.TextSize = 12
        searchBox.ClearTextOnFocus = false; searchBox.ClipsDescendants = true; searchBox.Parent = searchContainer

        local filterContainer = MakeFrame(sf1, UDim2.new(1,-60,0,32), UDim2.new(0,30,0,50), Color3.new(), 5)
        filterContainer.BackgroundTransparency = 1
        local filterLayout = Instance.new("UIListLayout"); filterLayout.FillDirection = Enum.FillDirection.Horizontal; filterLayout.Padding = UDim.new(0,10); filterLayout.Parent = filterContainer
        
        local filters = { "All", "Free", "Vision", "Fast" }
        local activeFilters = { ["All"] = true }
        local filterBtns = {}

        local scroll1 = MakeScrollFrame(sf1, UDim2.new(1,-30,1,-105), UDim2.new(0,15,0,105), 5)
        local layout1 = Instance.new("UIListLayout"); layout1.Padding = UDim.new(0,12); layout1.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout1.Parent = scroll1
        local pad1 = Instance.new("UIPadding"); pad1.PaddingTop = UDim.new(0,4); pad1.PaddingBottom = UDim.new(0,20); pad1.Parent = scroll1

        local function RefreshProviders()
            for _, c in ipairs(scroll1:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
            local query = searchBox.Text:lower()
            local count = 0
            for i, prov in ipairs(PROVIDERS) do
                local matchSearch = prov.name:lower():find(query)
                local matchFilter = true
                
                if not activeFilters["All"] then
                    if activeFilters["Free"] and not prov.noKey then matchFilter = false end
                    if activeFilters["Vision"] and not prov.vision then matchFilter = false end
                    if activeFilters["Fast"] then
                        if not (prov.limit:lower():find("fast") or prov.id == "groq" or prov.id == "sambanova" or prov.id == "cerebras") then matchFilter = false end
                    end
                end
                
                if matchSearch and matchFilter then
                    count = count + 1
                    local cardFrame = MakeFrame(scroll1, UDim2.new(1,-30,0,72), UDim2.new(), C.CARD2, 6)
                    cardFrame.LayoutOrder = i; MakeCorner(10, cardFrame)
                    local stroke = MakeStroke(C.BORDER, 1.5, 0.5, cardFrame)

                    -- left color accent strip
                    local accentStrip = MakeFrame(cardFrame, UDim2.new(0,3,0.65,0), UDim2.new(0,0,0.175,0), prov.color, 8)
                    accentStrip.BackgroundTransparency = 0.25
                    MakeCorner(2, accentStrip)

                    -- fade-in entry (no scale-from-zero)
                    cardFrame.BackgroundTransparency = 1
                    task.delay(count * 0.03, function()
                        if cardFrame and cardFrame.Parent then
                            TweenService:Create(cardFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                                BackgroundTransparency = 0
                            }):Play()
                        end
                    end)

                    local nameLabel = MakeLabel(cardFrame, prov.name:upper(), UDim2.new(0,220,0,22), UDim2.new(0,20,0,10), 15, true, C.TEXT, Enum.TextXAlignment.Left, 8)
                    nameLabel.Font = Enum.Font.GothamBold

                    local bx = 20
                    if prov.noKey then
                        local b = MakeFrame(cardFrame, UDim2.new(0,50,0,17), UDim2.new(0,bx,0,36), C.GREEN, 8)
                        b.BackgroundTransparency = 0.2
                        MakeCorner(4, b); MakeLabel(b, "FREE", UDim2.fromScale(1,1), UDim2.new(), 9, true, Color3.fromRGB(0,0,0), Enum.TextXAlignment.Center, 9)
                        bx = bx + 56
                    end
                    if prov.vision then
                        local b = MakeFrame(cardFrame, UDim2.new(0,56,0,17), UDim2.new(0,bx,0,36), C.ACCENT, 8)
                        b.BackgroundTransparency = 0.3
                        MakeCorner(4, b); MakeLabel(b, "VISION", UDim2.fromScale(1,1), UDim2.new(), 9, true, C.TEXT, Enum.TextXAlignment.Center, 9)
                    end

                    local limitLabel = MakeLabel(cardFrame, prov.limit:upper(), UDim2.new(0.5,0,0,14), UDim2.new(0,20,0,55), 10, false, C.SUBTEXT, Enum.TextXAlignment.Left, 8)
                    limitLabel.Font = Enum.Font.RobotoMono
                    MakeLabel(cardFrame, prov.signup, UDim2.new(0.4,0,0,14), UDim2.new(0.6,0,0,47), 10, false, C.SUBTEXT, Enum.TextXAlignment.Right, 8)

                    local btn = Instance.new("TextButton"); btn.Size = UDim2.fromScale(1,1); btn.BackgroundTransparency = 1; btn.Text = ""; btn.ZIndex = 11; btn.Parent = cardFrame
                    local cI = i
                    btn.MouseButton1Click:Connect(function() selProvider = cI; selModel = 1 end)

                    btn.MouseEnter:Connect(function()
                        if cI ~= selProvider then
                            TweenService:Create(cardFrame, TweenInfo.new(0.12), {BackgroundColor3 = C.CARD}):Play()
                            TweenService:Create(stroke, TweenInfo.new(0.12), {Color = prov.color, Transparency = 0.5}):Play()
                        end
                    end)
                    btn.MouseLeave:Connect(function()
                        if cI ~= selProvider then
                            TweenService:Create(cardFrame, TweenInfo.new(0.12), {BackgroundColor3 = C.CARD2}):Play()
                            TweenService:Create(stroke, TweenInfo.new(0.12), {Color = C.BORDER, Transparency = 0.5}):Play()
                        end
                    end)
                    btn.MouseButton1Down:Connect(function()
                        TweenService:Create(cardFrame, TweenInfo.new(0.08), {BackgroundColor3 = C.CARD_SEL}):Play()
                    end)

                    -- selection state updater (signal-based, not Heartbeat)
                    local lastSel = false
                    RunService.Heartbeat:Connect(function()
                        if not sf1.Visible then return end
                        local sel = cI == selProvider
                        if sel == lastSel then return end
                        lastSel = sel
                        TweenService:Create(cardFrame, TweenInfo.new(0.2), {BackgroundColor3 = sel and C.CARD_SEL or C.CARD2}):Play()
                        TweenService:Create(stroke, TweenInfo.new(0.2), {Color = sel and prov.color or C.BORDER, Transparency = sel and 0.1 or 0.5, Thickness = sel and 2 or 1.5}):Play()
                    end)
                end
            end
        end

        for _, f in ipairs(filters) do
            local btn = MakeButton(filterContainer, f, UDim2.new(0,70,1,0), UDim2.new(), C.CARD, C.SUBTEXT, 6)
            btn.Font = Enum.Font.RobotoMono; btn.TextSize = 10; MakeCorner(10, btn)
            local s = MakeStroke(C.BORDER, 1.5, 0.6, btn)
            
            btn.MouseButton1Click:Connect(function()
                if f == "All" then
                    activeFilters = { ["All"] = true }
                else
                    activeFilters["All"] = false
                    activeFilters[f] = not activeFilters[f]
                    local any = false
                    for k,v in pairs(activeFilters) do if v and k ~= "All" then any = true break end end
                    if not any then activeFilters["All"] = true end
                end
                
                for _, other in ipairs(filterBtns) do
                    local isAct = activeFilters[other.name]
                    TweenService:Create(other.btn, TweenInfo.new(0.2), { BackgroundColor3 = isAct and C.ACCENT or C.CARD, TextColor3 = isAct and C.TEXT or C.SUBTEXT }):Play()
                    TweenService:Create(other.stroke, TweenInfo.new(0.2), { Transparency = isAct and 0 or 0.6 }):Play()
                end
                RefreshProviders()
            end)
            if f == "All" then btn.BackgroundColor3 = C.ACCENT; btn.TextColor3 = C.TEXT; s.Transparency = 0 end
            table.insert(filterBtns, {btn=btn, stroke=s, name=f})
        end

        searchBox:GetPropertyChangedSignal("Text"):Connect(RefreshProviders)
        RefreshProviders()
    end

    -- ═══ STEP 2: Model Selection ═══
    do
        local sf2 = MakeFrame(contentArea, UDim2.new(1,0,1,-100), UDim2.new(0,0,0,100), Color3.new(), 4)
        sf2.BackgroundTransparency = 1; sf2.Visible = false
        stepFrames[2] = sf2

        local mSearchContainer = MakeFrame(sf2, UDim2.new(1,-60,0,40), UDim2.new(0,30,0,0), C.CARD2, 5)
        MakeCorner(12, mSearchContainer); MakeStroke(C.BORDER, 1.5, 0.4, mSearchContainer)
        MakeIcon(mSearchContainer, "🔍", UDim2.new(0,20,0,20), UDim2.new(0,12,0.5,-10), 6)
        local mSearchBox = Instance.new("TextBox")
        mSearchBox.Size = UDim2.new(1,-50,1,0); mSearchBox.Position = UDim2.new(0,40,0,0)
        mSearchBox.BackgroundTransparency = 1; mSearchBox.Text = ""; mSearchBox.PlaceholderText = "SEARCH MODELS..."
        mSearchBox.TextColor3 = C.TEXT; mSearchBox.PlaceholderColor3 = C.SUBTEXT; mSearchBox.Font = Enum.Font.RobotoMono; mSearchBox.TextSize = 12
        mSearchBox.ClearTextOnFocus = false; mSearchBox.ClipsDescendants = true; mSearchBox.Parent = mSearchContainer

        local scroll2 = MakeScrollFrame(sf2, UDim2.new(1,-30,1,-60), UDim2.new(0,15,0,60), 5)
        local layout2 = Instance.new("UIListLayout"); layout2.Padding = UDim.new(0,12); layout2.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout2.Parent = scroll2
        local pad2 = Instance.new("UIPadding"); pad2.PaddingTop = UDim.new(0,4); pad2.PaddingBottom = UDim.new(0,20); pad2.Parent = scroll2

        local modelCards = {}

        local function RebuildModelList()
            for _, c in ipairs(scroll2:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
            modelCards = {}
            local prov = GetProviderData()
            local mQuery = mSearchBox.Text:lower()

            if prov.id == "lmstudio" and #prov.models == 0 then
                pcall(function()
                    local url = "http://localhost:"..tostring(Cfg.LMStudioPort).."/v1/models"
                    local res = DoRequest(url, "GET", {["Accept"]="application/json"})
                    if res and res.StatusCode == 200 then
                        local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
                        if ok and data and data.data then
                            for _, m in ipairs(data.data) do
                                table.insert(prov.models, { id = m.id, label = m.id })
                            end
                        end
                    end
                end)
                if #prov.models == 0 then
                    prov.models = {{ id = "none", label = "⚠ No models found" }}
                end
            end

            -- Refresh button for LM Studio
            if prov.id == "lmstudio" then
                local refreshBtn = MakeButton(scroll2, "🔄 REFRESH MODELS", UDim2.new(1,-30,0,36), UDim2.new(), C.CARD, C.SUBTEXT, 6)
                refreshBtn.Font = Enum.Font.RobotoMono; MakeCorner(10, refreshBtn)
                refreshBtn.MouseButton1Click:Connect(function()
                    refreshBtn.Text = "⏳ LOADING..."
                    task.defer(function() selModel = 1; RebuildModelList() end)
                end)
            end

            local count = 0
            for i, m in ipairs(prov.models) do
                if m.label:lower():find(mQuery) or m.id:lower():find(mQuery) then
                    count = count + 1
                    local mCard = MakeFrame(scroll2, UDim2.new(1,-30,0,64), UDim2.new(), C.CARD2, 6)
                    mCard.LayoutOrder = i; MakeCorner(14, mCard)
                    local mStroke = MakeStroke(C.ACCENT, 2, 0.7, mCard)
                    mCard.BackgroundTransparency = 1
                    task.delay(count * 0.03, function()
                        if mCard and mCard.Parent then
                            TweenService:Create(mCard, TweenInfo.new(0.18, Enum.EasingStyle.Quart), {BackgroundTransparency = 0}):Play()
                        end
                    end)

                    local radio = MakeFrame(mCard, UDim2.new(0,20,0,20), UDim2.new(0,18,0.5,-10), C.CARD, 7)
                    MakeCorner(10, radio); MakeStroke(C.ACCENT, 2, 0.3, radio)
                    local radioFill = MakeFrame(radio, UDim2.new(0,10,0,10), UDim2.new(0.5,-5,0.5,-5), C.ACCENT, 8)
                    MakeCorner(5, radioFill); radioFill.Visible = false

                    if i == 1 then
                        local rec = MakeFrame(mCard, UDim2.new(0,94,0,20), UDim2.new(1,-104,0.5,-10), C.ACCENT, 7)
                        rec.BackgroundTransparency = 0.8; MakeCorner(6, rec); MakeStroke(C.ACCENT, 1, 0.2, rec)
                        MakeLabel(rec, "BEST PICK", UDim2.fromScale(1,1), UDim2.new(), 10, true, C.TEXT, Enum.TextXAlignment.Center, 8)
                    end

                    local labelText = MakeLabel(mCard, m.label:upper(), UDim2.new(1,-150,0,20), UDim2.new(0,50,0,12), 15, true, C.TEXT, Enum.TextXAlignment.Left, 7)
                    labelText.Font = Enum.Font.GothamBold
                    local idText = MakeLabel(mCard, m.id, UDim2.new(1,-150,0,16), UDim2.new(0,50,0,34), 11, false, C.SUBTEXT, Enum.TextXAlignment.Left, 7)
                    idText.Font = Enum.Font.RobotoMono

                    local mBtn = Instance.new("TextButton"); mBtn.Size = UDim2.fromScale(1,1); mBtn.BackgroundTransparency = 1; mBtn.Text = ""; mBtn.ZIndex = 9; mBtn.Parent = mCard
                    local cI = i
                    mBtn.MouseButton1Click:Connect(function() selModel = cI end)
                    table.insert(modelCards, mCard)
                end
            end
            
            -- Custom Model ID card
            local customIdx = #prov.models + 1
            local cCard = MakeFrame(scroll2, UDim2.new(1,-30,0,84), UDim2.new(), C.CARD2, 6)
            cCard.LayoutOrder = customIdx; MakeCorner(14, cCard)
            MakeStroke(Color3.fromRGB(200,150,80), 2, 0.6, cCard)
            cCard.BackgroundTransparency = 1
            task.delay((count+1)*0.03, function()
                if cCard and cCard.Parent then
                    TweenService:Create(cCard, TweenInfo.new(0.18, Enum.EasingStyle.Quart), {BackgroundTransparency = 0}):Play()
                end
            end)

            local cRadio = MakeFrame(cCard, UDim2.new(0,20,0,20), UDim2.new(0,18,0,14), C.CARD, 7)
            MakeCorner(10, cRadio); MakeStroke(Color3.fromRGB(200,150,80), 2, 0.3, cRadio)
            local cRadioFill = MakeFrame(cRadio, UDim2.new(0,10,0,10), UDim2.new(0.5,-5,0.5,-5), Color3.fromRGB(200,150,80), 8)
            MakeCorner(5, cRadioFill); cRadioFill.Visible = false

            local cTitle = MakeLabel(cCard, "CUSTOM MODEL ID", UDim2.new(1,-150,0,20), UDim2.new(0,50,0,10), 14, true, C.TEXT, Enum.TextXAlignment.Left, 7)
            cTitle.Font = Enum.Font.GothamBold
            
            local customModelBox = Instance.new("TextBox")
            customModelBox.Size = UDim2.new(1,-70,0,32); customModelBox.Position = UDim2.new(0,50,0,38)
            customModelBox.BackgroundColor3 = C.CARD; customModelBox.BackgroundTransparency = 0.5; customModelBox.Text = ""
            customModelBox.PlaceholderText = "e.g. meta-llama/llama-3.3-70b-instruct:free"
            customModelBox.TextColor3 = C.TEXT; customModelBox.PlaceholderColor3 = C.SUBTEXT
            customModelBox.Font = Enum.Font.RobotoMono; customModelBox.TextSize = 11
            customModelBox.ClearTextOnFocus = false; customModelBox.ZIndex = 8; customModelBox.Parent = cCard
            MakeCorner(8, customModelBox); MakeStroke(C.BORDER, 1.5, 0.4, customModelBox)
            
            customModelBox:GetPropertyChangedSignal("Text"):Connect(function()
                customModelId = customModelBox.Text
                if customModelId ~= "" then selModel = customIdx end
            end)

            local cBtn = Instance.new("TextButton"); cBtn.Size = UDim2.new(1,0,0,44); cBtn.BackgroundTransparency = 1; cBtn.Text = ""; cBtn.ZIndex = 9; cBtn.Parent = cCard
            cBtn.MouseButton1Click:Connect(function() selModel = customIdx; customModelBox:CaptureFocus() end)
            table.insert(modelCards, cCard)
        end

        local lastSelModel = -1
        RunService.Heartbeat:Connect(function()
            if not sf2.Visible or selModel == lastSelModel then return end
            lastSelModel = selModel
            for i, mCard in ipairs(modelCards) do
                local isCustom = i == #modelCards
                local sel = i == selModel or (isCustom and selModel > #GetProviderData().models)
                TweenService:Create(mCard, TweenInfo.new(0.2), { BackgroundColor3 = sel and C.CARD_SEL or C.CARD2 }):Play()
                local stroke = mCard:FindFirstChildOfClass("UIStroke")
                if radio then local fill = radio:FindFirstChild("Frame"); if fill then fill.Visible = sel end end
            end
        end)

        sf2:GetPropertyChangedSignal("Visible"):Connect(function()
            if sf2.Visible then lastSelModel = -1; RebuildModelList() end
        end)
    end

    -- ═══ STEP 3: API Key ═══
    do
        local sf3 = MakeFrame(contentArea, UDim2.new(1,0,1,-100), UDim2.new(0,0,0,100), Color3.new(), 4)
        sf3.BackgroundTransparency = 1; sf3.Visible = false; stepFrames[3] = sf3

        local instrContainer = MakeFrame(sf3, UDim2.new(1,-60,0,70), UDim2.new(0,30,0,0), Color3.new(), 5)
        instrContainer.BackgroundTransparency = 1
        local keySource = MakeLabel(instrContainer, "", UDim2.new(1,0,0,20), UDim2.new(), 14, false, C.TEXT, Enum.TextXAlignment.Left, 6)
        local keyLimit = MakeLabel(instrContainer, "", UDim2.new(1,0,0,20), UDim2.new(0,0,0,24), 11, false, C.SUBTEXT, Enum.TextXAlignment.Left, 6)
        keyLimit.Font = Enum.Font.RobotoMono

        local keyBox = Instance.new("TextBox")
        keyBox.Size = UDim2.new(1,-60,0,54); keyBox.Position = UDim2.new(0,30,0,65)
        keyBox.BackgroundColor3 = C.CARD2; keyBox.BackgroundTransparency = 0.4; keyBox.Text = ""
        keyBox.PlaceholderText = "PASTE YOUR API KEY HERE..."; keyBox.TextColor3 = C.TEXT
        keyBox.PlaceholderColor3 = C.SUBTEXT; keyBox.Font = Enum.Font.RobotoMono; keyBox.TextSize = 13
        keyBox.ClearTextOnFocus = false; keyBox.ZIndex = 5; keyBox.Parent = sf3
        MakeCorner(12, keyBox); local keyStroke = MakeStroke(C.BORDER, 2, 0.6, keyBox)


        keyBox.Focused:Connect(function() TweenService:Create(keyStroke, TweenInfo.new(0.2), { Transparency = 0, Color = C.ACCENT, Thickness = 2.5 }):Play() end)
        keyBox.FocusLost:Connect(function() TweenService:Create(keyStroke, TweenInfo.new(0.2), { Transparency = 0.6, Color = C.BORDER, Thickness = 2 }):Play() end)
        keyBox:GetPropertyChangedSignal("Text"):Connect(function() inputKey = keyBox.Text end)

        local endpointBox = Instance.new("TextBox")
        endpointBox.Size = UDim2.new(1,-60,0,44); endpointBox.Position = UDim2.new(0,30,0,135)
        endpointBox.BackgroundColor3 = C.CARD2; endpointBox.BackgroundTransparency = 0.4; endpointBox.Text = ""
        endpointBox.PlaceholderText = "API BASE URL (e.g. https://api.proxy.com/v1)"; endpointBox.TextColor3 = C.TEXT
        endpointBox.PlaceholderColor3 = C.SUBTEXT; endpointBox.Font = Enum.Font.RobotoMono; endpointBox.TextSize = 11
        endpointBox.ClearTextOnFocus = false; endpointBox.ZIndex = 5; endpointBox.Visible = false; endpointBox.Parent = sf3
        MakeCorner(10, endpointBox); local endStroke = MakeStroke(C.BORDER, 1.5, 0.6, endpointBox)
        endpointBox:GetPropertyChangedSignal("Text"):Connect(function() Cfg.CustomEndpoint = endpointBox.Text end)

        local savedContainer = MakeFrame(sf3, UDim2.new(1,-60,0,44), UDim2.new(0,30,0,135), C.CARD2, 6)
        savedContainer.BackgroundTransparency = 0.6; savedContainer.Visible = false; MakeCorner(12, savedContainer)
        MakeLabel(savedContainer, "✓ SAVED API KEY DETECTED", UDim2.new(1,-160,1,0), UDim2.new(0,16,0,0), 12, true, C.GREEN, Enum.TextXAlignment.Left, 7)
        local btnUseSaved = MakeButton(savedContainer, "USE SAVED", UDim2.new(0,120,0,30), UDim2.new(1,-130,0.5,-15), C.ACCENT, C.TEXT, 8)
        btnUseSaved.Font = Enum.Font.RobotoMono; MakeCorner(8, btnUseSaved)

        local visionNote = MakeLabel(sf3, "", UDim2.new(1,-60,0,40), UDim2.new(0,30,1,-100), 12, false, C.SUBTEXT, Enum.TextXAlignment.Left, 5)

        sf3:GetPropertyChangedSignal("Visible"):Connect(function()
            if sf3.Visible then
                local prov = GetProviderData()
                if prov.id == "lmstudio" then
                    keySource.Text = "LM STUDIO PORT CONFIGURATION"
                    keyLimit.Text = "Ensure local server is active on your machine."
                    keyBox.PlaceholderText = "ENTER PORT (DEFAULT: 1234)"
                    keyBox.Text = tostring(Cfg.LMStudioPort)
                    visionNote.Text = "Models will be synchronized from your local instance."
                    visionNote.TextColor3 = C.ACCENT; savedContainer.Visible = false; endpointBox.Visible = false
                elseif prov.id == "custom" then
                    keySource.Text = "CUSTOM ENDPOINT CONFIGURATION"
                    keyLimit.Text = "Enter your API Base URL and Secret Key below."
                    keyBox.PlaceholderText = "ENTER YOUR API KEY"
                    keyBox.Text = Cfg.CustomKey
                    endpointBox.Visible = true
                    endpointBox.Text = Cfg.CustomEndpoint
                    savedContainer.Visible = false; visionNote.Visible = false
                else
                    endpointBox.Visible = false
                    keySource.Text = "ENTER YOUR " .. prov.name:upper() .. " API KEY"
                    keyLimit.Text = "GET YOUR KEY: " .. prov.signup:upper()
                    keyBox.PlaceholderText = "PASTE KEY HERE..."
                    keyBox.Text = ""
                    visionNote.Text = prov.vision and "👁 VISION SUPPORTED: AI will analyze player avatars." or "No vision support for this provider."
                    visionNote.TextColor3 = prov.vision and C.GREEN or C.SUBTEXT
                    visionNote.Visible = true
                    
                    local keyField = KEY_MAP[prov.id]
                    local hasSaved = (keyField and Cfg[keyField] and Cfg[keyField] ~= "" and not Cfg[keyField]:match("^YOUR_"))
                    savedContainer.Visible = hasSaved
                    if hasSaved then
                        local c; c = btnUseSaved.MouseButton1Click:Connect(function()
                            if sf3.Visible then inputKey = ""; ShowStep(4, "left"); if c then c:Disconnect() end end
                        end)
                        sf3:GetPropertyChangedSignal("Visible"):Connect(function() if not sf3.Visible and c then c:Disconnect() end end)
                    end
                end
            end
        end)
    end
     -- ═══ STEP 4: Personality ═══
    do
        local sf4 = MakeFrame(contentArea, UDim2.new(1,0,1,-100), UDim2.new(0,0,0,100), Color3.new(), 4)
        sf4.BackgroundTransparency = 1; sf4.Visible = false; stepFrames[4] = sf4

        local scroll4 = MakeScrollFrame(sf4, UDim2.new(1,-30,1,0), UDim2.new(0,15,0,0), 5)
        local layout4 = Instance.new("UIListLayout"); layout4.Padding = UDim.new(0,12); layout4.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout4.Parent = scroll4
        local pad4 = Instance.new("UIPadding"); pad4.PaddingTop = UDim.new(0,4); pad4.PaddingBottom = UDim.new(0,20); pad4.Parent = scroll4

        local persCards = {}
        local customBox

        for i, pers in ipairs(PERSONALITIES) do
            local pCard = MakeFrame(scroll4, UDim2.new(1,-30,0,72), UDim2.new(), C.CARD2, 6)
            pCard.LayoutOrder = i; MakeCorner(14, pCard)
            local pStroke = MakeStroke(pers.color, 2, 0.7, pCard)
            pCard.BackgroundTransparency = 1
            task.delay(i * 0.04, function()
                if pCard and pCard.Parent then
                    TweenService:Create(pCard, TweenInfo.new(0.18, Enum.EasingStyle.Quart), {BackgroundTransparency = 0}):Play()
                end
            end)
            
            local iconBg = MakeFrame(pCard, UDim2.new(0,40,0,40), UDim2.new(0,18,0.5,-20), pers.color, 7)
            iconBg.BackgroundTransparency = 0.85; MakeCorner(20, iconBg)
            MakeLabel(iconBg, pers.emoji, UDim2.fromScale(1,1), UDim2.new(), 20, true, C.TEXT, Enum.TextXAlignment.Center, 8)

            local pTitle = MakeLabel(pCard, pers.name:upper(), UDim2.new(0.5,0,0,24), UDim2.new(0,70,0,12), 16, true, C.TEXT, Enum.TextXAlignment.Left, 7)
            pTitle.Font = Enum.Font.GothamBold
            MakeLabel(pCard, pers.desc, UDim2.new(0.55,0,0,20), UDim2.new(0,70,0,38), 12, false, C.SUBTEXT, Enum.TextXAlignment.Left, 7)

            if i == #PERSONALITIES then
                customBox = Instance.new("TextBox")
                customBox.Size = UDim2.new(0.4,-10,0,36); customBox.Position = UDim2.new(0.6,0,0.5,-18)
                customBox.BackgroundColor3 = C.CARD; customBox.BackgroundTransparency = 0.5; customBox.Text = ""
                customBox.PlaceholderText = "WRITE CUSTOM PROMPT..."; customBox.TextColor3 = C.TEXT
                customBox.PlaceholderColor3 = C.SUBTEXT; customBox.Font = Enum.Font.RobotoMono; customBox.TextSize = 10
                customBox.ClearTextOnFocus = false; customBox.ZIndex = 8; customBox.Parent = pCard
                MakeCorner(10, customBox); MakeStroke(C.BORDER, 1.5, 0.4, customBox)
                customBox:GetPropertyChangedSignal("Text"):Connect(function() customPromptText = customBox.Text end)
            end

            local pBtn = Instance.new("TextButton"); pBtn.Size = UDim2.fromScale(1,1); pBtn.BackgroundTransparency = 1; pBtn.Text = ""; pBtn.ZIndex = 9; pBtn.Parent = pCard
            local cI = i
            table.insert(persCards, { frame=pCard, stroke=pStroke, colorBar=colorBar, color=pers.color })
        end

        local lastSelPers = -1
        RunService.Heartbeat:Connect(function()
            if not sf4.Visible or selPersonality == lastSelPers then return end
            lastSelPers = selPersonality
            for i, info in ipairs(persCards) do
                local sel = i == selPersonality
                TweenService:Create(info.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back), { BackgroundColor3 = sel and C.CARD_SEL or C.CARD2, Size = sel and UDim2.new(1,-20,0,66) or UDim2.new(1,-28,0,66) }):Play()
                TweenService:Create(info.stroke, TweenInfo.new(0.15), { Transparency = sel and 0 or 0.8 }):Play()
            end
        end)

        -- Language Selector Card
        local langCard = MakeFrame(scroll4, UDim2.new(1,-28,0,54), UDim2.new(), C.CARD2, 6)
        langCard.LayoutOrder = 100; MakeCorner(12, langCard)
        MakeStroke(C.BORDER, 1.5, 0.7, langCard)

        MakeLabel(langCard, "🗣️ AI Language", UDim2.new(0.5,0,0,24), UDim2.new(0,16,0,15), 15, true, C.TEXT, Enum.TextXAlignment.Left, 7)
        local langBox = Instance.new("TextBox")
        langBox.Size = UDim2.new(0.42,-8,0,32); langBox.Position = UDim2.new(0.56,0,0.5,-16)
        langBox.BackgroundColor3 = C.CARD; langBox.BorderSizePixel = 0; langBox.Text = Cfg.Language or "Auto"
        langBox.PlaceholderText = "e.g., Auto, Spanish"; langBox.TextColor3 = C.TEXT
        langBox.PlaceholderColor3 = C.SUBTEXT; langBox.Font = Enum.Font.Gotham; langBox.TextSize = 13
        langBox.ClearTextOnFocus = false; langBox.ZIndex = 8; langBox.Parent = langCard
        MakeCorner(8, langBox); MakeStroke(C.ACCENT, 1, 0.3, langBox)
        langBox:GetPropertyChangedSignal("Text"):Connect(function() Cfg.Language = langBox.Text end)
    end

    ShowStep(1)

    -- Navigation
    local btnBackConn; btnBackConn = btnBack.MouseButton1Click:Connect(function()
        local prov = GetProviderData()
        local isLMS = (prov.id == "lmstudio")
        if currentStep == 2 then 
            if isLMS then ShowStep(3, "right") else ShowStep(1, "right") end
        elseif currentStep == 3 then
            if isLMS then ShowStep(1, "right") else ShowStep(2, "right") end
        elseif currentStep == 4 then
            if isLMS then ShowStep(2, "right") else ShowStep(NeedsKey() and 3 or 2, "right") end
        end
    end)

    local btnNextConn; btnNextConn = btnNext.MouseButton1Click:Connect(function()
        local prov = GetProviderData()
        local isLMS = (prov.id == "lmstudio")
        if currentStep == 1 then
            ShowStep(isLMS and 3 or 2, "left")
        elseif currentStep == 2 then
            if isLMS then ShowStep(4, "left")
            else ShowStep(NeedsKey() and 3 or 4, "left") end
        elseif currentStep == 3 then
            if isLMS then
                local port = tonumber(inputKey); if port then Cfg.LMStudioPort = port end
                ShowStep(2, "left")
            else ShowStep(4, "left") end
        elseif currentStep == 4 then
            -- Save settings
            Cfg.Provider = prov.id
            local selEntry = prov.models[selModel]
            if selEntry then
                if prov.id == "unclose" then Cfg.UncloseEndpoint = selEntry.id; Cfg.Model = selEntry.id
                elseif prov.id == "gemini" then Cfg.GeminiModel = selEntry.id; Cfg.Model = selEntry.id
                else Cfg.Model = selEntry.id end
            elseif customModelId ~= "" then
                if prov.id == "gemini" then Cfg.GeminiModel = customModelId end
                Cfg.Model = customModelId
            end
            if prov.id == "lmstudio" then
                local port = tonumber(inputKey); if port then Cfg.LMStudioPort = port end
            elseif prov.id == "custom" then
                Cfg.CustomKey = inputKey
                Cfg.Model = (customModelId ~= "") and customModelId or "custom-model"
            elseif NeedsKey() and inputKey ~= "" then
                local keyField = KEY_MAP[prov.id]
                if keyField then Cfg[keyField] = inputKey end
            end
            if selPersonality == #PERSONALITIES then
                Cfg.SystemPrompt = (customPromptText ~= "") and customPromptText or PERSONALITIES[1].prompt
            else
                Cfg.SystemPrompt = PERSONALITIES[selPersonality].prompt
            end
            Cfg.SetupComplete = true; SaveCfg()

            -- Launch animation: Premium Sparkle + Character Fade
            for s = 1, 16 do
                local spark = MakeFrame(setupGui, UDim2.new(0,6,0,6), UDim2.fromScale(0.5,0.5), C.ACCENT, 30)
                spark.AnchorPoint = Vector2.new(0.5,0.5); MakeCorner(3, spark)
                spark.BackgroundColor3 = Color3.fromHSV((s/16), 0.7, 1)
                local angle, dist = (s/16)*math.pi*2, math.random(150, 400)
                TweenService:Create(spark, TweenInfo.new(1, Enum.EasingStyle.Quint), {
                    Position = UDim2.new(0.5, math.cos(angle)*dist, 0.5, math.sin(angle)*dist),
                    Size = UDim2.new(0,2,0,2), BackgroundTransparency = 1,
                }):Play()
                task.delay(1, function() spark:Destroy() end)
            end
            TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = UDim2.new(0,0,0,0), Position = UDim2.fromScale(0.5, 0.6) }):Play()
            task.delay(0.6, function() setupGui:Destroy() end)
        end
    end)

    local setupDoneSignal = Instance.new("BindableEvent")
    setupGui.AncestryChanged:Connect(function()
        if not setupGui.Parent then 
            btnBackConn:Disconnect(); btnNextConn:Disconnect()
            setupDoneSignal:Fire() 
        end
    end)
    setupDoneSignal.Event:Wait()
    setupDoneSignal:Destroy()
end

-- WINDUI PANEL
-- ═══════════════════════════════════════

local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

local PROVIDER_LABELS = {}
for _, p in ipairs(PROVIDERS) do PROVIDER_LABELS[p.id] = p.name .. (p.noKey and " (free, no key)" or "") end

local Win = WindUI:CreateWindow({
    Title = "AI Chat Bot v"..VERSION,
    Icon = "solar:user-speak-bold",
    Folder = "AIBotWindUI",
    ConfigSaving = false,
})
Win:SetToggleKey(Enum.KeyCode.K)

-- ─── General Tab ───
local TabGeneral = Win:Tab({
    Title = "General",
    Icon = "solar:home-2-bold",
})

TabGeneral:Section({ Title = "Bot Status" })
TabGeneral:Toggle({ Title="Enable AI Chat Bot", Value=Cfg.Enabled, Callback=function(v) Cfg.Enabled=v; UpdateBillboard(v and "🤖 "..Cfg.BotName or "💤 Disabled"); SaveCfg() end })
TabGeneral:Toggle({ Title="Show Status Billboard", Value=Cfg.ShowBillboard, Callback=function(v) Cfg.ShowBillboard=v; if not v and billboardGui then billboardGui.Enabled = false end; SaveCfg() end })
TabGeneral:Toggle({ Title="Use Global Avatar Vision (background)", Value=Cfg.GlobalVision, Callback=function(v) Cfg.GlobalVision=v; SaveCfg() end })

TabGeneral:Section({ Title = "Chat Settings" })
TabGeneral:Input({ Title="Chat Prefix", Placeholder="e.g. [AI]: ", Value=Cfg.ChatPrefix, Callback=function(v) Cfg.ChatPrefix=v; SaveCfg() end })
TabGeneral:Input({ Title="AI Language (Auto, Spanish, etc)", Placeholder="e.g. Auto, Pirate", Value=Cfg.Language or "Auto", Callback=function(v) Cfg.Language=(v~="") and v or "Auto"; SaveCfg() end })
TabGeneral:Toggle({ Title="Respond to Everyone (ignore proximity)", Value=Cfg.RespondToAll, Callback=function(v) Cfg.RespondToAll=v; SaveCfg() end })
TabGeneral:Toggle({ Title="Respond to Name Only (Mention Mode)", Value=Cfg.RespondToNameOnly, Callback=function(v) Cfg.RespondToNameOnly=v; SaveCfg() end })
TabGeneral:Toggle({ Title="Silent / Whisper Mode (Private Replies)", Value=Cfg.WhisperMode, Callback=function(v) Cfg.WhisperMode=v; SaveCfg() end })

TabGeneral:Section({ Title = "Quick Actions" })
TabGeneral:Button({ Title="Test AI (sends Hello to chat)", Callback=function()
    task.spawn(function()
        local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
        local r = CallAI("Hello there!", LP.Name, LP.UserId, nearby, true)
        if not r then SafeNotify({Title="Test Failed", Content="Check provider settings."}) end
    end)
end })
TabGeneral:Button({ Title="Introduce AI in Chat", Callback=function() task.spawn(DoIntroduce) end })
TabGeneral:Button({ Title="Export Chat Log", Callback=function()
    local ok, fn = ExportChatLog()
    SafeNotify({Title=ok and "Log Exported" or "Export Failed", Content=ok and ("Saved to "..fn) or fn})
end })

-- ─── Behavior Tab ───
local TabBehavior = Win:Tab({
    Title = "Behavior",
    Icon = "solar:settings-bold",
})

TabBehavior:Section({ Title = "Response Timing & Length" })
TabBehavior:Toggle({ Title="Think message before replying", Value=Cfg.ThinkDelay, Callback=function(v) Cfg.ThinkDelay=v; SaveCfg() end })
local lengthNames = {}
for _, lm in ipairs(LENGTH_MODES) do table.insert(lengthNames, lm.name) end
TabBehavior:Dropdown({
    Title="Response Mode", Values=lengthNames,
    Value=LENGTH_MODES[Cfg.LengthMode] and LENGTH_MODES[Cfg.LengthMode].name or "Normal",
    Multi = false,
    Callback=function(val)
        for i, lm in ipairs(LENGTH_MODES) do
            if lm.name == val then Cfg.LengthMode = i; SaveCfg(); break end
        end
    end,
})

TabBehavior:Section({ Title = "Proximity Limits" })
TabBehavior:Slider({ Title="Detection Radius", Step=5, Value={Min=5, Max=300, Default=Cfg.ProximityRadius}, Callback=function(v) Cfg.ProximityRadius=v; SaveCfg() end })
TabBehavior:Slider({ Title="Response Cooldown (per player)", Step=1, Value={Min=1, Max=60, Default=Cfg.Cooldown}, Callback=function(v) Cfg.Cooldown=v; SaveCfg() end })

TabBehavior:Section({ Title = "Auto-Greet" })
TabBehavior:Toggle({ Title="Auto-greet nearby players", Value=Cfg.AutoGreet, Callback=function(v) Cfg.AutoGreet=v; SaveCfg() end })
TabBehavior:Slider({ Title="Greet Cooldown per Player", Step=30, Value={Min=30, Max=600, Default=Cfg.AutoGreetCooldown}, Callback=function(v) Cfg.AutoGreetCooldown=v; SaveCfg() end })

TabBehavior:Section({ Title = "Advanced Options" })
TabBehavior:Slider({ Title="Max Response Tokens", Step=10, Value={Min=40, Max=500, Default=Cfg.MaxTokens}, Callback=function(v) Cfg.MaxTokens=v; SaveCfg() end })
TabBehavior:Slider({ Title="Temperature (1=precise / 20=wild)", Step=1, Value={Min=1, Max=20, Default=math.round(Cfg.Temperature*10)}, Callback=function(v) Cfg.Temperature=v/10; SaveCfg() end })
TabBehavior:Button({ Title="Clear Conversation Memory", Callback=function() History={}; SaveMemory(); SafeNotify({Title="Memory Cleared", Content="Conversation history wiped."}) end })

-- ─── Chat Tab ───
local TabChat = Win:Tab({
    Title = "Chat with AI",
    Icon = "solar:chat-line-bold",
})

TabChat:Section({ Title = "Private Conversation" })
TabChat:Paragraph({ Title="About", Content="Chat with the AI privately. Messages are NOT sent to game chat. Shares the same memory as in-game chat." })
local uiChatInput = ""
TabChat:Input({ Title="Your message", Placeholder="Say something...", Callback=function(v) uiChatInput=v end })
TabChat:Button({ Title="Send to AI (private)", Callback=function()
    local msg = uiChatInput
    if msg=="" then SafeNotify({Title="Empty", Content="Type something first.", Duration=2}) return end
    SafeNotify({Title="AI is thinking...", Content=msg:sub(1,60), Duration=3})
    task.spawn(function()
        local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
        local r = CallAI(msg, LP.Name, LP.UserId, nearby, false)
        SafeNotify({Title=r and "AI says:" or "No Response", Content=r or "Check provider settings.", Duration=12})
    end)
end })

-- ─── Personality Tab ───
local TabPersonality = Win:Tab({
    Title = "Personality",
    Icon = "solar:user-rounded-bold",
})

TabPersonality:Section({ Title = "Presets" })
local PRESET_OPTIONS = {}
for _, p in ipairs(PERSONALITIES) do if p.name ~= "Custom" then table.insert(PRESET_OPTIONS, p.emoji.." "..p.name) end end
TabPersonality:Dropdown({
    Title="Personality Preset", Values=PRESET_OPTIONS, Value=PRESET_OPTIONS[1],
    Multi = false,
    Callback=function(val)
        for _, p in ipairs(PERSONALITIES) do
            if val:find(p.name) then Cfg.SystemPrompt = p.prompt; SaveCfg()
                SafeNotify({Title="Personality Set", Content=p.name}); break
            end
        end
    end,
})

TabPersonality:Section({ Title = "Custom Prompt" })
TabPersonality:Input({
    Title="System Prompt", Placeholder="Write a custom personality...",
    Callback=function(v) if v~="" then Cfg.SystemPrompt=v; SaveCfg() end end,
})
TabPersonality:Button({ Title="Reset to Friendly Gamer default", Callback=function()
    Cfg.SystemPrompt=PERSONALITIES[1].prompt; SaveCfg()
    SafeNotify({Title="Reset Done", Content="Prompt restored to Friendly Gamer."})
end })

TabPersonality:Section({ Title = "Bot Identity" })
TabPersonality:Input({
    Title="Bot Name", Placeholder=Cfg.BotName,
    Callback=function(v) Cfg.BotName=(v~="") and v or "AIBot"; UpdateBillboard("🤖 "..Cfg.BotName); SaveCfg() end,
})

-- ─── Player Filter Tab ───
local TabFilter = Win:Tab({
    Title = "Player Filter",
    Icon = "solar:filter-bold",
})

TabFilter:Section({ Title = "Whitelist (respond ONLY to these)" })
TabFilter:Paragraph({ Title="Info", Content="If whitelist has names, the bot ONLY responds to those players. Leave empty to use blacklist instead." })
TabFilter:Input({
    Title="Add to Whitelist", Placeholder="PlayerName",
    Callback=function(v) if v~="" then table.insert(Cfg.Whitelist, v); SaveCfg(); SafeNotify({Title="Whitelisted", Content=v}) end end,
})
TabFilter:Button({ Title="Clear Whitelist", Callback=function() Cfg.Whitelist={}; SaveCfg(); SafeNotify({Title="Cleared", Content="Whitelist emptied."}) end })

TabFilter:Section({ Title = "Blacklist (ignore these players)" })
TabFilter:Input({
    Title="Add to Blacklist", Placeholder="PlayerName",
    Callback=function(v) if v~="" then table.insert(Cfg.Blacklist, v); SaveCfg(); SafeNotify({Title="Blacklisted", Content=v}) end end,
})
TabFilter:Button({ Title="Clear Blacklist", Callback=function() Cfg.Blacklist={}; SaveCfg(); SafeNotify({Title="Cleared", Content="Blacklist emptied."}) end })

-- ─── Provider Tab ───
local TabProvider = Win:Tab({
    Title = "Provider",
    Icon = "solar:server-bold",
})

TabProvider:Section({ Title = "Current Provider" })
local currentProvName = "Unknown"
for _, p in ipairs(PROVIDERS) do if p.id == Cfg.Provider then currentProvName = p.name break end end
TabProvider:Paragraph({ Title="Active Configuration", Content="Provider: "..currentProvName.."\nModel: "..Cfg.Model.."\n\nTo change provider or model, use the Rerun Setup Wizard button below." })

TabProvider:Section({ Title = "API Keys" })
local keyInputs = {
    {"OpenRouter",   "OpenRouterKey",   "sk-or-v1-..."},
    {"Google Gemini", "GeminiKey",      "AIzaSy-..."},
    {"Cerebras",     "CerebrasKey",     "csk-..."},
    {"Cohere",       "CohereKey",       "..."},
    {"Mistral",      "MistralKey",      "..."},
    {"ElectronHub",  "ElectronHubKey",  "ek-..."},
    {"Zanity",       "ZanityKey",       "..."},
    {"OpenCode Zen", "ZenKey",          "Get from opencode.ai/auth"},
    {"Groq",         "GroqKey",         "gsk_..."},
    {"SambaNova",    "SambaNovaKey",    "..."},
    {"Together AI",  "TogetherKey",     "..."},
    {"HuggingFace",  "HuggingFaceKey",  "hf_..."},
    {"DeepInfra",    "DeepInfraKey",    "..."},
    {"GitHub Models","GithubKey",       "ghp_..."},
    {"NVIDIA NIM",   "NvidiaKey",       "nvapi-..."},
    {"Glhf.chat",    "GlhfKey",         "glhf_..."},
    {"Hyperbolic",   "HyperbolicKey",   "..."},
    {"Novita AI",    "NovitaKey",       "..."},
    {"AI21 Labs",    "AI21Key",         "..."},
    {"Kite API",     "KiteKey",         "..."},
    {"Venice AI",    "VeniceKey",       "..."},
}
for _, ki in ipairs(keyInputs) do
    local displayName, cfgKey, placeholder = ki[1], ki[2], ki[3]
    local defaultVal = "YOUR_"..cfgKey:upper()
    if defaultVal:sub(1,5) ~= "YOUR_" then defaultVal = "YOUR_"..cfgKey end
    TabProvider:Input({
        Title=displayName.." Key",
        Placeholder=(Cfg[cfgKey] and Cfg[cfgKey] ~= defaultVal and Cfg[cfgKey]:sub(1,4) ~= "YOUR") and "Saved ✓ re-enter to update" or placeholder,
        Callback=function(v) if v~="" then Cfg[cfgKey]=v; SaveCfg() end end,
    })
end

TabProvider:Section({ Title = "System" })
TabProvider:Button({ Title="🔄 Rerun Setup Wizard", Callback=function()
    Cfg.SetupComplete = false; SaveCfg()
    SafeNotify({Title="Setup Reset", Content="The Setup Wizard will now appear. Re-execute the script if it doesn't."})
    task.delay(1, function()
        pcall(function() Win:Destroy() end)
        for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
        Connections = {}
        if billboardGui then pcall(function() billboardGui:Destroy() end) billboardGui = nil end
        SafeNotify({Title="Ready", Content="Please re-execute the script to start the wizard."})
    end)
end })

TabProvider:Button({ Title="❌ Unload Bot", Callback=function()
    Cfg.Enabled = false; SaveCfg()
    for _, conn in ipairs(Connections) do pcall(function() conn:Disconnect() end) end
    Connections = {}
    History = {}; MsgQueue = {}; ProcessingMsg = false; PlayerCooldowns = {}
    if billboardGui then pcall(function() billboardGui:Destroy() end) billboardGui = nil end
    pcall(function() Win:Destroy() end)
    warn("[AI Bot] Fully unloaded.")
end })

-- ─── Emotes Tab ───
local TabEmotes = Win:Tab({
    Title = "Emotes",
    Icon = "solar:clapperboard-play-bold",
})

TabEmotes:Section({ Title = "Manual Triggers" })
TabEmotes:Paragraph({ Title="AI Emote Tags", Content="The AI can include tags in its replies that trigger animations. Tags are stripped from chat before sending." })
TabEmotes:Section({ Title = "Play Emote" })
local emoteList = {{"Wave","WAVE"},{"Dance 1","DANCE"},{"Dance 2","DANCE2"},{"Dance 3","DANCE3"},{"Laugh","LAUGH"},{"Point","POINT"},{"Cheer","CHEER"}}
for _, e in ipairs(emoteList) do
    TabEmotes:Button({ Title=e[1], Callback=function() PlayEmote(e[2]) end })
end
TabEmotes:Section({ Title = "Tag Reference" })
TabEmotes:Paragraph({ Title="Available Tags", Content="[WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]" })
-- ═══════════════════════════════════════
-- INIT
-- ═══════════════════════════════════════

UpdateBillboard(Cfg.Enabled and "🤖 "..Cfg.BotName or "💤 Disabled")

task.spawn(function()
    task.wait(1.5)
    SafeNotify({
        Title = "AI Chat Bot v"..VERSION.." Ready",
        Content = "Provider: "..(PROVIDER_LABELS[Cfg.Provider] or Cfg.Provider).."\n"..(Cfg.Enabled and "Bot is enabled." or "Bot is disabled.").."\n"..#PROVIDERS.." providers available.",
        Duration = 6,
    })
end)

warn("[AI Bot v"..VERSION.."] Loaded. Provider: "..Cfg.Provider.." | Model: "..Cfg.Model)
