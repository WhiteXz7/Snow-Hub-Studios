--[[
	Mock mínimo do Roblox (Lua 5.1 / LuaJIT) para TESTAR o conversor fora do Studio.
	Não faz parte da entrega: existe só para `tests/run_test.lua` rodar o conversor
	verdadeiro contra uma árvore de instâncias e conferir o resultado.
]]
local M = {}

------------------------------------------------------------- DATA TYPES
local types = {}
local function defType(name, spec, mt)
	spec.type = name
	mt = mt or {}
	mt.__index = mt
	mt.__rbxspec = spec
	types[name] = { spec = spec, meta = mt, ctor = mt }
	return mt
end

local function isDataType(v)
	return type(v) == "table" and getmetatable(v) ~= nil and getmetatable(v).__rbxspec ~= nil
end

-- Color3
local Color3 = {}
function Color3.new(r, g, b)
	return setmetatable({ _rbxtype = "Color3", R = r or 0, G = g or 0, B = b or 0 }, Color3)
end
function Color3.fromRGB(r, g, b) return Color3.new(r / 255, g / 255, b / 255) end
Color3.__index = Color3
Color3.__rbxspec = { type = "Color3", fields = { "R", "G", "B" } }
Color3.__tostring = function(c)
	return string.format("%g, %g, %g", c.R, c.G, c.B)
end

-- UDim / UDim2
local UDim = {}
function UDim.new(s, o) return setmetatable({ _rbxtype = "UDim", Scale = s or 0, Offset = o or 0 }, UDim) end
UDim.__index = UDim
UDim.__rbxspec = { type = "UDim", fields = { "Scale", "Offset" } }
UDim.__tostring = function(u) return string.format("%g, %d", u.Scale, u.Offset) end

local UDim2 = {}
function UDim2.new(sx, ox, sy, oy)
	return setmetatable({ _rbxtype = "UDim2", X = UDim.new(sx or 0, ox or 0), Y = UDim.new(sy or 0, oy or 0) }, UDim2)
end
function UDim2.fromScale(sx, sy) return UDim2.new(sx, 0, sy, 0) end
UDim2.__index = UDim2
UDim2.__rbxspec = { type = "UDim2", fields = { "X", "Y" } }
UDim2.__tostring = function(u) return tostring(u.X) .. ", " .. tostring(u.Y) end

-- Vector2 / Vector3
local Vector2 = {}
function Vector2.new(x, y) return setmetatable({ _rbxtype = "Vector2", X = x or 0, Y = y or 0 }, Vector2) end
Vector2.__index = Vector2
Vector2.__rbxspec = { type = "Vector2", fields = { "X", "Y" } }
Vector2.__tostring = function(v) return string.format("%g, %g", v.X, v.Y) end

local Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ _rbxtype = "Vector3", X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end
Vector3.__index = Vector3
Vector3.__rbxspec = { type = "Vector3", fields = { "X", "Y", "Z" } }
Vector3.__tostring = function(v) return string.format("%g, %g, %g", v.X, v.Y, v.Z) end

-- CFrame (posição + rotação identidade, suficiente para o teste)
local CFrame = {}
function CFrame.new(a, b, c, d, e, f, g, h, i, j, k, l)
	local self = { _rbxtype = "CFrame", comps = {} }
	if d == nil then
		self.comps = { a or 0, b or 0, c or 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	else
		self.comps = { a, b, c, d, e, f, g, h, i, j, k, l }
	end
	return setmetatable(self, CFrame)
end
CFrame.__index = CFrame
function CFrame:GetComponents() return unpack(self.comps) end
CFrame.__rbxspec = { type = "CFrame", comps = true }
CFrame.__tostring = function(cf) return table.concat(cf.comps, ", ") end

-- Rect
local Rect = {}
function Rect.new(a, b, c, d)
	local min, max
	if isDataType(a) then min, max = a, b else min, max = Vector2.new(a or 0, b or 0), Vector2.new(c or 0, d or 0) end
	return setmetatable({ _rbxtype = "Rect", Min = min, Max = max }, Rect)
end
Rect.__index = Rect
Rect.__rbxspec = { type = "Rect", fields = { "Min", "Max" } }
Rect.__tostring = function(r) return tostring(r.Min) .. ", " .. tostring(r.Max) end

-- NumberSequence / ColorSequence
local NumberSequence = {}
local NumberSequenceKeypoint = { new = function(t, v, e)
	return { _rbxtype = "NumberSequenceKeypoint", Time = t, Value = v, Envelope = e or 0 }
end }
function NumberSequence.new(kps)
	if type(kps) == "number" then
		kps = { NumberSequenceKeypoint.new(0, kps), NumberSequenceKeypoint.new(1, kps) }
	end
	return setmetatable({ _rbxtype = "NumberSequence", Keypoints = kps }, NumberSequence)
end
NumberSequence.__index = NumberSequence
NumberSequence.__rbxspec = { type = "NumberSequence", list = "Keypoints", fields = { "Time", "Value", "Envelope" } }
NumberSequence.__tostring = function(ns)
	local out = {}
	for _, kp in ipairs(ns.Keypoints) do out[#out + 1] = string.format("%g/%g/%g", kp.Time, kp.Value, kp.Envelope) end
	return table.concat(out, " ")
end

local ColorSequence = {}
local ColorSequenceKeypoint = { new = function(t, c)
	return { _rbxtype = "ColorSequenceKeypoint", Time = t, Value = c }
end }
function ColorSequence.new(kps)
	if isDataType(kps) then
		kps = { ColorSequenceKeypoint.new(0, kps), ColorSequenceKeypoint.new(1, kps) }
	end
	return setmetatable({ _rbxtype = "ColorSequence", Keypoints = kps }, ColorSequence)
end
ColorSequence.__index = ColorSequence
ColorSequence.__rbxspec = { type = "ColorSequence", list = "Keypoints", fields = { "Time", "Value" } }
ColorSequence.__tostring = function(cs)
	local out = {}
	for _, kp in ipairs(cs.Keypoints) do out[#out + 1] = string.format("%g/%s", kp.Time, tostring(kp.Value)) end
	return table.concat(out, " ")
end

-- EnumItem / Enum
local EnumItem = {}
function EnumItem.new(enumType, name, value)
	return setmetatable({ _rbxtype = "EnumItem", EnumType = enumType, Name = name, Value = value }, EnumItem)
end
EnumItem.__index = EnumItem
EnumItem.__rbxspec = { type = "EnumItem", fields = { "EnumType", "Name" } }
EnumItem.__tostring = function(e) return "Enum." .. rawget(e.EnumType, "_typeName") .. "." .. e.Name end

local Enum = {}
local enumMeta = {
	__index = function(t, k)
		if k == "Name" then return rawget(t, "_typeName") end
		return nil
	end,
}
local function defEnum(name, names)
	local enumType = setmetatable({ _typeName = name, _rbxtype = "Enum" }, enumMeta)
	for i, n in ipairs(names) do
		enumType[n] = EnumItem.new(enumType, n, i - 1)
		if n == "Name" then rawset(enumType, "Name", enumType[n]) end -- membro sombreia o nome do tipo
	end
	Enum[name] = enumType
	return enumType
end
defEnum("ZIndexBehavior", { "Global", "Sibling" })
defEnum("Font", { "Legacy", "Gotham", "GothamBold", "Unknown" })
defEnum("FontWeight", { "Thin", "Regular", "Medium", "Bold", "Heavy" })
defEnum("FontStyle", { "Normal", "Italic" })
defEnum("TextXAlignment", { "Left", "Center", "Right" })
defEnum("TextYAlignment", { "Top", "Center", "Bottom" })
defEnum("SizeConstraint", { "RelativeXY", "RelativeXX", "RelativeYY" })
defEnum("AutomaticSize", { "None", "X", "Y", "XY" })
defEnum("ScaleType", { "Stretch", "Slice", "Tile", "Fit", "Crop" })
defEnum("FillDirection", { "Horizontal", "Vertical" })
defEnum("HorizontalAlignment", { "Left", "Center", "Right" })
defEnum("VerticalAlignment", { "Top", "Center", "Bottom" })
defEnum("SortOrder", { "LayoutOrder", "Name", "Custom" })
defEnum("EasingStyle", { "Linear", "Quad", "Back", "Elastic" })
defEnum("EasingDirection", { "In", "Out", "InOut" })
defEnum("AspectType", { "FitWithinMaxSize", "ScaleWithParentSize" })
defEnum("DominantAxis", { "Width", "Height" })
defEnum("BorderMode", { "Outline", "Middle", "Inset" })
defEnum("SafeAreaCompatibility", { "None", "PadInsetByCoreGuiSafeArea" })
defEnum("SelectionBehavior", { "Default", "Escape", "Stop" })
defEnum("NormalId", { "Top", "Bottom", "Left", "Right", "Front", "Back" })
defEnum("Axis", { "X", "Y", "Z" })
defEnum("Style", { "Custom", "Dropdown" })
defEnum("TextTruncate", { "None", "AtEnd" })
defEnum("ApplyStrokeMode", { "ContextBounds", "Border" })
defEnum("LineJoinMode", { "Round", "Bevel", "Miter" })

-- Font (DataType)
local Font = {}
function Font.new(family, weight, style)
	if type(family) == "string" then family = Enum.Font[family] or Enum.Font.Gotham end
	return setmetatable({
		_rbxtype = "Font", Family = family,
		Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal,
	}, Font)
end
Font.fromName = Font.new
Font.__index = Font
Font.__rbxspec = { type = "Font", fields = { "Family", "Weight", "Style" } }
Font.__tostring = function(f) return string.format("Font(%s,%s,%s)", f.Family.Name, f.Weight.Name, f.Style.Name) end

-- Content
local Content = {}
function Content.fromUri(uri) return setmetatable({ _rbxtype = "Content", uri = uri or "" }, Content) end
Content.__index = Content
Content.__rbxspec = { type = "Content", fields = { "uri" } }
Content.__tostring = function(c) return c.uri end

-- NumberRange
local NumberRange = {}
function NumberRange.new(a, b)
	return setmetatable({ _rbxtype = "NumberRange", Min = a or 0, Max = b or a or 0 }, NumberRange)
end
NumberRange.__index = NumberRange
NumberRange.__rbxspec = { type = "NumberRange", fields = { "Min", "Max" } }

-- BrickColor
local BrickColor = {}
function BrickColor.new(name) return setmetatable({ _rbxtype = "BrickColor", Name = name }, BrickColor) end
BrickColor.__index = BrickColor
BrickColor.__rbxspec = { type = "BrickColor", fields = { "Name" } }

------------------------------------------------------------------ ENUMS/CLASSES
local classDefs = {}
local function defClass(name, super, props, readonly)
	classDefs[name] = { super = super, props = props or {}, readonly = readonly or {} }
end

defClass("Instance", nil, { Name = nil, Archivable = true }, { ClassName = true })
defClass("LayerCollector", "Instance", { Enabled = true })
defClass("GuiBase2d", "LayerCollector", {
	SelectionGroup = false,
	SelectionBehaviorDown = Enum.SelectionBehavior.Default,
	SelectionBehaviorLeft = Enum.SelectionBehavior.Default,
	SelectionBehaviorRight = Enum.SelectionBehavior.Default,
	SelectionBehaviorUp = Enum.SelectionBehavior.Default,
})
defClass("GuiObject", "GuiBase2d", {
	Active = false, AnchorPoint = Vector2.new(0, 0), AutomaticSize = Enum.AutomaticSize.None,
	BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0,
	BorderColor3 = Color3.fromRGB(27, 42, 53), BorderMode = Enum.BorderMode.Outline,
	BorderSizePixel = 1, ClipsDescendants = false, Draggable = false,
	GroupColor3 = Color3.new(1, 1, 1), GroupTransparency = 0, LayoutOrder = 0,
	NextSelectionDown = nil, NextSelectionLeft = nil, NextSelectionRight = nil, NextSelectionUp = nil,
	Position = UDim2.new(0, 0, 0, 0), Rotation = 0, Selectable = false, SelectionImageObject = nil,
	Size = UDim2.new(0, 100, 0, 100), SizeConstraint = Enum.SizeConstraint.RelativeXY,
	Visible = true, ZIndex = 1,
}, { AbsolutePosition = true, AbsoluteSize = true })
defClass("Frame", "GuiObject", { Style = Enum.Style.Custom })
defClass("CanvasGroup", "GuiObject", {})
defClass("ScreenGui", "GuiBase2d", {
	ClipToDeviceSafeArea = false, DisplayOrder = 0, IgnoreGuiInset = false,
	ResetOnSpawn = true, SafeAreaCompatibility = Enum.SafeAreaCompatibility.None,
	ZIndexBehavior = Enum.ZIndexBehavior.Global,
})
local textProps = {
	Font = Enum.Font.Legacy, FontFace = Font.new(Enum.Font.Legacy), LineHeight = 1,
	MaxVisibleGraphemes = -1, RichText = false, Text = "Label", TextColor3 = Color3.new(0, 0, 0),
	TextScaled = false, TextSize = 14, TextStrokeColor3 = Color3.new(0, 0, 0),
	TextStrokeTransparency = 1, TextTransparency = 0, TextTruncate = Enum.TextTruncate.None,
	TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}
defClass("TextLabel", "GuiObject", textProps, { ContentText = true, TextBounds = true })
defClass("GuiButton", "GuiObject", {
	AutoButtonColor = true, Modal = false, Selected = false, Style = Enum.Style.Custom,
})
local buttonText = {}
for k, v in pairs(textProps) do buttonText[k] = v end
buttonText.Text = ""
defClass("TextButton", "GuiButton", buttonText)
local boxText = {}
for k, v in pairs(textProps) do boxText[k] = v end
boxText.Text = ""
boxText.ClearTextOnFocus = true
boxText.MultiLine = false
boxText.PlaceholderColor3 = Color3.fromRGB(178, 178, 178)
boxText.PlaceholderText = ""
boxText.TextEditable = true
defClass("TextBox", "GuiButton", boxText)
local imageProps = {
	Image = "", ImageColor3 = Color3.new(1, 1, 1), ImageContent = Content.fromUri(""),
	ImageRectOffset = Vector2.new(0, 0), ImageRectSize = Vector2.new(0, 0), ImageTransparency = 0,
	ScaleType = Enum.ScaleType.Stretch, SliceCenter = Rect.new(0, 0, 0, 0), SliceScale = 1,
	TileSize = UDim2.new(1, 0, 1, 0),
}
defClass("ImageLabel", "GuiObject", imageProps)
defClass("ImageButton", "GuiButton", imageProps)
defClass("ScrollingFrame", "GuiObject", {
	AutomaticCanvasSize = Enum.AutomaticSize.None, BottomImage = "rbxasset://textures/ui/Scroll/scroll-bottom.png",
	CanvasPosition = Vector2.new(0, 0), CanvasSize = UDim2.new(1, 0, 1, 0),
	MidImage = "rbxasset://textures/ui/Scroll/scroll-middle.png",
	ScrollBarImageColor3 = Color3.new(0, 0, 0), ScrollBarImageTransparency = 1,
	ScrollBarThickness = 12, ScrollingEnabled = true,
	TopImage = "rbxasset://textures/ui/Scroll/scroll-top.png", VerticalScrollBarThickness = 12,
})
defClass("ViewportFrame", "GuiObject", {
	Ambient = Color3.new(0, 0, 0), CameraCFrame = CFrame.new(0, 0, 0),
	CameraFieldOfView = 70, CurrentCamera = nil, ImageColor3 = Color3.new(1, 1, 1),
	ImageTransparency = 0, LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1),
})
defClass("UIBase", "Instance", {})
defClass("UIComponent", "UIBase", {})
defClass("UICorner", "UIComponent", { CornerRadius = UDim.new(0, 0) })
defClass("UIStroke", "UIComponent", {
	ApplyStrokeMode = Enum.ApplyStrokeMode.ContextBounds, Color = Color3.new(0, 0, 0),
	Enabled = true, LineJoinMode = Enum.LineJoinMode.Round, Thickness = 1, Transparency = 0,
})
defClass("UIGradient", "UIComponent", {
	Color = ColorSequence.new(Color3.new(1, 1, 1)), Enabled = true, Offset = Vector2.new(0, 0),
	Rotation = 0, Transparency = NumberSequence.new(0),
})
defClass("UIPadding", "UIComponent", {
	PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0),
	PaddingRight = UDim.new(0, 0), PaddingTop = UDim.new(0, 0),
})
defClass("UIScale", "UIComponent", { Scale = 1 })
defClass("UIConstraint", "UIComponent", {})
defClass("UIAspectRatioConstraint", "UIConstraint", {
	AspectRatio = 1, AspectType = Enum.AspectType.FitWithinMaxSize,
	DominantAxis = Enum.DominantAxis.Width, Enabled = true,
})
defClass("UISizeConstraint", "UIConstraint", {
	Enabled = true, MaxSize = Vector2.new(3.4028234663853e38, 3.4028234663853e38), MinSize = Vector2.new(0, 0),
})
defClass("UITextSizeConstraint", "UIConstraint", { MaxTextSize = 100, MinTextSize = 1 })
defClass("UILayout", "UIComponent", {})
defClass("UIListLayout", "UILayout", {
	FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Left,
	Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Top,
})
defClass("UIGridLayout", "UILayout", {
	CellPadding = UDim2.new(0, 4, 0, 4), CellSize = UDim2.new(0, 100, 0, 100),
	FillDirection = Enum.FillDirection.Horizontal, FillDirectionMaxCells = 0,
	HorizontalAlignment = Enum.HorizontalAlignment.Left, SortOrder = Enum.SortOrder.Name,
	VerticalAlignment = Enum.VerticalAlignment.Top,
})
defClass("UIPageLayout", "UILayout", {
	AnimatedEasingDirection = Enum.EasingDirection.Out, AnimatedEasingStyle = Enum.EasingStyle.Quad,
	Circular = false, EasingDirection = Enum.EasingDirection.Out, EasingStyle = Enum.EasingStyle.Quad,
	GamepadInputEnabled = true, Padding = UDim.new(0, 0), ScrollWheelInputEnabled = true,
	TouchInputEnabled = true, TweenTime = 1,
})
defClass("LuaSourceContainer", "Instance", { Source = "" })
defClass("LocalScript", "LuaSourceContainer", {})
defClass("Script", "LuaSourceContainer", { Enabled = true })
defClass("ModuleScript", "LuaSourceContainer", {})
defClass("Folder", "Instance", {})
defClass("ValueBase", "Instance", {})
defClass("StringValue", "ValueBase", { Value = "" })
defClass("IntValue", "ValueBase", { Value = 0 })
defClass("NumberValue", "ValueBase", { Value = 0 })
defClass("BoolValue", "ValueBase", { Value = false })
defClass("Color3Value", "ValueBase", { Value = Color3.new(1, 1, 1) })
defClass("ObjectValue", "ValueBase", { Value = nil })
defClass("Camera", "Instance", {})
defClass("PlayerGui", "Instance", {})
defClass("StarterGui", "Instance", {})
defClass("StarterPlayerScripts", "Instance", {})
defClass("StarterPlayer", "Instance", {})
defClass("Players", "Instance", {})
defClass("Player", "Instance", {})
defClass("ReflectionMetadataItem", "Instance", { IsScriptable = true })
defClass("ReflectionMetadataClass", "ReflectionMetadataItem", { Superclass = "" })
defClass("ReflectionMetadataProperty", "ReflectionMetadataItem", {})
defClass("ReflectionMetadataProperties", "ReflectionMetadataItem", {})

-- propriedades cujo valor padrão é nil (o Roblox tem, mas não dá pra guardar em table)
local nilDefaultProps = {
	GuiObject = { "NextSelectionDown", "NextSelectionLeft", "NextSelectionRight", "NextSelectionUp",
		"SelectionImageObject" },
	ViewportFrame = { "CurrentCamera" },
	ObjectValue = { "Value" },
}

local propSetCache, readonlyCache = {}, {}
local function propSet(className)
	if propSetCache[className] then return propSetCache[className] end
	local set = {}
	local c = className
	while c and classDefs[c] do
		for k in pairs(classDefs[c].props) do set[k] = true end
		for k in pairs(classDefs[c].readonly) do set[k] = true end
		for _, k in ipairs(nilDefaultProps[c] or {}) do set[k] = true end
		set.Parent = true
		set.Name = true
		c = classDefs[c].super
	end
	propSetCache[className] = set
	return set
end
local function readonlySet(className)
	if readonlyCache[className] then return readonlyCache[className] end
	local set = {}
	local c = className
	while c and classDefs[c] do
		for k in pairs(classDefs[c].readonly) do set[k] = true end
		c = classDefs[c].super
	end
	readonlyCache[className] = set
	return set
end
local function defaultOf(className, prop)
	local c = className
	while c and classDefs[c] do
		if classDefs[c].props[prop] ~= nil then return classDefs[c].props[prop] end
		if classDefs[c].readonly[prop] then
			if prop == "ClassName" then return className end
			if prop == "AbsolutePosition" then return Vector2.new(0, 0) end
			if prop == "AbsoluteSize" then return Vector2.new(100, 100) end
			if prop == "ContentText" then return "" end
			if prop == "TextBounds" then return Vector2.new(0, 0) end
		end
		c = classDefs[c].super
	end
	if prop == "Name" then return className end
	return nil
end

---------------------------------------------------------------- INSTANCE
local childrenOf = {}   -- instance -> array
local parentOf = {}
local tagsOf = {}
local instanceMethods = {}

local instMeta = {}
instMeta.__index = function(t, k)
	local props = rawget(t, "props")
	if props[k] ~= nil then return props[k] end
	local extra = rawget(t, "_extra")
	if extra and extra[k] ~= nil then return extra[k] end
	local m = instanceMethods[k]
	if m then return m end -- chamado com ':' pelo código testado
	local cls = rawget(t, "class")
	if k == "Name" then return className end
	if propSet(cls)[k] then
		local d = defaultOf(cls, k)
		if d == nil and (k == "NextSelectionDown" or k == "NextSelectionLeft" or k == "NextSelectionRight"
			or k == "NextSelectionUp" or k == "SelectionImageObject" or k == "CurrentCamera" or k == "Value") then
			return nil
		end
		return d
	end
	error(string.format("%s is not a valid member of %s", tostring(k), cls), 2)
end
instMeta.__newindex = function(t, k, v)
	local cls = rawget(t, "class")
	if k == "Parent" then
		local old = parentOf[t]
		if old then
			local list = childrenOf[old]
			for i, c in ipairs(list) do
				if c == t then table.remove(list, i) break end
			end
		end
		parentOf[t] = v
		if v then
			childrenOf[v] = childrenOf[v] or {}
			table.insert(childrenOf[v], t)
		end
		return
	end
	if readonlySet(cls)[k] then
		error(string.format("%s is not a valid (writable) member of %s", tostring(k), cls), 2)
	end
	if not propSet(cls)[k] then
		error(string.format("%s is not a valid member of %s", tostring(k), cls), 2)
	end
	rawget(t, "props")[k] = v
end
instMeta.__tostring = function(t) return tostring(rawget(t, "props").Name) end

function instanceMethods.IsA(t, className)
	local c = rawget(t, "class")
	while c do
		if c == className then return true end
		c = classDefs[c] and classDefs[c].super or nil
	end
	return false
end
function instanceMethods.GetChildren(t)
	local out = {}
	for _, c in ipairs(childrenOf[t] or {}) do out[#out + 1] = c end
	return out
end
function instanceMethods.GetDescendants(t)
	local out = {}
	local function rec(node)
		for _, c in ipairs(childrenOf[node] or {}) do out[#out + 1] = c rec(c) end
	end
	rec(t)
	return out
end
function instanceMethods.FindFirstChild(t, name)
	for _, c in ipairs(childrenOf[t] or {}) do
		if rawget(c, "props").Name == name then return c end
	end
	return nil
end
function instanceMethods.WaitForChild(t, name) return instanceMethods.FindFirstChild(t, name) end
function instanceMethods.GetParent(t) return parentOf[t] end
function instanceMethods.GetFullName(t)
	local parts, node = {}, t
	while node do
		parts[#parts + 1] = tostring(rawget(node, "props").Name)
		node = parentOf[node]
	end
	local out = {}
	for i = #parts, 1, -1 do out[#out + 1] = parts[i] end
	return table.concat(out, ".")
end
function instanceMethods.Destroy(t)
	local p = parentOf[t]
	if p then
		local list = childrenOf[p]
		for i, c in ipairs(list) do
			if c == t then table.remove(list, i) break end
		end
		parentOf[t] = nil
	end
	childrenOf[t] = {}
end
function instanceMethods.GetAttributes(t)
	local out = {}
	for k, v in pairs(rawget(t, "attributes") or {}) do out[k] = v end
	return out
end
function instanceMethods.SetAttribute(t, k, v)
	rawget(t, "attributes")[k] = v
end
function instanceMethods.GetAttribute(t, k) return rawget(t, "attributes")[k] end

local Instance = {}
function Instance.new(className, parent)
	if not classDefs[className] then error("Invalid class: " .. tostring(className), 2) end
	local t = setmetatable({
		class = className,
		props = { Name = defaultOf(className, "Name") },
		attributes = {},
		_extra = {},
	}, instMeta)
	childrenOf[t] = {}
	if parent then t.Parent = parent end
	return t
end

--------------------------------------------------------------- SERVIÇOS
local tagStore = {}
local CollectionService = {}
function CollectionService:GetTags(inst)
	local out = {}
	for _, tag in ipairs(tagStore[inst] or {}) do out[#out + 1] = tag end
	return out
end
function CollectionService:AddTag(inst, tag)
	tagStore[inst] = tagStore[inst] or {}
	table.insert(tagStore[inst], tag)
end
function CollectionService:RemoveTag(inst, tag)
	local list = tagStore[inst] or {}
	for i, t in ipairs(list) do
		if t == tag then table.remove(list, i) break end
	end
end

-- ReflectionMetadata fake: expõe as propriedades de cada classe (inclusive
-- readonly), para exercitar o caminho de reflexão do conversor.
local function buildReflectionMetadata()
	local root = Instance.new("Folder")
	root.Name = "ReflectionMetadata"
	local classes = Instance.new("Folder")
	classes.Name = "Classes"
	classes.Parent = root
	for className, def in pairs(classDefs) do
		local cls = Instance.new("ReflectionMetadataClass")
		cls.Name = className
		cls.Superclass = def.super or ""
		cls.Parent = classes
		local group = Instance.new("ReflectionMetadataProperties")
		group.Name = "Properties"
		group.Parent = cls
		for prop in pairs(propSet(className)) do
			local p = Instance.new("ReflectionMetadataProperty")
			p.Name = prop
			p.IsScriptable = true
			p.Parent = group
		end
	end
	return root
end

local function buildDataModel()
	local services = {}
	local game = {}
	function game:GetService(name)
		if not services[name] then
			if name == "CollectionService" then
				services[name] = CollectionService
			elseif name == "ReflectionMetadata" then
				services[name] = buildReflectionMetadata()
			elseif classDefs[name] then
				local s = Instance.new(name)
				s.Name = name
				services[name] = s
			else
				error("Service não mockado: " .. tostring(name), 2)
			end
		end
		return services[name]
	end
	game.GetService = game.GetService

	local players = game:GetService("Players")
	local localPlayer = Instance.new("Player")
	localPlayer.Name = "Tester"
	localPlayer.Parent = players
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	playerGui.Parent = localPlayer
	M.setExtra(players, "LocalPlayer", localPlayer)
	M.setExtra(players, "LocalPlayerChanged", { Wait = function() return localPlayer end })

	local starterPlayer = game:GetService("StarterPlayer")
	local sps = Instance.new("StarterPlayerScripts")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = starterPlayer
	return game
end

---------------------------------------------------------------- typeof
local function rbxTypeof(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__rbxspec then return mt.__rbxspec.type end
		if mt == instMeta then return "Instance" end
	end
	return t
end

M.Color3, M.UDim, M.UDim2, M.Vector2, M.Vector3, M.CFrame = Color3, UDim, UDim2, Vector2, Vector3, CFrame
M.Rect, M.NumberSequence, M.ColorSequence, M.NumberRange = Rect, NumberSequence, ColorSequence, NumberRange
M.NumberSequenceKeypoint, M.ColorSequenceKeypoint = NumberSequenceKeypoint, ColorSequenceKeypoint
M.Font, M.Content, M.BrickColor, M.Enum, M.EnumItem = Font, Content, BrickColor, Enum, EnumItem
M.Instance, M.classDefs, M.rbxTypeof = Instance, classDefs, rbxTypeof

function M.setExtra(inst, k, v) rawget(inst, "_extra")[k] = v end

function M.install(env)
	env = env or _G
	env.game = buildDataModel()
	env.Instance = Instance
	env.Enum = Enum
	env.Color3, env.UDim, env.UDim2 = Color3, UDim, UDim2
	env.Vector2, env.Vector3, env.CFrame = Vector2, Vector3, CFrame
	env.Rect, env.NumberRange = Rect, NumberRange
	env.NumberSequence, env.ColorSequence = NumberSequence, ColorSequence
	env.NumberSequenceKeypoint, env.ColorSequenceKeypoint = NumberSequenceKeypoint, ColorSequenceKeypoint
	env.Font, env.Content, env.BrickColor = Font, Content, BrickColor
	env.typeof = rbxTypeof
	env.CollectionService = CollectionService
	return env
end

return M
