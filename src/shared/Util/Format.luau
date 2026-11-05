local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa" }

-- 1234 -> "1,234"
function Format.commas(n: number): string
	local s = tostring(math.floor(n))
	local sign = ""
	if string.sub(s, 1, 1) == "-" then
		sign = "-"
		s = string.sub(s, 2)
	end
	local out = string.reverse(s):gsub("(%d%d%d)", "%1,")
	out = string.reverse(out)
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return sign .. out
end

-- 1234567 -> "1.23M"
function Format.short(n: number): string
	local i = 1
	local value = n
	while math.abs(value) >= 1000 and i < #SUFFIXES do
		value /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(value))
	end
	local text = string.format("%.2f%s", value, SUFFIXES[i]):gsub("%.?0+([A-Za-z]+)$", "%1")
	return text
end

-- 3725 -> "1h 2m"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return `{h}h {m}m`
	elseif m > 0 then
		return `{m}m {s}s`
	end
	return `{s}s`
end

return Format
