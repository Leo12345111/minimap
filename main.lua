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

local mapContainer = Instance.new("Frame")
mapContainer.Name = "MapContainer"
mapContainer.Size = UDim2.new(0, 250, 0, 250)
mapContainer.Position = UDim2.new(0, 10, 1, -360)
mapContainer.BackgroundTransparency = 1 
mapContainer.BorderSizePixel = 0
mapContainer.Parent = screenGui

local mapClip = Instance.new("CanvasGroup")
mapClip.Name = "MapClip"
mapClip.Size = UDim2.new(1, 0, 1, 0)
mapClip.BackgroundColor3 = Color3.fromRGB(135, 206, 235)
mapClip.BorderSizePixel = 0
mapClip.Parent = mapContainer

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
local partCache = {}

local lastUpdatePos = Vector3.new(0, 0, 0)
local lastUpdateRot = 0 

local SCAN_RADIUS = 150 
local SCAN_VERTICAL = 1000 
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
overlapParams.MaxParts = 2000 

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local camera = workspace.CurrentCamera

local function getCenterPosAndRot()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root then
        return root.Position, root.Orientation.Y
    end
    
    local camCFrame = camera.CFrame
    local _, y, _ = camCFrame:ToOrientation()
    return camCFrame.Position, math.deg(y)
end

local function getFrame()
    local f = table.remove(framePool)
    if not f then
        f = Instance.new("Frame")
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.BorderSizePixel = 0 
        
        local corner = Instance.new("UICorner")
        corner.Name = "UICorner"
        corner.CornerRadius = UDim.new(0, 0) 
        corner.Parent = f
        
        local stroke = Instance.new("UIStroke")
        stroke.Name = "UIStroke"
        stroke.Color = Color3.fromRGB(0, 0, 0)
        stroke.Thickness = 1
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

local function getCachedPartData(part)
    if partCache[part] then return partCache[part] end
    
    local size = part.Size
    local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
    local realSize = size
    if mesh and typeof(mesh.Scale) == "Vector3" then
        realSize = Vector3_new(size.X * mesh.Scale.X, size.Y * mesh.Scale.Y, size.Z * mesh.Scale.Z)
    end
    
    local isRound = false
    if part:IsA("Part") and (part.Shape == Enum.PartType.Ball or part.Shape == Enum.PartType.Cylinder) then
        isRound = true
    end
    
    local data = {
        sX = realSize.X * SCALE,
        sZ = realSize.Z * SCALE,
        color = part.Color,
        isRound = isRound
    }
    partCache[part] = data
    return data
end

local function updateElementPositions()
    local cPos, cRot = getCenterPosAndRot()
    local cX, cZ = cPos.X, cPos.Z

    for part, frame in next, partFrames do
        if not part.Parent then
            releaseFrame(frame)
            partFrames[part] = nil
            partCache[part] = nil
            continue
        end

        local pos = part.Position
        local relX = (pos.X - cX) * SCALE
        local relZ = (pos.Z - cZ) * SCALE
        
        local guiX = HALF_MAP + relX
        local guiY = HALF_MAP + relZ
        
        local data = getCachedPartData(part)
        
        frame.Visible = true
        frame.Position = UDim2_new(0, guiX, 0, guiY)
        frame.Size = UDim2_new(0, max(1, data.sX), 0, max(1, data.sZ))
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
                    pivot.Rotation = -cRot
                end
            end
        else
            container.Visible = false
        end
    end
end

local function performScan()
    local cPos, cRot = getCenterPosAndRot()
    
    table.clear(foundThisScan)
    local char = player.Character
    if char then
        overlapParams.FilterDescendantsInstances = {char}
        rayParams.FilterDescendantsInstances = {char}
    else
        overlapParams.FilterDescendantsInstances = {}
        rayParams.FilterDescendantsInstances = {}
    end
    
    local downRay = workspace:Raycast(cPos, Vector3_new(0, -10000, 0), rayParams)
    
    if downRay and downRay.Instance:IsA("Terrain") then
        local matColor = workspace.Terrain:GetMaterialColor(downRay.Material)
        mapClip.BackgroundColor3 = matColor
    else
        mapClip.BackgroundColor3 = Color3.fromRGB(135, 206, 235)
    end

    local parts = workspace:GetPartBoundsInBox(CFrame_new(cPos), Vector3_new(SCAN_RADIUS * 2, SCAN_VERTICAL, SCAN_RADIUS * 2), overlapParams)

    local columns = {}
    
    if downRay and downRay.Instance:IsA("BasePart") then
        table.insert(parts, downRay.Instance)
    end

    for i = 1, #parts do
        local obj = parts[i]
        if obj.Transparency < 1 and not Players:GetPlayerFromCharacter(obj.Parent) then
            local gridX = floor(obj.Position.X / 10)
            local gridZ = floor(obj.Position.Z / 10)
            local key = gridX * 100000 + gridZ 
            
            if not columns[key] then columns[key] = {} end
            
            local alreadyAdded = false
            local col = columns[key]
            for j = 1, #col do
                if col[j] == obj then alreadyAdded = true break end
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
        local data = getCachedPartData(obj)
        
        if not f then
            f = getFrame()
            f.BackgroundColor3 = data.color 
            partFrames[obj] = f
            
            local corner = f:FindFirstChild("UICorner")
            if corner then
                corner.CornerRadius = data.isRound and UDim.new(0.5, 0) or UDim.new(0, 0)
            end
        end
        
        local alpha = min((depth - 1) * 0.2, 0.8)
        f.BackgroundTransparency = alpha
        
        local stroke = f:FindFirstChild("UIStroke")
        if stroke then
            stroke.Transparency = alpha
        end
        
        f.ZIndex = floor(obj.Position.Y) 
    end

    for part, frame in next, partFrames do
        if not foundThisScan[part] then
            releaseFrame(frame)
            partFrames[part] = nil
            partCache[part] = nil
        end
    end

    for p, container in next, playerIcons do
        if not p.Parent then
            container:Destroy()
            playerIcons[p] = nil
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
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
        if inputConn then inputConn:Disconnect() end
        screenGui:Destroy()
    end
end)

RunService.Heartbeat:Connect(function()
    if not scriptActive then return end
    
    local currentPos, currentRot = getCenterPosAndRot()
    
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
