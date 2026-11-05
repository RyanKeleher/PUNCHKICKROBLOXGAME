-- Small helpers so UI code reads as layout, not property noise.

local UIKit = {}

UIKit.Colors = {
	Panel = Color3.fromRGB(22, 22, 28),
	PanelLight = Color3.fromRGB(34, 34, 44),
	Button = Color3.fromRGB(55, 55, 70),
	Accent = Color3.fromRGB(255, 196, 50),
	Good = Color3.fromRGB(70, 200, 100),
	Bad = Color3.fromRGB(220, 70, 70),
	Text = Color3.fromRGB(240, 240, 245),
	Muted = Color3.fromRGB(160, 160, 175),
	Xp = Color3.fromRGB(90, 170, 255),
	Coin = Color3.fromRGB(255, 205, 60),
}

function UIKit.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or Color3.fromRGB(0, 0, 0)
	s.Thickness = thickness or 1.5
	s.Transparency = 0.2
	s.Parent = parent
	return s
end

function UIKit.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
	return p
end

local function apply(instance: Instance, props: { [string]: any }?)
	if props then
		for k, v in props do
			(instance :: any)[k] = v
		end
	end
end

function UIKit.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.Colors.Panel
	f.BorderSizePixel = 0
	apply(f, props)
	f.Parent = parent
	return f
end

function UIKit.label(parent: Instance, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = UIKit.Colors.Text
	l.Font = Enum.Font.GothamBold
	l.TextSize = 16
	l.Text = ""
	apply(l, props)
	l.Parent = parent
	return l
end

function UIKit.button(parent: Instance, text: string, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = UIKit.Colors.Button
	b.TextColor3 = UIKit.Colors.Text
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 16
	b.Text = text
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	UIKit.corner(b, 8)
	apply(b, props)
	b.Parent = parent
	return b
end

-- Keeps a fixed-pixel design (`designSize`) readable on any screen by scaling
-- the given GuiObject around its anchor point.
function UIKit.autoScale(object: GuiObject, designSize: Vector2, minScale: number?, maxScale: number?)
	local scale = Instance.new("UIScale")
	scale.Parent = object
	local camera = workspace.CurrentCamera
	local function update()
		local vp = camera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / designSize.X, vp.Y / designSize.Y), minScale or 0.5, maxScale or 1.2)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	update()
	return scale
end

return UIKit
