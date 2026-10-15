-- GUI smoke tests use property-change signals, real callbacks and the full script.
local function autoEnum()
    return setmetatable({}, {__index=function(t,k) local v=autoEnum(); rawset(t,k,v); return v end})
end
Enum=autoEnum()
Color3.new=Color3.fromRGB; Color3.fromHSV=Color3.fromRGB
local function dimension(...) return {...} end
local UDim2={}
function UDim2.new(xs,xo,ys,yo) return {xs or 0,xo or 0,ys or 0,yo or 0,X={Scale=xs or 0,Offset=xo or 0},Y={Scale=ys or 0,Offset=yo or 0}} end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
local UDim={new=dimension}; local Vector2={new=dimension}; local Vector3={new=dimension}
local TweenInfo={new=dimension}; local ColorSequence={new=dimension}; local ColorSequenceKeypoint={new=dimension}
local nodes={}
local Instance={}
function Instance.new(class,parent)
    local properties={ClassName=class,Name=class,Visible=true,ZIndex=1,Text="",AbsoluteSize={X=1280,Y=800}}
    local events,changes,children={},{},{}
    local object
    local function event(name) if not events[name] then events[name]=signal() end; return events[name] end
    local methods={}
    function methods:GetChildren() return table.clone(children) end
    function methods:IsA(name) return name==class or (name=="GuiObject" and (class=="Frame" or class=="TextButton" or class=="TextLabel" or class=="TextBox")) end
    function methods:FindFirstChild(name) for _,child in ipairs(children) do if child.Name==name then return child end end end
    function methods:WaitForChild(name) return self:FindFirstChild(name) end
    function methods:FindFirstChildOfClass(name) for _,child in ipairs(children) do if child.ClassName==name then return child end end end
    function methods:GetPropertyChangedSignal(name) if not changes[name] then changes[name]=signal() end; return changes[name] end
    function methods:CaptureFocus() event("Focused"):Fire() end
    function methods:Destroy()
        if properties.destroyed then return end
        properties.destroyed=true; event("Destroying"):Fire()
        for _,child in ipairs(table.clone(children)) do child:Destroy() end
        self.Parent=nil
        for _,sig in pairs(events) do sig.disabled=true end
    end
    function methods:Fire(...) event("Event"):Fire(...) end
    object=setmetatable({}, {
        __index=function(_,key)
            if methods[key] then return methods[key] end
            if key=="_children" then return children end
            if key=="Activated" or key=="SelectionGained" or key=="SelectionLost" or key=="Event" or key=="Destroying" or key=="AncestryChanged" or key:find("Mouse",1,true) or key=="Focused" or key=="FocusLost" then return event(key) end
            return properties[key]
        end,
        __newindex=function(_,key,value)
            local previous=properties[key]
            if previous==value then return end
            if key=="Parent" and previous then
                local index=table.find(previous._children,object)
                if index then table.remove(previous._children,index) end
            end
            properties[key]=value
            if key=="Parent" then
                if value then table.insert(value._children,object) end
                event("AncestryChanged"):Fire(object,value)
            end
            if changes[key] then changes[key]:Fire() end
        end,
    })
    table.insert(nodes,object)
    if parent then object.Parent=parent end
    return object
end
services.CoreGui=Instance.new("Folder")
services.TweenService={Create=function(_,object,_,properties)
    return {Play=function() for key,value in pairs(properties) do object[key]=value end end, Pause=function() end, Cancel=function() end}
end}
local controls,notifications={},{}
local library={}
local windowOptions,unloaded,hidden
function library:CreateWindow(options)
    windowOptions=options
    assert(options.name=="AI Chat Bot v3" and options.sidebarLayout==false)
    assert(options.configuration.autoSave==false and options.configuration.autoLoad==false)
    local window={Unload=function() unloaded=true end,ToggleHide=function() hidden=not hidden end}
    function window:Notify(value)
        table.insert(notifications,{Title=value.title,Content=value.content,Duration=value.duration})
    end
    function window:CreateTab(options)
        assert(type(options.name)=="string")
        local tab={}
        for _,method in ipairs({"CreateSection","CreateToggle","CreateInput","CreateButton","CreateText","CreateDropdown","CreateSlider"}) do
            tab[method]=function(_,options)
                assert(type(options.name)=="string",method)
                if method=="CreateSlider" then assert(type(options.value)=="number" and #options.range==2 and options.increment) end
                if method=="CreateDropdown" then assert(type(options.options)=="table" and options.multiSelect==false) end
                if method=="CreateToggle" then assert(type(options.value)=="boolean") end
                if method=="CreateInput" or method=="CreateToggle" or method=="CreateSlider" or method=="CreateDropdown" then assert(options.forgetState==true) end
                -- Aliases here let semantic tests focus on user behavior while asserting real Gen2 props.
                options.Callback=options.callback; options.Values=options.options
                controls[options.name]=options
                return {
                    SetTitle=function(_,value) options.name=value end,
                    Refresh=function(_,values) options.options=values; options.Values=values end,
                    Set=function(_,value,skip)
                        if method=="CreateText" then options.text=value
                        else options.value=value; if not skip and options.callback then options.callback(value) end end
                    end,
                }
            end
        end
        return tab
    end
    return window
end
function game:HttpGet() return "mock library" end
local function loadstring() return function() return library end end
-- INSERT_FULL_SCRIPT
local function find(property,value)
    for i=#nodes,1,-1 do
        local node=nodes[i]
        if not node.destroyed and node[property]==value then return node end
    end
    error("Missing node: "..property.."="..value)
end
local function click(node)
    task.spawn(function() node.MouseButton1Click:Fire(); node.Activated:Fire() end); advance(0.5)
end
local function cardButton(text)
    local label=find("Text",text)
    for _,child in ipairs(label.Parent:GetChildren()) do if child.ClassName=="TextButton" then return child end end
    error("No card button for "..text)
end
local bot
files={}; environment={}; transport=nil
local thread=coroutine.create(function() bot=bootUI() end); schedule(thread,0); advance(1)
assert(find("Name","AIBotSetup"))
local providerSearch=find("Name","ProviderSearch")
local function visibleProviders()
    local visible={}
    for _,row in ipairs(find("Name","ProviderList"):GetChildren()) do
        if row.Name:find("ProviderRow_",1,true) and row.Visible then table.insert(visible,row) end
    end
    return visible
end
local initialRows=visibleProviders()
providerSearch.Text="["
assert(find("Name","ProviderEmptyState").Visible and #visibleProviders()==0,"Literal search should show an empty state")
click(find("Name","ResetProviderFilters"))
assert(#visibleProviders()==#initialRows and not find("Name","ProviderEmptyState").Visible)
assert(find("Name","ProviderFilters").Position.Y.Offset==0,"Wide layouts keep filters beside search")
click(find("Name","ProviderFilter_Local"))
assert(#visibleProviders()==1 and visibleProviders()[1].Name=="ProviderRow_lmstudio")
assert(find("Name","ProviderFilter_Local").Text:find(">1<",1,true),"Filter chips show live match counts")
assert(find("Name","ProviderResultCount").Text:find("^1 of "))
click(find("Name","ProviderFilter_Vision"))
assert(#visibleProviders()>0)
assert(not find("Name","ProviderRow_groq").Visible)
click(find("Name","ProviderFilter_All"))
providerSearch.Text="groq"
click(find("Name","SelectProvider_groq"))
assert(find("Name","SelectedProviderName").Text=="Groq","Details must update after selection")
assert(find("Name","SelectedProviderAuth").Text:find("API key required",1,true))
local row=find("Name","ProviderRow_groq")
providerSearch.Text="llama-3.1"
assert(row==find("Name","ProviderRow_groq"),"Filtering must reuse rows")
assert(row.Visible,"Search should match model IDs")
assert(row:FindFirstChild("ProviderDetail").Text=="Matches llama-3.1-8b-instant","Model-ID matches should name the model")
assert(row:FindFirstChild("SelectedMark").Visible,"Selected tile shows its mark")
click(find("Name","ClearProviderSearch"))
assert(providerSearch.Text=="" and #visibleProviders()==#initialRows)
assert(row:FindFirstChild("ProviderDetail").Text:find("suggested models",1,true),"Clearing search restores the tile summary")
providerSearch.Text="cerebras"; providerSearch.FocusLost:Fire(true)
assert(find("Name","SelectedProviderName").Text=="Cerebras","Enter should select the first result")
assert(not row:FindFirstChild("SelectedMark").Visible)
providerSearch.Text=""; click(find("Name","SelectProvider_groq"))
-- Clicking an already-selected provider must preserve the model when revisiting step 1.
click(find("Name","SelectProvider_groq"))
click(find("Name","SetupContinue"))
-- Required auth stays on the connection step with an inline error.
click(find("Name","SetupContinue"))
assert(find("Name","SetupError").Text:find("API key",1,true))
find("Name","SetupAPIKey").Text="test-key"
assert(find("Name","SetupAPIKey").TextTransparency==1,"Key must be masked by default")
click(find("Name","RevealAPIKey")); assert(find("Name","SetupAPIKey").TextTransparency==0)
click(find("Name","RevealAPIKey")); assert(find("Name","SetupAPIKey").TextTransparency==1)
click(find("Name","RememberSetupKeys"))
click(find("Name","SetupContinue"))
local modelSearch=find("Name","ModelSearch")
modelSearch.Text="["; modelSearch.Text="8b"
click(find("Name","Model_2"))
-- Model selection survives revisiting provider and connection screens.
click(find("Name","SetupBack")); click(find("Name","SetupBack"))
click(find("Name","SelectProvider_groq"))
click(find("Name","SetupContinue")); click(find("Name","SetupContinue"))
assert(find("Name","ManualModelID").Text=="llama-3.1-8b-instant")
click(find("Name","SetupContinue"))
click(find("Name","Personality_Sarcastic"))
click(find("Name","SetupContinue"))
assert(find("Name","SetupPage_5").Visible and find("Name","SetupContinue").Text=="Start bot · text only")
assert(find("Name","SetupVoice_Remember voice API keys on this device_Toggle").Text:find("✓",1,true))
click(find("Name","SetupVoice_Remember voice API keys on this device_Toggle"))
click(find("Name","SetupNav_2")); assert(find("Name","RememberSetupKeys").Text:find("○",1,true))
click(find("Name","SetupNav_5"))
click(find("Name","SetupContinue")); advance(2)
assert(bot and bot.runtime.ready,"Wizard did not finish")
assert(bot.cfg.Provider=="groq" and bot.cfg.Model=="llama-3.1-8b-instant","Filtered model selected wrong index")
assert(bot.cfg.GroqKey=="test-key","Groq key not saved")
assert(bot.cfg.SystemPrompt:find("sarcastic",1,true),"Personality click did not change selection")
assert(controls["Refresh Status"] and controls["Cancel Pending Replies"])
assert(controls["Test Connection (private)"])
controls["Model ID"].Callback("new-model")
assert(bot.cfg.Model=="new-model" and bot.cfg.GeminiModel=="new-model")
controls["Refresh Status"].Callback()
assert(notifications[#notifications].Title=="Session status")
controls["❌ Unload Bot"].Callback()
assert(not bot.runtime.alive)
print("PASS provider selector: filters, model search, empty/reset states, persistent selection, stable rows")
print("PASS full wizard: literal searches, filtered model selection, Groq key, personality, launch")
print("PASS control panel: diagnostics, model editing, unload")

-- A fresh custom-provider wizard discovers models after collecting connection details.
local function startFreshWizard()
    files={}; environment={}; scheduled={}; nodes={}; controls={}; notifications={}; bot=nil
    services.CoreGui=Instance.new("Folder")
    task.spawn(function() bot=bootUI() end); advance(1)
    click(find("Name","SelectProvider_custom")); click(find("Name","SetupContinue"))
    assert(find("Name","SetupCustomEndpoint").Visible,"Custom connection must precede model selection")
end
local discoveryVersion=1
transport=function(options)
    assert(options.Method=="GET","Discovery should only GET")
    assert(options.Url=="https://proxy.example/catalog/models",options.Url)
    assert(options.Headers.Authorization=="Bearer custom-test-key")
    local data=discoveryVersion==1 and {{id="alpha-model"},{id="beta-model"}} or {{id="new-model"},{id="beta-model"}}
    return {StatusCode=200,Body=HttpService:JSONEncode({data=data})}
end
startFreshWizard()
find("Name","SetupCustomEndpoint").Text="https://proxy.example/v1/chat/completions"
find("Name","SetupCustomModelsEndpoint").Text="/catalog/models"
find("Name","SetupAPIKey").Text="custom-test-key"
click(find("Name","SetupContinue")); advance(1)
assert(find("Name","ModelDiscoveryStatus").Text:find("2 models",1,true))
click(find("Name","Model_2"))
discoveryVersion=2
click(find("Name","RefreshDiscoveredModels")); advance(1)
assert(find("Text","new-model"))
click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); advance(2)
assert(bot.cfg.Provider=="custom" and bot.cfg.Model=="beta-model","Refresh should preserve the selected model")
assert(bot.cfg.CustomModelsEndpoint=="/catalog/models" and bot.cfg.CustomKey=="custom-test-key")
-- Fetching does not change the current model or clear history; choosing a result does.
table.insert(bot.history,{role="user",content="keep until selection"})
controls["Fetch / Refresh Custom Models"].Callback(); advance(1)
assert(#controls["Discovered custom models"].Values==2)
assert(bot.cfg.Model=="beta-model" and #bot.history==1)
controls["Discovered custom models"].Callback("new-model")
assert(bot.cfg.Model=="new-model" and #bot.history==0)
-- A response from an old endpoint cannot populate a newly configured endpoint's dropdown.
transport=function() task.wait(2); return {StatusCode=200,Body=HttpService:JSONEncode({data={{id="stale-model"}}})} end
controls["Fetch / Refresh Custom Models"].Callback(); advance(0.2)
controls["Custom endpoint / base URL"].Callback("https://changed.example/v1")
advance(3)
assert(#controls["Discovered custom models"].Values==0)
controls["❌ Unload Bot"].Callback()
print("PASS custom model discovery: authentication, custom path, refresh, selection persistence, panel dropdown, stale responses")
-- Discovery failure keeps the manual model-ID flow usable.
transport=function() return {StatusCode=401,Body=""} end
startFreshWizard()
find("Name","SetupCustomEndpoint").Text="http://localhost:1234/v1"
find("Name","SetupAPIKey").Text=""
click(find("Name","SetupContinue")); advance(1)
assert(find("Name","ModelDiscoveryStatus").Text:find("API key",1,true))
find("Name","ManualModelID").Text="manual-model"
click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); advance(2)
assert(bot.cfg.Provider=="custom" and bot.cfg.Model=="manual-model")
local mainEndpoint,mainModel=bot.cfg.CustomEndpoint,bot.cfg.Model
controls["Vision endpoint / base URL"].Callback("https://vision.example/v1")
controls["Vision API key (optional)"].Callback("vision-ui-key")
controls["Vision model-list URL / path (optional)"].Callback("/catalog/vision")
transport=function(options)
    assert(options.Url=="https://vision.example/catalog/vision" and options.Headers.Authorization=="Bearer vision-ui-key")
    return {StatusCode=200,Body=HttpService:JSONEncode({data={{id="vision-one"},{id="vision-two"}}})}
end
controls["Fetch / Refresh Vision Models"].Callback(); advance(1)
assert(#controls["Discovered vision models"].Values==2)
controls["Discovered vision models"].Callback("vision-two")
controls["Enable avatar vision"].Callback(true)
controls["Use separate custom vision provider"].Callback(true)
assert(bot.cfg.UseCustomVision and bot.cfg.GlobalVision and bot.cfg.CustomVisionModel=="vision-two")
assert(bot.cfg.Model==mainModel and bot.cfg.CustomEndpoint==mainEndpoint)
transport=function(options)
    if options.Method=="GET" then
        if options.Url:find("thumbnails.roblox.com",1,true) then
            return {StatusCode=200,Body=HttpService:JSONEncode({data={{imageUrl="https://images.example/me.png"}}})}
        end
        return {StatusCode=200,Body="\137PNG\r\n\26\nfixture"}
    end
    local body=HttpService:JSONDecode(options.Body)
    assert(body.model=="vision-two" and body.reasoning_effort=="none")
    return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="A red hat."}}}})}
end
local publicSends=#sent; local historySize=#bot.history
controls["Test custom vision on my avatar"].Callback(); advance(1)
assert(notifications[#notifications].Title=="Avatar description" and notifications[#notifications].Content=="A red hat.")
assert(#sent==publicSends and #bot.history==historySize)
-- Changing the vision connection clears old model choices and ignores stale discovery responses.
transport=function() task.wait(1); return {StatusCode=200,Body=HttpService:JSONEncode({data={{id="stale-vision"}}})} end
controls["Fetch / Refresh Vision Models"].Callback(); advance(0.2)
controls["Vision endpoint / base URL"].Callback("https://new-vision.example/v1")
advance(2)
assert(#controls["Discovered vision models"].Values==0 and bot.cfg.Model==mainModel)
controls["Use separate custom vision provider"].Callback(false)
assert(not bot.cfg.UseCustomVision)
print("PASS separate vision UI: independent endpoint/key/model, discovery, routing toggle, private test, stale response rejection")
controls["❌ Unload Bot"].Callback()
print("PASS custom model discovery failure: visible error and manual model fallback")

-- Narrow screens reflow; closing during discovery cannot launch or mutate settings.
transport=function() task.wait(2); return {StatusCode=200,Body=HttpService:JSONEncode({data={{id="late-model"}}})} end
startFreshWizard()
local gui=find("Name","AIBotSetup")
gui.AbsoluteSize={X=390,Y=700}
assert(find("Name","SetupWindow").Size.X.Offset==420)
assert(find("Name","ProviderFilters").Position.Y.Offset==48,"Compact filters stack below search")
assert(find("Name","ProviderFilter_All").Text=="All","Compact chips drop counts")
assert(not find("Name","ConnectionGuide").Visible)
assert(find("Name","PersonalityEditor").Position.Y.Offset==236)
assert(find("Name","Personality_Sarcastic").Size.X.Scale==0.5)
find("Name","SetupCustomEndpoint").Text="https://narrow.example/v1"
click(find("Name","SetupContinue")); advance(0.1)
click(find("Name","CloseSetup")); advance(3)
assert(gui.destroyed)
assert(not environment.AIChatBotRuntime.alive and bot==nil)
print("PASS responsive setup: compact connection/presets, scrolling, close cancels discovery")
-- A no-key provider can complete the same five-step flow without authentication.
files={}; environment={}; scheduled={}; nodes={}; controls={}; notifications={}; bot=nil; transport=nil
services.CoreGui=Instance.new("Folder")
task.spawn(function() bot=bootUI() end); advance(1)
click(find("Name","SelectProvider_unclose")); click(find("Name","SetupContinue"))
assert(not find("Name","SetupAPIKey").Visible)
click(find("Name","SetupContinue"))
find("Name","ManualModelID").Text="test-keyless-model"
click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); click(find("Name","SetupContinue")); advance(2)
assert(bot.runtime.ready and bot.cfg.Provider=="unclose")
-- Exercise status lifecycle with a character, not just an unattached GUI.
local function character()
    local char=Instance.new("Model")
    local head=Instance.new("Part",char); head.Name="Head"
    return char,head
end
local char,head=character(); LP.Character=char
LP.CharacterAdded:Fire(char)
local board=find("Name","AIBotBillboard")
assert(board.Adornee==head and board.Enabled and board.MaxDistance==120)
assert(find("Name","BotIdentity").Text==bot.cfg.BotName and find("Name","StatusText").Text=="Ready for chat")
local width,height=board.Size.X.Offset,board.Size.Y.Offset
bot.billboard("generating")
assert(find("Name","ActivityDots").Visible and bot.billboardState.animating)
controls["Bot Name"].Callback("A very long updated bot name for the identity row")
assert(find("Name","BotIdentity").Text==bot.cfg.BotName)
assert(find("Name","StatusText").Text=="Generating reply","Renaming must preserve the active status")
controls["Show Status Billboard"].Callback(false)
assert(not board.Enabled and not bot.billboardState.animating)
controls["Show Status Billboard"].Callback(true)
assert(board.Enabled and bot.billboardState.animating)
controls["Enable AI Chat Bot"].Callback(false)
assert(find("Name","StatusText").Text=="Replies paused" and not bot.billboardState.animating)
controls["Enable AI Chat Bot"].Callback(true)
assert(find("Name","StatusText").Text=="Ready for chat")
-- The queue displays actual activity, errors and resets after cancellation.
transport=function() task.wait(1); return {StatusCode=200,Body=HttpService:JSONEncode({choices={{message={content="Hello"}}}})} end
bot.cfg.Provider="custom"; bot.cfg.Model="test-model"; bot.cfg.CustomEndpoint="https://chat.example/v1"
bot.cfg.GlobalCooldown=1; bot.cfg.ThinkDelay=false; bot.runtime.nextRequestAt=0
bot.enqueue({name="Visitor",text="Hello",private=true}); advance(0.2)
assert(find("Name","StatusText").Text=="Generating reply")
bot.clear(); advance(2)
assert(find("Name","StatusText").Text=="Ready for chat" and not bot.billboardState.animating)
transport=function() return {StatusCode=400,Body=HttpService:JSONEncode({error={message="Bad model"}})} end
bot.runtime.nextRequestAt=0
bot.enqueue({name="Visitor",text="Hello",private=true}); advance(1)
assert(find("Name","StatusText").Text=="Request failed" and not find("Name","ActivityDots").Visible)
assert(board.Size.X.Offset==width and board.Size.Y.Offset==height,"Activity must not resize the badge")
LP.CharacterRemoving:Fire(char); LP.Character=nil
assert(not board.Enabled)
local nextChar,nextHead=character(); LP.Character=nextChar
LP.CharacterAdded:Fire(nextChar)
assert(board.Adornee==nextHead and board.Enabled,"Respawn must restore the badge")
board:Destroy(); bot.billboard("ready")
assert(bot.billboardState.gui~=board and bot.billboardState.gui.Adornee==nextHead)
local recreated=bot.billboardState.gui
-- Guided voice output uses a paired helper, keeps credentials separate, and
-- preserves the chat route while selecting speech-only models and voice IDs.
assert(controls["Voice setup platform"] and controls["TTS models"] and controls["TTS voices"])
controls["Speak public AI replies"].Callback(true)
assert(not bot.cfg.TTSEnabled and controls["Speak public AI replies"].value==false)
controls["Helper pairing key"].Callback("helper-ui-key")
local voiceJobs={}; local catalogDelay=0
transport=function(options)
    assert(options.Url:find("http://127.0.0.1:8765/v1/",1,true)==1)
    assert(options.Headers.Authorization=="Bearer helper-ui-key")
    if options.Method=="GET" then
        if options.Url:find("/devices",1,true) then return {StatusCode=200,Body=HttpService:JSONEncode({devices={{id="MME :: CABLE Input",name="CABLE Input",virtual=true}}})} end
        local jobs={}; for _,job in ipairs(voiceJobs) do table.insert(jobs,{id=job.id,state="done"}) end
        return {StatusCode=200,Body=HttpService:JSONEncode({service="aichatbot-voice",platform="windows",queue=0,active=false,stats={played=#jobs,errors=0,last_error=""},jobs=jobs})}
    end
    local body=HttpService:JSONDecode(options.Body)
    if options.Url:find("/cancel",1,true) then return {StatusCode=200,Body=HttpService:JSONEncode({cancelled=true})} end
    if options.Url:find("/speak",1,true) then
        table.insert(voiceJobs,body); return {StatusCode=202,Body=HttpService:JSONEncode({id=body.id,state="queued"})}
    end
    assert(options.Url:find("/catalog",1,true))
    assert(body.settings.provider=="custom" and body.settings.key=="custom-tts-key")
    if catalogDelay>0 then task.wait(catalogDelay) end
    return {StatusCode=200,Body=HttpService:JSONEncode({models={{id="kokoro"},{id="speech-special"}},voices={{id="af_bella",name="Bella"}},note="Speech-only catalog"})}
end
controls["Check helper / Refresh output devices"].Callback(); advance(1)
assert(controls["macOS · BlackHole setup"].name=="Windows · VB-CABLE setup")
assert(controls["macOS · BlackHole setup"].text:find("CABLE Output",1,true))
assert(#controls["Speech output device"].Values==1)
controls["Speech output device"].Callback("MME :: CABLE Input · virtual mic")
assert(bot.cfg.TTSDevice=="MME :: CABLE Input")
local mainModel,mainEndpoint,historyCount=bot.cfg.Model,bot.cfg.CustomEndpoint,#bot.history
controls["TTS provider"].Callback("Custom (OpenAI-compatible)")
controls["Custom TTS endpoint / base URL"].Callback("https://tts.example/v1")
controls["TTS provider API key"].Callback("custom-tts-key")
controls["Fetch / Refresh TTS models and voices"].Callback(); advance(1)
assert(#controls["TTS models"].Values==2 and controls["TTS models"].Values[1]=="kokoro")
controls["TTS models"].Callback("kokoro")
controls["TTS voices"].Callback("Bella · af_bella")
assert(bot.cfg.TTSModel=="kokoro" and bot.cfg.TTSVoice=="af_bella")
assert(bot.cfg.Model==mainModel and bot.cfg.CustomEndpoint==mainEndpoint and #bot.history==historyCount)
local publicBefore=#sent
controls["Test selected voice"].Callback(); advance(3)
assert(#voiceJobs==1 and voiceJobs[1].settings.voice=="af_bella")
assert(#sent==publicBefore and #bot.history==historyCount and not bot.cfg.TTSEnabled)
controls["Speak public AI replies"].Callback(true); assert(bot.cfg.TTSEnabled)
controls["Also speak private / local-preview replies"].Callback(true); assert(bot.cfg.TTSPrivate)
controls["Stop current / queued speech"].Callback(); advance(0.1)
controls["Refresh speech status"].Callback(); advance(1)
assert(controls["Voice output status"].text:find("Played: 1",1,true))
-- Changed connections invalidate late catalogs without changing chat history.
catalogDelay=2
controls["Fetch / Refresh TTS models and voices"].Callback(); advance(0.1)
controls["Custom TTS endpoint / base URL"].Callback("https://new-tts.example/v1")
advance(3)
assert(#controls["TTS models"].Values==0 and #controls["TTS voices"].Values==0)
controls["TTS provider"].Callback("OpenAI")
controls["TTS provider API key"].Callback("openai-tts-key")
controls["Manual TTS model ID"].Callback("tts-1")
assert(not table.find(controls["TTS voices"].Values,"cedar") and table.find(controls["TTS voices"].Values,"coral"))
controls["TTS provider"].Callback("ElevenLabs")
assert(bot.speech.settings().key=="" and not bot.cfg.TTSEnabled)
controls["TTS provider API key"].Callback("eleven-tts-key")
controls["TTS provider"].Callback("Custom (OpenAI-compatible)")
assert(bot.speech.settings().key=="custom-tts-key" and bot.cfg.TTSOpenAIKey=="openai-tts-key" and bot.cfg.TTSElevenLabsKey=="eleven-tts-key")
print("PASS voice output UI: guided Windows/macOS setup, pairing, devices, TTS catalog, model/voice selection, private test, key isolation, compatibility, stale responses")
controls["❌ Unload Bot"].Callback(); assert(unloaded)
assert(recreated.destroyed and not bot.billboardState.animating)
LP.Character=nil; transport=nil
print("PASS status billboard: activity, identity, toggles, cancellation, errors, fixed size, respawn, recreation, unload")
print("PASS keyless setup and native Rayfield Gen2 Unload lifecycle")

-- Initial voice setup uses draft settings, the same catalog/controller as the
-- panel, and starts without speech when the optional step is skipped.
local function startVoiceWizard()
    files={}; environment={}; scheduled={}; nodes={}; controls={}; notifications={}; bot=nil; transport=nil
    services.CoreGui=Instance.new("Folder")
    task.spawn(function() bot=bootUI() end); advance(1)
    click(find("Name","SelectProvider_unclose")); click(find("Name","SetupContinue"))
    click(find("Name","SetupContinue")); find("Name","ManualModelID").Text="setup-chat-model"
    click(find("Name","SetupContinue")); click(find("Name","SetupContinue"))
    assert(find("Name","SetupPage_5").Visible and bot==nil)
end
local function voiceName(name,suffix) return "SetupVoice_"..name.."_"..suffix end
local function voiceInput(name,value) find("Name",voiceName(name,"Input")).Text=value end
local function voiceButton(name) click(find("Name",voiceName(name,"Button"))) end
local function voiceToggle(name) click(find("Name",voiceName(name,"Toggle"))) end
local function voiceChoice(name,value)
    click(find("Name",voiceName(name,"Picker")))
    click(find("Name",voiceName(name,"Option_"..value)))
end
local function voiceText(name)
    for _,child in ipairs(find("Name","SetupVoice_"..name):GetChildren()) do
        if child.ClassName=="TextLabel" and child.Position.Y.Offset==28 then return child.Text end
    end
    error("Missing voice text: "..name)
end
startVoiceWizard()
voiceToggle("Speak public AI replies")
assert(find("Name",voiceName("Speak public AI replies","Toggle")).Text:find("○",1,true))
assert(find("Name","SetupContinue").Text=="Start bot · text only")
assert(voiceText("Voice output status"):find("pairing key",1,true))
voiceInput("Helper pairing key","setup-helper-key")
assert(find("Name",voiceName("Helper pairing key","Input")).TextTransparency==1)
click(find("Name",voiceName("Helper pairing key","Reveal")))
assert(find("Name",voiceName("Helper pairing key","Input")).TextTransparency==0)
click(find("Name",voiceName("Helper pairing key","Reveal")))
local setupJobs,setupCancels={},{}
transport=function(options)
    assert(options.Url:find("http://127.0.0.1:8765/v1/",1,true)==1,options.Url)
    assert(options.Headers.Authorization=="Bearer setup-helper-key")
    if options.Method=="GET" then
        if options.Url:find("/devices",1,true) then
            return {StatusCode=200,Body=HttpService:JSONEncode({devices={{id="MME :: CABLE Input",name="CABLE Input",virtual=true}}})}
        end
        local jobs={}; for _,job in ipairs(setupJobs) do table.insert(jobs,{id=job.id,state="done"}) end
        return {StatusCode=200,Body=HttpService:JSONEncode({service="aichatbot-voice",platform="windows",queue=0,active=false,stats={played=#jobs,errors=0,last_error=""},jobs=jobs})}
    end
    local body=HttpService:JSONDecode(options.Body)
    if options.Url:find("/cancel",1,true) then table.insert(setupCancels,body); return {StatusCode=200,Body=HttpService:JSONEncode({cancelled=true})} end
    if options.Url:find("/speak",1,true) then table.insert(setupJobs,body); return {StatusCode=202,Body=HttpService:JSONEncode({state="queued"})} end
    assert(options.Url:find("/catalog",1,true) and body.settings.provider=="custom")
    assert(body.settings.key=="setup-tts-key" and body.settings.models_path=="/speech/models")
    return {StatusCode=200,Body=HttpService:JSONEncode({models={{id="kokoro"}},voices={{id="af_bella",name="Bella"}}})}
end
voiceButton("Check helper / Refresh output devices"); advance(1)
assert(voiceText("macOS · BlackHole setup"):find("CABLE Output",1,true))
voiceChoice("Speech output device","MME :: CABLE Input · virtual mic")
voiceChoice("TTS provider","Custom (OpenAI-compatible)")
voiceInput("Custom TTS endpoint / base URL","https://setup-speech.example/v1")
voiceInput("TTS provider API key","setup-tts-key")
assert(find("Name",voiceName("TTS provider API key","Input")).TextTransparency==1)
voiceInput("TTS model-list URL / path (optional)","/speech/models")
voiceButton("Fetch / Refresh TTS models and voices"); advance(1)
voiceChoice("TTS models","kokoro"); voiceChoice("TTS voices","Bella · af_bella")
voiceInput("Speech volume (0–100)","65")
local sentBefore=#sent
voiceButton("Test selected voice"); advance(3)
assert(#setupJobs==1 and #sent==sentBefore)
assert(setupJobs[1].settings.model=="kokoro" and setupJobs[1].settings.voice=="af_bella")
assert(setupJobs[1].settings.endpoint=="https://setup-speech.example/v1" and setupJobs[1].settings.volume==0.65)
assert(setupJobs[1].settings.key=="setup-tts-key" and not setupJobs[1].disclose)
assert(not files["aichatbot_cfg_v3.json"] and bot==nil,"Voice setup must not commit draft settings or launch")
voiceToggle("Speak public AI replies")
assert(find("Name","SetupContinue").Text=="Start bot with voice")
click(find("Name","SetupBack")); click(find("Name","Personality_Sarcastic")); click(find("Name","SetupContinue"))
assert(find("Name",voiceName("Manual TTS model ID","Input")).Text=="kokoro","Back navigation must preserve voice settings")
click(find("Name","SetupContinue")); advance(2)
assert(bot.runtime.ready and bot.cfg.TTSEnabled and not bot.cfg.TTSPrivate)
assert(bot.cfg.Provider=="unclose" and bot.cfg.Model=="setup-chat-model")
assert(bot.cfg.TTSProvider=="custom" and bot.cfg.TTSModel=="kokoro" and bot.cfg.TTSVoice=="af_bella")
assert(bot.cfg.TTSCustomKey=="setup-tts-key" and bot.cfg.TTSDevice=="MME :: CABLE Input")
assert(controls["Speak public AI replies"].value and controls["Manual TTS model ID"].value=="kokoro")
local savedVoice=HttpService:JSONDecode(files["aichatbot_cfg_v3.json"])
assert(savedVoice.TTSEnabled and savedVoice.TTSCustomKey==nil and savedVoice.TTSBridgeKey==nil)
assert(#setupCancels>0,"Launching must cancel pending setup voice tests")
controls["❌ Unload Bot"].Callback()
print("PASS initial voice setup: pairing, masks, devices, custom catalog, private voice test, draft isolation, back navigation, launch and key privacy")

-- Connection changes and closing the wizard discard late catalog results and
-- cancel the helper's audio without writing a partial setup to disk.
startVoiceWizard()
local voiceGui=find("Name","AIBotSetup"); voiceGui.AbsoluteSize={X=390,Y=700}
assert(find("Name","SetupNav_5").Text=="5  Voice" and find("Name","SetupVoiceForm").Visible)
voiceInput("Helper pairing key","setup-helper-key")
voiceChoice("TTS provider","Custom (OpenAI-compatible)")
voiceInput("Custom TTS endpoint / base URL","https://setup-speech.example/v1")
voiceInput("TTS provider API key","setup-tts-key")
voiceInput("TTS model-list URL / path (optional)","/speech/models")
-- Reuse the paired helper fixture while this second wizard is open.
transport=function(options)
    local body=options.Body and HttpService:JSONDecode(options.Body)
    if options.Url:find("/catalog",1,true) then
        task.wait(2)
        return {StatusCode=200,Body=HttpService:JSONEncode({models={{id="stale-tts"}},voices={{id="stale-voice"}}})}
    end
    if options.Url:find("/cancel",1,true) then table.insert(setupCancels,body) end
    if options.Url:find("/speak",1,true) then task.wait(2) end
    return {StatusCode=202,Body=HttpService:JSONEncode({state="queued"})}
end
voiceButton("Fetch / Refresh TTS models and voices")
voiceInput("Custom TTS endpoint / base URL","https://new-speech.example/v1"); advance(3)
assert(not pcall(find,"Name",voiceName("TTS models","Option_stale-tts")),"An old connection must not populate the catalog")
voiceInput("Manual TTS model ID","manual-speech"); voiceInput("Manual TTS voice ID","manual-voice")
voiceInput("Helper pairing key","setup-helper-key")
-- Draft errors must redact keys even though the live configuration has none.
transport=function() return {StatusCode=400,Body=HttpService:JSONEncode({error="Rejected setup-tts-key / setup-helper-key"})} end
voiceButton("Fetch / Refresh TTS models and voices"); advance(1)
assert(not voiceText("Voice output status"):find("setup-tts-key",1,true))
assert(not voiceText("Voice output status"):find("setup-helper-key",1,true))
local closedRequests=0
-- Device IDs come from the helper, and closing cancels an in-flight voice test.
transport=function(options)
    if options.Url:find("/devices",1,true) then return {StatusCode=200,Body=HttpService:JSONEncode({devices={{id="Test :: Cable",name="Cable",virtual=true}}})} end
    if options.Url:find("/status",1,true) then return {StatusCode=200,Body=HttpService:JSONEncode({service="aichatbot-voice"})} end
    if options.Url:find("/cancel",1,true) then closedRequests=closedRequests+1 end
    task.wait(2); return {StatusCode=202,Body=HttpService:JSONEncode({state="queued"})}
end
voiceButton("Check helper / Refresh output devices"); advance(1)
voiceChoice("Speech output device","Test :: Cable · virtual mic")
voiceToggle("Remember voice API keys on this device")
assert(find("Name","RememberSetupKeys").Text:find("✓",1,true))
voiceButton("Fetch / Refresh TTS models and voices")
voiceButton("Test selected voice"); click(find("Name","CloseSetup")); advance(3)
assert(voiceGui.destroyed and not environment.AIChatBotRuntime.alive and bot==nil)
assert(closedRequests>0 and not files["aichatbot_cfg_v3.json"])
print("PASS initial voice setup cancellation: compact layout, stale catalogs, key redaction, storage preference, manual IDs and close during a voice test")
