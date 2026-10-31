--!strict
-- Buzzer Simulator — Theme (BS-07)
-- Visual tokens, palette, typography, and standard styling helpers.
-- Theme: BuzzerOS Cozy Retro Tech (docs/05).

local TweenService = game:GetService("TweenService")

local Theme = {}

-- Palette
Theme.Colors = {
	-- Cozy Retro Tech Base
	Charcoal = Color3.fromRGB(48, 52, 60),      -- #30343C Background / Main panels
	CharcoalDark = Color3.fromRGB(36, 39, 46),  -- #24272E Deep background / Sidebar
	CharcoalLight = Color3.fromRGB(60, 66, 76), -- #3C424C Card background / Secondary panels
	Border = Color3.fromRGB(78, 86, 98),        -- #4E5662 Subtle borders / Dividers
	BorderLight = Color3.fromRGB(105, 115, 130),-- #697382 Highlight borders

	-- Cozy Warm Elements
	Cream = Color3.fromRGB(242, 229, 213),      -- #F2E5D5 Text primary / Light accents
	CreamMuted = Color3.fromRGB(200, 190, 178), -- #C8BEB2 Text secondary
	Walnut = Color3.fromRGB(120, 88, 67),       -- #785843 Warm wood furniture accent
	Sage = Color3.fromRGB(168, 182, 156),       -- #A8B69C Muted sage accent
	Navy = Color3.fromRGB(52, 70, 90),          -- #34465A Header & banner background
	Amber = Color3.fromRGB(242, 188, 121),      -- #F2BC79 Warm gold / Soft amber accent

	-- Functional accents (restrained)
	Lime = Color3.fromRGB(140, 179, 105),       -- #8CB369 Active / Success / Online rate
	Coral = Color3.fromRGB(217, 125, 100),      -- #D97D64 Alert / Warning / Save blocked
	MutedGold = Color3.fromRGB(212, 168, 92),   -- #D4A85C Secondary currency tone
	Disabled = Color3.fromRGB(90, 96, 106),     -- #5A606A Disabled controls
	DisabledText = Color3.fromRGB(130, 136, 146),-- #828892 Disabled label
}

-- Typography
Theme.Fonts = {
	Regular = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Black = Enum.Font.GothamBlack,
}

Theme.TextSizes = {
	Tiny = 11,
	Small = 13,
	Body = 15,
	Subtitle = 18,
	Title = 22,
	Header = 26,
	Display = 32,
}

-- Spacing & Radii
Theme.Radii = {
	Small = UDim.new(0, 4),
	Medium = UDim.new(0, 8),
	Large = UDim.new(0, 12),
	Pill = UDim.new(1, 0),
}

Theme.Spacing = {
	XS = 4,
	SM = 8,
	MD = 12,
	LG = 16,
	XL = 24,
	XXL = 32,
}

-- Helper functions
function Theme.applyCorner(instance: GuiObject, radius: UDim?): UICorner
	local corner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.Radii.Medium
	corner.Parent = instance
	return corner
end

function Theme.applyStroke(instance: GuiObject, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local stroke = instance:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = color or Theme.Colors.Border
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

function Theme.applyPadding(instance: GuiObject, top: number?, right: number?, bottom: number?, left: number?): UIPadding
	local padding = instance:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	local t = top or 0
	local r = right or t
	local b = bottom or t
	local l = left or r
	padding.PaddingTop = UDim.new(0, t)
	padding.PaddingRight = UDim.new(0, r)
	padding.PaddingBottom = UDim.new(0, b)
	padding.PaddingLeft = UDim.new(0, l)
	padding.Parent = instance
	return padding
end

-- Reusable motion tween
function Theme.tween(instance: Instance, tweenInfo: TweenInfo, properties: { [string]: any }): Tween
	local tw = TweenService:Create(instance, tweenInfo, properties)
	tw:Play()
	return tw
end

-- Formats a number with commas for readable currency display (e.g. 1,234)
function Theme.formatNumber(n: number): string
	local formatted = tostring(math.floor(n))
	local k
	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return formatted
end

return Theme
