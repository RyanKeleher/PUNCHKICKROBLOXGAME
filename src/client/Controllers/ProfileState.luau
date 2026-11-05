-- Holds the latest copy of this player's profile from the server and tells
-- the UI when it changes. It's a mirror for display only; changing it does
-- nothing, because the server never reads it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)

local ProfileState = {}
ProfileState.data = nil :: any
ProfileState.Changed = Signal.new() -- (data, previous)

function ProfileState.start()
	Remotes.get("ProfileUpdated").OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then
			return
		end
		local previous = ProfileState.data
		ProfileState.data = data
		ProfileState.Changed:Fire(data, previous)
	end)
	-- In case the first push happened before we were listening.
	Remotes.get("RequestSync"):FireServer()
end

return ProfileState
