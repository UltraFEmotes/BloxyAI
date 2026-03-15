local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players     = game:GetService("Players")
local TCS         = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer

local Cfg = {
    ApiKey          = "YOUR_OPENROUTER_API_KEY",
    Model           = "openrouter/healer-alpha",
    SystemPrompt    = [[You are a fun, witty Roblox player taking part in the game world around you. Keep every reply SHORT (1-2 sentences). Be playful and react naturally to what players say. You may optionally include ONE emote tag from this list at the end of your reply: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. Do NOT explain your reasoning. Do NOT include any internal thoughts, planning, or <think> blocks. Just reply directly. Be aware that Roblox has a chat filter — if you are told a previous message was filtered, use that context to choose cleaner words going forward.]],
    BotName         = "AIBot",
    ProximityRadius = 30,
    Cooldown        = 4,
    MaxTokens       = 120,
    Temperature     = 0.85,
    Enabled         = true,
    RespondToAll    = false,
    ThinkDelay      = false,
}

local History      = {}
local LastReply    = 0
local LastSentMsg  = ""

local EMOTES = {
    WAVE   = "rbxassetid://507770239",
    DANCE  = "rbxassetid://507771019",
    DANCE2 = "rbxassetid://507776043",
    DANCE3 = "rbxassetid://507776048",
    LAUGH  = "rbxassetid://507770818",
    POINT  = "rbxassetid://507770453",
    CHEER  = "rbxassetid://507770677",
}

local function DoRequest(url, method, headers, body)
    local fn = request or (syn and syn.request) or http_request or (http and http.request)
    if not fn then
        warn("No http methods")
        return nil
    end
    local ok, res = pcall(fn, {
        Url     = url,
        Method  = method or "GET",
        Headers = headers or {},
        Body    = body,
    })
    if not ok then
        warn("Request error: " .. tostring(res))
        return nil
    end
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
    local actions = {}
    local text = raw

    text = text:gsub("<think>.-</think>", "")
    text = text:gsub("<thinking>.-</thinking>", "")

    for name in pairs(EMOTES) do
        if text:find("%[" .. name .. "%]") then
            table.insert(actions, name)
            text = text:gsub("%[" .. name .. "%]", "")
        end
    end
    text = text:match("^%s*(.-)%s*$") or text
    text = text:gsub("%s+", " ")
    return text, actions
end

local function IsFiltered(text)
    if not text or #text == 0 then return false end
    return text:match("^[#%s]+$") ~= nil
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
                    table.insert(result, {
                        username    = p.Name,
                        displayName = p.DisplayName,
                        distance    = math.round(dist),
                    })
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

local function GetGeneralChannel()
    local channels = TCS:FindFirstChild("TextChannels")
    return (channels and channels:FindFirstChild("RBXGeneral"))
        or TCS:FindFirstChild("RBXGeneral")
end

local function SendChat(msg)
    if #msg > 200 then msg = msg:sub(1, 197) .. "..." end
    local ok, err = pcall(function()
        local ch = GetGeneralChannel()
        if ch then
            LastSentMsg = msg
            ch:SendAsync(msg)
        else
            warn("[AI Bot] Could not find RBXGeneral channel.")
        end
    end)
    if not ok then warn("[AI Bot] SendChat failed: " .. tostring(err)) end
end

local MAX_RETRIES = 3
local RETRY_DELAY = 2

local ERROR_HINTS = {
    [400] = "Bad request — model may not support this input.",
    [401] = "Invalid API key — check the Personality tab.",
    [402] = "Payment issue — check your OpenRouter account.",
    [403] = "Forbidden — key may not have access to this model.",
    [429] = "Rate limit hit — increase cooldown or wait.",
    [500] = "Model overloaded — will retry automatically.",
    [502] = "Gateway error — model host is down.",
    [503] = "Model unavailable — may be offline.",
}

local function BuildMessages(userMsg, nearby, extraSystemNote)
    local ctx = {
        "\n\n--- GAME CONTEXT ---",
        "Bot name: " .. Cfg.BotName,
        "Your Roblox username: " .. LP.Name
            .. (LP.DisplayName ~= LP.Name and (" (display name: " .. LP.DisplayName .. ")") or ""),
    }

    if #nearby > 0 then
        local nearStr = {}
        for _, p in ipairs(nearby) do
            table.insert(nearStr, string.format("%s (@%s) — %d studs away",
                p.displayName, p.username, p.distance))
        end
        table.insert(ctx, "Nearby players: " .. table.concat(nearStr, ", "))
    else
        table.insert(ctx, "No other players are nearby right now.")
    end

    table.insert(ctx, "--- END CONTEXT ---")

    if extraSystemNote then
        table.insert(ctx, "\n[SYSTEM NOTE]: " .. extraSystemNote)
    end

    table.insert(ctx, "Reply ONLY with your chat message. No reasoning. No thinking out loud.")

    local fullSystem = Cfg.SystemPrompt .. table.concat(ctx, "\n")

    local messages = {{role = "system", content = fullSystem}}
    for _, h in ipairs(History) do
        table.insert(messages, h)
    end
    table.insert(messages, {role = "user", content = userMsg})
    return messages
end

local function RawCallAPI(messages)
    local bodyTbl = {
        model       = Cfg.Model,
        messages    = messages,
        max_tokens  = Cfg.MaxTokens,
        temperature = Cfg.Temperature,
        stream      = false,
    }

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. Cfg.ApiKey,
        ["HTTP-Referer"]  = "https://roblox.com",
        ["X-Title"]       = "Roblox AI Chat Bot",
    }

    local res
    for attempt = 1, MAX_RETRIES do
        res = DoRequest(
            "https://openrouter.ai/api/v1/chat/completions",
            "POST",
            headers,
            HttpService:JSONEncode(bodyTbl)
        )

        if not res then
            warn(string.format("[AI Bot] Attempt %d/%d — no HTTP response.", attempt, MAX_RETRIES))
        elseif res.StatusCode == 200 then
            break
        else
            local hint = ERROR_HINTS[res.StatusCode] or ("HTTP " .. res.StatusCode)
            local detail = tostring(res.Body or ""):sub(1, 150)
            local ok2, errData = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
            if ok2 and errData and errData.error and errData.error.message then
                detail = errData.error.message
            end
            warn(string.format("[AI Bot] Attempt %d/%d — %s | %s", attempt, MAX_RETRIES, hint, detail))

            if res.StatusCode == 429 then
                Rayfield:Notify({Title = "Rate Limited", Content = "Too many requests — try raising the cooldown.", Duration = 5})
                return nil
            elseif res.StatusCode < 500 then
                Rayfield:Notify({Title = "API Error " .. res.StatusCode, Content = hint, Duration = 5})
                return nil
            end

            if attempt < MAX_RETRIES then
                task.wait(RETRY_DELAY)
            else
                Rayfield:Notify({Title = "Model Unavailable", Content = "Got " .. res.StatusCode .. " after " .. MAX_RETRIES .. " attempts.", Duration = 5})
                return nil
            end
        end
    end

    if not res or res.StatusCode ~= 200 then return nil end

    local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    if not ok or not data then
        warn("[AI Bot] JSON decode failed.")
        return nil
    end

    return data.choices
        and data.choices[1]
        and data.choices[1].message
        and data.choices[1].message.content
end

local function CallAI(userLine, senderName, nearby, sendToChat)
    if Cfg.ApiKey == "YOUR_OPENROUTER_API_KEY" or Cfg.ApiKey == "" then
        Rayfield:Notify({Title = "No API Key", Content = "Paste your OpenRouter key in the Personality tab.", Duration = 5})
        warn("[AI Bot] API key not set!")
        return nil
    end

    local userMsg = string.format("[%s]: %s", senderName, userLine)

    if sendToChat and Cfg.ThinkDelay then
        SendChat("Gimme a bit to think...")
        task.wait(0.3)
    end

    local messages = BuildMessages(userMsg, nearby)
    local content  = RawCallAPI(messages)
    if not content then return nil end

    local clean, actions = ParseAIText(content)

    table.insert(History, {role = "user",      content = userMsg})
    table.insert(History, {role = "assistant", content = content})
    while #History > 20 do table.remove(History, 1) end

    if sendToChat then

        for _, a in ipairs(actions) do
            PlayEmote(a)
            task.wait(0.1)
        end
        if clean ~= "" then
            SendChat(clean)
        end
    end

    return clean
end

TCS.MessageReceived:Connect(function(msg)
    local src = msg.TextSource
    if not src then return end
    if src.UserId ~= LP.UserId then return end

    if IsFiltered(msg.Text) and LastSentMsg ~= "" then
        warn("[AI Bot] Last message was filtered: " .. LastSentMsg)

        Rayfield:Notify({
            Title   = "⚠️ Message Filtered",
            Content = "Roblox filtered that reply.\nThe AI has been notified and will keep it in mind.",
            Duration = 5,
        })

        local note = string.format(
            "[SYSTEM]: Your last message was blocked by Roblox's chat filter and appeared as ####. "
            .. "The original text was: \"%s\". "
            .. "Keep this in mind — if you need to say something similar again, use different simpler words.",
            LastSentMsg
        )
        table.insert(History, {role = "user",      content = note})
        table.insert(History, {role = "assistant", content = "Understood, my last message got filtered. I'll be more careful with my wording."})
        while #History > 20 do table.remove(History, 1) end

        LastSentMsg = ""
    end
end)

TCS.MessageReceived:Connect(function(msg)
    if not Cfg.Enabled then return end
    local src = msg.TextSource
    if not src then return end
    local sender = Players:GetPlayerByUserId(src.UserId)
    if not sender or sender == LP then return end

    local now = tick()
    if now - LastReply < Cfg.Cooldown then return end
    if not Cfg.RespondToAll and not IsNearby(sender, Cfg.ProximityRadius) then return end

    local text = msg.Text
    if not text or text == "" or IsFiltered(text) then return end

    LastReply = now

    task.spawn(function()
        local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
        CallAI(text, sender.Name, nearby, true)
    end)
end)

local Win = Rayfield:CreateWindow({
    Name                  = "BloxyAI",
    LoadingTitle          = "Universal AI Chatbot",
    LoadingSubtitle       = "by Miiself (Originally White Cat)",
    Theme                 = "DarkBlue",
    DisableRayfieldPrompts  = false,
    DisableBuildWarnings    = false,
    ConfigurationSaving   = {Enabled = false},
    KeySystem             = false,
})

local TabMain = Win:CreateTab("Controls", 4483362458)

TabMain:CreateSection("Bot Status")

TabMain:CreateToggle({
    Name         = "Enable AI Chat Bot",
    CurrentValue = Cfg.Enabled,
    Flag         = "Enabled",
    Callback     = function(v) Cfg.Enabled = v end,
})

TabMain:CreateToggle({
    Name         = "Respond to Everyone  (ignore proximity)",
    CurrentValue = Cfg.RespondToAll,
    Flag         = "RespondAll",
    Callback     = function(v) Cfg.RespondToAll = v end,
})

TabMain:CreateToggle({
    Name         = "Say 'Gimme a bit to think' before responding",
    CurrentValue = Cfg.ThinkDelay,
    Flag         = "ThinkDelay",
    Callback     = function(v) Cfg.ThinkDelay = v end,
})

TabMain:CreateSection("Proximity & Timing")

TabMain:CreateSlider({
    Name         = "Detection Radius",
    Range        = {5, 300},
    Increment    = 5,
    Suffix       = " studs",
    CurrentValue = Cfg.ProximityRadius,
    Flag         = "Radius",
    Callback     = function(v) Cfg.ProximityRadius = v end,
})

TabMain:CreateSlider({
    Name         = "Response Cooldown",
    Range        = {1, 60},
    Increment    = 1,
    Suffix       = " sec",
    CurrentValue = Cfg.Cooldown,
    Flag         = "Cooldown",
    Callback     = function(v) Cfg.Cooldown = v end,
})

TabMain:CreateSlider({
    Name         = "Max Response Tokens",
    Range        = {40, 400},
    Increment    = 10,
    Suffix       = " tokens",
    CurrentValue = Cfg.MaxTokens,
    Flag         = "MaxTok",
    Callback     = function(v) Cfg.MaxTokens = v end,
})

TabMain:CreateSlider({
    Name         = "Temperature  (1 = precise · 20 = wild)",
    Range        = {1, 20},
    Increment    = 1,
    CurrentValue = math.round(Cfg.Temperature * 10),
    Flag         = "Temp",
    Callback     = function(v) Cfg.Temperature = v / 10 end,
})

TabMain:CreateSection("Actions")

TabMain:CreateButton({
    Name     = "🗑  Clear Conversation Memory",
    Callback = function()
        History = {}
        Rayfield:Notify({Title = "Memory Cleared", Content = "AI conversation history wiped.", Duration = 3})
    end,
})

TabMain:CreateButton({
    Name     = "🧪  Test AI  (sends 'Hello!' to chat)",
    Callback = function()
        task.spawn(function()
            local nearby = GetNearbyPlayers(Cfg.ProximityRadius)
            local result = CallAI("Hello there!", LP.Name, nearby, true)
            if not result then
                Rayfield:Notify({Title = "Test Failed", Content = "Check your API key in the Personality tab.", Duration = 4})
            end
        end)
    end,
})

TabMain:CreateButton({
    Name     = "Introduce AI in Chat",
    Callback = function()
        task.spawn(function()
            if Cfg.ApiKey == "YOUR_OPENROUTER_API_KEY" or Cfg.ApiKey == "" then
                Rayfield:Notify({Title = "No API Key", Content = "Paste your OpenRouter key in the Personality tab.", Duration = 5})
                return
            end

            local introPrompt = string.format(
                "Introduce yourself as %s in 20 characters or less. No punctuation at the end. Just the intro, nothing else.",
                Cfg.BotName
            )

            local messages = {
                {role = "system", content = "You are " .. Cfg.BotName .. ". Reply with ONLY a self-introduction that is 20 characters or fewer. Count every letter, space and punctuation mark. Do not exceed 20 characters under any circumstance."},
                {role = "user",   content = introPrompt},
            }

            local bodyTbl = {
                model       = Cfg.Model,
                messages    = messages,
                max_tokens  = 20,
                temperature = 0.7,
                stream      = false,
            }

            local headers = {
                ["Content-Type"]  = "application/json",
                ["Authorization"] = "Bearer " .. Cfg.ApiKey,
                ["HTTP-Referer"]  = "https://roblox.com",
                ["X-Title"]       = "Roblox AI Chat Bot",
            }

            local res = DoRequest(
                "https://openrouter.ai/api/v1/chat/completions",
                "POST",
                headers,
                HttpService:JSONEncode(bodyTbl)
            )

            if not res or res.StatusCode ~= 200 then
                Rayfield:Notify({Title = "Introduce Failed", Content = "API error. Check your key.", Duration = 4})
                return
            end

            local ok, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
            if not ok or not data then return end

            local content = data.choices
                and data.choices[1]
                and data.choices[1].message
                and data.choices[1].message.content

            if not content or content == "" then return end

            content = content:gsub("<think>.-</think>", "")
            content = content:gsub('^"(.-)"$', "%1")
            content = content:match("^%s*(.-)%s*$") or content

            if #content > 20 then
                content = content:sub(1, 20)
            end

            SendChat(content)
        end)
    end,
})

local TabChat = Win:CreateTab("Chat with AI", 4483362458)

TabChat:CreateSection("Private Conversation")

TabChat:CreateParagraph({
    Title   = "About this tab",
    Content = "Type anything here to talk to the AI privately. Your message will NOT be sent to the game chat — only you will see the response, shown as a notification.",
})

local uiChatInput = ""

TabChat:CreateInput({
    Name                     = "Your message",
    PlaceholderText          = "Say something to the AI...",
    RemoveTextAfterFocusLost = false,
    Flag                     = "UIChatInput",
    Callback                 = function(v)
        uiChatInput = v
    end,
})

TabChat:CreateButton({
    Name     = "Send to AI  (private, no game chat)",
    Callback = function()
        local msg = uiChatInput
        if msg == "" then
            Rayfield:Notify({Title = "Empty Message", Content = "Type something first!", Duration = 2})
            return
        end

        Rayfield:Notify({Title = "AI is thinking...", Content = "\"" .. msg:sub(1, 60) .. "\"", Duration = 3})

        task.spawn(function()
            local nearby = GetNearbyPlayers(Cfg.ProximityRadius)

            local result = CallAI(msg, LP.Name, nearby, false)
            if result then

                Rayfield:Notify({
                    Title    = "AI says:",
                    Content  = result,
                    Duration = 12,
                })
            else
                Rayfield:Notify({
                    Title   = "No Response",
                    Content = "The AI didn't reply. Check your API key.",
                    Duration = 5,
                })
            end
        end)
    end,
})

TabChat:CreateSection("Notes")
TabChat:CreateParagraph({
    Title   = "Shared memory",
    Content = "Messages sent from this tab are added to the same conversation history as in-game chat, so the AI will remember the context across both.",
})

local TabPers = Win:CreateTab("Personality", 4483362458)

TabPers:CreateSection("OpenRouter API Key")

TabPers:CreateParagraph({
    Title   = "How to get a OpenRouter Key",
    Content = "1. Go to openrouter.ai\n2. Sign up with just an email\n3. Dashboard → Keys → Create Key\n4. Paste it below",
})

TabPers:CreateInput({
    Name                     = "OpenRouter API Key",
    PlaceholderText          = "sk-or-v1-xxxxxxxxxxxxxxxxxxxx",
    RemoveTextAfterFocusLost = false,
    Flag                     = "ApiKey",
    Callback                 = function(v)
        if v ~= "" then Cfg.ApiKey = v end
    end,
})

TabPers:CreateInput({
    Name                     = "Bot Name",
    PlaceholderText          = "AIBot",
    RemoveTextAfterFocusLost = false,
    Flag                     = "BotName",
    Callback                 = function(v)
        Cfg.BotName = (v ~= "") and v or "AIBot"
    end,
})

TabPers:CreateSection("System Prompt  (AI Personality)")

TabPers:CreateInput({
    Name                     = "System Prompt",
    PlaceholderText          = "You are a friendly Roblox player...",
    RemoveTextAfterFocusLost = false,
    Flag                     = "SysPrompt",
    Callback                 = function(v)
        if v ~= "" then Cfg.SystemPrompt = v end
    end,
})

TabPers:CreateButton({
    Name     = "↺ Reset to Default Prompt",
    Callback = function()
        Cfg.SystemPrompt = [[You are a fun, witty Roblox player taking part in the game world around you. Keep every reply SHORT (1-2 sentences). Be playful and react naturally to what players say. You may optionally include ONE emote tag from this list at the end of your reply: [WAVE] [DANCE] [DANCE2] [DANCE3] [LAUGH] [POINT] [CHEER]. Do NOT explain your reasoning. Do NOT include any internal thoughts, planning, or <think> blocks. Just reply directly. Be aware that Roblox has a chat filter — if you are told a previous message was filtered, use that context to choose cleaner words going forward.]]
        Rayfield:Notify({Title = "Reset Done", Content = "System prompt restored to default.", Duration = 3})
    end,
})

local TabEmotes = Win:CreateTab("Emotes", 4483362458)

TabEmotes:CreateSection("Manual Triggers")
TabEmotes:CreateParagraph({
    Title   = "About AI Emotes",
    Content = "The AI includes tags like [DANCE] or [LAUGH] in its game chat replies. They are stripped from the sent message and played as animations on your character automatically.",
})

TabEmotes:CreateSection("Play Emote")
local emoteList = {
    {"Wave",    "WAVE"},
    {"Dance 1", "DANCE"},
    {"Dance 2", "DANCE2"},
    {"Dance 3", "DANCE3"},
    {"Laugh",   "LAUGH"},
    {"Point",   "POINT"},
    {"Cheer",   "CHEER"},
}
for _, e in ipairs(emoteList) do
    local label, id = e[1], e[2]
    TabEmotes:CreateButton({
        Name     = label,
        Callback = function() PlayEmote(id) end,
    })
end

TabEmotes:CreateSection("Tag Reference")
TabEmotes:CreateParagraph({
    Title   = "Tags the AI can use in replies",
    Content = "[WAVE]  [DANCE]  [DANCE2]  [DANCE3]\n[LAUGH]  [POINT]  [CHEER]",
})

Rayfield:Notify({
    Title    = "BloxyAI Bot Loaded",
    Content  = "Paste your OpenRouter API key in the Personality tab to get started!",
    Duration = 7,
})
