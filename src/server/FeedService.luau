--!strict
-- Public feed projections are shared with the native client UI.
local Presentation = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Presentation"))

export type FeedCard = Presentation.FeedCard

return Presentation
