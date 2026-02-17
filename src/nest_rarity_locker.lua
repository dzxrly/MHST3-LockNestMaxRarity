local modVersion = "v0.2.0"

local enumNone = "NONE"
local enumMax = "MAX"
local enumUnknown = "UNKNOWN"
local enumInvalid = "INVALID"
local nestRandom = "RANDOM"

local nestTypeEnum = nil
local nestRarityEnum = nil
local nestTypeRandomFixedId = nil
local nestMaxRartyFixedId = nil
local checkedChanged = false
local comboChanged = false
local comboSelectedIdx = 1
local isLoadedUserConfig = false

local configPath = "NestRarityLocker.json"
local userConfig = {
    enableLock = false,
    currentSelectRareFixedId = nil
}

local function isValidEnumName(enumName)
    return tostring(enumName) ~= enumNone and tostring(enumName) ~= enumMax and tostring(enumName) ~= enumUnknown and
               tostring(enumName) ~= enumInvalid
end

local function appendEnumValue(enumState, enumName, enumValue)
    enumState.fixedIdToContent[enumValue] = enumName
    enumState.contentToFixedId[enumName] = enumValue
    table.insert(enumState.fixedId, enumValue)
    table.insert(enumState.content, enumName)
end

local function parseEnumFields(typeName, enumState, dedupeByValue)
    local typeDef = sdk.find_type_definition(typeName)
    if typeDef == nil then
        return
    end

    local enumFields = typeDef:get_fields()
    if enumFields == nil then
        return
    end

    local seenEnumValue = {}
    for _, field in ipairs(enumFields) do
        if field:is_static() then
            local enumName = field:get_name()
            local enumValue = field:get_data(nil)
            local valueKey = tostring(enumValue)
            if isValidEnumName(enumName) and (not dedupeByValue or not seenEnumValue[valueKey]) then
                seenEnumValue[valueKey] = true
                appendEnumValue(enumState, enumName, enumValue)
            end
        end
    end
end

local function readUserConfig()
    if json ~= nil then
        local jsonContent = json.load_file(configPath)
        if jsonContent then
            userConfig.enableLock = jsonContent.enableLock
            userConfig.currentSelectRareFixedId = jsonContent.currentSelectRareFixedId
        else
            json.dump_file(configPath, userConfig)
        end
    else
        print("JSON library not found. User configuration will not be saved.")
    end
end

local function saveUserConfig()
    if json ~= nil then
        json.dump_file(configPath, userConfig)
    else
        print("JSON library not found. User configuration will not be saved.")
    end
end

re.on_application_entry("UpdateScene", function()
    if nestTypeEnum == nil or nestRarityEnum == nil then
        nestTypeEnum = {
            fixedIdToContent = {},
            contentToFixedId = {},
            fixedId = {},
            content = {}
        }
        nestRarityEnum = {
            fixedIdToContent = {},
            contentToFixedId = {},
            fixedId = {},
            content = {}
        }
        parseEnumFields("app.NestDef.NEST_TYPE_Fixed", nestTypeEnum, false)
        parseEnumFields("app.NestDef.NEST_RARITY_Fixed", nestRarityEnum, false)

        nestTypeRandomFixedId = nestTypeEnum.contentToFixedId[nestRandom]
        print("Random Nest Type Fixed ID: ", nestTypeRandomFixedId)
    end

    if not isLoadedUserConfig then
        readUserConfig()
        isLoadedUserConfig = true
    end
end)

sdk.hook(sdk.find_type_definition("app.NestController"):get_method(
    "createContext(app.NestDef.NestPlaceData, app.NestDef.NEST_TYPE_Fixed, app.NestDef.NEST_RARITY_Fixed, System.Boolean, app.cBattleResult.cHomingInfo)"),
    function(args)
        local originNestType = sdk.to_int64(args[4])
        local originNestRarity = sdk.to_int64(args[5])
        if originNestType ~= nil and originNestRarity ~= nil and userConfig.enableLock and
            userConfig.currentSelectRareFixedId ~= nil then
            if originNestType == nestTypeRandomFixedId then
                args[5] = sdk.to_ptr(userConfig.currentSelectRareFixedId)
            end
        end
    end, function(retval)
        return retval
    end)

re.on_draw_ui(function()
    if imgui.tree_node("Nest Rarity Locker") then
        imgui.text("VERSION: " .. modVersion .. " | by Egg Targaryen")

        imgui.text("Current Selected Rarity: ")
        imgui.same_line()
        if nestRarityEnum ~= nil and nestTypeEnum ~= nil then
            if userConfig.currentSelectRareFixedId ~= nil then
                local rarityName = nestRarityEnum.fixedIdToContent[userConfig.currentSelectRareFixedId]
                -- find the index of rarityName in nestRarityEnum.content
                for idx, name in ipairs(nestRarityEnum.content) do
                    if name == rarityName then
                        comboSelectedIdx = idx
                        break
                    end
                end
            end

            comboChanged, comboSelectedIdx = imgui.combo("##NestRarityCombo", comboSelectedIdx, nestRarityEnum.content)
            if comboChanged then
                local selectedRarityFixedId = nestRarityEnum.contentToFixedId[nestRarityEnum.content[comboSelectedIdx]]
                userConfig.currentSelectRareFixedId = selectedRarityFixedId
                saveUserConfig()
            end
        end

        checkedChanged, userConfig.enableLock = imgui.checkbox("Enable Lock", userConfig.enableLock)
        if checkedChanged then
            saveUserConfig()
        end

        imgui.tree_pop()
    end
end)
