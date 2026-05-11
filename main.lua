local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MiniMapGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- THE CONTAINER: Holds everything together
local mapContainer = Instance.new("Frame")
mapContainer.Name = "MapContainer"
mapContainer.Size = UDim2.new(0, 250, 0, 250)
mapContainer.Position = UDim2.new(0, 10, 1, -360)
mapContainer.BackgroundTransparency = 1 
mapContainer.BorderSizePixel = 0
mapContainer.Parent = screenGui

-- THE SCISSORS: CanvasGroup physically cuts all pixels that go outside of its box
local mapClip = Instance.new("CanvasGroup")
mapClip.Name = "MapClip"
mapClip.Size = UDim2.new(1, 0, 1, 0)
mapClip.BackgroundColor3 = Color3.fromRGB(135, 206, 235)
mapClip.BorderSizePixel = 0
mapClip.Parent = mapContainer

-- THE OUTLINE: Draws the big black border around the whole minimap
local mapOutline = Instance.new("Frame")
mapOutline.Name = "MapOutline"
mapOutline.Size = UDim2.new(1, 0, 1, 0)
mapOutline.BackgroundTransparency = 1
mapOutline.BorderColor3 = Color3.fromRGB(0, 0, 0)
mapOutline.BorderSizePixel = 2
mapOutline.ZIndex = 99999 
mapOutline.Parent = mapContainer

local scriptActive = true
local partFrames = {}
local playerIcons = {}

local lastUpdatePos = Vector3.new(0, 0, 0)
local lastUpdateRot = 0 

local SCAN_RADIUS = 150 
local SCAN_VERTICAL = 10000 
local MAP_SIZE = 250
local SCALE = MAP_SIZE / (SCAN_RADIUS * 2)
local HALF_MAP = MAP_SIZE / 2

local framePool = {}

local floor = math.floor
local max = math.max
local min = math.min
local abs = math.abs
local UDim2_new = UDim2.new
local Vector3_new = Vector3.new
local CFrame_new = CFrame.new

local foundThisScan = {}
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.MaxParts = 100000 

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function getFrame()
    local f = table.remove(framePool)
    if not f then
        f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        -- Turn off default border because UICorner breaks it
        f.BorderSizePixel = 0 
        
        local corner = Instance.new("UICorner")
        corner.Name = "UICorner"
        corner.CornerRadius = UDim.new(0, 0) 
        corner.Parent = f
        
        -- THE FIX: UIStroke forces an outline on the shape even if it has rounded corners!
        local stroke = Instance.new("UIStroke")
        stroke.Name = "UIStroke"
        stroke.Color = Color3.fromRGB(0, 0, 0) -- Black outline
        stroke.Thickness = 1 -- 1 pixel thick
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = f
        
        f.Parent = mapClip
    end
    f.Visible = true
    return f
end

local function releaseFrame(f)
    f.Visible = false
    table.insert(framePool, f)
end

local function getRealSize(part)
    local size = part.Size
    local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
    if mesh and typeof(mesh.Scale) == "Vector3" then
        return Vector3_new(size.X * mesh.Scale.X, size.Y * mesh.Scale.Y, size.Z * mesh.Scale.Z)
    end
    return size
end

local function updateElementPositions()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local centerPos = root.Position
    local cX, cZ = centerPos.X, centerPos.Z

    for part, frame in next, partFrames do
        if not part.Parent then
            releaseFrame(frame)
            partFrames[part] = nil
            continue
        end

        local pos = part.Position
        local relX = (pos.X - cX) * SCALE
        local relZ = (pos.Z - cZ) * SCALE
        
        local guiX = HALF_MAP + relX
        local guiY = HALF_MAP + relZ
        
        local realSize = getRealSize(part)
        local sX, sZ = realSize.X * SCALE, realSize.Z * SCALE
        
        frame.Visible = true
        frame.Position = UDim2_new(0, guiX, 0, guiY)
        frame.Size = UDim2_new(0, max(1, sX), 0, max(1, sZ))
        frame.Rotation = -part.Orientation.Y
    end

    for p, container in next, playerIcons do
        local pChar = p.Character
        local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
        local pVis = pChar and pChar:FindFirstChildOfClass("Humanoid")
        
        if pRoot and pVis and pVis.Health > 0 then
            local pPos = pRoot.Position
            local guiX = HALF_MAP + ((pPos.X - cX) * SCALE)
            local guiY = HALF_MAP + ((pPos.Z - cZ) * SCALE)
            
            container.Position = UDim2_new(0, guiX - 10, 0, guiY - 10)
            container.Visible = (guiX >= 0 and guiX <= MAP_SIZE and guiY >= 0 and guiY <= MAP_SIZE)
            
            if p == player then
                local pivot = container:FindFirstChild("DirectionPivot")
                if pivot then
                    pivot.Rotation = -root.Orientation.Y
                end
            end
        else
            container.Visible = false
        end
    end
end

local function performScan()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    table.clear(foundThisScan)
    overlapParams.FilterDescendantsInstances = {char}
    rayParams.FilterDescendantsInstances = {char}
    
    local downRay = workspace:Raycast(root.Position, Vector3_new(0, -10000, 0), rayParams)
    
    if downRay and downRay.Instance:IsA("Terrain") then
        local matColor = workspace.Terrain:GetMaterialColor(downRay.Material)
        mapClip.BackgroundColor3 = matColor
    else
        mapClip.BackgroundColor3 = Color3.fromRGB(135, 206, 235)
    end

    local parts = workspace:GetPartBoundsInBox(CFrame_new(root.Position), Vector3_new(SCAN_RADIUS * 2, SCAN_VERTICAL, SCAN_RADIUS * 2), overlapParams)

    local columns = {}
    
    if downRay and downRay.Instance:IsA("BasePart") then
        table.insert(parts, downRay.Instance)
    end

    for i = 1, #parts do
        local obj = parts[i]
        if obj.Transparency < 1 and not Players:GetPlayerFromCharacter(obj.Parent) then
            local gridX = floor(obj.Position.X / 10)
            local gridZ = floor(obj.Position.Z / 10)
            local key = gridX .. "_" .. gridZ
            
            if not columns[key] then columns[key] = {} end
            
            local alreadyAdded = false
            for _, existingObj in ipairs(columns[key]) do
                if existingObj == obj then alreadyAdded = true break end
            end
            
            if not alreadyAdded then
                table.insert(columns[key], obj)
            end
        end
    end

    local partDepth = {}
    for _, col in pairs(columns) do
        table.sort(col, function(a, b) return a.Position.Y < b.Position.Y end)
        for idx, obj in ipairs(col) do
            partDepth[obj] = max(partDepth[obj] or 1, idx)
        end
    end

    for obj, depth in pairs(partDepth) do
        foundThisScan[obj] = true
        local f = partFrames[obj]
        
        if not f then
            f = getFrame()
            f.BackgroundColor3 = obj.Color 
            partFrames[obj] = f
            
            local isRound = false
            if obj:IsA("Part") and (obj.Shape == Enum.PartType.Ball or obj.Shape == Enum.PartType.Cylinder) then
                isRound = true
            end
            
            local corner = f:FindFirstChild("UICorner")
            if corner then
                corner.CornerRadius = isRound and UDim.new(0.5, 0) or UDim.new(0, 0)
            end
        end
        
        -- Keeps the 20% layering math perfect
        f.BackgroundTransparency = min((depth - 1) * 0.2, 0.8)
        
        -- Also applies transparency to the stroke outline so it matches perfectly
        local stroke = f:FindFirstChild("UIStroke")
        if stroke then
            stroke.Transparency = min((depth - 1) * 0.2, 0.8)
        end
        
        f.ZIndex = floor(obj.Position.Y) 
    end

    for part, frame in next, partFrames do
        if not foundThisScan[part] then
            releaseFrame(frame)
            partFrames[part] = nil
        end
    end

    for p, container in next, playerIcons do
        if not p.Parent then
            container:Destroy()
            playerIcons[p] = nil
        end
    end

    for _, p in next, Players:GetPlayers() do
        if not playerIcons[p] and p.Character then
            local container = Instance.new("Frame")
            container.Name = p.Name .. "Icon"
            container.Size = UDim2_new(0, 20, 0, 20)
            container.BackgroundTransparency = 1
            container.ZIndex = 50000 
            container.Parent = mapClip
            playerIcons[p] = container
            
            local icon = Instance.new("ImageLabel")
            icon.Size = UDim2_new(1, 0, 1, 0)
            icon.BackgroundTransparency = 1
            icon.ZIndex = 50001 
            icon.Parent = container
            
            if p == player then
                local pivot = Instance.new("Frame")
                pivot.Name = "DirectionPivot"
                pivot.Size = UDim2_new(0, 0, 0, 0)
                pivot.Position = UDim2_new(0.5, 0, 0.5, 0)
                pivot.BackgroundTransparency = 1
                pivot.ZIndex = 50000 
                pivot.Parent = container
                
                local arrow = Instance.new("TextLabel")
                arrow.Name = "Arrow"
                arrow.Size = UDim2_new(0, 14, 0, 14)
                arrow.AnchorPoint = Vector2.new(0.5, 1) 
                arrow.Position = UDim2_new(0, 0, 0, -11) 
                arrow.BackgroundTransparency = 1
                arrow.Text = "▲" 
                arrow.TextColor3 = Color3.fromRGB(255, 0, 0) 
                arrow.TextScaled = true
                arrow.ZIndex = 50000
                arrow.Parent = pivot
            end
            
            task.spawn(function()
                local content, ready = Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                if ready then icon.Image = content end
            end)
        end
    end
end

local inputConn
inputConn = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.M then
        performScan()
    elseif input.KeyCode == Enum.KeyCode.U then
        scriptActive = false
        inputConn:Disconnect()
        screenGui:Destroy()
    end
end)

RunService.Heartbeat:Connect(function()
    if not scriptActive then return end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    
    local currentPos = root.Position
    local currentRot = root.Orientation.Y
    
    local magX = currentPos.X - lastUpdatePos.X
    local magZ = currentPos.Z - lastUpdatePos.Z
    
    local posChanged = (magX * magX + magZ * magZ) > 0.01
    local rotChanged = abs(currentRot - lastUpdateRot) > 0.5
    
    if posChanged or rotChanged then
        updateElementPositions()
        lastUpdatePos = currentPos
        lastUpdateRot = currentRot
    end
end)

task.spawn(function()
    while scriptActive do
        performScan()
        task.wait(0.25)
    end
end)
