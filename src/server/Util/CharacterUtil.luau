local CharacterUtil = {}

-- Returns the player's HumanoidRootPart only if they are alive.
-- Dead players must not be able to drop, pick up, gather, etc.
function CharacterUtil.getAliveRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

return CharacterUtil
