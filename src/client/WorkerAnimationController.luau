--!strict
-- Client-only cosmetics. Confirmed world markers control existence, never income.
local WorkerAnimationController = {}
WorkerAnimationController.__index = WorkerAnimationController

function WorkerAnimationController.new(root: Instance, prefab: Model, reducedMotion: (() -> boolean)?): any
	local self: any = setmetatable({ _root = root, _prefab = prefab, _records = {}, _connections = {}, _elapsed = 0, _destroyed = false, _reducedMotion = reducedMotion }, WorkerAnimationController)
	local function added(instance: Instance)
		if instance:IsA("Folder") and instance.Name == "Trainee1" and instance:GetAttribute("WorkerCosmetic") == true then
			self:_mount(instance)
		end
	end
	table.insert(self._connections, root.DescendantAdded:Connect(added))
	table.insert(self._connections, root.DescendantRemoving:Connect(function(instance)
		if self._records[instance] then self:_remove(instance) end
	end))
	for _, instance in ipairs(root:GetDescendants()) do added(instance) end
	return self
end

function WorkerAnimationController:_mount(marker: Instance)
	if self._destroyed or self._records[marker] then return end
	local seat = marker.Parent
	if not seat or not seat:IsA("BasePart") then return end
	local model = self._prefab:Clone()
	model.Name = "WorkerCosmeticRig"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.EvaluateStateMachine = false end
	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("BasePart") then
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
			instance.Massless = true
		end
	end
	model:PivotTo(seat.CFrame)
	local joints = {}
	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("Motor6D") then joints[instance.Name] = { motor = instance, base = instance.C0 } end
	end
	self._records[marker] = { model = model, joints = joints }
	model.Parent = marker
end

function WorkerAnimationController:_remove(marker: Instance)
	local record = self._records[marker]
	if not record then return end
	self._records[marker] = nil
	for _, joint in pairs(record.joints) do joint.motor.C0 = joint.base end
	record.model:Destroy()
end

function WorkerAnimationController:Step(dt: number)
	if self._destroyed then return end
	self._elapsed += dt
	local t = self._elapsed
	local still = self._reducedMotion and self._reducedMotion()
	for marker, record in pairs(self._records) do
		if not marker:IsDescendantOf(self._root) or record.model.Parent ~= marker then
			self:_remove(marker)
		else
			-- A four-second typing phrase with a quiet pause, and a slow head glance.
			local typing = if still or t % 4 > 3 then 0 else math.sin(t * 12) * 0.035
			for _, side in ipairs({ "Left", "Right" }) do
				local direction = if side == "Left" then 1 else -1
				local wrist = record.joints[side .. "Wrist"]
				local elbow = record.joints[side .. "Elbow"]
				if wrist then wrist.motor.C0 = wrist.base * CFrame.Angles(direction * typing, 0, 0) end
				if elbow then elbow.motor.C0 = elbow.base * CFrame.new(0, typing * direction * 0.3, 0) end
			end
			local neck = record.joints.Neck
			local glance = if still then 0 else math.sin(math.clamp((t % 12 - 8) / 3, 0, 1) * math.pi) * 0.08
			if neck then neck.motor.C0 = neck.base * CFrame.Angles(0, glance, 0) end
		end
	end
end

function WorkerAnimationController:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, connection in ipairs(self._connections) do connection:Disconnect() end
	table.clear(self._connections)
	local markers = {}
	for marker in pairs(self._records) do table.insert(markers, marker) end
	for _, marker in ipairs(markers) do self:_remove(marker) end
end

return WorkerAnimationController
