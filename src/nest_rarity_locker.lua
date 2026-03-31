local modVersion = "v1.1.1"

local enumNone = "NONE"
local enumMax = "MAX"
local enumUnknown = "UNKNOWN"
local enumInvalid = "INVALID"
local nestRandom = "RANDOM"
local nestEggFes = "EGG"

local nestTypeEnum = nil
local nestRarityEnum = nil
local nestFesTypeEnum = nil

local nestTypeRandomFixedId = nil
local nestEggFesId = nil
local checkedLockChanged = false
local checkedEnableDualEggChanged = false
local comboChanged = false
local comboSelectedIdx = 1
local isLoadedUserConfig = false

local configPath = "NestRarityLocker.json"
local userConfig = {
    enableLock = false,
    currentSelectRareFixedId = nil,
    enableDualEggNest = false
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
            userConfig.enableDualEggNest = jsonContent.enableDualEggNest
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
        nestFesTypeEnum = {
            fixedIdToContent = {},
            contentToFixedId = {},
            fixedId = {},
            content = {}
        }
        parseEnumFields("app.NestDef.NEST_TYPE_Fixed", nestTypeEnum, false)
        parseEnumFields("app.NestDef.NEST_RARITY_Fixed", nestRarityEnum, false)
        parseEnumFields("app.NestDef.FES_TYPE", nestFesTypeEnum, false)

        nestTypeRandomFixedId = nestTypeEnum.contentToFixedId[nestRandom]
        print("Random Nest Type Fixed ID: ", nestTypeRandomFixedId)
        nestEggFesId = nestFesTypeEnum.contentToFixedId[nestEggFes]
        print("Egg Fes Type ID: ", nestEggFesId)
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

local _this = nil
sdk.hook(sdk.find_type_definition("app.NestDungeonControllerData")
    :get_method("setupFesData(app.user_data.NestTableData.cData)"),
    function(args)
        _this = sdk.to_managed_object(args[2])
    end,
    function(retval)
        if _this ~= nil and
            userConfig.enableDualEggNest and
            nestEggFesId ~= nil
        then
            _this:call("set_FesType(app.NestDef.FES_TYPE)", nestEggFesId)
        end
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

        checkedLockChanged, userConfig.enableLock = imgui.checkbox("Enable Lock", userConfig.enableLock)
        if checkedLockChanged then
            saveUserConfig()
        end

        checkedEnableDualEggChanged, userConfig.enableDualEggNest = imgui.checkbox("Force Dual-egg Nest",
            userConfig.enableDualEggNest)
        if checkedEnableDualEggChanged then
            saveUserConfig()
        end

        imgui.tree_pop()
    end
end)
