ConfigFilePath = "YMS_CombatLottery/config.txt"
Vars = nil

function ReadConfig(ConfigFilePath)
    local defaults = {
        {"debug", "0"},
        {"number", "4"},
        {"gameover", "0"},
    }
    
    local config = {}
    local configFileContent = Ext.IO.LoadFile(ConfigFilePath)
    if configFileContent and configFileContent ~= "" then
        for line in configFileContent:gmatch("[^\r\n]+") do
            local key, value = line:match("^(%w+)=(%w+)")
            if key and value then
                config[key] = value
            end
        end
    end
    
    local configText = ""
    for _, keyValuePair in ipairs(defaults) do
        local key = keyValuePair[1]
        local defaultValue = keyValuePair[2]
        config[key] = config[key] or defaultValue
        configText = configText .. key .. "=" .. config[key]  .. "\n"
    end
    Ext.IO.SaveFile(ConfigFilePath, configText)
    
    return config  -- config 변수를 반환하여 Vars를 초기화
end

function GetVar(varName)
    if (Vars == nil) then
        Vars = ReadConfig(ConfigFilePath)
    end
    return tonumber(Vars[varName])
end

-- 파티원을 로또에 등록하고, 등록한 파티원 순서를 섞고 앞에서 4개를 뺀 나머지 파티원 추방
registry = {}
teleportList = {}
oldCombatID = 0
oldPosition = {0, 0, 0}

-- Fisher-Yates 알고리즘을 사용하여 배열을 무작위로 섞는 함수
function shuffleArray(array)
    print("[CMBT_LTRY_DBG]: shuffleArray 호출")
    local currentIndex = #array
    local randomIndex
    while currentIndex > 1 do
        randomIndex = math.random(currentIndex)
        array[currentIndex], array[randomIndex] = array[randomIndex], array[currentIndex]
        currentIndex = currentIndex - 1
    end
end

-- 캠프로 보낼 파티원 뽑기
function setTeleportList()
    print("[CMBT_LTRY_DBG]: setTeleportList 호출")
    -- 트루 파티 초기화
    registry = {}
    local Party = Osi.DB_PartyMembers:Get(nil)
    print("[CMBT_LTRY_DBG]: 전체 파티원:")
    for i = 1, #Party do
        print("[CMBT_LTRY_DBG]: 파티원", i, Party[i][1])
    end
    -- 등록된 파티원 카운트
    for i = #Party, 1, -1 do 
        -- 파티에 참여한 캐릭터가 소환물이 아닌 경우
        if ( Osi.IsSummon(Party[i][1]) == 0 ) then
            if Osi.HasActiveStatus(Party[i][1], 'REGISTERED') == 1 then
                table.insert(registry,i)
            end
        end
    end
    print("[CMBT_LTRY_DBG]: 등록된 파티원:")
    for i = 1, #registry do
        print("[CMBT_LTRY_DBG]: 파티원", i, Party[registry[i]][1])
    end
    shuffleArray(registry)
    -- 1부터 n번째 원소를 제거
    local n = GetVar("number")
    for i = 1, n do
        table.remove(registry, 1)  -- 첫 번째 원소를 제거하면 나머지 원소들이 앞으로 이동합니다.
    end
    teleportList = registry
    print("[CMBT_LTRY_DBG]: 이동할 파티원:")
    for i = 1, #teleportList do
        print("[CMBT_LTRY_DBG]: 파티원", i, Party[teleportList[i]][1])
    end
end

-- 전투 시작
Ext.Osiris.RegisterListener("EnteredCombat", 2, "before", function(CharID, newCombatID)
    print("[CMBT_LTRY_DBG]: 전투 시작, 기존 전투 ID: ", oldCombatID)
    print("[CMBT_LTRY_DBG]: 전투 시작, 현재 전투 ID: ", newCombatID)
    if (oldCombatID == newCombatID) then
        print("[CMBT_LTRY_DBG]: 기존 전투 참가")
    else
        print("[CMBT_LTRY_DBG]: 신규 전투 발생")
        local Party = Osi.DB_PartyMembers:Get(nil)
        local newPosition1, newPosition2, newPosition3 = Osi.GetPosition(Party[1][1])
        print("[CMBT_LTRY_DBG]: 전투 시작, 아바타 기존 위치: ", oldPosition[1], oldPosition[2], oldPosition[3])
        print("[CMBT_LTRY_DBG]: 전투 시작, 아바타 신규 위치: ", newPosition1, newPosition2, newPosition3)
        -- 캐릭터 추방하기 전에 추방된거 되돌리기 (몇몇 전투에서 추방된 캐릭터가 전투에 참여해서 캐릭터 3개로 싸워야하는 버그가 있음)
        for i = #Party, 1, -1 do 
            print("[CMBT_LTRY_DBG]: 추방 해제:", Party[i][1])
            Osi.RemovePassive(Party[i][1], "DISABLED_IN_COMBAT")
            Osi.SetCanJoinCombat(Party[i][1], 1)
            -- Osi.TeleportToPosition(Party[i][1], oldPosition[1], oldPosition[2], oldPosition[3])
        end
        -- 목록 섞기
        setTeleportList()
        -- 캐릭터 추방
        for i = 1, #teleportList do
            print("[CMBT_LTRY_DBG]: 추방:", Party[ teleportList[i] ][1])
            Osi.AddPassive(Party[teleportList[i] ][1], "DISABLED_IN_COMBAT")
            Osi.SetCanJoinCombat(Party[teleportList[i] ][1], 0)
        end
        -- 추방된 캐릭터의 소환수 추방
        for j = #Party, 1, -1 do 
            local owner = Osi.CharacterGetOwner(Party[j][1])
            print("[CMBT_LTRY_DBG]: 소환수 주인 검사:", Party[j][1], "의 주인: ", owner)
            for k = 1, #teleportList do
                possibleOwner = Party[ teleportList[k] ][1]
                slicedPossibleOwner = string.sub(possibleOwner, #possibleOwner - 35)
                print(slicedPossibleOwner)
                if ( slicedPossibleOwner == owner ) then
                    print("[CMBT_LTRY_DBG]: 소환수 추방:", Party[j][1])
                    Osi.AddPassive(Party[j][1], "DISABLED_IN_COMBAT")
                    Osi.SetCanJoinCombat(Party[j][1], 0)
                end
            end
        end
        -- 추방된 캐릭터 이동
        -- for l = #Party, 1, -1 do 
        --     if ( Osi.HasPassive(Party[l][1], "DISABLED_IN_COMBAT") ) then
        --         print("[CMBT_LTRY_DBG]: 이동:", Party[l][1])
        --         Osi.TeleportTo(Party[l][1], Osi.DB_Camp:Get(Osi.DB_ActiveCamp:Get(nil)[1][1],nil,nil,nil)[1][2], "", 0, 1, 1, 1, 1)
        --     end
        -- end
        -- print("[CMBT_LTRY_DBG]: 야영지 이동 완료")
        print("[CMBT_LTRY_DBG]: 전투 ID 갱신")
        oldCombatID = newCombatID
        print("[CMBT_LTRY_DBG]: 아바타 위치 갱신")
        oldPosition = {newPosition1, newPosition2, newPosition3}
    end
end)

-- 전투 끝
Ext.Osiris.RegisterListener("CombatEnded",1,"after",function(combat)
    print("[CMBT_LTRY_DBG]: 전투 종료")
    local Party = Osi.DB_PartyMembers:Get(nil)
    -- 저장된 위치가 올바른지 검사
    -- if (oldPosition[1] == 0) then
    --     local newPosition1, newPosition2, newPosition3 = Osi.GetPosition(Party[1][1])
    --     oldPosition = {newPosition1, newPosition2, newPosition3}
    -- end
    for i = #Party, 1, -1 do 
        print("[CMBT_LTRY_DBG]: 추방 해제:", Party[i][1])
        Osi.RemovePassive(Party[i][1], "DISABLED_IN_COMBAT")
        Osi.SetCanJoinCombat(Party[i][1], 1)
        -- Osi.TeleportToPosition(Party[i][1], oldPosition[1], oldPosition[2], oldPosition[3])
    end
    print("[CMBT_LTRY_DBG]: 전투 ID 초기화")
    oldCombatID = 0
end)

-- 캐릭터가 파티에 참여할 때
Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    print("[CMBT_LTRY_DBG]: 캐릭터가 파티에 합류")
    -- 파티에 참여한 캐릭터가 소환물이 아닌 경우
    if ( Osi.IsSummon(character) == 0 ) then
        -- 등록 주문 추가
        if ( Osi.HasPassive(character, "Passive_Register") == 0 ) then
            Osi.AddPassive(character, "Passive_Register")
        end
        if ( Osi.HasPassive(character, "Passive_Register_All") == 0 ) then
            Osi.AddPassive(character, "Passive_Register_All")
        end
    end
end)

-- 캐릭터가 파티를 떠날 때
Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", function(character)
    print("[CMBT_LTRY_DBG]: 파티에서 떠남", character)
end)

Ext.Osiris.RegisterListener("SavegameLoaded", 0, "after", function ()
    print("[CMBT_LTRY_DBG]: 세이브 게임 로드됨")
    local Party = Osi.DB_PartyMembers:Get(nil)
    for i = #Party, 1, -1 do 
        if ( Osi.IsSummon(Party[i][1]) == 0 ) then
            -- 등록 주문 추가
            print("[CMBT_LTRY_DBG]: 등록 패시브 검사", Party[i][1])
            if ( Osi.HasPassive(Party[i][1], "Passive_Register") == 0 ) then
                Osi.AddPassive(Party[i][1], "Passive_Register")
                print("[CMBT_LTRY_DBG]: 등록 패시브 추가", Party[i][1])
            end
            if ( Osi.HasPassive(Party[i][1], "Passive_Register_All") == 0 ) then
                Osi.AddPassive(Party[i][1], "Passive_Register_All")
                print("[CMBT_LTRY_DBG]: 아군 등록 패시브 추가", Party[i][1])
            end
        end
    end
end)