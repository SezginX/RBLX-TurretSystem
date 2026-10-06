-- Connected Discord-GitHub | Roblox: Sezrynn | Discord: _romax
local TurretManager = {}
TurretManager.__index = TurretManager -- using metatables to avoid high memory usage, flexible and easy to use


export type TurretConfig = { --using export type to make things easier for users
	FireRate: number,
	Damage: number,
	SFX: Sound,
	Range: number,
	AoE: number?,
	Active: boolean?,
	Priority: string,
}


export type TurretObject = { -- again making things easier for users when they create a turret they can change/adjust these values easily
	FireRate: number,
	Damage: number,
	HitSound: Sound,
	Range: number,
	AreaOfEffect: number,
	Active: boolean,
	Instance: Model,
	TurretPart: BasePart,
	AimPart: BasePart,
	OriginalPosition: CFrame,
	Beam: Beam,
	Priority: string,
	
	Activate: (self: TurretObject) -> (),
	Deactivate: (self: TurretObject) -> (),
	Destroy: (self: TurretObject) -> ()
}

local TweenService = game:GetService("TweenService") -- using tweenservice to make turret rotation smooth

local tweenInfo = TweenInfo.new(0.25,Enum.EasingStyle.Cubic,Enum.EasingDirection.InOut, 0, false)
local minimumFireRate = 0.1 -- put a minimum fire rate to prevent users from entering values such as 0.0001 and 0, which may cause the game to crash


function TurretManager.New(turretModel:Model, turretAim:BasePart, turretPart:BasePart, proximityPart: BasePart, cfg:TurretConfig): TurretObject
	local self = setmetatable({}, TurretManager)
	
	cfg = cfg or {} -- we used config as a parameter so that we don't have to create a parameter for each property we're using, only used parts and the turret model as a normal parameter
	assert(cfg.FireRate, "[TURRET MANAGER]: You need to set a fire rate!")
	assert(cfg.Damage, "[TURRET MANAGER]: You need to set a damage!")
	assert(cfg.SFX,"[TURRET MANAGER]: You need to set a hit sound!")
	assert(cfg.Range, "[TURRET MANAGER]: You need to set a range!")
	assert(cfg.Priority, "[TURRET MANAGER]: You need to set a priority! ('Nearest', 'LowestHealth', 'HighestHealth'")
    --giving errors if they haven't set the values we need for the turret to work, we could also give default values but I didn't want to do that and this is the way I prefer it to work

	--//CONFIGURATION//--
	self.FireRate = math.max(cfg.FireRate, minimumFireRate)
	self.Damage = cfg.Damage
	self.AreaOfEffect = cfg.AoE or 0
	self.HitSound = cfg.SFX
	self.Range = cfg.Range
	self.Active = cfg.Active or false
	self.Priority = cfg.Priority
	self.Instance = turretModel -- the turret model
	self.TurretPart = turretPart -- the part we'll use when rotating the turret, turretAim part can't be anchored, and a motor6D is needed inside the turretPart, p0 being turretpart, p1 being turretaim, then set its position properly
	self.AimPart = turretAim -- the part we'll use when raycasting & beam
	self.ProximityPart = proximityPart -- added this so we can easily test turrets
	--//CONFIGURATION END//--
	
	--//SETUP//--
	self.OriginalPosition = turretPart.CFrame -- we're saving original position of the turretpart to use it when deactivating the turret
	self.SwitchDelay = 0.25 -- added a delay when activating or deactivating the turret so that it doesn't create problems 
	self.Debounce = false -- added debounce to use the switch delay
	self.Attachment1 = Instance.new("Attachment") -- we're going to use these for the beam
	self.Attachment1.Parent = self.AimPart
	self.Attachment2 = Instance.new("Attachment")
	self.Attachment2.Parent = workspace.Terrain
	self.Beam = Instance.new("Beam")
	self.Beam.Parent = self.AimPart
	self.Beam.Attachment0 = self.Attachment1
	self.Beam.FaceCamera = true
	self.Beam.Width0 = 0.225
	self.Beam.Width1 = 0.225
	self.Beam.Enabled = true
	self.Beam.LightEmission = 1
	self.Beam.Color = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0))
	}
    self.Targets = {} -- used inside the _GetAppropriateTarget function
	self.OriginalMotorC0 = self.TurretPart.Motor6D.C0 -- again, saving it so we can use when we deactivate the turret
	
	self.Proximity = Instance.new("ProximityPrompt") -- this is honestly just for testing, you guys can enter and test out turrets by using the red parts in front of them
	self.Proximity.ActionText = "Enable"
	self.Proximity.ObjectText = "Turret"
	self.Proximity.Parent = self.ProximityPart
	self.Proximity.HoldDuration = 0.5
	self.Proximity.RequiresLineOfSight = false
	self.Proximity.MaxActivationDistance = 10
	self.Proximity.Triggered:Connect(function()
		if not self.Active then
			self:Activate()
		else
			self:Deactivate()
		end
		self.Proximity.ActionText = self.Active and "Disable" or "Enable"
	
	end)
	
	if self.Active then --if active is true then we instantly activate the turret
		task.spawn(function()
			self:_detectAndHit()
			self.Proximity.ActionText = "Disable"
		end)
	end
	return self
end

function TurretManager:_detectAndHit()
	while self.Active do
		    local parts = workspace:GetPartBoundsInRadius(self.AimPart.Position,self.Range) -- using getpartsboundinradius to get parts in the RANGE, instead of using any kind of Touched mechanic, or trying out the whole workspace parts, we're using this method, easy to use, doesn't overwhelm the server since it only checks the parts within the radius
			local filteredTarget = self:_GetAppropriateTarget(parts) -- we're getting the target with this function
		    if not filteredTarget then task.wait(self.FireRate); continue end -- if there is no target, wait and continue scanning, if we do not wait this code will create huge fps loss
		    local dir = filteredTarget.RootPart.Position - self.AimPart.Position -- we're getting the direction of the target from our turret, using this to calculate yaw and pitch
			local raycastParam = RaycastParams.new() -- we're using raycast params to ignore the turret instance
			raycastParam.FilterType = Enum.RaycastFilterType.Exclude 
			raycastParam.FilterDescendantsInstances = {self.Instance} -- ignoring turret instance
			local raycast = workspace:Raycast(self.AimPart.Position,dir,raycastParam) -- raycasting so we do not hit anyone behind walls or anything similar
			if raycast and filteredTarget.Humanoid.Health >0 then
				if raycast.Instance and raycast.Instance:IsDescendantOf(filteredTarget.RootPart.Parent) then -- what we're doing here is checking if the raycast hits the target we WANT, we're using isdescendantof because it's really easier than any other method such as doing a for loop to see if the part we're hitting is a player and it's the player we want etc.
					
					local yaw = math.atan2(-dir.X,-dir.Z) -- classic yaw calculation
					local facedCFrame = CFrame.new(self.TurretPart.Position) * CFrame.Angles(0,yaw,0) --using the yaw
					
					local pitch = math.asin(dir.Unit.Y) -- classic pitch calculation
					local minPitch = math.rad(-30) -- limiting the pitch when looking below
					local maxPitch = math.rad(25) -- limiting the pitch when looking up
				    local clampedPitch = math.clamp(pitch, minPitch, maxPitch) -- limiting method
					
					TweenService:Create(self.TurretPart, tweenInfo, {["CFrame"]=facedCFrame}):Play() -- smoothly aiming the turret
					
			      	local targetC0 = CFrame.new(self.OriginalMotorC0.Position) * CFrame.Angles(clampedPitch, 0, 0)
			     	TweenService:Create(self.TurretPart.Motor6D, tweenInfo, {C0 = targetC0}):Play() -- aiming the aimpart at the same time, we used motor6d to make it smooth and look like an actual part of the turret
					
					if self.AreaOfEffect <= 0 then -- basic condition check 
							filteredTarget.Humanoid:TakeDamage(self.Damage) -- damaging the humanoid
					else
						self:_ApplyAoEDamage(raycast.Position)
					end
					
					self:_createBeam(raycast.Position)
					self.HitSound:Play()
				
				end
			end
	    task.wait(self.FireRate) -- waiting fire rate
	end
end

function TurretManager:_GetAppropriateTarget(targets) -- parameter given here is getpartboundsinradius from the recent function
	local result	-- the variable we're going to use to store the data before we delete the self.Targets table
	local addedHumanoids = {} -- added a table for humanoids so that the function ignores the humanoid we already detected and logged
	for _, target in targets do
		local humanoid = target.Parent:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 and not table.find(addedHumanoids,humanoid) then -- if there is a humanoid and it's not already added then
			local hrp = humanoid.Parent:FindFirstChild("HumanoidRootPart")
			if hrp then 
				table.insert(self.Targets,{RootPart = hrp, Humanoid = humanoid}) -- logging both hrp and humanoid so we can use it when sorting out tables
				table.insert(addedHumanoids,humanoid) -- added to the ignore list
			end
		end
	end
	if #self.Targets>0 then
	   if self.Priority == "Nearest"then
			table.sort(self.Targets,function(a, b) -- using the table sort method, easier, shorter. We could also use another way which is just for looping the self.Targets table and using values such as local currentClosestDist etc
				return (a.RootPart.Position - self.AimPart.Position).Magnitude < (b.RootPart.Position - self.AimPart.Position).Magnitude -- classic distance calculation
			end)
        -- all below is same logic as mentioned above
	   elseif self.Priority == "LowestHealth" then
			table.sort(self.Targets, function(a,b)
				return a.Humanoid.Health < b.Humanoid.Health
			end)
	   elseif self.Priority == "HighestHealth" then
			table.sort(self.Targets, function(a,b) 
				return a.Humanoid.Health > b.Humanoid.Health
			end)
	   end
	end
	result = self.Targets[1] -- saving the data to the result variable because we need to clear self.Targets table, if we do it now(table.clear(self.Targets)) without using result variable and then return it (self.Targets[1]), it will return nil
	table.clear(self.Targets) -- we can clear it now since we saved the data
	return result -- returning the filtered result
end

function TurretManager:_ApplyAoEDamage(goalPosition:Vector3)
	local result = workspace:GetPartBoundsInRadius(goalPosition,self.AreaOfEffect) -- radius
	if result then
		local damagedHumanoids = {} -- saving damaged humanoids for same logic, so that they don't get damaged again
		local explosion = Instance.new("Explosion")
		explosion.Parent = workspace
		explosion.BlastPressure = 0 -- no pressure needed
		explosion.DestroyJointRadiusPercent = 0 -- not needed, we just want a visual explosion
		explosion.Position = goalPosition -- explosion point
		for _, part in result do
			local humanoid = part.Parent:FindFirstChild("Humanoid")
			if humanoid then
				if not table.find(damagedHumanoids,humanoid) then -- if its not on ignore list
					
					humanoid:TakeDamage(self.Damage)
					table.insert(damagedHumanoids,humanoid) -- added to ignore list so they don't get damage again
				end
			end
		end
	end
end

function TurretManager:_createBeam(goalPosition:Vector3)
	if not self.Active or not self.Beam or not self.Attachment2 then return end -- we're using this to prevent the function from crashing in case it gets destroyed via :Destroy method while turret is firing and rotating

	self.Attachment2.WorldPosition = goalPosition -- beam end position, not creating a beam instance for each time turret shoots, no need. I just made it so we don't set beam.attachment1 at first so beam is invisible, then when we set it, its instantly visible
	self.Beam.Attachment1 = self.Attachment2

	task.delay(0.075, function()
		if self.Beam and self.Beam.Parent then
			self.Beam.Attachment1 = nil -- shortly after remove the attachment from the beam
		end
	end)
end

function TurretManager:Deactivate()
	if self.Debounce then return end -- using this so they can't spam activate/deactivate
	self.Debounce = true
	
	self.Active = false
	TweenService:Create(self.TurretPart,tweenInfo,{["CFrame"] = self.OriginalPosition}):Play() -- smoothly moving the turretPart to original position
	TweenService:Create(self.TurretPart.Motor6D, tweenInfo, {C0 = self.OriginalMotorC0}):Play() -- smoothly moving the aimpart to original position
	task.delay(self.SwitchDelay, function()
		self.Debounce = false --debounce handling
	end)
end

function TurretManager:Activate()
	if self.Debounce then return end -- same logic above
	self.Debounce = true
	self.Active = true

	task.spawn(function()
		self:_detectAndHit() -- executing the scanner function and starting the turret
	end)
	task.delay(self.SwitchDelay, function()
		self.Debounce = false
	
	end)
end

function TurretManager:Destroy()
	self.Active = false -- ending the while loop immediately, to cause no issues
	if self.Instance then
		self.Instance:Destroy() -- destroying the whole turret model
 	end
	setmetatable(self, nil) -- removing the metatable to prevent memory leaks
	table.clear(self) -- clearing out the table
end

return TurretManager
