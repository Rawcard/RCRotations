--[[
  RCRotations credit line.
  RCRotations by Rob is a fork of Forever Rotation by Vohnka (wow-forever.fr), MIT license.
  /rcrmsg on|off
]]

RCRotationsCreditDB = RCRotationsCreditDB or {}

local CREDIT = {
	LINE = "|cff66ccff%s|r by |cffffd100Rob|r \226\128\148 based on Forever Rotation by |cffffd100Vohnka|r (MIT)",
	ON = "|cff66ccffRCRotations|r \226\128\148 credit message: |cff66ff66ON|r",
	OFF = "|cff66ccffRCRotations|r \226\128\148 credit message: |cffff6060OFF|r",
	STATE = "|cff66ccffRCRotations|r \226\128\148 credit message: ",
	USAGE = "|cffaaaaaa/rcrmsg on|off|r",
}

local function db()
	RCRotationsCreditDB = RCRotationsCreditDB or {}
	if RCRotationsCreditDB.loginMessage == nil then
		RCRotationsCreditDB.loginMessage = true
	end
	return RCRotationsCreditDB
end

function RCRotations_ShouldPrintCredit()
	return db().loginMessage ~= false
end

function RCRotations_PrintCredit(title)
	if not RCRotations_ShouldPrintCredit() then
		return
	end
	print(CREDIT.LINE:format(tostring(title or "RCRotations")))
end

SLASH_RCRMSG1 = "/rcrmsg"
SLASH_RCRMSG2 = "/rcrcredit"
SlashCmdList.RCRMSG = function(msg)
	msg = strtrim(strlower(msg or ""))
	local store = db()
	if msg == "off" or msg == "0" then
		store.loginMessage = false
		print(CREDIT.OFF)
	elseif msg == "on" or msg == "1" then
		store.loginMessage = true
		print(CREDIT.ON)
	else
		print(CREDIT.STATE .. (store.loginMessage and "|cff66ff66ON|r" or "|cffff6060OFF|r"))
		print(CREDIT.USAGE)
	end
end
