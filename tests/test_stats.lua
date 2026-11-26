local source=assert(arg[1])
local function near(a,b)assert(math.abs(a-b)<0.000001,tostring(a)..' differs from '..tostring(b))end
function UnitName()return 'Héro "Example"' end
function UnitLevel()return 29 end
function UnitClass()return 'Priest','PRIEST',5 end
function UnitRace(unit)assert(unit=='player');return 'Elfe de la nuit','NightElf',4 end
function UnitFactionGroup(unit)assert(unit=='player');return 'Alliance','Localized Alliance' end
function GetMoney(...)assert(select('#',...)==0);return 123456 end
function UnitXP(unit)assert(unit=='player');return 150 end
function UnitXPMax(unit)assert(unit=='player');return 1000 end
function GetXPExhaustion(...)assert(select('#',...)==0);return 250 end
function IsXPUserDisabled(...)assert(select('#',...)==0);return false end
function GetZoneText()return 'Example City' end
function GetSubZoneText()return 'Example District' end
C_Map={GetBestMapForUnit=function()return 1453 end,GetPlayerMapPosition=function()return {GetXY=function()return .64,.72 end}end}
local currentReads=0
function UnitHealth()currentReads=currentReads+1;error('Current health must not be queried')end
function UnitHealthMax()return 500 end
function UnitPower()currentReads=currentReads+1;error('Current mana must not be queried')end
function UnitPowerMax(unit,power)assert(unit=='player' and power==0);return 800 end
function GetUnitSpeed()return 0,8.4,14,4.7 end
function UnitStat(unit,index)assert(unit=='player');return 20+index,25+index,7,-2 end
function UnitAttackSpeed()return 2.5,nil,1.8 end
function UnitDamage()return 25,50,9,11,5,-1,1.2 end
function UnitRangedDamage()return 2,40,60,3,-1,1.1 end
function GetInventoryItemID(unit,slot)assert(slot==18);return 123 end
function UnitAttackPower()return 100,20,-5 end
function UnitRangedAttackPower()return 80,10,-3 end
function GetCritChance()return 4.5 end
function GetRangedCritChance()return 5.5 end
function GetSpellCritChance(index)assert(index>=2 and index<=7);return index+.5 end
function GetMeleeHaste()return 2 end
function GetRangedHaste()return 3 end
function UnitSpellHaste(unit)assert(unit=='player');return 4 end
function GetSpellBonusDamage(index)assert(index>=2 and index<=7);return index*10 end
function GetSpellBonusHealing()return 77 end
function UnitDefenseSkill()return 145,5 end
function GetDodgeChance()return 6.5 end
function UnitArmor()return 200,250,220,30 end
function UnitResistance(unit,index)return index*10,index*10+1,index*10+5,4 end
Enum={Damageclass={Arcane=6,Fire=2,Frost=4,Nature=3,Shadow=5}}
dofile(source)
local basic=ExporterStats.Basic(1234)
assert(basic.available and basic.name=='Héro "Example"' and basic.level==29 and basic.classID==5)
assert(basic.status=='available' and basic.raceName=='Elfe de la nuit' and basic.faction=='Alliance')
assert(basic.moneyCopper==123456 and basic.xp.current==150 and basic.xp.levelTotal==1000
    and basic.xp.rested==250 and basic.xp.disabled==false)
local location=ExporterStats.Location(1234)
assert(location.status=='available' and location.x==.64 and location.capturedAt==1234)
local s=ExporterStats.Capture(1234)
assert(s.status=='available' and s.capturedAt==1234)
assert(s.general.health.maximum==500 and s.general.mana.maximum==800)
assert(currentReads==0 and s.general.status=='available')
assert(s.general.health.current==nil and s.general.health.fieldStatus.current==nil)
assert(s.general.mana.current==nil and s.general.mana.fieldStatus.current==nil)
assert(s.general.movementSpeed.current==0);near(s.general.movementSpeed.runPercent,120)
assert(s.primaryAttributes.spirit.current==25 and s.primaryAttributes.spirit.effective==30)
assert(s.weapons.mainHand.minimumDamage==25 and s.weapons.mainHand.damagePerSecond==15)
assert(s.weapons.ranged.attackSpeedSeconds==1.8);near(s.weapons.ranged.damagePerSecond,50/1.8)
assert(s.weapons.attackPower.melee.effective==115 and s.weapons.attackPower.ranged.effective==87)
assert(s.modifiers.criticalStrike.spell.holy.value==2.5 and s.modifiers.spellDamage.arcane.value==70)
assert(s.modifiers.haste.spell.value==4 and s.modifiers.spellHealing.value==77)
assert(s.defense.defense.effective==150 and s.defense.armor.effective==250 and s.defense.dodge.value==6.5)
assert(s.resistances.arcane.effective==65 and s.resistances.fire.effective==25 and s.resistances.frost.effective==45)
assert(s.resistances.nature.effective==35 and s.resistances.shadow.effective==55)
print('PASS: requested stat groups, Forever return ordering, school indices, speed units, AP and weapon calculations')

-- Valid zeroes must remain zero; mana queries stay mana even for a non-mana class.
function UnitPowerMax()return 0 end
function UnitHealthMax()return 0 end
function GetCritChance()return 0 end
function GetMeleeHaste()return -10 end
function GetInventoryItemID()return nil end
s=ExporterStats.Capture(2000)
assert(currentReads==0 and s.general.health.maximum==0 and s.general.mana.maximum==0 and s.modifiers.criticalStrike.melee.value==0)
assert(s.modifiers.haste.melee.value==-10 and s.weapons.ranged.status=='not_applicable')
print('PASS: zero health/mana/crit, negative haste and no ranged weapon')

-- Missing/throwing/restricted APIs never invent a zero or prevent other groups.
local token=setmetatable({},{__add=function()error('secret arithmetic')end,__lt=function()error('secret comparison')end})
function issecretvalue(value)return value==token end
function UnitStat()return 30,token,2,-1 end
GetRangedHaste=nil
function GetSpellBonusHealing()error('unavailable')end
function UnitDefenseSkill()return 0/0,math.huge end
function GetUnitSpeed()return token,7,0,4.7 end
s=ExporterStats.Capture(3000)
assert(s.available and s.status=='partial')
assert(s.primaryAttributes.strength.effective==nil and s.primaryAttributes.strength.fieldStatus.effective=='restricted')
assert(s.modifiers.haste.ranged.value==nil and s.modifiers.haste.ranged.status=='unsupported')
assert(s.modifiers.spellHealing.fieldStatus.value=='api_error')
assert(s.defense.defense.effective==nil and not s.defense.defense.available)
assert(s.general.movementSpeed.currentPercent==nil and s.general.movementSpeed.runPercent==100)
assert(s.resistances.fire.effective==25)
assert(currentReads==0)
C_Map.GetPlayerMapPosition=function()error('map not ready')end
location=ExporterStats.Location(3000)
assert(location.status=='partial' and location.zone=='Example City' and location.x==nil)
C_Map.GetPlayerMapPosition=function()return {GetXY=function()return token,.5 end}end
location=ExporterStats.Location(3000)
assert(location.fieldStatus.x=='restricted' and location.x==nil and location.y==.5)
UnitClass=nil
basic=ExporterStats.Basic(3000)
assert(basic.status=='partial' and basic.name and basic.className==nil and basic.fieldStatus.className=='unsupported')
print('PASS: partial data, missing APIs, errors, restricted values, nonfinite values and independent categories')

-- Race/faction are independent observations, never inferred from each other.
UnitRace=nil
function UnitFactionGroup()return 'Neutral','' end
basic=ExporterStats.Basic(4000)
assert(basic.raceName==nil and basic.fieldStatus.raceName=='unsupported' and basic.faction=='Neutral')
function UnitRace()error('race unavailable')end
UnitFactionGroup=nil
basic=ExporterStats.Basic(4001)
assert(basic.fieldStatus.raceName=='api_error' and basic.fieldStatus.faction=='unsupported' and basic.name)
function UnitRace()return token,'NightElf',4 end
function UnitFactionGroup()error('faction unavailable')end
basic=ExporterStats.Basic(4002)
assert(basic.raceName==nil and basic.fieldStatus.raceName=='restricted' and basic.fieldStatus.faction=='api_error')
function UnitRace()return '','NightElf',4 end
function UnitFactionGroup()return token,'Alliance' end
basic=ExporterStats.Basic(4003)
assert(basic.raceName==nil and basic.fieldStatus.raceName=='unavailable' and basic.fieldStatus.faction=='restricted')
function UnitRace()return nil end
function UnitFactionGroup()return nil end
basic=ExporterStats.Basic(4004)
assert(basic.raceName==nil and basic.faction==nil and basic.name and basic.level==29)
assert(basic.fieldStatus.raceName=='unavailable' and basic.fieldStatus.faction=='unavailable')
print('PASS: localized race, faction tag, Neutral and independent missing/error/restricted race/faction handling')

-- Progress is fresh; a nil rested value is never fabricated as zero.
function UnitXP()return 400 end
function GetMoney()return 0 end
function GetXPExhaustion()return nil end
function IsXPUserDisabled()return true end
basic=ExporterStats.Basic(5000)
assert(basic.xp.current==400 and basic.xp.levelTotal==1000 and basic.moneyCopper==0 and basic.xp.disabled==true)
assert(basic.xp.rested==nil and basic.xp.fieldStatus.rested=='unavailable')
function UnitXP()return 0 end
function UnitXPMax()return 0 end
function GetXPExhaustion()return 0 end
function IsXPUserDisabled()return false end
basic=ExporterStats.Basic(5001)
assert(basic.xp.current==0 and basic.xp.levelTotal==0 and basic.xp.rested==0 and basic.xp.disabled==false)
assert(basic.xp.atMaxLevel==nil and basic.xp.percent==nil and basic.xp.remaining==nil)
function UnitXP()return token end
function UnitXPMax()error('max XP unavailable')end
GetXPExhaustion=nil
function IsXPUserDisabled()return token end
function GetMoney()return token end
basic=ExporterStats.Basic(5002)
assert(basic.moneyCopper==nil and basic.fieldStatus.moneyCopper=='restricted' and basic.xp==nil and basic.name)
function UnitXP()return 42 end
basic=ExporterStats.Basic(5003)
assert(basic.xp.current==42 and basic.xp.levelTotal==nil and basic.xp.disabled==nil)
assert(basic.xp.fieldStatus.levelTotal=='api_error' and basic.xp.fieldStatus.rested=='unsupported'
    and basic.xp.fieldStatus.disabled=='restricted')
for _,bad in ipairs({-1,1.5,math.huge,-math.huge,0/0,'42',false}) do
    GetMoney=function()return bad end; UnitXP=function()return bad end
    UnitXPMax=function()return bad end; GetXPExhaustion=function()return bad end
    IsXPUserDisabled=function()return 0 end
    basic=ExporterStats.Basic(5004)
    assert(basic.moneyCopper==nil and basic.xp==nil and basic.name and basic.level==29)
end
GetMoney=nil; UnitXP=nil; UnitXPMax=nil; GetXPExhaustion=nil; IsXPUserDisabled=nil
basic=ExporterStats.Basic(5005)
assert(basic.fieldStatus.moneyCopper=='unsupported' and basic.fieldStatus.xp=='unsupported' and basic.xp==nil)
function GetMoney()error('wallet unavailable')end
function IsXPUserDisabled()error('XP disabled unavailable')end
function UnitXPMax()return 500 end
basic=ExporterStats.Basic(5006)
assert(basic.fieldStatus.moneyCopper=='api_error' and basic.xp.levelTotal==500
    and basic.xp.fieldStatus.disabled=='api_error')
assert(currentReads==0)
print('PASS: fresh XP/money, zero/false, nil rested XP, disabled XP and independent invalid/restricted/API failures')
