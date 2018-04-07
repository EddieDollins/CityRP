PLUGIN.name = "Organization"
PLUGIN.author = "Black Tea"
PLUGIN.desc = "Organization plugin."

nut.org = nut.org or {}
nut.org.loaded = nut.org.loaded or {}

ORGANIZATION_ENABLED = true

if (ORGANIZATION_ENABLED != true) then return end

ORGANIZATION_DEFUALT_NAME = "Unnamed Organization"
ORGANIZATION_AUTO_DELETE_TIME = 60*60*24*5 -- 5 days of inactivity will get your organization deleted.

nut.util.include("meta/sh_character.lua")
nut.util.include("meta/sh_organization.lua")
nut.util.include("vgui/cl_orgmanager.lua")
nut.util.include("vgui/cl_orgjoiner.lua")
nut.util.include("sv_database.lua")

if (SERVER) then
    function nut.org.create(callback)
        local ponNull = pon.encode({})

		local timeStamp = os.date("%Y-%m-%d %H:%M:%S", os.time())
        nut.db.insertTable({
            _name = ORGANIZATION_DEFUALT_NAME,
            _lastModify = timeStamp,
            _level = 1, 
            _experience = 0,
            _data = ponNull
        }, function(succ, orgID) 
            if (succ != false) then
                local org = nut.org.new()
                org.id = orgID
                nut.org.loaded[orgID] = org

                if (callback) then
                    org:sync()
                    callback(org)
                end
            end
        end, "organization")
    end

    function nut.org.delete(id)
        local org = nut.org.loaded[id]
        
        if (org) then
            local affectedPlayers

            for k, v in ipairs(player.GetAll()) do
                local char = v:getChar()

                if (char) then
                    local charOrg = char:getOrganization()

                    if (charOrg == id) then
                        targetChar:setData("organization", nil, nil, player.GetAll())
                        targetChar:setData("organizationRank", nil, nil, player.GetAll())

                        table.insert(affectedPlayers, v)
                    end
                end
            end

            hook.Run("OnOranizationDeleted", org, affectedPlayers)

            org:unsync()

            nut.org.loaded[id] = nil
            nut.db.query("DELETE FROM nut_organization WHERE _id IN ("..org.id..")")

            return true
        else
            return false, "invalidOrg"
        end
    end

    function nut.org.syncAll(recipient)
        local orgData = {}
        for k, v in pairs(nut.org.loaded) do
            orgData[k] = v:getSyncInfo()
        end
        netstream.Start(recipient, "nutOrgSyncAll", orgData)
    end

    function nut.org.purge(callback)
        local timeStamp = os.date("%Y-%m-%d %H:%M:%S", os.time() - ORGANIZATION_AUTO_DELETE_TIME)
        
        nut.db.query("DELETE FROM nut_organization WHERE _lastModify <= '".. timeStamp .."'", function(data, data2)
            if (callback) then
                callback()
            end
        end)
    end

    function nut.org.load(id, callback)
        local org = nut.org.new()

        nut.db.query("SELECT _id, _name, _level, _experience, _data FROM nut_organization WHERE _id IN ("..id..")", function(data)
            if (data) then
                for k, v in ipairs(data) do
                    local org = nut.org.new()
                    org.id = tonumber(v._id)
                    org.name = v._name
                    org.level = tonumber(v._level)
                    org.experience = tonumber(v._experience)
                    org.data = pon.decode(v._data)

                    nut.org.loaded[org.id] = org

                    nut.db.query("SELECT _orgID, _charID, _rank, _name FROM nut_orgmembers WHERE _orgID IN ("..org.id..")", function(data)
                        if (data) then
                            for k, v in ipairs(data) do
                                local rank = tonumber(v._rank)
                                org.members[rank] = org.members[rank] or {}
                                org.members[rank][tonumber(v._charID)] = v._name
                            end
                        end

                        if (callback) then
                            callback(org)
                        end
                    end)
                end
            end
        end)
    end
    
    function nut.org.loadAll(callback)
        local org = nut.org.new()

        nut.db.query("SELECT _id, _name, _level, _experience, _data FROM nut_organization", function(data)
            if (data) then
                for k, v in ipairs(data) do
                    local org = nut.org.new()
                    org.id = tonumber(v._id)
                    org.name = v._name
                    org.level = tonumber(v._level)
                    org.experience = tonumber(v._experience)
                    org.data = pon.decode(v._data)

                    nut.org.loaded[org.id] = org

                    nut.db.query("SELECT _orgID, _charID, _rank, _name FROM nut_orgmembers WHERE _orgID IN ("..org.id..")", function(data)
                        if (data) then
                            for k, v in ipairs(data) do
                                local rank = tonumber(v._rank)
                                org.members[rank] = org.members[rank] or {}
                                org.members[rank][tonumber(v._charID)] = v._name
                            end
                        end

                        if (callback) then
                            callback(org)
                        end
                    end)
                end
            end
        end)
    end
end

if (SERVER) then
    function PLUGIN:PlayerInitialSpawn(client)
        nut.org.syncAll(client)

        local fookinData = {}
        for k, v in ipairs(player.GetAll()) do
            if (v == client) then continue end
            
            local char = v:getChar()

            if (char) then
                local id = char:getID()

                if (char:getOrganization() != -1) then
                    fookinData[id] = {
                        char:getData("organization"),
                        char:getData("organizationRank")
                    }
                end
            end
        end
        netstream.Start(client, "nutOrgCharSync", fookinData)
    end

    function PLUGIN:InitializedPlugins()
        nut.org.purge(function()
            nut.org.loadAll(function(org)
                hook.Run("OnOrganizationLoaded", org)
            end)
        end)
    end

    function PLUGIN:CanChangeOrganizationVariable(client, key, value)

    end

    function PLUGIN:CanCreateOrganization(client)
        return true
    end

    function PLUGIN:OnCreateOrganization(client, organization)

    end

    function PLUGIN:PlayerCanJoinOrganization()

    end
end

if (CLIENT) then
    -- organization networkings
    do
        netstream.Hook("nutOrgCharSync", function(data)
            for id, syncDat in pairs(data) do
                local character = nut.char.loaded[id]
                
                if (character) then
                    character.vars.data = character.vars.data or {}

                    character:getData()["organization"] = syncDat[1]
                    character:getData()["organizationRank"] = syncDat[2]
                end
            end
        end)
        --sync specific server organization data
        netstream.Hook("nutOrgSyncAll", function(orgsData)
            if (data) then
                for id, data in pairs(orgsData) do
                    local org = nut.org.new()

                    for k, v in pairs(data) do
                        org[k] = v
                    end

                    nut.org.loaded[id] = org
                end
            else
                print("got org sync request but no data found")
            end
        end)

        --sync specific server organization data
        netstream.Hook("nutOrgSync", function(id, data)
            if (data) then
                local org = nut.org.new()

                for k, v in pairs(data) do
                    org[k] = v
                end

                nut.org.loaded[id] = org
            else
                print("got org sync request but no data found")
            end
        end)

        netstream.Hook("nutOrgRemove", function(id)
            nut.org.loaded[id] = nil
        end)
        --sync 
        netstream.Hook("nutOrgSyncValue", function(id, key, value)
            if (nut.org.loaded[id]) then
                nut.org.loaded[id][key] = value
            end
        end)

        netstream.Hook("nutOrgSyncData", function(id, key, value)
            print(id, key, value)
            if (nut.org.loaded[id] and nut.org.loaded[id].data) then
                nut.org.loaded[id].data[key] = value
            end
        end)
        
        netstream.Hook("nutOrgSyncMember", function(id, rank, charID, isChange)
            local org = nut.org.loaded[id]

            if (org) then
                if (isChange) then
                    for i = ORGANIZATION_MEMBER, ORGANIZATION_OWNER do
                        if (org.members[i] and org.members[i][charID]) then
                            org.members[i][charID] = nil
                            break
                        end
                    end
                end

                local char = nut.char.loaded[charID]

                org.members[rank] = org.members[rank] or {}
                org.members[rank][charID] = char and char:getName() or true
            end
        end)
    end
else
    -- ui networkings
    do
        netstream.Hook("nutOrgCreate", function(client)
            local char = client:getChar()
            
            if (char) then
                if (hook.Run("CanCreateOrganization", client) == false) then return end

                nut.org.create(function(orgObject)
                    orgObject:setOwner(char)
                    hook.Run("OnCreateOrganization", client, orgObject)
                end)
            end
        end)

        netstream.Hook("nutOrgJoin", function(client, orgID)
            local char = client:getChar()
            
            if (char) then
                local org = nut.org.loaded[orgID]

                if (org) then
                    local bool, reason = char:canJoinOrganization()

                    if (bool != false) then
                        org:addCharacter(char)
                    else
                        client:notifyLocalized(reason)
                    end
                else
                    client:notifyLocalized("invalidOrg")
                end
            end
        end)

        netstream.Hook("nutOrgExit", function(client)
            local char = client:getChar()
            
            if (char) then
                local org = char:getOrganizationInfo()

                if (org) then
                    org:removeCharacter(char)
                else
                    client:notifyLocalized("invalidOrg")
                end
            end
        end)

        netstream.Hook("nutOrgDelete", function(client)
            local char = client:getChar()
            
            if (char) then
                local org = char:getOrganizationInfo()

                if (org) then
                    nut.org.delete(org:getID())
                else
                    client:notifyLocalized("invalidOrg")
                end
            end
        end)

        netstream.Hook("nutOrgKick", function(client, target)
            
        end)

        netstream.Hook("nutOrgAssign", function(client, target, rank)
            local char = client:getChar()
            
            if (char) then
                local org = char:getOrganizationInfo()

                if (org) then
                    nut.org.delete(org:getID())
                else
                    client:notifyLocalized("invalidOrg")
                end
            end
        end)

        netstream.Hook("nutOrgChangeOwner", function(client, target)
        
        end)

        netstream.Hook("nutOrgChangeValue", function(client, key, value)
            local char = client:getChar()
            
            if (char) then
                local org = char:getOrganizationInfo()

                if (org) then
                    local bool, reason = hook.Run("CanChangeOrganizationVariable", client, key, value)

                    if (bool) then
                        org:setData(key, value)
                    else
                        client:notifyLocalized(reason)
                    end
                else
                    client:notifyLocalized("invalidOrg")
                end
            end
        end)
    end
end

--TODO: on player change the name, update the organization db!
--TODO: on player deletes the character, wipe out organization data!