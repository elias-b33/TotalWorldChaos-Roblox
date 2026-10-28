--!strict
-- Your own shop state, as the server tells it (Shop remote): owned items, equipped items, VIP, purchase history,
-- whether Robux purchases are open and whether to show the starter-pack offer. The client never grants anything.
-- Also the [VIP] chat tag: players with VIP carry a "Vip" attribute the server sets.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local ShopState = {}

local view: Types.ShopView? = nil
local ownedSet: { [string]: boolean } = {}
local listeners: { (offer: boolean) -> () } = {}

function ShopState.init()
	Remotes.event("Shop").OnClientEvent:Connect(function(data: Types.ShopView)
		view = data
		ownedSet = {}
		for _, id in data.owned do
			ownedSet[id] = true
		end
		for _, fn in listeners do
			task.spawn(fn, data.starterOffer)
		end
	end)
	-- [VIP] before VIP players' chat messages (TextChatService as-is: no custom chat)
	pcall(function()
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local player = if source then Players:GetPlayerByUserId(source.UserId) else nil
			if player and player:GetAttribute("Vip") == true then
				props.PrefixText = '<font color="#F2C14E">[VIP]</font> ' .. message.PrefixText
			end
			return props
		end
	end)
end

function ShopState.view(): Types.ShopView?
	return view
end

-- Owned in the profile (items bought, offers bought). Free and VIP items: see ShopState.owns.
function ShopState.inProfile(id: string): boolean
	return ownedSet[id] == true
end

function ShopState.vip(): boolean
	return view ~= nil and view.vip
end

-- The same profile shape Sim.Shop reads, from what the server sent.
local function profile(): Types.PlayerProfile
	return ({ owned = ownedSet, equipped = if view then view.equipped else {} } :: any) :: Types.PlayerProfile
end

-- Do I own this item or offer (bought, free, or with VIP)?
function ShopState.owns(id: string): boolean
	return Shop.owns(profile(), id, ShopState.vip())
end

-- Is this item what I wear in its slot?
function ShopState.isEquipped(item: Types.CatalogueItem): boolean
	return Shop.equippedIn(profile(), Shop.equipKey(item), ShopState.vip()) == item.id
end

-- fn(offer) after every update; offer = true when the starter-pack pop-up should show now.
function ShopState.onChange(fn: (offer: boolean) -> ())
	table.insert(listeners, fn)
end

return ShopState
