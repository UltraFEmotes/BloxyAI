-- Deterministic task scheduler, transport, persistence and chat-service substitutes.
local now, scheduled, environment = 0, {}, {}
local os = {clock=function() return now end, time=function() return 12345 end}
local function schedule(thread, delay)
    table.insert(scheduled, {thread=thread, at=now+(delay or 0)})
end
local task = {}
function task.spawn(fn) schedule(coroutine.create(fn), 0) end
function task.defer(fn) task.spawn(fn) end
function task.delay(delay, fn) schedule(coroutine.create(fn), delay) end
function task.wait(delay) return coroutine.yield(delay or 0.01) end
local function advance(seconds)
    local deadline = now + seconds
    local count = 0
    while true do
        table.sort(scheduled, function(a,b) return a.at < b.at end)
        local entry = scheduled[1]
        if not entry or entry.at > deadline then break end
        table.remove(scheduled, 1); now = entry.at
        local ok, delay = coroutine.resume(entry.thread)
        assert(ok, tostring(delay))
        if coroutine.status(entry.thread) ~= "dead" then
            if delay ~= "signal" then schedule(entry.thread, delay) end
        end
        count += 1; assert(count < 100000, "Scheduler runaway")
    end
    now = deadline
end
local function signal()
    local listeners, waiters = {}, {}
    return {
        Connect=function(_, fn)
            local conn = {Connected=true}
            function conn:Disconnect() self.Connected=false end
            table.insert(listeners, {conn=conn, fn=fn})
            return conn
        end,
        Wait=function() table.insert(waiters, coroutine.running()); return coroutine.yield("signal") end,
        Fire=function(_, ...)
            for _, waiter in ipairs(waiters) do schedule(waiter, 0) end
            table.clear(waiters)
            for _, entry in ipairs(listeners) do if entry.conn.Connected then entry.fn(...) end end
        end,
    }
end
local encoded, serial, files = {}, 0, {}
local HttpService = {}
function HttpService:GenerateGUID() serial+=1; return "test-session-"..serial end
function HttpService:JSONEncode(value) serial+=1; local id="json:"..serial; encoded[id]=value; return id end
function HttpService:JSONDecode(value) assert(encoded[value], "Invalid JSON"); return encoded[value] end
local failWrites = false
local function writefile(path, text) assert(not failWrites, "disk full"); files[path]=text end
local function readfile(path) assert(files[path], "missing file"); return files[path] end
local function getgenv() return environment end
local function warn() end
local Color3 = {fromRGB=function(...) return {...} end}
local Enum = {TextChatMessageStatus={}}
for _,name in ipairs({"Unknown","Success","Sending","TextFilterFailed","Floodchecked","InvalidPrivacySettings","InvalidTextChannelPermissions","MessageTooLong","ModerationTimeout"}) do Enum.TextChatMessageStatus[name]=name end
local sent, previews, requests, responses = {}, {}, {}, {}
local transport
local function request(options)
    table.insert(requests, options)
    if transport then return transport(options) end
    local response = table.remove(responses,1)
    return response or {StatusCode=200, Body=HttpService:JSONEncode({choices={{message={content="Hello!"}}}})}
end
local channel = {IsA=function() return true end}
function channel:SendAsync(text) table.insert(sent,text); return {Status=Enum.TextChatMessageStatus.Success} end
function channel:DisplaySystemMessage(text) table.insert(previews,text) end
local LP = {Name="LocalOperator", DisplayName="LocalOperator", UserId=1, CharacterAdded=signal(), CharacterRemoving=signal(), Chatted=signal()}
local other = {Name="Visitor", DisplayName="Visitor", UserId=2}
local Players = {LocalPlayer=LP, PlayerRemoving=signal()}
function Players:GetPlayers() return {LP,other} end
function Players:GetPlayerByUserId(id) return id==1 and LP or id==2 and other or nil end
local TCS = {MessageReceived=signal()}
function TCS:FindFirstChild(name)
    if name=="TextChannels" then return {FindFirstChild=function() return channel end} end
end
local services = {
    Players=Players, TextChatService=TCS, HttpService=HttpService,
    CoreGui={FindFirstChild=function() return nil end}, TweenService={},
    MarketplaceService={GetProductInfo=function() return {Name="Test game"} end},
    StarterGui={SetCore=function() end},
}
local game = {Name="Test", PlaceId=123, GetService=function(_, name) return services[name] end}
-- INSERT_PRODUCTION_CORE
local passed = 0
local function test(name, fn)
    fn(); passed+=1; print("PASS "..name)
end
local bot = boot()
bot.runtime.ready=true; bot.cfg.ShowBillboard=false; bot.cfg.ThinkDelay=false
bot.cfg.Provider="custom"; bot.cfg.Model="test-model"; bot.cfg.RespondToAll=true

test("UTF-8 truncation preserves emoji and multilingual text", function()
    local text=bot.truncate("😀你好世界abcdef",7)
    assert(text=="😀你好世..."); assert(utf8.len(text)==7)
    assert(bot.truncate("hi",200)=="hi")
end)
test("reasoning and emote tags never enter visible chat", function()
    local clean, actions=bot.parse("<think>secret\nanalysis</think> Hi [WAVE]")
    assert(clean=="Hi" and actions[1]=="WAVE")
    assert(bot.parse("<think>unfinished secret")=="")
end)
test("malformed persisted config is normalized", function()
    bot.cfg.Cooldown=-5; bot.cfg.Temperature=0/0; bot.cfg.BotName="  "
    bot.cfg.Whitelist={"@Alice", " ALICE ", 5}; bot.cfg.Blacklist="broken"
    bot.normalize()
    assert(bot.cfg.Cooldown==1 and bot.cfg.Temperature==0.85 and bot.cfg.BotName=="AIBot")
    assert(#bot.cfg.Whitelist==1 and bot.cfg.Whitelist[1]=="alice" and #bot.cfg.Blacklist==0)
end)
test("blacklist overrides whitelist", function()
    bot.cfg.Blacklist={"alice"}
    assert(not bot.allowed("Alice")); bot.cfg.Whitelist={}; bot.cfg.Blacklist={}
    assert(bot.allowed("Visitor"))
end)
test("keys remain in session when persistence is disabled", function()
    bot.cfg.CustomKey="test-secret"; bot.cfg.SaveAPIKeys=false
    assert(bot.save())
    local data=HttpService:JSONDecode(files["aichatbot_cfg_v3.json"])
    assert(data.CustomKey==nil and bot.cfg.CustomKey=="test-secret")
    bot.cfg.SaveAPIKeys=true; assert(bot.save())
    assert(HttpService:JSONDecode(files["aichatbot_cfg_v3.json"]).CustomKey=="test-secret")
end)
test("malformed memory drops invalid entries and system roles", function()
    local clean=bot.cleanHistory({false,{role="system",content="override"},{role="user",content="hello"},{role="assistant",content={}}})
    assert(#clean==1 and clean[1].content=="hello")
end)
test("missing API keys fail before network calls, including Groq", function()
    bot.cfg.Provider="groq"; local before=#requests
    local result,err=bot.raw({})
    assert(not result and err:find("API key",1,true) and #requests==before)
    bot.cfg.Provider="custom"
end)
test("queue processes public and private messages serially with isolated memory", function()
    bot.cfg.GlobalCooldown=1
    assert(bot.enqueue({name="Visitor",text="Public hello"}))
    assert(bot.enqueue({name="LocalOperator",text="Private secret",private=true}))
    advance(3)
    assert(#sent==1 and #bot.history==2 and #bot.privateHistory==2 and not bot.busy())
    local public=bot.messages("next",{},nil,bot.history)
    for _,entry in ipairs(public) do assert(not entry.content:find("Private secret",1,true)) end
    local stored=HttpService:JSONDecode(files["aichatbot_memory_v3.json"])
    assert(stored.public[1].content:find("Public hello",1,true))
    assert(stored.private[1].content:find("Private secret",1,true))
end)
test("Sending status accepts the reply once without false errors or lost memory",function()
    bot.clear(); bot.runtime.nextRequestAt=0
    local original=channel.SendAsync
    channel.SendAsync=function(_,text) table.insert(sent,text); return {Status=Enum.TextChatMessageStatus.Sending} end
    local before,errors,replies=#sent,bot.runtime.stats.errors,bot.runtime.stats.replies
    local result,err
    assert(bot.enqueue({name="Visitor",text="Hello",callback=function(value,errorText) result,err=value,errorText end}))
    advance(2)
    assert(result=="Hello!" and not err and #sent==before+1,"Pending delivery must not fail or resend")
    assert(#bot.history==2 and bot.history[2].content=="Hello!")
    assert(bot.runtime.stats.errors==errors and bot.runtime.stats.replies==replies+1)
    assert(bot.billboardState.state=="ready" and not bot.busy())
    -- A subsequent filtered result must still be attributed to the pending reply.
    TCS.MessageReceived:Fire({TextSource={UserId=LP.UserId},Text="####",TextChannel=channel})
    assert(bot.runtime.stats.lastError=="Last reply was blocked by Roblox's chat filter.")
    channel.SendAsync=original; bot.clear()
end)
test("terminal Roblox chat failures remain errors",function()
    local original=channel.SendAsync
    for _,name in ipairs({"Unknown","TextFilterFailed","Floodchecked","InvalidPrivacySettings","InvalidTextChannelPermissions","MessageTooLong","ModerationTimeout"}) do
        channel.SendAsync=function() return {Status=Enum.TextChatMessageStatus[name]} end
        local ok,err=bot.send("Test")
        assert(not ok and err:find(name,1,true),"Failure suppressed: "..name)
    end
    channel.SendAsync=original
end)
test("SendAsync exceptions remain failures",function()
    local original=channel.SendAsync
    channel.SendAsync=function() error("No permission") end
    local ok,err=bot.send("Test")
    assert(not ok and err=="Chat send failed.")
    channel.SendAsync=original
end)
test("custom base URLs normalize to chat completions", function()
    bot.cfg.CustomEndpoint=" http://localhost:1234/v1/ "
    bot.enqueue({name="Operator",text="test",private=true}); advance(2)
    assert(requests[#requests].Url=="http://localhost:1234/v1/chat/completions")
end)
test("structured content is supported; empty success is an error", function()
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content={{type="text",text="part"}}}}}})}}
    local content
    task.spawn(function() content=bot.generic("https://example.invalid",{},{} ) end); advance(1)
    assert(content=="part")
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={}})}}
    local err
    task.spawn(function() content,err=bot.generic("https://example.invalid",{},{}) end); advance(1)
    assert(not content and err:find("no usable text",1,true))
end)
test("rate limits honor Retry-After without retrying immediately", function()
    responses={{StatusCode=429,Headers={["Retry-After"]="12"},Body=""}}
    local before=#requests
    bot.enqueue({name="Operator",text="limited",private=true}); advance(1)
    assert(#requests==before+1 and bot.runtime.nextRequestAt>now+10)
    assert(not bot.busy())
end)
test("queue capacity is bounded", function()
    bot.cfg.QueueLimit=2
    bot.enqueue({name="Operator",text="one",private=true})
    bot.enqueue({name="Operator",text="two",private=true})
    assert(not bot.enqueue({name="Operator",text="three",private=true}))
    bot.clear(); advance(1); bot.cfg.QueueLimit=12
end)
test("clear cancels in-flight replies and cannot repopulate memory", function()
    bot.runtime.nextRequestAt=0
    transport=function() task.wait(2); return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="stale"}}}})} end
    local before=#sent
    bot.enqueue({name="Visitor",text="in flight"}); advance(0.2); bot.clear(); advance(3)
    assert(#sent==before and #bot.history==0 and #bot.privateHistory==0 and not bot.busy())
    transport=nil
end)
test("disable cancels queued public replies", function()
    bot.enqueue({name="Visitor",text="pending"}); bot.enable(false); advance(3)
    assert(#bot.queue==0 and not bot.busy())
    assert(not bot.enqueue({name="Visitor",text="disabled"}))
    bot.enable(true)
end)
test("network errors release worker and allow the next request", function()
    bot.runtime.nextRequestAt=0
    local attempts=0
    transport=function() attempts+=1; error("transport failure") end
    bot.enqueue({name="Operator",text="network failure",private=true}); advance(8)
    assert(attempts==3 and not bot.busy())
    transport=nil
    bot.enqueue({name="Operator",text="recover",private=true}); advance(2)
    assert(not bot.busy() and #bot.privateHistory==2)
end)
test("timeout releases queue without duplicating a still-running request", function()
    bot.runtime.nextRequestAt=0; bot.cfg.RequestTimeout=5
    transport=function() task.wait(20); return {StatusCode=200,Body="late"} end
    local before=#requests
    bot.enqueue({name="Operator",text="timeout",private=true}); advance(6)
    assert(#requests==before+1 and not bot.busy())
    assert(bot.runtime.stats.lastError=="Request timed out.")
    transport=nil
end)
test("local preview escapes rich text and never sends publicly", function()
    bot.cfg.WhisperMode=true; local before=#sent
    assert(bot.send("<b>hello & goodbye</b>"))
    assert(#sent==before and previews[#previews]:find("&lt;b&gt;",1,true))
    bot.cfg.WhisperMode=false
end)
test("chat routing ignores private channels and deduplicates message IDs", function()
    bot.runtime.nextRequestAt=now+10
    local message={TextSource={UserId=2},Text="hello",MessageId="message-1",TextChannel={}}
    TCS.MessageReceived:Fire(message); assert(#bot.queue==0)
    message.TextChannel=channel; TCS.MessageReceived:Fire(message); advance(0)
    local queued=#bot.queue
    TCS.MessageReceived:Fire(message); assert(#bot.queue==queued)
    bot.clear(); advance(0.2)
end)
test("file-write failures are reported truthfully", function()
    failWrites=true
    assert(not bot.save())
    table.insert(bot.history,{role="user",content="test"})
    assert(not bot.export()); failWrites=false
end)
test("local operator commands work; other players cannot issue them", function()
    LP.Chatted:Fire("/ai model replacement-model")
    assert(bot.cfg.Model=="replacement-model" and bot.cfg.GeminiModel=="replacement-model")
    LP.Chatted:Fire("/ai off"); assert(not bot.cfg.Enabled)
    TCS.MessageReceived:Fire({TextSource={UserId=2},Text="/ai on",TextChannel=channel,MessageId="command"})
    assert(not bot.cfg.Enabled); LP.Chatted:Fire("/ai on")
end)
test("thinking markup variants are stripped without losing the answer", function()
    assert(bot.parse("<thinking>secret</thinking>Visible")=="Visible")
    assert(bot.parse('<THINK mode="deep">secret</THINK>Ready')=="Ready")
    assert(bot.parse("orphaned reasoning</think>Answer")=="Answer")
    assert(bot.parse("<analysis>secret</analysis><reasoning>secret</reasoning>Final")=="Final")
    assert(bot.parse("<thinker>ordinary text</thinker>")=="<thinker>ordinary text</thinker>")
end)
test("old assistant reasoning is removed from request history", function()
    local messages=bot.messages("hello",{},nil,{{role="assistant",content="<think>old secret</think>Old answer"}})
    assert(messages[2].content=="Old answer")
end)
test("off policy overrides attempts to enable OpenRouter thinking", function()
    bot.cfg.Provider="openrouter"; bot.cfg.OpenRouterKey="test"
    bot.cfg.Model="qwen/qwen3-32b"
    local content
    task.spawn(function() content=bot.raw({}, {reasoning={enabled=true,effort="high"},reasoning_effort="high"}) end)
    advance(1)
    assert(content)
    local body=HttpService:JSONDecode(requests[#requests].Body)
    assert(body.reasoning.enabled==false and body.reasoning.effort=="none" and body.reasoning.exclude==true)
    assert(body.reasoning_effort==nil)
end)
test("thinking is disabled with provider-specific fields", function()
    local cases={
        {provider="groq",key="GroqKey",model="qwen/qwen3-32b"},
        {provider="gemini",key="GeminiKey",model="gemini-2.5-flash"},
        {provider="cerebras",key="CerebrasKey",model="qwen-3.8-27b"},
        {provider="lmstudio",model="qwen3-8b"},
    }
    for _,case in ipairs(cases) do
        bot.cfg.Provider=case.provider; bot.cfg.Model=case.model
        if case.key then bot.cfg[case.key]="test" end
        local content
        task.spawn(function() content=bot.raw({}) end); advance(1)
        assert(content,case.provider)
        local body=HttpService:JSONDecode(requests[#requests].Body)
        assert(body.reasoning_effort=="none",case.provider)
        if case.provider=="cerebras" then assert(body.max_tokens==nil and body.max_completion_tokens) end
    end
    bot.cfg.Provider="together"; bot.cfg.TogetherKey="test"; bot.cfg.Model="Qwen/Qwen3-32B"
    task.spawn(function() bot.raw({}) end); advance(1)
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning.enabled==false)
end)
test("ordinary and unknown custom models also receive thinking off", function()
    bot.cfg.Provider="groq"; bot.cfg.Model="llama-3.1-8b-instant"
    task.spawn(function() bot.raw({}) end); advance(1)
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning_effort=="none")
    bot.cfg.Provider="custom"; bot.cfg.Model="my-opaque-alias"
    task.spawn(function() bot.raw({}, {
        reasoning_effort="high",thinking={type="enabled"},enable_thinking=true,
        chat_template_kwargs={enable_thinking=true},extra_body={reasoning_effort="high"},
    }) end); advance(1)
    local body=HttpService:JSONDecode(requests[#requests].Body)
    assert(body.reasoning_effort=="none" and body.thinking==nil and body.enable_thinking==nil)
    assert(body.chat_template_kwargs==nil and body.extra_body==nil)
end)
test("all model names receive an off request without model-name blocking", function()
    local cases={
        {"groq","openai/gpt-oss-120b"}, {"gemini","gemini-2.5-pro"},
        {"gemini","gemini-3-flash-preview"}, {"openrouter","deepseek/deepseek-r1"},
        {"cerebras","kimi-k2.7-code"}, {"together","Qwen/Qwen3-235B-A22B-Thinking-2507"},
    }
    for _,case in ipairs(cases) do
        bot.cfg.Provider=case[1]; bot.cfg.Model=case[2]
        local before=#requests; local result
        task.spawn(function() result=bot.raw({}) end); advance(1)
        assert(result and #requests==before+1,case[2])
        local body=HttpService:JSONDecode(requests[#requests].Body)
        assert(body.reasoning_effort=="none" or body.reasoning.enabled==false,case[2])
    end
end)
test("every provider adapter sends an explicit off setting", function()
    for key in pairs(bot.cfg) do if key:match("Key$") then bot.cfg[key]="test" end end
    for _,provider in ipairs(bot.providers) do
        bot.cfg.Provider=provider.id; bot.cfg.Model="opaque-model"
        local before=#requests
        task.spawn(function() bot.raw({}) end); advance(1)
        assert(#requests==before+1,provider.id)
        local body=HttpService:JSONDecode(requests[#requests].Body)
        assert(body.reasoning_effort=="none" or (body.reasoning and body.reasoning.enabled==false),provider.id)
    end
    bot.cfg.Provider="custom"; bot.cfg.Model="test-model"
end)
test("providers rejecting off return an error without a thinking-enabled retry", function()
    responses={{StatusCode=400,Body=HttpService:JSONEncode({error={message="Unsupported reasoning_effort none for this model"}})}}
    local result,err; local before=#requests
    task.spawn(function() result,err=bot.raw({}) end); advance(10)
    assert(not result and err:find("thinking=off",1,true) and #requests==before+1)
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning_effort=="none")
end)
test("custom and local endpoints send both forms of thinking off", function()
    -- Some Ollama-based gateways ignore top-level reasoning_effort and only honor the reasoning object.
    for _,provider in ipairs({"custom","lmstudio"}) do
        bot.cfg.Provider=provider; bot.cfg.Model="gemma4:e2b"
        task.spawn(function() bot.raw({}) end); advance(1)
        local body=HttpService:JSONDecode(requests[#requests].Body)
        assert(body.reasoning_effort=="none" and type(body.reasoning)=="table" and body.reasoning.effort=="none",provider)
    end
    bot.cfg.Provider="groq"; bot.cfg.GroqKey="test"; bot.cfg.Model="llama-3.1-8b-instant"
    task.spawn(function() bot.raw({}) end); advance(1)
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning==nil,"Strict cloud APIs keep the single form")
    bot.cfg.Provider="custom"; bot.cfg.Model="test-model"
end)
test("servers rejecting the reasoning object retry once with reasoning_effort none only", function()
    responses={
        {StatusCode=400,Body=HttpService:JSONEncode({error={message="Unrecognized request argument supplied: reasoning"}})},
        {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="Hello!"}}}})},
    }
    local result,err; local before=#requests
    task.spawn(function() result,err=bot.raw({}) end); advance(10)
    assert(result=="Hello!" and #requests==before+2,tostring(err))
    local retry=HttpService:JSONDecode(requests[#requests].Body)
    assert(retry.reasoning==nil and retry.reasoning_effort=="none","The retry still requests thinking off")
end)
test("model lists keep each model's published reasoning levels", function()
    local models=bot.parseModels({data={
        {id="plain-model"},
        {id="gemma4:e2b",reasoning={supported=true,efforts={"none","on"," on ",""},default=true}},
        {id="other-thinker",supported_reasoning_efforts={"low","high"}},
    }})
    assert(models[1].id=="gemma4:e2b" and #models[1].efforts==2 and models[1].efforts[2]=="on")
    assert(models[2].id=="other-thinker" and models[2].efforts[1]=="low")
    assert(models[3].id=="plain-model" and models[3].efforts==nil)
end)
test("a chosen reasoning level is sent with headroom and its reasoning stays private", function()
    bot.cfg.Provider="custom"; bot.cfg.Model="gemma4:e2b"; bot.cfg.MaxTokens=120
    bot.cfg.ReasoningEffort="on"; bot.cfg.ReasoningModel="gemma4:e2b"
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="Hi there!",reasoning="private thoughts"}}},
        usage={completion_tokens_details={reasoning_tokens=40}}})}}
    local result,err
    task.spawn(function() result,err=bot.raw({}) end); advance(1)
    assert(result=="Hi there!",tostring(err))
    local body=HttpService:JSONDecode(requests[#requests].Body)
    assert(body.reasoning_effort=="on" and body.reasoning.effort=="on")
    assert(body.max_tokens>120,"Thinking gets extra tokens so it cannot consume the whole reply")
    -- Vision descriptions stay off even with a chat reasoning level.
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="A hat."}}}})}}
    task.spawn(function() bot.generic("https://vision.example/v1/chat/completions",{},{model="gemma4:e2b",messages={}},"custom") end); advance(1)
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning_effort=="none")
end)
test("a level chosen for another model falls back to thinking off", function()
    bot.cfg.Provider="custom"; bot.cfg.Model="different-model"
    bot.cfg.ReasoningEffort="on"; bot.cfg.ReasoningModel="gemma4:e2b"
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="answer",reasoning="leaked"}}}})}}
    local result,err
    task.spawn(function() result,err=bot.raw({}) end); advance(1)
    assert(not result and err:find("thinking=off",1,true),"Off-mode still rejects reported reasoning")
    assert(HttpService:JSONDecode(requests[#requests].Body).reasoning_effort=="none")
    bot.cfg.ReasoningEffort="none"; bot.cfg.ReasoningModel=""; bot.cfg.Model="test-model"; bot.cfg.MaxTokens=120
end)
test("thinking rejections name the model and how to use it", function()
    bot.cfg.Provider="custom"; bot.cfg.Model="qwen3-vl:4b"
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="",reasoning="<think>hmm"}}}})}}
    local result,err
    task.spawn(function() result,err=bot.raw({}) end); advance(1)
    assert(not result and err:find("qwen3-vl:4b",1,true) and err:find("Reasoning level",1,true),tostring(err))
    bot.cfg.Model="test-model"
end)
test("a chosen level accepts inline think blocks and strips them from chat", function()
    bot.cfg.Provider="custom"; bot.cfg.Model="qwen3-vl:4b"; bot.cfg.ReasoningEffort="on"; bot.cfg.ReasoningModel="qwen3-vl:4b"
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="<think>private plan</think>Hey there!"}}}})}}
    bot.runtime.nextRequestAt=0
    local before=#sent
    bot.enqueue({name="Visitor",text="hello"}); advance(2)
    assert(#sent==before+1 and sent[#sent]:find("Hey there!",1,true) and not sent[#sent]:find("private plan",1,true))
    bot.cfg.ReasoningEffort="none"; bot.cfg.ReasoningModel=""; bot.cfg.Model="test-model"
end)
test("reported reasoning is rejected even when a final answer exists", function()
    local cases={
        {choices={{message={content="answer",reasoning_content="hidden reasoning"}}}},
        {choices={{message={content="answer"}}},usage={completion_tokens_details={reasoning_tokens=3}}},
        {choices={{message={content="answer"}}},usage={output_tokens_details={reasoning_tokens=2}}},
        {choices={{message={content="<think>secret</think>answer"}}}},
        {choices={{message={content={{type="reasoning",text="secret"},{type="text",text="answer"}}}}}},
    }
    for _,data in ipairs(cases) do
        responses={{StatusCode=200,Body=HttpService:JSONEncode(data)}}
        local answer,err; local before=#requests
        task.spawn(function() answer,err=bot.generic("https://example.invalid",{},{}) end); advance(1)
        assert(not answer and err:find("thinking=off",1,true) and err:find("discarded",1,true) and #requests==before+1)
    end
end)
test("zero reasoning and empty thinking delimiters are accepted", function()
    responses={{StatusCode=200,Body=HttpService:JSONEncode({
        choices={{message={content="<think> </think>answer",reasoning=""}}},
        usage={completion_tokens_details={reasoning_tokens=0}},
    })}}
    local answer
    task.spawn(function() answer=bot.generic("https://example.invalid",{},{}) end); advance(1)
    assert(bot.parse(answer)=="answer")
end)
test("discarded reasoning never enters public chat or memory", function()
    responses={{StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="answer",reasoning="ignored off"}}}})}}
    bot.runtime.nextRequestAt=0
    local before=#sent; local memories=#bot.history
    bot.enqueue({name="Visitor",text="off test"}); advance(2)
    assert(#sent==before and #bot.history==memories and not bot.busy())
end)
test("custom endpoints normalize roots, versioned bases and full chat URLs", function()
    local cases={
        {"https://proxy.example","https://proxy.example/v1/chat/completions","https://proxy.example/v1/models"},
        {"https://proxy.example/v1/","https://proxy.example/v1/chat/completions","https://proxy.example/v1/models"},
        {"https://proxy.example/v1/chat/completions/","https://proxy.example/v1/chat/completions","https://proxy.example/v1/models"},
        {"https://proxy.example/api/v2","https://proxy.example/api/v2/chat/completions","https://proxy.example/api/v2/models"},
        {"https://proxy.example/v1/models?token=test","https://proxy.example/v1/chat/completions?token=test","https://proxy.example/v1/models?token=test"},
    }
    for _,case in ipairs(cases) do
        local urls=bot.resolveEndpoints(case[1],"")
        assert(urls.chat==case[2] and urls.models[1]==case[3],case[1])
    end
    assert(bot.resolveEndpoints("https://proxy.example/v1","/api/tags").models[1]=="https://proxy.example/api/tags")
    assert(bot.resolveEndpoints("https://proxy.example/v1","https://catalog.example/list").models[1]=="https://catalog.example/list")
    assert(not bot.resolveEndpoints("invalid","") and not bot.resolveEndpoints("https://proxy.example/v1","bad path"))
end)
test("model lists accept common shapes, remove duplicates and sort IDs", function()
    local models=bot.parseModels({data={{id=" beta "},{id="alpha",display_name="Alpha model"},{id="beta"},{bad=true}}})
    assert(#models==2 and models[1].id=="alpha" and models[1].label=="Alpha model" and models[2].id=="beta")
    models=bot.parseModels({models={{model="llama3:latest"},{name="qwen3:latest"}}})
    assert(#models==2 and models[1].id=="llama3:latest")
    assert(#bot.parseModels({"beta","alpha","alpha"})==2)
    assert(not bot.parseModels({data="invalid"}) and not bot.parseModels({error="denied"}) and not bot.parseModels({data={}}))
end)
test("custom discovery uses GET with the configured bearer key", function()
    responses={{StatusCode=200,Body=HttpService:JSONEncode({data={{id="available"}}})}}
    local models
    task.spawn(function() models=bot.discover("https://proxy.example/v1/chat/completions"," secret ","") end); advance(1)
    local call=requests[#requests]
    assert(models[1].id=="available" and call.Method=="GET" and call.Url=="https://proxy.example/v1/models")
    assert(call.Headers.Authorization=="Bearer secret" and call.Body==nil)
end)
test("model discovery falls back to /models only when the route is missing", function()
    responses={{StatusCode=404,Body=""},{StatusCode=200,Body=HttpService:JSONEncode({data={{id="fallback"}}})}}
    local models; local before=#requests
    task.spawn(function() models=bot.discover("https://proxy.example/v1","","") end); advance(1)
    assert(models[1].id=="fallback" and #requests==before+2)
    assert(requests[#requests].Url=="https://proxy.example/models" and requests[#requests].Headers.Authorization==nil)
    responses={{StatusCode=401,Body=""}}
    local err; before=#requests
    task.spawn(function() models,err=bot.discover("https://proxy.example/v1","wrong","") end); advance(1)
    assert(not models and err:find("API key",1,true) and #requests==before+1)
end)
test("custom model paths and invalid JSON return useful results", function()
    responses={{StatusCode=200,Body=HttpService:JSONEncode({models={{name="local-model"}}})}}
    local models,err
    task.spawn(function() models=bot.discover("http://localhost:11434/v1","","/api/tags") end); advance(1)
    assert(models[1].id=="local-model" and requests[#requests].Url=="http://localhost:11434/api/tags")
    responses={{StatusCode=200,Body="not-json"}}
    task.spawn(function() models,err=bot.discover("https://proxy.example/v1","","") end); advance(1)
    assert(not models and err:find("invalid JSON",1,true))
end)
local function configureVision()
    bot.cfg.GlobalVision=true; bot.cfg.UseCustomVision=true; bot.cfg.AvatarVisionTool=false
    bot.cfg.CustomVisionEndpoint="https://vision.example/v1"
    bot.cfg.CustomVisionModelsEndpoint=""; bot.cfg.CustomVisionKey="vision-key"; bot.cfg.CustomVisionModel="image-reader"
    bot.cfg.Provider="groq"; bot.cfg.Model="text-chat-model"; bot.cfg.GroqKey="chat-key"
    bot.cfg.Enabled=true; bot.runtime.nextRequestAt=0; bot.clearVision()
end
local avatarImage="https://images.example/avatar.png"
local function thumbnailResponse()
    return {StatusCode=200,Body=HttpService:JSONEncode({data={{imageUrl=avatarImage}}})}
end
local function textResponse(text,reasoning)
    return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content=text,reasoning=reasoning}}}})}
end

test("custom vision sends images to its own endpoint and text to the main model",function()
    configureVision(); bot.clear()
    local visionCalls,chatCalls=0,0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        local body=HttpService:JSONDecode(options.Body)
        if options.Url=="https://vision.example/v1/chat/completions" then
            visionCalls+=1
            assert(body.model=="image-reader" and body.max_tokens==160 and body.reasoning_effort=="none")
            assert(options.Headers.Authorization=="Bearer vision-key")
            assert(body.messages[2].content[2].image_url.url:find("data:image/png;base64,",1,true)==1)
            return textResponse("A blue hat and red glasses.")
        end
        chatCalls+=1
        assert(body.model=="text-chat-model" and options.Headers.Authorization=="Bearer chat-key")
        assert(type(body.messages[#body.messages].content)=="string")
        assert(body.messages[#body.messages].content:find("A blue hat and red glasses.",1,true))
        return textResponse("Nice blue hat!")
    end
    bot.enqueue({name="Visitor",text="How do I look?",userId=2,private=true}); advance(3)
    assert(visionCalls==1 and chatCalls==1 and #bot.privateHistory==2)
    assert(bot.cfg.Provider=="groq" and bot.cfg.Model=="text-chat-model" and bot.cfg.GroqKey=="chat-key")
    bot.enqueue({name="Visitor",text="Describe my avatar again",userId=2,private=true}); advance(3)
    assert(visionCalls==1 and chatCalls==2 and bot.runtime.stats.visionCacheHits>=1)
    transport=nil
end)
test("vision API dialect is independent of the chat provider",function()
    configureVision(); bot.cfg.Provider="openrouter"
    transport=function(options)
        local body=HttpService:JSONDecode(options.Body)
        -- The custom dialect sends both off forms, never OpenRouter's enabled/exclude object.
        assert(body.model=="image-reader" and body.reasoning_effort=="none" and body.reasoning.effort=="none")
        assert(body.reasoning.enabled==nil and body.reasoning.exclude==nil)
        return textResponse("A green hood.")
    end
    local caption
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage,"Visitor") end); advance(1)
    assert(caption=="A green hood." and bot.cfg.Provider=="openrouter")
    bot.cfg.CustomVisionEndpoint="https://openrouter.ai/api/v1"
    transport=function(options)
        local body=HttpService:JSONDecode(options.Body)
        assert(body.reasoning.enabled==false and body.reasoning.effort=="none" and body.reasoning_effort==nil)
        return textResponse("A green hood.")
    end
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage,"Visitor") end); advance(1)
    assert(caption=="A green hood.")
    transport=nil
end)
test("vision caches invalidate for thumbnail changes, model changes and expiry",function()
    configureVision()
    local calls=0
    transport=function() calls+=1; return textResponse("Appearance "..calls) end
    local caption
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage,"Visitor") end); advance(1)
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage,"Visitor") end); advance(1)
    assert(calls==1)
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage.."?changed=1","Visitor") end); advance(1)
    assert(calls==2)
    bot.cfg.CustomVisionModel="another-image-reader"
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage.."?changed=1","Visitor") end); advance(1)
    assert(calls==3)
    advance(121)
    task.spawn(function() caption=bot.describeAvatar(2,avatarImage.."?changed=1","Visitor") end); advance(1)
    assert(calls==4)
    Players.PlayerRemoving:Fire(other); assert(bot.visionCache[2]==nil)
    transport=nil
end)
test("vision errors never send the image or a substitute reply through the chat model",function()
    configureVision(); bot.clear()
    local visionCalls,chatCalls=0,0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        if options.Url=="https://vision.example/v1/chat/completions" then
            visionCalls+=1; return textResponse("caption","thinking ignored off")
        end
        chatCalls+=1; return textResponse("unexpected")
    end
    local replies=bot.runtime.stats.replies
    bot.enqueue({name="Visitor",text="look at me",userId=2,private=true}); advance(3)
    assert(visionCalls==1 and chatCalls==0 and #bot.privateHistory==0 and bot.visionCache[2]==nil)
    assert(bot.runtime.stats.replies==replies and bot.runtime.stats.lastError:find("thinking=off",1,true))
    transport=nil
end)
test("disabled avatar vision performs no image or vision requests",function()
    configureVision(); bot.cfg.GlobalVision=false
    local calls=0
    transport=function(options)
        calls+=1; assert(options.Method=="POST" and options.Url~="https://vision.example/v1/chat/completions")
        local body=HttpService:JSONDecode(options.Body)
        assert(type(body.messages[#body.messages].content)=="string")
        return textResponse("Text only")
    end
    bot.enqueue({name="Visitor",text="hello",userId=2,private=true}); advance(2)
    assert(calls==1)
    transport=nil
end)
test("turning off custom vision preserves the main-model image route",function()
    configureVision(); bot.cfg.UseCustomVision=false; bot.cfg.Provider="gemini"; bot.cfg.Model="gemini-2.5-flash"
    local chatCalls=0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        chatCalls+=1; assert(options.Url:find("generativelanguage.googleapis.com",1,true))
        local body=HttpService:JSONDecode(options.Body)
        assert(body.model=="gemini-2.5-flash" and body.messages[#body.messages].content[2].image_url.url:find("data:image/png;base64,",1,true)==1)
        return textResponse("Main model sees the image")
    end
    bot.enqueue({name="Visitor",text="hello",userId=2,private=true}); advance(2)
    assert(chatCalls==1)
    transport=nil
end)
test("missing custom vision settings fail before network requests",function()
    configureVision(); bot.cfg.CustomVisionModel=""
    local before=#requests
    bot.enqueue({name="Visitor",text="hello",userId=2,private=true}); advance(2)
    assert(#requests==before and bot.runtime.stats.lastError:find("Configure the custom vision",1,true))
end)
test("vision keys follow the existing key-persistence preference",function()
    configureVision(); bot.cfg.SaveAPIKeys=false
    bot.save()
    local saved=HttpService:JSONDecode(files["aichatbot_cfg_v3.json"])
    assert(saved.CustomVisionKey==nil and saved.CustomVisionModel=="image-reader" and saved.UseCustomVision==true)
    assert(bot.cfg.CustomVisionKey=="vision-key")
    bot.cfg.SaveAPIKeys=true; bot.save()
    assert(HttpService:JSONDecode(files["aichatbot_cfg_v3.json"]).CustomVisionKey=="vision-key")
end)
test("cancelling during vision cannot cache a late caption or generate a chat reply",function()
    configureVision(); bot.clear()
    local chatCalls=0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        if options.Url=="https://vision.example/v1/chat/completions" then task.wait(2); return textResponse("late caption") end
        chatCalls+=1; return textResponse("unexpected")
    end
    bot.enqueue({name="Visitor",text="hello",userId=2,private=true}); advance(0.2)
    bot.enable(false); advance(3)
    assert(chatCalls==0 and bot.visionCache[2]==nil and #bot.privateHistory==0 and not bot.busy())
    bot.enable(true); transport=nil
    bot.cfg.GlobalVision=false; bot.cfg.UseCustomVision=false; bot.cfg.Provider="custom"; bot.cfg.Model="test-model"
end)

test("base64 encodes binary PNG data and RFC vectors",function()
    local vectors={ [""]="",f="Zg==",fo="Zm8=",foo="Zm9v",foob="Zm9vYg==",fooba="Zm9vYmE=",foobar="Zm9vYmFy" }
    for input,expected in pairs(vectors) do assert(bot.base64(input)==expected) end
    assert(bot.base64("\0\255\128")=="AP+A")
end)
test("avatar images are inline base64, cached and validated",function()
    bot.clearVision()
    local downloads=0
    transport=function(options)
        if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
        downloads+=1; return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
    end
    local image
    task.spawn(function() image=bot.avatarImage(2) end); advance(1)
    assert(image=="data:image/png;base64,"..bot.base64("\137PNG\r\n\26\nfixture"))
    task.spawn(function() assert(bot.avatarImage(2)==image) end); advance(1); assert(downloads==1)
    bot.clearVision()
    transport=function(options)
        if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
        return {StatusCode=200,Body="<html>not an image</html>"}
    end
    task.spawn(function() local value,err=bot.avatarImage(2); assert(not value and err:find("supported image",1,true)) end); advance(1)
    transport=nil
end)
test("provider bad requests expose the cause and redact credentials",function()
    bot.cfg.Provider="custom"; bot.cfg.CustomKey="secret+key.value"
    local result,err
    transport=function() return {StatusCode=400,Body=HttpService:JSONEncode({error={message="Image URLs unsupported: "..bot.cfg.CustomKey.." Bearer leaked-token"}})} end
    task.spawn(function() result,err=bot.generic("https://chat.example/v1/chat/completions",{}, {model="gemma4:e2b",messages={}}) end); advance(1)
    assert(not result and err:find("Image URLs unsupported",1,true))
    assert(not err:find(bot.cfg.CustomKey,1,true) and not err:find("leaked-token",1,true))
    transport=nil
end)
local function toolResponse(userId,name)
    return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="",tool_calls={{id="avatar-call",type="function",["function"]={name=name or "describe_avatar",arguments=HttpService:JSONEncode({user_id=userId})}}}}}}})}
end
local function enableTools()
    configureVision(); bot.clear(); table.clear(bot.toolSupport)
    bot.cfg.AvatarVisionTool=true; bot.cfg.GlobalCooldown=0; bot.runtime.nextRequestAt=0
end
test("tool support is probed and cached using actual model responses",function()
    enableTools(); local calls=0
    transport=function(options)
        calls+=1; local body=HttpService:JSONDecode(options.Body)
        assert(body.reasoning_effort=="none" and body.tools[1]["function"].name=="describe_avatar")
        return toolResponse(1)
    end
    task.spawn(function() assert(bot.checkTools()) end); advance(1)
    task.spawn(function() assert(bot.checkTools()) end); advance(1)
    assert(calls==1)
    bot.cfg.Model="another-model"
    task.spawn(function() assert(bot.checkTools()) end); advance(1); assert(calls==2)
    transport=nil
end)
test("avatar tool performs a complete function call, vision request and final chat",function()
    enableTools(); local chatCalls,visionCalls=0,0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        local body=HttpService:JSONDecode(options.Body); assert(body.reasoning_effort=="none")
        if options.Url=="https://vision.example/v1/chat/completions" then
            visionCalls+=1; assert(body.model=="image-reader")
            assert(body.messages[2].content[2].image_url.url:find("data:image/png;base64,",1,true)==1)
            return textResponse("Blue hat.")
        end
        chatCalls+=1
        if chatCalls==1 then return toolResponse(1) end -- support probe
        if chatCalls==2 then return toolResponse(2) end
        assert(chatCalls==3 and body.tools)
        local result=body.messages[#body.messages]
        assert(result.role=="tool" and result.tool_call_id=="avatar-call")
        assert(HttpService:JSONDecode(result.content).description=="Blue hat.")
        assert(body.messages[#body.messages-1].role=="assistant" and body.messages[#body.messages-1].tool_calls)
        return textResponse("Nice blue hat!")
    end
    local publicSends=#sent; local calls=bot.runtime.stats.avatarToolCalls
    bot.enqueue({name="Visitor",text="What am I wearing?",userId=2,private=true}); advance(2)
    assert(chatCalls==3 and visionCalls==1 and #sent==publicSends)
    assert(bot.runtime.stats.avatarToolCalls==calls+1 and #bot.privateHistory==2)
    assert(bot.privateHistory[2].content=="Nice blue hat!")
    assert(#bot.history==0,"Tool exchanges must not enter public memory")
    transport=nil
end)
test("tool mode does not inspect avatars when the model answers directly",function()
    enableTools(); local calls=0
    transport=function(options)
        assert(options.Method=="POST")
        calls+=1; return calls==1 and toolResponse(1) or textResponse("Hello there!")
    end
    bot.enqueue({name="Visitor",text="Hello",userId=2,private=true}); advance(2)
    assert(calls==2 and #bot.privateHistory==2)
    transport=nil
end)
test("unsupported tool parameters fall back to automatic captions",function()
    enableTools(); local chatCalls,visionCalls=0,0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        local body=HttpService:JSONDecode(options.Body); assert(body.reasoning_effort=="none")
        if options.Url=="https://vision.example/v1/chat/completions" then visionCalls+=1; return textResponse("Blue hat.") end
        chatCalls+=1
        if body.tools then return {StatusCode=400,Body=HttpService:JSONEncode({error={message="tools are not supported"}})} end
        assert(type(body.messages[#body.messages].content)=="string" and body.messages[#body.messages].content:find("Blue hat.",1,true))
        return textResponse("Blue suits you!")
    end
    bot.enqueue({name="Visitor",text="My avatar?",userId=2,private=true}); advance(2)
    assert(chatCalls==2 and visionCalls==1 and #bot.privateHistory==2)
    transport=nil
end)
test("unknown tool names and players outside this game are rejected",function()
    for _,case in ipairs({{id=999,name="describe_avatar"},{id=2,name="run_code"},{id=2.5,name="describe_avatar"}}) do
        enableTools(); local calls=0; local before=bot.runtime.stats.avatarToolCalls
        transport=function(options)
            assert(options.Method=="POST"); calls+=1
            return calls==1 and toolResponse(1) or toolResponse(case.id,case.name)
        end
        bot.enqueue({name="Visitor",text="My avatar?",userId=2,private=true}); advance(2)
        assert(calls==2 and #bot.privateHistory==0 and bot.runtime.stats.avatarToolCalls==before)
    end
    transport=nil
end)
test("tool loops are bounded and cannot send partial replies",function()
    enableTools(); local chats=0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        if options.Url=="https://vision.example/v1/chat/completions" then return textResponse("Blue hat.") end
        chats+=1; return chats==1 and toolResponse(1) or toolResponse(2)
    end
    bot.enqueue({name="Visitor",text="My avatar?",userId=2,private=true}); advance(2)
    assert(chats==5 and #bot.privateHistory==0 and not bot.busy())
    transport=nil
end)
test("cancelling avatar download prevents the tool's vision and follow-up calls",function()
    enableTools(); local chats,visions=0,0
    transport=function(options)
        if options.Method=="GET" then
            if options.Url:find("thumbnails.roblox.com",1,true) then return thumbnailResponse() end
            task.wait(2); return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
        end
        if options.Url=="https://vision.example/v1/chat/completions" then visions+=1; return textResponse("Unexpected") end
        chats+=1; return chats==1 and toolResponse(1) or toolResponse(2)
    end
    bot.enqueue({name="Visitor",text="My avatar?",userId=2,private=true}); advance(0.2)
    bot.enable(false); advance(3)
    assert(chats==2 and visions==0 and #bot.privateHistory==0 and not bot.busy())
    bot.enable(true); transport=nil; bot.cfg.GlobalVision=false; bot.cfg.UseCustomVision=false
end)

local speechJobs,speechCancels,speechState,speechError
local function speechTransport(options)
    if options.Url:find("http://127.0.0.1:8765/v1/",1,true)==1 then
        assert(options.Headers.Authorization=="Bearer helper-test-key")
        if options.Method=="GET" then
            local jobs={}; for _,job in ipairs(speechJobs) do table.insert(jobs,{id=job.id,state=speechState or "done"}) end
            return {StatusCode=200,Body=HttpService:JSONEncode({service="aichatbot-voice",queue=0,active=false,stats={played=#jobs,errors=speechError and 1 or 0,last_error=speechError or ""},jobs=jobs})}
        end
        local body=HttpService:JSONDecode(options.Body)
        if options.Url:find("/v1/cancel",1,true) then table.insert(speechCancels,body); return {StatusCode=200,Body=HttpService:JSONEncode({cancelled=true})} end
        assert(options.Url:find("/v1/speak",1,true))
        table.insert(speechJobs,body)
        return {StatusCode=202,Body=HttpService:JSONEncode({id=body.id,state="queued"})}
    end
    local body=HttpService:JSONDecode(options.Body)
    assert(body.reasoning_effort=="none" and body.model=="chat-model")
    return textResponse("Hello! [WAVE] <think></think>")
end
local function configureSpeech()
    speechJobs={}; speechCancels={}; speechState=nil; speechError=nil
    transport=speechTransport
    bot.clear(); advance(0.1)
    bot.cfg.Provider="custom"; bot.cfg.Model="chat-model"; bot.cfg.CustomEndpoint="https://chat.example/v1"
    bot.cfg.GlobalVision=false; bot.cfg.UseCustomVision=false; bot.cfg.WhisperMode=false; bot.cfg.Enabled=true
    bot.cfg.TTSEnabled=true; bot.cfg.TTSPrivate=false; bot.cfg.TTSProvider="custom"
    bot.cfg.TTSEndpoint="https://speech.example/v1"; bot.cfg.TTSModel="kokoro"; bot.cfg.TTSVoice="af_bella"
    bot.cfg.TTSCustomKey="speech-key"; bot.cfg.TTSDevice="Test :: Cable"; bot.cfg.TTSBridgeKey="helper-test-key"
    bot.cfg.TTSBridgeURL="http://127.0.0.1:8765"; bot.runtime.nextRequestAt=0
end
test("disabled speech makes no helper requests",function()
    configureSpeech(); bot.cfg.TTSEnabled=false
    bot.enqueue({name="Visitor",text="Hello"}); advance(3)
    assert(#speechJobs==0 and #bot.history==2)
end)
test("public replies speak cleaned text once with independent provider/model/voice",function()
    configureSpeech()
    bot.enqueue({name="Visitor",text="Hello"}); advance(3)
    assert(#speechJobs==1 and speechJobs[1].text=="Hello!")
    assert(speechJobs[1].settings.model=="kokoro" and speechJobs[1].settings.voice=="af_bella")
    assert(speechJobs[1].settings.endpoint=="https://speech.example/v1" and speechJobs[1].settings.key=="speech-key")
    assert(speechJobs[1].disclose==true and speechJobs[1].session==bot.speech.session)
    assert(bot.cfg.Model=="chat-model" and not next(bot.speech.pending))
end)
test("public speech matches the visible truncated chat text without its prefix",function()
    configureSpeech()
    transport=function(options)
        if options.Url:find("127.0.0.1",1,true) then return speechTransport(options) end
        return textResponse(string.rep("Hello ",60))
    end
    bot.enqueue({name="Visitor",text="Long reply"}); advance(3)
    assert(#speechJobs==1 and speechJobs[1].text==sent[#sent]:sub(#bot.cfg.ChatPrefix+1))
    assert(utf8.len(sent[#sent])<=200 and utf8.len(speechJobs[1].text)<200)
end)
test("private and local-preview replies stay silent unless opted in",function()
    configureSpeech()
    bot.enqueue({name="Visitor",text="Private",private=true}); advance(3)
    assert(#speechJobs==0)
    bot.cfg.WhisperMode=true; bot.runtime.nextRequestAt=0
    bot.enqueue({name="Visitor",text="Local preview"}); advance(3)
    assert(#speechJobs==0)
    bot.cfg.TTSPrivate=true; bot.runtime.nextRequestAt=0
    bot.enqueue({name="Visitor",text="Private",private=true}); advance(3)
    assert(#speechJobs==1 and speechJobs[1].disclose==false)
end)
test("voice tests work with automatic speech off and never send chat",function()
    configureSpeech(); bot.cfg.TTSEnabled=false
    local before=#sent
    assert(bot.speech.enqueue("Test [WAVE]",{private=true},true)); advance(3)
    assert(#speechJobs==1 and speechJobs[1].text=="Test" and #sent==before and #bot.history==0)
end)
test("helper submission failures preserve successful text replies and memory",function()
    configureSpeech()
    transport=function(options)
        if options.Url:find("/v1/speak",1,true) then return {StatusCode=502,Body=HttpService:JSONEncode({error="Provider rejected speech-key"})} end
        return speechTransport(options)
    end
    local errors,replies,voiceErrors=bot.runtime.stats.errors,bot.runtime.stats.replies,bot.speech.errors
    local result,err
    bot.enqueue({name="Visitor",text="Hello",callback=function(value,errorText) result,err=value,errorText end}); advance(3)
    assert(result=="Hello!" and not err and #bot.history==2)
    assert(bot.runtime.stats.errors==errors and bot.runtime.stats.replies==replies+1 and bot.speech.errors==voiceErrors+1)
    assert(not bot.speech.lastError:find("speech-key",1,true))
end)
test("asynchronous provider/playback failures are surfaced by speech status polling",function()
    configureSpeech(); speechState="failed"; speechError="Output device disconnected"
    local before=bot.speech.errors
    bot.enqueue({name="Visitor",text="Hello"}); advance(3)
    assert(bot.speech.errors==before+1 and bot.speech.lastError==speechError and not next(bot.speech.pending))
    assert(#bot.history==2)
end)
test("speech cancellation clears local jobs and invalidates late helper requests",function()
    configureSpeech()
    transport=function(options)
        if options.Url:find("/v1/speak",1,true) then local result=speechTransport(options); task.wait(2); return result end
        return speechTransport(options)
    end
    bot.enqueue({name="Visitor",text="Hello"}); advance(0.3)
    assert(#speechJobs==1)
    local oldGeneration=speechJobs[1].generation; local queued=bot.speech.queued
    bot.enable(false); advance(3)
    assert(#bot.speech.queue==0 and not next(bot.speech.pending) and not bot.speech.busy)
    assert(speechCancels[#speechCancels].generation>oldGeneration and speechCancels[#speechCancels].session==bot.speech.session)
    assert(bot.speech.queued==queued,"Late acceptance must not revive cancelled speech")
    bot.enable(true)
end)
test("TTS provider keys are isolated and respect the existing saving preference",function()
    configureSpeech()
    bot.cfg.TTSOpenAIKey="openai-voice-key"; bot.cfg.TTSElevenLabsKey="eleven-voice-key"
    bot.cfg.TTSProvider="openai"; assert(bot.speech.settings().key=="openai-voice-key")
    local signature=bot.speech.signature(); assert(signature==bot.speech.signature())
    bot.cfg.TTSProvider="elevenlabs"; assert(bot.speech.settings().key=="eleven-voice-key" and signature~=bot.speech.signature())
    bot.cfg.SaveAPIKeys=false; bot.save()
    local saved=HttpService:JSONDecode(files["aichatbot_cfg_v3.json"])
    assert(saved.TTSOpenAIKey==nil and saved.TTSElevenLabsKey==nil and saved.TTSCustomKey==nil and saved.TTSBridgeKey==nil)
    assert(saved.TTSModel=="kokoro" and bot.cfg.TTSOpenAIKey=="openai-voice-key")
    bot.cfg.SaveAPIKeys=true; bot.save()
    assert(HttpService:JSONDecode(files["aichatbot_cfg_v3.json"]).TTSCustomKey=="speech-key")
end)
test("saved voice settings disable speech when pairing credentials are missing",function()
    configureSpeech(); bot.cfg.TTSBridgeKey=""; bot.normalize()
    assert(not bot.cfg.TTSEnabled)
    bot.cfg.TTSBridgeKey="helper-test-key"
end)
test("helper endpoints must remain on loopback and voice queues are bounded",function()
    configureSpeech()
    bot.cfg.TTSBridgeURL="https://external.example:8765"
    local before=#requests; local ok,err=bot.speech.enqueue("Hello",{private=true},true)
    assert(not ok and err:find("local helper",1,true) and #requests==before)
    bot.cfg.TTSBridgeURL="http://127.0.0.1:8765"
    transport=function(options)
        if options.Url:find("/v1/speak",1,true) then task.wait(2) end
        return speechTransport(options)
    end
    assert(bot.speech.enqueue("One",{private=true},true)); advance(0.1)
    for i=1,8 do assert(bot.speech.enqueue("Queued "..i,{private=true},true)) end
    assert(not bot.speech.enqueue("Overflow",{private=true},true))
    bot.speech.cancel(); advance(3)
    assert(not bot.speech.busy and #bot.speech.queue==0)
    bot.cfg.TTSEnabled=false; bot.cfg.TTSPrivate=false; bot.cfg.WhisperMode=false
    bot.speech.connection=nil; transport=nil
end)

test("unload disconnects all listeners and cancels in-flight work", function()
    bot.runtime.nextRequestAt=0; bot.cfg.RequestTimeout=30
    transport=function() task.wait(2); return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="late"}}}})} end
    local before=#sent
    bot.enqueue({name="Visitor",text="last"}); advance(0.2)
    local connections=table.clone(bot.runtime.connections)
    bot.runtime.Stop(); advance(3)
    assert(not bot.runtime.alive and #sent==before)
    for _,connection in ipairs(connections) do assert(not connection.Connected) end
    assert(not bot.enqueue({name="Visitor",text="after unload"}))
    bot.runtime.Stop() -- idempotent
end)
print(string.format("%d regression tests passed",passed))
