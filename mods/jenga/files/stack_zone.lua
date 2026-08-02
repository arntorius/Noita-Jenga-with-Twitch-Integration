local zone=GetUpdatedEntityID()
if zone==nil or zone==0 or not EntityGetIsAlive(zone) then return end
local zx,zy=EntityGetTransform(zone)
local sprite=EntityGetFirstComponentIncludingDisabled(zone,"SpriteComponent")
if sprite~=nil then ComponentSetValue2(sprite,"alpha",0.89+math.sin(GameGetFrameNum()*0.06)*0.11) end
local wands=EntityGetInRadiusWithTag(zx,zy,140,"jenga_stacked_wand") or {}
table.sort(wands,function(a,b) return a<b end)
for index,wand in ipairs(wands) do
 if index<=30 and EntityGetIsAlive(wand) then
  local dir=index%2==0 and 1 or -1
  local rot=index%2==0 and math.rad(3) or math.rad(-3)
  EntitySetTransform(wand,zx+dir*5,zy-7-(index-1)*4,rot)
  local v=EntityGetFirstComponentIncludingDisabled(wand,"VelocityComponent")
  if v~=nil then ComponentSetValue2(v,"mVelocity",0,0) end
 end
end
