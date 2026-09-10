--[[
	╔═══════════════════════════════════════════════════════════════════════════╗
	║  ScreenGui ➜ LocalScript                                                  ║
	║  Converte a ÚNICA ScreenGui do StarterGui em um LocalScript completo      ║
	╚═══════════════════════════════════════════════════════════════════════════╝

	COMO USAR
	1. Abra no Roblox Studio o lugar que tem a sua ScreenGui dentro de StarterGui.
	2. Abra a Command Bar (aba View -> Command Bar).
	3. Cole ESTE arquivo inteiro e aperte Enter. (ou, na Command Bar:
	   loadstring(game:HttpGet("<link raw deste arquivo>"))() )
	4. Leia o Output: o LocalScript aparece no Explorer, dentro do StarterGui.

	O QUE ELE FAZ
	• Acha a única ScreenGui do StarterGui (se tiver mais de uma, avisa e usa a
	  primeira; você pode fixar o nome em CONFIG.ScreenGuiName).
	• Lê TODA a hierarquia: filhos, netos, ORDEM exata dos filhos, propriedades
	  (só as que diferem do padrão), atributos, tags do CollectionService e o
	  Source de Script/LocalScript/ModuleScript que estiverem dentro.
	• Gera um LocalScript que recria isso 1:1, na mesma organização.
	• Nada é inventado: cada linha gerada veio de uma instância que já existia.

	ONDE O LocalScript É CRIADO
	CONFIG.OutputParent = "StarterGui"          -> StarterGui (padrão)
	CONFIG.OutputParent = "StarterPlayerScripts"-> StarterPlayer.StarterPlayerScripts
	CONFIG.OutputParent = nil                   -> só imprime o código, não cria

	A ScreenGui original NÃO é apagada (CONFIG.DestroyOriginal = false).
	O código gerado apaga a cópia antiga que existir no PlayerGui antes de montar
	a nova, então na tela aparece exatamente a mesma estrutura, sem duplicar.
	Depois de conferir, você pode apagar a ScreenGui original do StarterGui e
	ficar só com o LocalScript.

	Compatível com Luau (Roblox) e sem dependências.
--]]

---------------------------------------------------------------- CONFIGURAÇÃO
local CONFIG = {
	ScreenGuiName = nil,        -- nil = pega a única ScreenGui do StarterGui
	LocalScriptName = nil,      -- nil = "<NomeDaScreenGui> (LocalScript)"
	OutputParent = "StarterGui",-- "StarterGui" | "StarterPlayerScripts" | nil
	DestroyOriginal = false,    -- apagar a ScreenGui original depois de converter
	EmbedScriptSources = true,  -- recriar Script/LocalScript/ModuleScript filhos
	IncludeAttributes = true,   -- copiar atributos (GetAttributes)
	IncludeTags = true,         -- copiar tags (CollectionService)
	PrintSource = true,         -- imprimir o código gerado no Output
	SkipClasses = {},           -- ex.: { "Sound" } (pula a instância e a subárvore)
}

------------------------------------------------------------------- SERVIÇOS
local StarterGui = game:GetService("StarterGui")
local CollectionService = game:GetService("CollectionService")

local ty = (typeof ~= nil) and typeof or type

-------------------------------------------------------------------- UTILS
-- número: inteiro quando dá, senão precisão máxima sem perder valor
local function numFmt(n)
	if n ~= n then return nil end                        -- NaN
	if n == math.huge then return "math.huge" end
	if n == -math.huge then return "-math.huge" end
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return string.format("%.0f", n)
	end
	local s = string.format("%.14g", n)
	if tonumber(s) == n then return s end
	return string.format("%.17g", n)
end

-- string literal segura (mantém UTF-8, escapa aspas, quebras de linha e controles)
local function q(s)
	local out = {}
	for i = 1, #s do
		local c = string.sub(s, i, i)
		local b = string.byte(c)
		if c == '"' then out[#out + 1] = '\\"'
		elseif c == '\\' then out[#out + 1] = '\\\\'
		elseif c == '\n' then out[#out + 1] = '\\n'
		elseif c == '\r' then out[#out + 1] = '\\r'
		elseif c == '\t' then out[#out + 1] = '\\t'
		elseif b < 32 or b == 127 then out[#out + 1] = string.format("\\%d", b)
		else out[#out + 1] = c end
	end
	return '"' .. table.concat(out) .. '"'
end

-- string longa [=[ ]=] para Source de scripts
local function longBracket(s)
	local level = 0
	while level < 12 and string.find(s, "]" .. string.rep("=", level) .. "]", 1, true) do
		level = level + 1
	end
	if level >= 12 then return nil end
	local head = "[" .. string.rep("=", level) .. "["
	local tail = "]" .. string.rep("=", level) .. "]"
	if string.sub(s, 1, 1) == "]" or string.sub(s, 1, 1) == "\n" then
		s = "\n" .. s
	end
	return head .. s .. tail
end

-- Enum.X.Y sem cair na armadilha de enums que têm um membro chamado "Name"
-- (ex.: Enum.SortOrder.Name é o EnumItem, não o nome do tipo)
local function enumCode(item)
	local okName, itemName = pcall(function() return item.Name end)
	if not okName or type(itemName) ~= "string" then return nil end
	local typeName = nil
	local ok, n = pcall(function() return item.EnumType.Name end)
	if ok and type(n) == "string" then typeName = n end
	if not typeName then
		local s = tostring(item) -- "Enum.SortOrder.Name"
		local suffix = "." .. itemName
		if string.sub(s, 1, 5) == "Enum." and string.sub(s, -#suffix) == suffix then
			typeName = string.sub(s, 6, #s - #suffix)
		end
	end
	if typeName then return "Enum." .. typeName .. "." .. itemName end
	return nil
end

local function serColor3(c)
	local r, g, b = c.R, c.G, c.B
	local br, bg, bb = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
	local ok, exact = pcall(function()
		local f = Color3.fromRGB(br, bg, bb)
		return f.R == r and f.G == g and f.B == b
	end)
	if ok and exact then
		return string.format("Color3.fromRGB(%d, %d, %d)", br, bg, bb)
	end
	local sr, sg, sb = numFmt(r), numFmt(g), numFmt(b)
	if not (sr and sg and sb) then return nil end
	return string.format("Color3.new(%s, %s, %s)", sr, sg, sb)
end

------------------------------------------------------------------ ESTADO
local nodes = {}         -- registros na ordem DFS (mesma ordem do Explorer)
local indexByInst = {}   -- Instance -> índice em `nodes`
local warnings = {}
local skipSet = {}
for _, c in ipairs(CONFIG.SkipClasses) do skipSet[c] = true end

local function warn_(msg)
	warnings[#warnings + 1] = msg
end

---------------------------------------------------------------- SERIALIZER
-- devolve o código Lua que recria o valor, ou nil + motivo
local function ser(value)
	local t = ty(value)

	if t == "nil" then return "nil"
	elseif t == "boolean" then return tostring(value)
	elseif t == "number" then return numFmt(value)
	elseif t == "string" then return q(value)
	elseif t == "EnumItem" then return enumCode(value)
	elseif t == "Color3" then return serColor3(value)
	elseif t == "UDim" then
		local a, b = numFmt(value.Scale), numFmt(value.Offset)
		if a and b then return string.format("UDim.new(%s, %s)", a, b) end
	elseif t == "UDim2" then
		local a, b = numFmt(value.X.Scale), numFmt(value.X.Offset)
		local c, d = numFmt(value.Y.Scale), numFmt(value.Y.Offset)
		if a and b and c and d then
			return string.format("UDim2.new(%s, %s, %s, %s)", a, b, c, d)
		end
	elseif t == "Vector2" then
		local a, b = numFmt(value.X), numFmt(value.Y)
		if a and b then return string.format("Vector2.new(%s, %s)", a, b) end
	elseif t == "Vector3" then
		local a, b, c = numFmt(value.X), numFmt(value.Y), numFmt(value.Z)
		if a and b and c then return string.format("Vector3.new(%s, %s, %s)", a, b, c) end
	elseif t == "Vector2int16" then
		return string.format("Vector2int16.new(%d, %d)", value.X, value.Y)
	elseif t == "Vector3int16" then
		return string.format("Vector3int16.new(%d, %d, %d)", value.X, value.Y, value.Z)
	elseif t == "CFrame" then
		local parts = { value:GetComponents() }
		local out = {}
		for i = 1, #parts do
			local s = numFmt(parts[i])
			if not s then return nil end
			out[i] = s
		end
		return "CFrame.new(" .. table.concat(out, ", ") .. ")"
	elseif t == "Rect" then
		local a, b = numFmt(value.Min.X), numFmt(value.Min.Y)
		local c, d = numFmt(value.Max.X), numFmt(value.Max.Y)
		if a and b and c and d then
			return string.format("Rect.new(%s, %s, %s, %s)", a, b, c, d)
		end
	elseif t == "NumberRange" then
		local a, b = numFmt(value.Min), numFmt(value.Max)
		if a and b then return string.format("NumberRange.new(%s, %s)", a, b) end
	elseif t == "NumberSequence" then
		local out = {}
		for _, kp in ipairs(value.Keypoints) do
			local a, b, c = numFmt(kp.Time), numFmt(kp.Value), numFmt(kp.Envelope)
			if not (a and b and c) then return nil end
			out[#out + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)", a, b, c)
		end
		return "NumberSequence.new({" .. table.concat(out, ", ") .. "})"
	elseif t == "ColorSequence" then
		local out = {}
		for _, kp in ipairs(value.Keypoints) do
			local a = numFmt(kp.Time)
			local c = serColor3(kp.Value)
			if not (a and c) then return nil end
			out[#out + 1] = string.format("ColorSequenceKeypoint.new(%s, %s)", a, c)
		end
		return "ColorSequence.new({" .. table.concat(out, ", ") .. "})"
	elseif t == "BrickColor" then return "BrickColor.new(" .. q(tostring(value.Name)) .. ")"
	elseif t == "PhysicalProperties" then
		return string.format("PhysicalProperties.new(%s, %s, %s, %s, %s)",
			numFmt(value.Density), numFmt(value.Friction), numFmt(value.Elasticity),
			numFmt(value.FrictionWeight), numFmt(value.ElasticityWeight))
	elseif t == "TweenInfo" then
		local style, dir = enumCode(value.EasingStyle), enumCode(value.EasingDirection)
		if not (style and dir) then return nil end
		return string.format("TweenInfo.new(%s, %s, %s, %d, %s, %s)",
			numFmt(value.Time), style, dir, value.RepeatCount,
			tostring(value.Reverses), numFmt(value.DelayTime))
	elseif t == "DateTime" then
		return string.format("DateTime.fromUnixTimestampMillis(%s)", numFmt(value.UnixTimestampMillis))
	elseif t == "Font" then
		local fam, weight, style = enumCode(value.Family), enumCode(value.Weight), enumCode(value.Style)
		if fam and weight and style then
			return string.format("Font.new(%s, %s, %s)", fam, weight, style)
		end
		return nil, "Font com família/weight/style ilegível"
	elseif t == "Content" then return q(tostring(value))
	elseif t == "Ray" then
		return string.format("Ray.new(%s, %s)", ser(value.Origin), ser(value.Direction))
	elseif t == "Faces" then
		local order = { "Front", "Back", "Bottom", "Left", "Right", "Top" }
		local out = {}
		for _, n in ipairs(order) do
			if value[n] then out[#out + 1] = "Enum.NormalId." .. n end
		end
		return "Faces.new(" .. table.concat(out, ", ") .. ")"
	elseif t == "Axes" then
		local out = {}
		for _, n in ipairs({ "X", "Y", "Z" }) do
			if value[n] then out[#out + 1] = "Enum.Axis." .. n end
		end
		return "Axes.new(" .. table.concat(out, ", ") .. ")"
	elseif t == "PathWaypoint" then
		local act = enumCode(value.Action)
		if not act then return nil end
		return string.format("PathWaypoint.new(%s, %s)", ser(value.Position), act)
	elseif t == "Instance" then
		if value == nil then return "nil" end
		local idx = indexByInst[value]
		if idx then return "o[" .. idx .. "]" end
		local ok, path = pcall(function() return value:GetFullName() end)
		return nil, "referência para fora da ScreenGui (" .. (ok and path or "?") .. ")"
	elseif t == "table" then
		local out, keys = {}, {}
		for k in pairs(value) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do
			out[#out + 1] = "[" .. q(k) .. "] = " .. tostring(value[k])
		end
		return "{" .. table.concat(out, ", ") .. "}"
	end

	return nil, "tipo " .. t .. " não suportado"
end

local function sameValue(a, b)
	local ta, tb = ty(a), ty(b)
	if ta ~= tb then return false end
	if ta == "Instance" then return a == b end
	if ta == "number" or ta == "boolean" or ta == "nil" then return a == b end
	local ca, cb = ser(a), ser(b)
	if ca and cb then return ca == cb end
	return tostring(a) == tostring(b)
end

------------------------------------------- LISTA DE PROPRIEDADES CONHECIDAS
-- Rede de segurança: mesmo sem ReflectionMetadata, todas as propriedades de UI
-- que importam são checadas. (Propriedades readonly caem fora no teste de escrita.)
local STATIC_PROPS = {
	{ isa = "Instance", props = { "Name", "Archivable" } },
	{ isa = "GuiBase2d", props = { "SelectionGroup", "SelectionBehaviorDown",
		"SelectionBehaviorLeft", "SelectionBehaviorRight", "SelectionBehaviorUp" } },
	{ isa = "LayerCollector", props = { "Enabled" } },
	{ isa = "ScreenGui", props = { "ClipToDeviceSafeArea", "DisplayOrder", "IgnoreGuiInset",
		"ResetOnSpawn", "SafeAreaCompatibility", "ZIndexBehavior" } },
	{ isa = "GuiObject", props = { "Active", "AnchorPoint", "AutomaticSize", "BackgroundColor3",
		"BackgroundTransparency", "BorderColor3", "BorderMode", "BorderSizePixel",
		"ClipsDescendants", "Draggable", "GroupColor3", "GroupTransparency", "LayoutOrder",
		"NextSelectionDown", "NextSelectionLeft", "NextSelectionRight", "NextSelectionUp",
		"Position", "Rotation", "Selectable", "SelectionImageObject", "Size",
		"SizeConstraint", "Visible", "ZIndex" } },
	{ isa = "TextLabel", props = { "Font", "FontFace", "LineHeight", "MaxVisibleGraphemes",
		"RichText", "Text", "TextColor3", "TextScaled", "TextSize", "TextStrokeColor3",
		"TextStrokeTransparency", "TextTransparency", "TextTruncate", "TextWrapped",
		"TextXAlignment", "TextYAlignment" } },
	{ isa = "TextButton", props = { "Font", "FontFace", "LineHeight", "MaxVisibleGraphemes",
		"RichText", "Text", "TextColor3", "TextScaled", "TextSize", "TextStrokeColor3",
		"TextStrokeTransparency", "TextTransparency", "TextTruncate", "TextWrapped",
		"TextXAlignment", "TextYAlignment" } },
	{ isa = "TextBox", props = { "ClearTextOnFocus", "Font", "FontFace", "LineHeight",
		"MultiLine", "PlaceholderColor3", "PlaceholderText", "RichText", "Text",
		"TextColor3", "TextEditable", "TextScaled", "TextSize", "TextStrokeColor3",
		"TextStrokeTransparency", "TextTransparency", "TextTruncate", "TextWrapped",
		"TextXAlignment", "TextYAlignment" } },
	{ isa = "GuiButton", props = { "AutoButtonColor", "Modal", "Selected", "Style" } },
	{ isa = "ImageLabel", props = { "Image", "ImageColor3", "ImageContent", "ImageRectOffset",
		"ImageRectSize", "ImageTransparency", "ResampleMode", "ScaleType", "SliceCenter",
		"SliceScale", "TileSize" } },
	{ isa = "ImageButton", props = { "Image", "ImageColor3", "ImageContent", "ImageRectOffset",
		"ImageRectSize", "ImageTransparency", "ResampleMode", "ScaleType", "SliceCenter",
		"SliceScale", "TileSize" } },
	{ isa = "ScrollingFrame", props = { "AutomaticCanvasSize", "BottomImage", "CanvasPosition",
		"CanvasSize", "ElasticBehavior", "HorizontalScrollBarInset", "MidImage",
		"ScrollBarImageColor3", "ScrollBarImageTransparency", "ScrollBarThickness",
		"ScrollingDirection", "ScrollingEnabled", "TopImage", "VerticalScrollBarInset",
		"VerticalScrollBarThickness" } },
	{ isa = "Frame", props = { "Style" } },
	{ isa = "ViewportFrame", props = { "Ambient", "CameraCFrame", "CameraFieldOfView",
		"CurrentCamera", "ImageColor3", "ImageTransparency", "LightColor", "LightDirection" } },
	{ isa = "SurfaceGui", props = { "Adornee", "AlwaysOnTop", "CanvasSize", "Face",
		"LightInfluence", "PixelsPerStud", "SizingMode", "ToolPunchThroughDistance", "ZOffset" } },
	{ isa = "BillboardGui", props = { "Adornee", "AlwaysOnTop", "CurrentDistance",
		"ExtentsOffset", "ExtentsOffsetWorldSpace", "LightInfluence", "MaxDistance", "Size",
		"SizeOffset", "StudsOffset", "StudsOffsetWorldSpace" } },
	{ isa = "UICorner", props = { "CornerRadius" } },
	{ isa = "UIStroke", props = { "ApplyStrokeMode", "Color", "Enabled", "LineJoinMode",
		"Thickness", "Transparency" } },
	{ isa = "UIGradient", props = { "Color", "Enabled", "Offset", "Rotation", "Transparency" } },
	{ isa = "UIPadding", props = { "PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop" } },
	{ isa = "UIScale", props = { "Scale" } },
	{ isa = "UIAspectRatioConstraint", props = { "AspectRatio", "AspectType", "DominantAxis", "Enabled" } },
	{ isa = "UISizeConstraint", props = { "Enabled", "MaxSize", "MinSize" } },
	{ isa = "UITextSizeConstraint", props = { "MaxTextSize", "MinTextSize" } },
	{ isa = "UIListLayout", props = { "FillDirection", "HorizontalAlignment", "HorizontalFlex",
		"ItemLineAlignment", "Padding", "SortOrder", "VerticalAlignment", "VerticalFlex", "Wraps" } },
	{ isa = "UIGridLayout", props = { "CellPadding", "CellSize", "FillDirection",
		"FillDirectionMaxCells", "HorizontalAlignment", "SortOrder", "StartCorner",
		"VerticalAlignment" } },
	{ isa = "UIPageLayout", props = { "AnimatedEasingDirection", "AnimatedEasingStyle", "Circular",
		"EasingDirection", "EasingStyle", "GamepadInputEnabled", "Padding",
		"ScrollWheelInputEnabled", "TouchInputEnabled", "TweenTime" } },
	{ isa = "UITableLayout", props = { "FillDirection", "HorizontalAlignment", "MajorAxis",
		"Padding", "SortOrder", "VerticalAlignment" } },
	{ isa = "LuaSourceContainer", props = { "Source" } },
	{ isa = "Script", props = { "Enabled", "LinkedSource", "RunContext" } },
	{ isa = "ValueBase", props = { "Value" } },
	{ isa = "Sound", props = { "Looping", "PlaybackSpeed", "RollOffMaxDistance",
		"RollOffMinDistance", "RollOffMode", "SoundId", "Volume" } },
}

-- ReflectionMetadata (Studio): pega propriedades que a lista acima não conhece.
local reflectionCache = {}
local function reflectionProps(className)
	local cached = reflectionCache[className]
	if cached then return cached end
	local out = {}
	pcall(function()
		local rm = game:GetService("ReflectionMetadata")
		local byName = {}
		for _, c in ipairs(rm.Classes:GetChildren()) do
			if c:IsA("ReflectionMetadataClass") then byName[c.Name] = c end
		end
		local cls = byName[className]
		local guard = 0
		while cls and guard < 32 do
			guard = guard + 1
			local function read(node)
				for _, p in ipairs(node:GetChildren()) do
					local isProp = false
					pcall(function() isProp = p:IsA("ReflectionMetadataProperty") end)
					if isProp then
						local scriptable = true
						pcall(function() scriptable = (p.IsScriptable ~= false) end)
						if scriptable then out[p.Name] = true end
					elseif p:IsA("ReflectionMetadataProperties") then
						read(p)
					end
				end
			end
			read(cls)
			local superName = nil
			pcall(function()
				local s = cls.Superclass
				if type(s) == "string" and s ~= "" then superName = s end
			end)
			cls = superName and byName[superName] or nil
		end
	end)
	local list = {}
	for name in pairs(out) do list[#list + 1] = name end
	table.sort(list)
	reflectionCache[className] = list
	return list
end

local propCache = {}
local function candidateProps(inst)
	local cls = inst.ClassName
	local cached = propCache[cls]
	if cached then return cached end
	local seen, order = {}, {}
	local function add(name)
		if name and not seen[name] then seen[name] = true order[#order + 1] = name end
	end
	add("Name")
	for _, group in ipairs(STATIC_PROPS) do
		local ok, match = pcall(function() return inst:IsA(group.isa) end)
		if ok and match then
			for _, name in ipairs(group.props) do add(name) end
		end
	end
	for _, name in ipairs(reflectionProps(cls)) do add(name) end
	propCache[cls] = order
	return order
end

------------------------------------------------ PADRÃO / TESTE DE ESCRITA
local classDefaults = {}
local function classDefault(className)
	if classDefaults[className] == nil then
		local ok, inst = pcall(function() return Instance.new(className) end)
		classDefaults[className] = (ok and inst) or false
	end
	return classDefaults[className] or nil
end

local writableCache = {}
local function isWritable(className, prop, value)
	local key = className .. "|" .. prop
	local cached = writableCache[key]
	if cached ~= nil then return cached end
	if not classDefault(className) then
		writableCache[key] = true -- não dá pra testar; o set() gerado já usa pcall
		return true
	end
	local ok = pcall(function()
		local tmp = Instance.new(className)
		tmp[prop] = value
		tmp:Destroy()
	end)
	writableCache[key] = ok
	return ok
end

------------------------------------------------------------- LEITURA DA ÁRVORE
local SCRIPT_CLASSES = { Script = true, LocalScript = true, ModuleScript = true }

local function visit(inst, depth, parentIndex)
	local className = inst.ClassName
	if skipSet[className] then
		warn_("pulado (CONFIG.SkipClasses): " .. className)
		return
	end

	local idx = #nodes + 1
	local node = {
		index = idx, inst = inst, class = className, depth = depth,
		parentIndex = parentIndex, props = {}, refs = {}, refValues = {},
		attrs = {}, tags = {},
	}
	nodes[idx] = node
	indexByInst[inst] = idx

	local def = classDefault(className)
	for _, name in ipairs(candidateProps(inst)) do
		if name ~= "Parent" and not (name == "Source" and not CONFIG.EmbedScriptSources) then
			local okRead, value = pcall(function() return inst[name] end)
			if okRead and value ~= nil then
				local differs = true
				if def then
					local okDef, dvalue = pcall(function() return def[name] end)
					if okDef then differs = not sameValue(value, dvalue) end
				end
				if differs then
					if ty(value) == "Instance" then
						-- resolvida depois da leitura completa (pode apontar para um
						-- objeto que ainda vai ser lido)
						node.refValues[#node.refValues + 1] = { name = name, value = value }
					else
						local code, err
						if name == "Source" and ty(value) == "string" then
							code = longBracket(value) or q(value)
						else
							code, err = ser(value)
						end
						if not code then
							warn_(string.format("%s.%s: %s", className, name, err or "não serializável"))
						elseif not isWritable(className, name, value) then
							warn_(string.format("%s.%s: somente leitura, ignorada", className, name))
						else
							node.props[#node.props + 1] = {
								name = name, code = code, isSource = (name == "Source"),
							}
						end
					end
				end
			end
		end
	end

	if CONFIG.IncludeAttributes then
		local okA, attrs = pcall(function() return inst:GetAttributes() end)
		if okA and attrs then
			local names = {}
			for k in pairs(attrs) do names[#names + 1] = k end
			table.sort(names)
			for _, k in ipairs(names) do
				local code, err = ser(attrs[k])
				if code then
					node.attrs[#node.attrs + 1] = { name = k, code = code }
				else
					warn_(string.format("atributo %s de %s: %s", q(k), className, err or "?"))
				end
			end
		end
	end

	if CONFIG.IncludeTags then
		local okT, tags = pcall(function() return CollectionService:GetTags(inst) end)
		if okT and tags then
			local sorted = {}
			for _, t in ipairs(tags) do sorted[#sorted + 1] = t end
			table.sort(sorted)
			for _, t in ipairs(sorted) do node.tags[#node.tags + 1] = t end
		end
	end

	for _, child in ipairs(inst:GetChildren()) do
		visit(child, depth + 1, idx)
	end
end

---------------------------------------------------- ACHA A ScreenGui ALVO
local function findTarget()
	local found = {}
	for _, child in ipairs(StarterGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			if CONFIG.ScreenGuiName == nil or child.Name == CONFIG.ScreenGuiName then
				found[#found + 1] = child
			end
		end
	end
	return found
end

local targets = findTarget()
if #targets == 0 then
	return error("[Conversor] Nenhuma ScreenGui encontrada em StarterGui" ..
		(CONFIG.ScreenGuiName and (" com o nome " .. q(CONFIG.ScreenGuiName)) or "") .. ".")
end
if #targets > 1 then
	local names = {}
	for _, t in ipairs(targets) do names[#names + 1] = t.Name end
	warn_(string.format("%d ScreenGuis no StarterGui (%s). Usando a primeira: %s. " ..
		"Fixe CONFIG.ScreenGuiName se quiser outra.", #targets, table.concat(names, ", "), targets[1].Name))
end
local target = targets[1]

visit(target, 0, nil)

-- resolve as referências entre objetos agora que todo mundo já tem índice
for _, node in ipairs(nodes) do
	for _, ref in ipairs(node.refValues) do
		local idx = indexByInst[ref.value]
		if idx then
			node.refs[#node.refs + 1] = { name = ref.name, code = "o[" .. idx .. "]" }
		else
			local ok, path = pcall(function() return ref.value:GetFullName() end)
			warn_(string.format("%s.%s: aponta para fora da ScreenGui (%s), ignorada",
				node.class, ref.name, ok and path or "?"))
		end
	end
end

---------------------------------------------------------- GERAÇÃO DO CÓDIGO
local function nodeName(node)
	local ok, name = pcall(function() return node.inst.Name end)
	return string.format("%s %s", node.class, q(ok and name or "?"))
end

local totalProps, totalAttrs, totalTags, totalScripts = 0, 0, 0, 0
for _, n in ipairs(nodes) do
	totalProps = totalProps + #n.props + #n.refs
	totalAttrs = totalAttrs + #n.attrs
	totalTags = totalTags + #n.tags
	if SCRIPT_CLASSES[n.class] then totalScripts = totalScripts + 1 end
end

local L = {}
local function w(line) L[#L + 1] = line end
local function indent(depth) return string.rep("\t", depth) end

w("--[[")
w("\t" .. string.rep("=", 74))
w(string.format("\t %s  ➜  ScreenGui recriada 100%% por código", target.Name))
w("\t" .. string.rep("=", 74))
w(string.format("\t Gerado em: %s (UTC) pelo conversor ScreenGui ➜ LocalScript", os.date("!%Y-%m-%d %H:%M:%S")))
w(string.format("\t Origem:    StarterGui.%s", target.Name))
w(string.format("\t Conteúdo:  %d instâncias · %d propriedades · %d atributos · %d tags · %d scripts",
	#nodes, totalProps, totalAttrs, totalTags, totalScripts))
w("\t Hierarquia, nomes, ordem dos filhos e propriedades idênticos ao original.")
w("\t Nada foi inventado: cada linha veio de uma instância que já existia.")
w("--]]")
w("")
w("local Players = game:GetService(\"Players\")")
w("local CollectionService = game:GetService(\"CollectionService\")")
w("")
w("-- O StarterGui copia tudo para o PlayerGui de cada jogador, então é lá que a")
w("-- ScreenGui é montada. Se ainda existir uma cópia da ScreenGui original com o")
w("-- mesmo nome, ela é removida para não duplicar (mude para false se quiser).")
w("local REPLACE_EXISTING = true")
w("")
w("local localPlayer = Players.LocalPlayer or Players.LocalPlayerChanged:Wait()")
w("local rootParent = localPlayer:WaitForChild(\"PlayerGui\")")
w("")
w("-- aplica propriedade sem derrubar o script inteiro se alguma falhar")
w("local function set(object, property, value)")
w("\tlocal ok, err = pcall(function() object[property] = value end)")
w("\tif not ok then")
w("\t\twarn(string.format(\"[build] %s.%s falhou: %s\", object.ClassName, tostring(property), tostring(err)))")
w("\tend")
w("\treturn ok")
w("end")
w("")
w("local o = {}")

for _, node in ipairs(nodes) do
	local ind = indent(node.depth)
	w("")
	w(string.format("%s-- [%d] %s", ind, node.index, nodeName(node)))
	w(string.format("%so[%d] = Instance.new(%s)", ind, node.index, q(node.class)))

	if #node.props > 0 or #node.attrs > 0 then
		for _, p in ipairs(node.props) do
			if p.isSource then
				w(ind .. "-- ⚠ Source exige PluginSecurity. Se o Output acusar erro aqui,")
				w(ind .. "--   abra este objeto e cole o conteúdo manualmente.")
			end
			w(string.format("%sset(o[%d], %s, %s)", ind, node.index, q(p.name), p.code))
		end
		for _, a in ipairs(node.attrs) do
			w(string.format("%so[%d]:SetAttribute(%s, %s)", ind, node.index, q(a.name), a.code))
		end
	end

	if node.parentIndex then
		w(string.format("%so[%d].Parent = o[%d]", ind, node.index, node.parentIndex))
	end
end

-- referências entre objetos (NextSelection*, ObjectValue, SelectionImageObject...)
local refLines = {}
for _, node in ipairs(nodes) do
	for _, r in ipairs(node.refs) do
		refLines[#refLines + 1] = string.format("set(o[%d], %s, %s)", node.index, q(r.name), r.code)
	end
end
if #refLines > 0 then
	w("")
	w("-- ══ referências entre objetos (apontam para instâncias criadas acima) ══")
	for _, line in ipairs(refLines) do w(line) end
end

local tagLines = {}
for _, node in ipairs(nodes) do
	for _, t in ipairs(node.tags) do
		tagLines[#tagLines + 1] = string.format("CollectionService:AddTag(o[%d], %s)", node.index, q(t))
	end
end
if #tagLines > 0 then
	w("")
	w("-- ══ tags do CollectionService ══")
	for _, line in ipairs(tagLines) do w(line) end
end

w("")
w("-- ══ coloca na tela ══")
w("local screenGui = o[1]")
w("if REPLACE_EXISTING then")
w("\tlocal old = rootParent:FindFirstChild(screenGui.Name)")
w("\tif old and old ~= screenGui then old:Destroy() end")
w("end")
w("screenGui.Parent = rootParent")

local source = table.concat(L, "\n")

------------------------------------------------------- CRIA O LocalScript
local scriptName = CONFIG.LocalScriptName or (target.Name .. " (LocalScript)")
local createdPath = nil

if CONFIG.OutputParent then
	local okParent, parent = pcall(function()
		if CONFIG.OutputParent == "StarterGui" then
			return StarterGui
		elseif CONFIG.OutputParent == "StarterPlayerScripts" then
			return game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
		end
		return game:GetService(CONFIG.OutputParent)
	end)
	if okParent and parent then
		local old = parent:FindFirstChild(scriptName)
		if old then old:Destroy() end
		local ls = Instance.new("LocalScript")
		ls.Name = scriptName
		ls.Source = source
		ls.Parent = parent
		createdPath = parent:GetFullName() .. "." .. scriptName
	else
		warn_("não achei o destino " .. tostring(CONFIG.OutputParent) .. "; código só impresso")
	end
end

if CONFIG.DestroyOriginal then
	target:Destroy()
end

-------------------------------------------------------------- RELATÓRIO
print("════════════════════════════════════════════════════════════")
print(string.format("[Conversor] ScreenGui convertida: StarterGui.%s", target.Name))
print(string.format("[Conversor] %d instâncias · %d propriedades · %d atributos · %d tags · %d scripts",
	#nodes, totalProps, totalAttrs, totalTags, totalScripts))
if createdPath then
	print("[Conversor] LocalScript criado em: " .. createdPath)
	print("[Conversor] LocalScript dentro do StarterGui roda para cada jogador (vai pro PlayerGui).")
	print("[Conversor] A ScreenGui original NÃO foi apagada. Confira e depois pode apagar.")
end
if #warnings > 0 then
	print(string.format("[Conversor] %d avisos:", #warnings))
	for _, msg in ipairs(warnings) do print("   ! " .. msg) end
end
print(string.format("[Conversor] código gerado: %d bytes", #source))
print("════════════════════════════════════════════════════════════")

if CONFIG.PrintSource then
	if #source <= 4000 then
		print(source)
	else
		print("[Conversor] Código grande: imprimindo em blocos. Dica: dê 2 cliques no")
		print("[Conversor] LocalScript gerado no Explorer para ver/copiar tudo de uma vez.")
		local blocks, current, size = {}, {}, 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			current[#current + 1] = line
			size = size + #line + 1
			if size >= 1600 then
				blocks[#blocks + 1] = table.concat(current, "\n")
				current, size = {}, 0
			end
		end
		if #current > 0 then blocks[#blocks + 1] = table.concat(current, "\n") end
		for i, block in ipairs(blocks) do
			print(string.format("---------- código %d/%d ----------", i, #blocks))
			print(block)
		end
	end
end

return source
