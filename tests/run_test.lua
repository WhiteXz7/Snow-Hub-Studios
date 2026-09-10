--[[
	Teste de ponta a ponta do conversor ScreenGui ➜ LocalScript.

	1. monta uma ScreenGui propositalmente cheia de casos chatos
	2. roda o conversor DE VERDADE (ScreenGui_To_LocalScript.lua)
	3. executa o LocalScript gerado
	4. compara a árvore reconstruída com a original, propriedade por propriedade

	Uso: luajit tests/run_test.lua   (a partir da raiz do repositório)
]]
package.path = package.path .. ";./tests/?.lua;./?.lua"
local mock = require("mock_roblox")
mock.install(_G)

local Color3, UDim, UDim2, Vector2, Vector3, CFrame = _G.Color3, _G.UDim, _G.UDim2, _G.Vector2, _G.Vector3, _G.CFrame
local Rect, NumberSequence, ColorSequence = _G.Rect, _G.NumberSequence, _G.ColorSequence
local NumberSequenceKeypoint, ColorSequenceKeypoint = _G.NumberSequenceKeypoint, _G.ColorSequenceKeypoint
local Font, Enum, Instance = _G.Font, _G.Enum, _G.Instance

local logs = {}
function _G.warn(...) logs[#logs + 1] = "warn: " .. table.concat({ ... }, " ") end
local realPrint = print
function _G.print(...)
	local parts = { ... }
	for i = 1, #parts do parts[i] = tostring(parts[i]) end
	logs[#logs + 1] = table.concat(parts, " ")
end

local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

---------------------------------------------------------------- GUI DE TESTE
local function N(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props or {}) do i[k] = v end
	if parent then i.Parent = parent end
	return i
end

local gui = N("ScreenGui", {
	Name = "SnowHub❄️",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 7,
	IgnoreGuiInset = true,
	ClipToDeviceSafeArea = true,
}, StarterGui)

local main = N("Frame", {
	Name = "Main",
	Size = UDim2.new(0.5, -20, 0.25, 3),
	Position = UDim2.new(0.25, 10, 0.5, -1.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(16, 18, 26),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	Rotation = 12.5,
	ZIndex = 3,
	AutomaticSize = Enum.AutomaticSize.XY,
	LayoutOrder = -3,
	Active = true,
	ClipsDescendants = true,
	Archivable = false,
}, gui)

N("UICorner", { CornerRadius = UDim.new(0, 12) }, main)
N("UIStroke", {
	Color = Color3.fromRGB(55, 60, 80), Thickness = 2, Transparency = 0.25,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Miter,
}, main)
N("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.5, Color3.new(0.25, 0.75, 0.125)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 255)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1, 0.05),
		NumberSequenceKeypoint.new(1, 0.9, 0),
	}),
	Rotation = 45,
	Offset = Vector2.new(0.1, -0.2),
}, main)
N("UIPadding", {
	PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0.02, 2), PaddingRight = UDim.new(0, 6),
}, main)
N("UIListLayout", {
	Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.Custom,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	FillDirection = Enum.FillDirection.Horizontal,
}, main)
N("UIScale", { Scale = 1.25 }, main)
N("UISizeConstraint", { MaxSize = Vector2.new(500, 300), MinSize = Vector2.new(120, 80) }, main)

local title = N("TextLabel", {
	Name = "Título",
	Text = "Título \"citado\"\nquebra\\barra ❄️ ]] ]==] [=[ ]]",
	Font = Enum.Font.Gotham,
	FontFace = Font.new(Enum.Font.GothamBold, Enum.FontWeight.Bold, Enum.FontStyle.Italic),
	RichText = true,
	TextColor3 = Color3.new(0.639216, 0.658824, 0.72549),
	TextSize = 18,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.new(1, 0, 0, 30),
}, main)
N("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 8 }, title)

local btn = N("TextButton", {
	Name = "Btn", Text = "OK", Modal = true, AutoButtonColor = false,
	Size = UDim2.new(0, 90, 0, 28), LayoutOrder = 2,
}, main)

local campo = N("TextBox", {
	Name = "Campo", PlaceholderText = "digite \"aqui\"", ClearTextOnFocus = false,
	TextEditable = false, Text = "abc", Size = UDim2.new(0, 120, 0, 24),
}, main)

-- referência para a frente (Btn aponta para Img, que ainda vai ser criada)
btn.NextSelectionDown = campo

N("ImageLabel", {
	Name = "Img", Image = "rbxassetid://123456789", ImageColor3 = Color3.fromRGB(200, 100, 50),
	ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(10, 10, 20, 20), SliceScale = 1.5,
	ImageRectOffset = Vector2.new(4, 4), ImageRectSize = Vector2.new(32, 32),
	ImageTransparency = 0.5, Size = UDim2.new(0, 48, 0, 48),
}, main)

N("ImageButton", {
	Name = "ImgBtn", Image = "rbxasset://textures/ui/Back.png",
	Size = UDim2.new(0, 24, 0, 24),
}, main)

local scroll = N("ScrollingFrame", {
	Name = "Scroll", CanvasSize = UDim2.new(1, 0, 0, 400), CanvasPosition = Vector2.new(0, 12),
	ScrollBarThickness = 6, ScrollingEnabled = false, Size = UDim2.new(1, 0, 0.5, 0),
}, main)
local itens = N("Folder", { Name = "Itens" }, scroll)
N("UIGridLayout", {
	CellSize = UDim2.new(0, 40, 0, 40), CellPadding = UDim2.new(0, 6, 0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, itens)
for i = 1, 3 do
	N("Frame", { Name = "Item" .. i, LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(30 * i, 40, 90) }, itens)
end

N("CanvasGroup", {
	Name = "Grupo", GroupColor3 = Color3.fromRGB(255, 128, 0), GroupTransparency = 0.5,
	Size = UDim2.new(0, 60, 0, 60),
}, main)

-- ViewportFrame com CFrame de 12 componentes + referência para FORA da ScreenGui
local outsideCamera = N("Camera", { Name = "CameraDeFora" })
N("ViewportFrame", {
	Name = "VF",
	CameraCFrame = CFrame.new(1, 2, 3, 0, 0, 1, 0, 1, 0, -1, 0, 0),
	CameraFieldOfView = 55,
	CurrentCamera = outsideCamera,
	LightColor = Color3.fromRGB(255, 240, 200),
	LightDirection = Vector3.new(0, -1, 0),
	Size = UDim2.new(0, 80, 0, 80),
}, main)

-- scripts filhos (Source com ]], [=[ e aspas para testar o long bracket)
N("LocalScript", {
	Name = "Animator",
	Source = '--[[ bloco ]] local x = [=[ texto ]=] ]==[ outro ]==]\n'
		.. 'print("aspas" .. \' ❄️ \' .. tostring(1/3))\n'
		.. 'local t = { [1] = "a", [2] = \'b\' }\n-- fim',
}, gui)
N("ModuleScript", { Name = "Utils", Source = "-- módulo\nreturn {}" }, gui)

-- valores
N("StringValue", { Name = "Cfg", Value = "valor com \"aspas\" e\nquebra ❄️" }, gui)
N("NumberValue", { Name = "Speed", Value = 1.5 }, gui)
N("IntValue", { Name = "Count", Value = 42 }, gui)
N("BoolValue", { Name = "Flag", Value = true }, gui)
N("Color3Value", { Name = "Cor", Value = Color3.fromRGB(65, 130, 255) }, gui)
N("ObjectValue", { Name = "Ref", Value = title }, gui)

-- invisível + frame com atributos e tags
N("Frame", { Name = "Invisivel", Visible = false, Size = UDim2.new(0, 10, 0, 10) }, gui)

local holder = N("Frame", { Name = "Holder" }, gui)
holder:SetAttribute("numero", 3.14159)
holder:SetAttribute("texto", "atributo ❄️ \"aspas\"")
holder:SetAttribute("logico", false)
holder:SetAttribute("cor", Color3.fromRGB(250, 195, 45))
holder:SetAttribute("vetor", Vector3.new(1, -2.5, 3))
holder:SetAttribute("ponto", Vector2.new(0.25, 0.75))
holder:SetAttribute("inteiro", 0)
CollectionService:AddTag(holder, "snow:holder")
CollectionService:AddTag(holder, "a-tag")

-- UIPageLayout com páginas (ordem importa)
local pages = N("Frame", { Name = "Paginas", Size = UDim2.new(1, 0, 1, 0) }, gui)
N("UIPageLayout", {
	TweenTime = 0.4, EasingStyle = Enum.EasingStyle.Back,
	EasingDirection = Enum.EasingDirection.InOut, Circular = true, Padding = UDim.new(0, 2),
}, pages)
for i = 1, 3 do N("Frame", { Name = "Pagina" .. i, LayoutOrder = i }, pages) end

local aspectHolder = N("Frame", { Name = "Aspecto" }, gui)
N("UIAspectRatioConstraint", {
	AspectRatio = 1.7777, AspectType = Enum.AspectType.ScaleWithParentSize,
	DominantAxis = Enum.DominantAxis.Height,
}, aspectHolder)

-- ordem proposital: o último filho do gui é um Frame chamado "ZZZ"
N("Frame", { Name = "ZZZ", Size = UDim2.new(0, 5, 0, 5) }, gui)

---------------------------------------------------------------- 1) CONVERSOR
local originalCount = 0
for _ in ipairs(gui:GetDescendants()) do originalCount = originalCount + 1 end

local chunk, loadErr = loadfile("ScreenGui_To_LocalScript.lua")
assert(chunk, "não consegui carregar o conversor: " .. tostring(loadErr))
local okRun, sourceOrErr = pcall(chunk)
assert(okRun, "conversor explodiu: " .. tostring(sourceOrErr))
local source = sourceOrErr
assert(type(source) == "string" and #source > 500, "conversor não devolveu o código gerado")

local generated = StarterGui:FindFirstChild("SnowHub❄️ (LocalScript)")
assert(generated, "LocalScript não foi criado no StarterGui")
assert(generated.Source == source, "Source do LocalScript criado difere do código devolvido")

local built = nil
local runChunk, syntaxErr = loadstring(source, "gerado")
assert(runChunk, "código gerado com erro de sintaxe: " .. tostring(syntaxErr))
local okGen, genErr = pcall(runChunk)
assert(okGen, "código gerado falhou ao rodar: " .. tostring(genErr))

local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
built = playerGui:FindFirstChild("SnowHub❄️")
assert(built, "a ScreenGui reconstruída não apareceu no PlayerGui")

---------------------------------------------------------------- 2) COMPARAÇÃO
local function pathMap(root)
	local map = {}
	local function rec(node, prefix)
		map[node] = prefix
		for _, c in ipairs(node:GetChildren()) do
			rec(c, prefix .. "/" .. tostring(c.Name))
		end
	end
	rec(root, "")
	return map
end

local function canon(v, map)
	local t = typeof(v)
	if t == "Instance" then return "ref:" .. (map[v] or "FORA:" .. tostring(v.Name)) end
	if t == "number" then return string.format("%.17g", v) end
	if v == nil or t == "boolean" or t == "string" then return tostring(v) end
	if t == "EnumItem" then return tostring(v) end
	local spec = getmetatable(v).__rbxspec
	if not spec then return "<" .. t .. ">" end
	if spec.comps then
		local parts = { v:GetComponents() }
		local out = {}
		for i = 1, #parts do out[i] = string.format("%.17g", parts[i]) end
		return "CFrame(" .. table.concat(out, ",") .. ")"
	end
	if spec.list then
		local out = {}
		for _, kp in ipairs(v[spec.list]) do
			local row = {}
			for _, f in ipairs(spec.fields) do row[#row + 1] = canon(kp[f], map) end
			out[#out + 1] = "(" .. table.concat(row, ",") .. ")"
		end
		return spec.type .. "{" .. table.concat(out, " ") .. "}"
	end
	if spec.fields then
		local out = {}
		for _, f in ipairs(spec.fields) do out[#out + 1] = f .. "=" .. canon(v[f], map) end
		return spec.type .. "(" .. table.concat(out, ",") .. ")"
	end
	return "<" .. t .. ">"
end

-- propriedades esperadas (ignora readonly, Parent e as que o conversor avisa que pulou)
local IGNORED_PROPS = { Parent = true, CurrentCamera = true }

local function propsOf(inst, map)
	local out = {}
	local class = inst.ClassName
	local def = mock.classDefs[class]
	local names = {}
	local c = class
	while c and mock.classDefs[c] do
		for k in pairs(mock.classDefs[c].props) do names[#names + 1] = k end
		c = mock.classDefs[c].super
	end
	for _, name in ipairs(names) do
		if not IGNORED_PROPS[name] then
			local ok, value = pcall(function() return inst[name] end)
			if ok and value ~= nil then out[name] = canon(value, map) end
		end
	end
	local okA, attrs = pcall(function() return inst:GetAttributes() end)
	if okA then
		for k, v in pairs(attrs) do out["@attr:" .. k] = canon(v, map) end
	end
	local okT, tags = pcall(function() return game:GetService("CollectionService"):GetTags(inst) end)
	if okT then
		local sorted = {}
		for _, t in ipairs(tags) do sorted[#sorted + 1] = t end
		table.sort(sorted)
		out["@tags"] = table.concat(sorted, ",")
	end
	return out
end

local diffs, compared = {}, 0
local function compare(a, b, path)
	compared = compared + 1
	if a.ClassName ~= b.ClassName then
		diffs[#diffs + 1] = path .. ": classe " .. a.ClassName .. " ~= " .. b.ClassName
		return
	end
	local mapA, mapB = pathMap(a), pathMap(b)
	local pa, pb = propsOf(a, mapA), propsOf(b, mapB)
	local keys = {}
	for k in pairs(pa) do keys[k] = true end
	for k in pairs(pb) do keys[k] = true end
	local sorted = {}
	for k in pairs(keys) do sorted[#sorted + 1] = k end
	table.sort(sorted)
	for _, k in ipairs(sorted) do
		if pa[k] ~= pb[k] then
			diffs[#diffs + 1] = string.format("%s [%s]: %s = %s  ->  %s",
				path, a.ClassName, k, tostring(pa[k]), tostring(pb[k]))
		end
	end
	local ca, cb = a:GetChildren(), b:GetChildren()
	if #ca ~= #cb then
		diffs[#diffs + 1] = string.format("%s: %d filhos no original vs %d no reconstruído", path, #ca, #cb)
		return
	end
	for i = 1, #ca do
		if ca[i].Name ~= cb[i].Name then
			diffs[#diffs + 1] = string.format("%s: filho %d é %s no original e %s no reconstruído",
				path, i, ca[i].Name, cb[i].Name)
		end
		compare(ca[i], cb[i], path .. "/" .. ca[i].Name)
	end
end

compare(gui, built, "")

local rebuiltCount = 0
for _ in ipairs(built:GetDescendants()) do rebuiltCount = rebuiltCount + 1 end

---------------------------------------------------------------- 3) RELATÓRIO
realPrint("────────────────────────────────────────────────────────────")
realPrint(string.format("instâncias: original %d (fora a raiz) · reconstruída %d", originalCount, rebuiltCount))
realPrint(string.format("nós comparados: %d", compared))
realPrint(string.format("código gerado: %d bytes / %d linhas", #source,
	select(2, source:gsub("\n", "")) + 1))

local sawOutsideRef = false
for _, line in ipairs(logs) do
	if line:find("aponta para fora", 1, true) then sawOutsideRef = true end
end
realPrint("aviso de referência externa (esperado): " .. tostring(sawOutsideRef))

-- Source do LocalScript filho voltou idêntico?
local origAnim = gui:FindFirstChild("Animator")
local newAnim = built:FindFirstChild("Animator")
realPrint("Source do LocalScript filho idêntico: " ..
	tostring(newAnim and origAnim.Source == newAnim.Source))

if originalCount ~= rebuiltCount then
	diffs[#diffs + 1] = "contagem de instâncias difere: " .. originalCount .. " vs " .. rebuiltCount
end
if not sawOutsideRef then
	diffs[#diffs + 1] = "o conversor não avisou sobre a referência para fora da ScreenGui"
end
if not (newAnim and origAnim.Source == newAnim.Source) then
	diffs[#diffs + 1] = "Source do LocalScript filho não bate"
end

-- o que o Output imprime (caminho copiar/colar) precisa reconstruir o código exato
local printed, blocks = {}, 0
for _, line in ipairs(logs) do
	if string.find(line, "código ", 1, true) and string.find(line, "----", 1, true) then
		blocks = blocks + 1
	elseif blocks > 0 and #printed < blocks then
		printed[#printed + 1] = line
	end
end
local fromOutput = table.concat(printed, "\n")
realPrint(string.format("blocos impressos no Output: %d (%d bytes)", blocks, #fromOutput))
if blocks > 0 and fromOutput ~= source then
	diffs[#diffs + 1] = string.format("o código impresso no Output não confere (%d bytes vs %d)",
		#fromOutput, #source)
end

if #diffs == 0 then
	realPrint("RESULTADO: PASSOU — a estrutura recriada é idêntica à original")
	realPrint("────────────────────────────────────────────────────────────")
	os.exit(0)
else
	realPrint(string.format("RESULTADO: %d diferença(s)", #diffs))
	for i, d in ipairs(diffs) do realPrint("  " .. i .. ") " .. d) end
	realPrint("────────────────────────────────────────────────────────────")
	os.exit(1)
end
