local MODULE_TAG = "BZKdia"
if not istable(_G.mayrr) then
	pcall(require, "mayrr")
end
if not istable(_G.mayrr) then
	pcall(require, "zxcmodule")
end

local nativeBridge = _G.mayrr or _G.ded
local startupTime = SysTime()

if SERVER then
	return
end

if _G["BZKdia_mayrr_instance"] then
	MsgC(Color(255, 100, 100), "[Kefir] second instance already running! Skipping load to prevent conflicts/freeze.\n")

	return
end

_G["BZKdia_mayrr_instance"] = true

local Kefir = {}
local requestFailureCount = 0
local nativeApi = nativeBridge

if istable(nativeApi) then
	nativeApi.util_calcScreen0Fov = nativeApi.util_calcScreen0Fov or function(x, y, left, top, size)
		return x >= left and x <= left + size and y >= top and y <= top + size
	end

	nativeApi.util_calcScreen2Fov = nativeApi.util_calcScreen2Fov or function(x, y, cx, cy, radius)
		local dx, dy = x - cx, y - cy

		return dx * dx + dy * dy <= radius * radius
	end
end
local moduleTag = MODULE_TAG
local runtimeApi = {}
local localCache = {}
local localPlayer
local activeWeapon
local DEBUG_MODE = false
local hookSequence = 0
	local BUILD_NUMBER = 21

do
	if not istable(nativeApi) then
		error("mayrr module is not loaded (expected global table 'mayrr')")
	end

	local USE_NATIVE_HUDPAINT = true

	local nativeRender = isfunction(nativeApi.RenderAvailable) and nativeApi.RenderAvailable()

	nativeApi.standalone_vgui = not nativeRender

	local nativeCallbacks = {}
	local unloadCallback
	local unloaded = false
	local hookNames = {
		renderscreenspaceeffects = "RenderScreenspaceEffects",
		hudpaint = "HUDPaint",
		postdrawopaquerenderables = "PostDrawOpaqueRenderables",
		postcleanupmap = "PostCleanupMap",
		override_view = "CalcView",
		send_net_msg = "SendNetMsg",
		pre_frame_stage_notify = "PreFrameStageNotify",
		prerender = "PreRender",
		think = "Think"
	}

	if nativeRender then
		hookNames.view_render = "ZXCRender2D"
		hookNames.prerender = "ZXCPreRenderView"

		if USE_NATIVE_HUDPAINT then
			hookNames.hudpaint = "ZXCPostRenderView"
		end
	end

	local hookIds = {}

	function nativeApi.bax_fn(name, callback)
		nativeCallbacks[name] = callback

		local eventName = hookNames[name]
		local target, handler

		if eventName then
			target, handler = eventName, callback
		elseif name == "aspect_ratio" then
			target = "PreRender"
			handler = function()
				if isfunction(nativeApi.SetAspectRatio) then
					nativeApi.SetAspectRatio(callback() or 0)
				end
			end
		end

		if not target then
			return
		end

		local id = "\255" .. Kefir:RandomString(16)

		hookIds[#hookIds + 1] = { target, id }

		hook.Add(target, id, handler)
	end

	function nativeApi.bax_unload(callback)
		unloadCallback = callback
	end

	local function unloadStandalone()
		if unloaded then
			return
		end

		unloaded = true

		_G["BZKdia_mayrr_instance"] = nil

		for index = 1, #hookIds do
			local entry = hookIds[index]

			hook.Remove(entry[1], entry[2])
		end

		hookIds = {}

		if unloadCallback then
			unloadCallback()
		end
	end

	local function safeConfigName(name)
		return string.GetFileFromFilename(tostring(name or "")):gsub("[^%w%._%-]", "_")
	end

	if not isfunction(nativeApi.config_write) then
		local storeDir = "mayrr_cfg"

		local function storePath(name)
			return storeDir .. "/" .. safeConfigName(name) .. ".txt"
		end

		file.CreateDir(storeDir)

		function nativeApi.config_write(name, contents)
			file.Write(storePath(name), contents or "")
		end

		function nativeApi.config_read(name)
			return file.Read(storePath(name), "DATA") or ""
		end

		function nativeApi.config_create(name)
			nativeApi.config_write(name, "")
		end

		function nativeApi.config_delete(name)
			file.Delete(storePath(name))
		end

		function nativeApi.config_list()
			local files = file.Find(storeDir .. "/*.txt", "DATA") or {}

			for index = 1, #files do
				files[index] = string.gsub(files[index], "%.txt$", "")
			end

			return files
		end
	end

	nativeApi.service_getlogin = function() return "" end
	nativeApi.service_getpassword = function() return "" end
	nativeApi.service_getug = function() return "" end
	nativeApi.service_getbranch = function() return "local" end
	nativeApi.service_getenv = function() return "Invalid", false end
	nativeApi.service_saveenv = function() end
	nativeApi.service_request = function(_, callback)
		if callback then
			timer.Simple(0, function() callback("{}", true) end)
		end
	end
	nativeApi.service_unload = unloadStandalone

	nativeApi.util_calcWeekend = function(value)
		return value * 164
	end
	nativeApi.util_calcNearest = function(x, y, width, height)
		local dx = x - width * 0.5
		local dy = y - height * 0.5
		return dx * dx + dy * dy
	end
	if not isfunction(nativeApi.util_calcAng2Diff) then
		nativeApi.util_calcAng2Diff = function(origin, target, muzzleAngle, commandAngle)
			local wantedAngle = (target - origin):Angle()
			local pitchError = math.AngleDifference(wantedAngle.p, muzzleAngle.p)
			local yawError = math.AngleDifference(wantedAngle.y, muzzleAngle.y)

			if math.abs(pitchError) > 35 or math.abs(yawError) > 35 then
				wantedAngle:Normalize()
				wantedAngle.p = math.Clamp(wantedAngle.p, -89, 89)
				return wantedAngle
			end

			local result = Angle(
				commandAngle.p + pitchError,
				commandAngle.y + yawError,
				0
			)

			result:Normalize()
			result.p = math.Clamp(result.p, -89, 89)

			return result
		end
	end
	nativeApi.util_calcStepSide = function(smooth, minimum, maximum)
		local fraction = math.Clamp((tonumber(smooth) or 1) - 1, 0, 9) / 9
		return Lerp(fraction, maximum, minimum)
	end
	nativeApi.util_captureMiss = function() end
	nativeApi.util_setMenuPanel = function() end
	nativeApi.util_exitprocess = unloadStandalone

	local function fillMissing(name, fn)
		if not isfunction(nativeApi[name]) then
			nativeApi[name] = fn
		end
	end

	fillMissing("engine_isCapture", function()
		return isfunction(nativeApi.IsCapture) and nativeApi.IsCapture() or false
	end)
	fillMissing("engine_plugPacket", function(send)
		if isfunction(nativeApi.SetBSendPacket) then
			nativeApi.SetBSendPacket(send ~= false)
		end
	end)
	fillMissing("engine_setViewAngles", function(cmd, angles)
		if cmd and angles then
			cmd:SetViewAngles(angles)
		end
	end)
	fillMissing("engine_predictSpread", function(cmd, spread)
		if isfunction(nativeApi.PredictSpread) and cmd and spread then
			return nativeApi.PredictSpread(cmd, spread)
		end

		return Vector(1, 0, 0)
	end)

	fillMissing("tickbase_access", function() end)
	fillMissing("tickbase_setMin", function() end)
	fillMissing("tickbase_setMax", function() end)
	fillMissing("tickbase_recharge", function() end)
	fillMissing("tickbase_safeRecharge", function() end)
	fillMissing("tickbase_shifting", function() end)
	fillMissing("tickbase_getCharge", function() return 0 end)
	fillMissing("util_rpcstate", function() end)
	fillMissing("util_rpc_details", function() end)
	fillMissing("util_rpc_text", function() end)
end

if DEBUG_MODE then
	print("[KV] Pre Init", "Memory: " .. collectgarbage("count") / 1024 .. " MB")
end

Kefir.text_sg = "Will be screengrabbed!"
Kefir.zpBase = {
	weapon_hg_grenade_tpik = true,
	weapon_hg_legacy_grenade = true
}
Kefir.ignore_netmsg = {
	zmeyka_net = true,
	ZB_ChooseSpecPly = true,
	VChatVoiceState = true,
	ChatWhisper = true,
	LookAway = true,
	zChatTyping = true
}
Kefir.branch = DEBUG_MODE and "dev" or "?"
Kefir.assert = assert
Kefir.error = error
Kefir.ipairs = ipairs
Kefir.pcall = pcall
Kefir.pairs = pairs
Kefir.setmetatable = setmetatable
Kefir.getmetatable = getmetatable
Kefir.MsgC = MsgC
Kefir.getconvar = GetConVar
Kefir.isvector = isvector
Kefir.createclientconvar = CreateClientConVar
Kefir.convarexists = ConVarExists
Kefir.runconsolecommand = RunConsoleCommand
Kefir.problem_server = 0
Kefir.imenu = true
Kefir.qfaq = ""
Kefir.qfaq_text = "@ chefir.vip skachat besplatno"

local AngleCtor = Angle
local VectorCtor = Vector
local ZERO_ANGLE = AngleCtor(0, 0, 0)
local ZERO_VECTOR = VectorCtor(0, 0, 0)
local ONE_VECTOR = VectorCtor(1, 1, 1)

Kefir.DevicePitch = {
	Down = 90,
	Up = -90,
	Zero = 0,
	Jitter = 0
}
Kefir.width = ScrW
Kefir.height = ScrH
Kefir.material = Material
Kefir.type = type
Kefir.unpack = unpack
Kefir.frametime = FrameTime
Kefir.LerpAngle = LerpAngle
Kefir.curtime = CurTime
Kefir.player = nil
Kefir.silentangle = false
Kefir.menu = nil
Kefir.menu_groups = {}
Kefir.menu_scroll = nil
Kefir.fl_ticks = 0
Kefir.fd_ticks = 0
Kefir.keystates = {}
Kefir.fakeatt_weapons = {}
Kefir.findmetatable = FindMetaTable
Kefir.hooks = Kefir.hooks or {}
Kefir.cmds = Kefir.cmds or {}
Kefir.files = Kefir.files or {}
Kefir.me_cmd = Kefir.me_cmd or nil
Kefir.timers = Kefir.timers or {}
Kefir.realfps = 0
Kefir.alphabet = Kefir.alphabet or "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
Kefir.numbers = Kefir.numbers or "0123456789"
Kefir.players = Kefir.players or {}
Kefir.original_source = Kefir.original_source or {}
Kefir.render2d = Kefir.render2d or {}
Kefir.render3d = Kefir.render3d or {}
Kefir.EmitSound = EmitSound
Kefir.guiHideGameUI = gui.HideGameUI
Kefir.rview = Kefir.rview or {}
Kefir.zcity_weapons = Kefir.zcity_weapons or {
	{},
	{}
}
Kefir.sightfov = Kefir.sightfov or 0
Kefir.hits = Kefir.hits or {}
Kefir.lines = Kefir.lines or {}
Kefir.attackers = Kefir.attackers or {}
Kefir.texts = Kefir.texts or {}
Kefir.logs = Kefir.logs or {}
Kefir.hasfirearm = Kefir.hasfirearm or {}
Kefir.hasmelee = Kefir.hasmelee or {}
Kefir.traitors = Kefir.traitors or {}
Kefir.filters = Kefir.filters or {}
Kefir.gunmans = Kefir.gunmans or {}
Kefir.users = Kefir.users or {}
Kefir.aimtarget = Kefir.aimtarget or nil
Kefir.thirdperson = nil
Kefir.aimlock = {
	pos = Vector()
}
Kefir.aimpos = Kefir.aimpos or ZERO_VECTOR
Kefir.aimcsl = Kefir.aimcsl or nil
Kefir.aimend = Kefir.aimend or 0
Kefir.aimwork = Kefir.aimwork or false
Kefir.aimwall = Kefir.aimwall or false
Kefir.aimmisses = Kefir.aimmisses or false
Kefir.shooted = Kefir.shooted or false

local fallbackMode = playerOptions_sk or false
local ricochetTraces = {}

Kefir.hotkey_choosing = Kefir.hotkey_choosing or {
	{
		"none"
	}
}
Kefir.configlist = Kefir.configlist or nil
Kefir.original_armors = Kefir.original_armor or {}
Kefir.cam_manipulated = Kefir.cam_manipulated or false
Kefir.cpick_act = Kefir.cpick_act or false
Kefir.cpickl = nil
Kefir.tab_frame = nil
Kefir.translatebone = Kefir.translatebone or {
	R_Thigh = "Right Thigh",
	R_Foot = "Right Foot",
	R_Upperarm = "Right Upperarm",
	R_Hand = "Right Hand",
	R_Clavicle = "Right Clavicle",
	L_Forearm = "Left Forearm",
	R_Calf = "Right Calf",
	Spine = "Lower Spine",
	L_Thigh = "Left Thigh",
	Spine1 = "Mid Spine",
	Spine2 = "Up Spine",
	L_Calf = "Left Calf",
	L_Hand = "Left Hand",
	Pelvis = "Pelvis",
	Head1 = "Head",
	L_Foot = "Left Foot",
	Neck1 = "Neck",
	L_Upperarm = "Left Upperarm",
	L_Clavicle = "Left Clavicle",
	R_Forearm = "Right Forearm"
}
Kefir.body_bones = {
	"-",
	"-",
	"Spine2",
	"Spine1",
	"Spine",
	"Pelvis"
}
Kefir.activebones = {
	"Head1",
	"Spine2",
	"Spine1",
	"Spine",
	"Pelvis",
	"R_Hand",
	"R_Forearm",
	"R_Upperarm",
	"R_Clavicle",
	"L_Hand",
	"L_Forearm",
	"L_Upperarm",
	"L_Clavicle",
	"L_Foot",
	"L_Calf",
	"L_Thigh",
	"R_Foot",
	"R_Calf",
	"R_Thigh"
}

Kefir.skeletonlinks = {
	{ "Head1", "Spine2" },
	{ "Spine2", "Spine1" },
	{ "Spine1", "Spine" },
	{ "Spine", "Pelvis" },
	{ "Spine2", "R_Clavicle" },
	{ "R_Clavicle", "R_Upperarm" },
	{ "R_Upperarm", "R_Forearm" },
	{ "R_Forearm", "R_Hand" },
	{ "Spine2", "L_Clavicle" },
	{ "L_Clavicle", "L_Upperarm" },
	{ "L_Upperarm", "L_Forearm" },
	{ "L_Forearm", "L_Hand" },
	{ "Pelvis", "R_Thigh" },
	{ "R_Thigh", "R_Calf" },
	{ "R_Calf", "R_Foot" },
	{ "Pelvis", "L_Thigh" },
	{ "L_Thigh", "L_Calf" },
	{ "L_Calf", "L_Foot" }
}
Kefir.bpacket = Kefir.bpacket or true
Kefir.dw_bone = Kefir.dw_bone or {}

for indexA = 1, #Kefir.activebones do
	local boneName = Kefir.activebones[indexA]

	Kefir.dw_bone[boneName] = {
		0,
		0,
		0
	}
end

Kefir.hs_priority = Kefir.hs_priority or {
	0,
	1,
	3,
	4,
	5,
	6,
	10,
	9,
	8,
	7,
	10,
	9,
	8,
	7,
	14,
	13,
	12,
	14,
	13,
	12
}
Kefir.friendlist = Kefir.friendlist or {}
Kefir.espignore = Kefir.espignore or {}
Kefir.fakeangles = Kefir.fakeangles or nil
Kefir.humanizer = {
	noiseTimer = 0,
	vel = Angle(0, 0, 0),
	noise = Angle(0, 0, 0),
	noiseTarget = Angle(0, 0, 0)
}
Kefir.realangles = Kefir.realangles or nil
Kefir.antiaim_angle = Kefir.antiaim_angle or nil
Kefir.realpos = Kefir.realpos or nil
Kefir.offdangerfn = false
Kefir.relative_muzzle = Kefir.relative_muzzle or {}
Kefir.command_muzzle = Kefir.command_muzzle or {}
Kefir.keybindpos = {
	x = 100,
	y = 100
}
Kefir.spectatorpos = {
	x = 300,
	y = 300
}
Kefir.watermarkpos = {
	x = 500,
	y = 20
}
Kefir.watermark_draw = {
	x = 500,
	y = 20
}
Kefir.inited = false
Kefir.saveinit = Kefir.saveinit or {}
Kefir.revealme = Kefir.revealme or false
Kefir.goodbn = Kefir.goodbn or {
	["ValveBiped.Bip01_L_Forearm"] = "Left Arm",
	["ValveBiped.Bip01_R_Thigh"] = "Right Leg",
	["ValveBiped.Bip01_R_Upperarm"] = "Right Arm",
	["ValveBiped.Bip01_L_Calf"] = "Left Leg",
	["ValveBiped.Bip01_R_Hand"] = "Right Hand",
	["ValveBiped.Bip01_Spine1"] = "Lower Spine",
	["ValveBiped.Bip01_L_Clavicle"] = "Left Arm",
	["ValveBiped.Bip01_R_Foot"] = "Right Leg",
	["ValveBiped.Bip01_R_Forearm"] = "Right Arm",
	["ValveBiped.Bip01_L_Foot"] = "Left Leg",
	["ValveBiped.Bip01_Spine"] = "Mid Spine",
	["ValveBiped.Bip01_R_Calf"] = "Right Leg",
	["ValveBiped.Bip01_L_Hand"] = "Left Hand",
	["ValveBiped.Bip01_Pelvis"] = "Pelvis",
	["ValveBiped.Bip01_Spine4"] = "Up Spine",
	["ValveBiped.Bip01_L_Upperarm"] = "Left Arm",
	["ValveBiped.Bip01_Spine3"] = "Up Spine",
	["ValveBiped.Bip01_R_Clavicle"] = "Right Arm",
	["ValveBiped.Bip01_Head1"] = "Head",
	["ValveBiped.Bip01_Neck1"] = "Neck",
	["ValveBiped.Bip01_L_Thigh"] = "Left Leg",
	["ValveBiped.Bip01_Spine2"] = "Mid Spine"
}
Kefir.manualdir = Kefir.manualdir or 0
Kefir.settingable_yaw = Kefir.settingable_yaw or {
	Static = "antiaim_yaw_static",
	Jitter = "antiaim_yaw_jitter",
	Spin = "antiaim_yaw_spin"
}
Kefir.index_colors = {
	"groupbox",
	"groupname",
	"kefir_red",
	"footeri",
	"selectedline"
}
Kefir.standart_color = {
	Color(59, 12, 12),
	Color(135, 31, 15),
	Color(95, 11, 11),
	Color(48, 47, 47),
	(Color(234, 100, 100))
}
Kefir.color = Kefir.color or {
	groupbox = Color(59, 12, 12),
	groupname = Color(135, 31, 15),
	kefir_red = Color(95, 11, 11),
	kefir_black = Color(3, 3, 3),
	footeri = Color(48, 47, 47),
	selectedline = Color(234, 100, 100),
	white = Color(255, 255, 255),
	black = Color(0, 0, 0),
	ping = Color(228, 207, 18),
	karma = Color(171, 172, 233),
	kefir_green = Color(45, 132, 8),
	friendlushe = Color(13, 255, 0),
	line = Color(45, 47, 48),
	tabbox = Color(24, 22, 22, 250),
	picker_clr = Color(15, 15, 15),
	firearment = Color(202, 110, 5),
	is_screengrabing = Color(195, 157, 30),
	cfunction = Color(149, 188, 230),
	is_melee = Color(27, 147, 211),
	flashlight = Color(26, 228, 208),
	sling = Color(249, 202, 13),
	ammo = Color(230, 222, 10),
	reloading = Color(206, 157, 34),
	aiming = Color(128, 26, 26),
	traitor = Color(216, 9, 9),
	gunman = Color(15, 41, 187),
	keybind = Color(161, 155, 155),
	keybindhov = Color(223, 217, 217),
	faking = Color(100, 98, 216),
	armor = Color(16, 148, 201),
	attachment = Color(43, 102, 129),
	consumable = Color(238, 175, 41),
	red = Color(255, 0, 0),
	green = Color(0, 255, 0),
	ug = {
		admin = Color(233, 45, 45),
		premium = Color(246, 246, 22),
		moderator = Color(25, 106, 226),
		helper = Color(114, 198, 18),
		user = Color(85, 85, 85)
	}
}
Kefir.pclass_color = Kefir.pclass_color or {
	furry = Color(209, 19, 171),
	combine = Color(36, 88, 230),
	sc_infiltrator = Color(230, 166, 36),
	metrocop = Color(81, 114, 203),
	slugcat = Color(255, 255, 255),
	terrorist = Color(170, 17, 17),
	police = Color(15, 90, 139),
	swat = Color(20, 16, 213),
	none = Color(126, 138, 137),
	rebel = Color(255, 157, 1),
	bloodz = Color(233, 16, 16),
	groove = Color(73, 231, 15)
}
Kefir.pclass_transform = Kefir.pclass_transform or {
	sc_infiltrator = "INFILTRATOR"
}
Kefir.meta = {
	player = Kefir.findmetatable("Player"),
	entity = Kefir.findmetatable("Entity"),
	weapon = Kefir.findmetatable("Weapon"),
	cmd = Kefir.findmetatable("CUserCmd")
}
Kefir.global = {
	hook = hook,
	render = render,
	concommand = concommand,
	draw = draw,
	table = table,
	math = math,
	vgui = vgui,
	surface = surface,
	util = util,
	timer = timer,
	chat = chat,
	player = player,
	input = input,
	timer = timer,
	net = net,
	gevent = gameevent,
	debug = debug,
	string = string,
	http = http,
	cam = cam,
	engine = engine,
	bit = bit,
	weapons = weapons,
	file = file,
	ents = ents,
	os = os
}

for keyA, item in Kefir.pairs(Kefir.global) do
	runtimeApi[keyA] = item
end

runtimeApi.random = runtimeApi.math.random
runtimeApi.teamGetName = team.GetName
runtimeApi.teamGetColor = team.GetColor

function Kefir.RandomString(selfRef, length)
	local valueA = ""
	local valueB
	local numbersA = selfRef.alphabet .. selfRef.numbers

	for indexB = length, 1, -1 do
		local valueC = runtimeApi.random(#numbersA)

		valueA = valueA .. numbersA:sub(valueC, valueC)
	end

	return valueA
end

Kefir.nameglow = Kefir:RandomString(2)
Kefir.namemglow = "Material [" .. Kefir.global.string.lower(Kefir.nameglow) .. "]"

local createMaterial = CreateMaterial
local materialCatalog = {
	Textured = createMaterial(Kefir:RandomString(3), "VertexLitGeneric", {
		["$model"] = 1,
		["$basetexture"] = "models/debug/debugwhite",
		["$nocull"] = 0,
		["$ignorez"] = 0
	}),
	Wireframe = createMaterial(Kefir:RandomString(4), "VertexLitGeneric", {
		["$ignorez"] = 0,
		["$wireframe"] = 1
	}),
	Selfillum = createMaterial(Kefir:RandomString(5), "VertexLitGeneric", {
		["$model"] = "1",
		["$bumpmap"] = "vgui/white_additive",
		["$nocull"] = "0",
		["$selfillum"] = 1,
		["$ignorez"] = 0,
		["$basetexture"] = "vgui/white_additive",
		["$selfIllumFresnelMinMaxExp"] = "[0.3 0.9 0.6]",
		["$selfillumtint"] = "[0.0 0.0 0.0]",
		["$selfIllumFresnel"] = 1
	}),
	Metal = createMaterial(Kefir:RandomString(6), "VertexLitGeneric", {
		["$ignorez"] = 0,
		["$rimlightboost"] = "1.5",
		["$nocull"] = "1",
		["$phongexponent"] = "25",
		["$phongboost"] = "2",
		["$basetexture"] = "models/debug/debugwhite",
		["$rimlight"] = "1",
		["$rimlightexponent"] = "2",
		["$envmap"] = "env_cubemap",
		["$phong"] = "1",
		["$envmaptint"] = "[0.85 0.85 0.85]"
	}),
	Pulse = createMaterial(Kefir.nameglow, "VertexLitGeneric", {
		["$model"] = "1",
		["$bumpmap"] = "vgui/white_additive",
		["$nocull"] = "0",
		["$selfillum"] = 1,
		["$additive"] = 0,
		["$ignorez"] = 0,
		["$basetexture"] = "vgui/white_additive",
		["$selfIllumFresnelMinMaxExp"] = "[0.1 0.9 0.1]",
		["$selfillumtint"] = "[0.0 0.0 0.0]",
		["$selfIllumFresnel"] = 1
	}),
	Glass = createMaterial(Kefir:RandomString(11), "VertexLitGeneric", {
		["$model"] = 1,
		["$basetexture"] = "models/debug/debugwhite",
		["$translucent"] = 1,
		["$nocull"] = 0,
		["$ignorez"] = 0,
		["$envmap"] = "env_cubemap",
		["$envmaptint"] = "[0.4 0.5 0.6]"
	}),
	Crystal = createMaterial(Kefir:RandomString(12), "VertexLitGeneric", {
		["$model"] = 1,
		["$basetexture"] = "models/debug/debugwhite",
		["$nocull"] = 0,
		["$ignorez"] = 0,
		["$phong"] = 1,
		["$phongboost"] = 5,
		["$phongexponent"] = 8,
		["$envmap"] = "env_cubemap",
		["$envmaptint"] = "[0.7 0.85 1.0]"
	}),
	Gold = createMaterial(Kefir:RandomString(13), "VertexLitGeneric", {
		["$model"] = 1,
		["$basetexture"] = "models/debug/debugwhite",
		["$nocull"] = 1,
		["$ignorez"] = 0,
		["$phong"] = 1,
		["$phongboost"] = 2,
		["$phongexponent"] = 25,
		["$rimlight"] = 1,
		["$rimlightexponent"] = 2,
		["$rimlightboost"] = 1.5,
		["$envmap"] = "env_cubemap",
		["$envmaptint"] = "[1.0 0.72 0.3]"
	}),
	Dark = createMaterial(Kefir:RandomString(14), "UnlitGeneric", {
		["$color"] = "[0.03 0.03 0.03]"
	}),
	Plastic = createMaterial(Kefir:RandomString(19), "VertexLitGeneric", {
		["$model"] = 1,
		["$basetexture"] = "models/debug/debugwhite",
		["$nocull"] = 0,
		["$ignorez"] = 0,
		["$phong"] = 1,
		["$phongboost"] = 1,
		["$phongexponent"] = 10,
		["$envmap"] = "env_cubemap",
		["$envmaptint"] = "[0.3 0.3 0.3]"
	}),
	Original = createMaterial("_Original_", "VertexLitGeneric"),
	Flat = createMaterial("_Flat_", "UnlitGeneric"),
	Additive = {
		Textured = createMaterial(Kefir:RandomString(7), "VertexLitGeneric", {
			["$model"] = 1,
			["$basetexture"] = "models/debug/debugwhite",
			["$nocull"] = 0,
			["$ignorez"] = 0,
			["$additive"] = 1
		}),
		Wireframe = createMaterial(Kefir:RandomString(8), "VertexLitGeneric", {
			["$ignorez"] = 0,
			["$wireframe"] = 1,
			["$additive"] = 1
		}),
		Selfillum = createMaterial(Kefir:RandomString(9), "VertexLitGeneric", {
			["$model"] = "1",
			["$bumpmap"] = "vgui/white_additive",
			["$nocull"] = "0",
			["$selfillum"] = 1,
			["$additive"] = 1,
			["$ignorez"] = 0,
			["$basetexture"] = "vgui/white_additive",
			["$selfIllumFresnelMinMaxExp"] = "[0.3 0.9 0.6]",
			["$selfillumtint"] = "[0.0 0.0 0.0]",
			["$selfIllumFresnel"] = 1
		}),
		Metal = createMaterial(Kefir:RandomString(10), "VertexLitGeneric", {
			["$ignorez"] = 0,
			["$rimlightboost"] = "1.5",
			["$nocull"] = "1",
			["$phongexponent"] = "25",
			["$phongboost"] = "2",
			["$basetexture"] = "models/debug/debugwhite",
			["$additive"] = 1,
			["$rimlight"] = "1",
			["$rimlightexponent"] = "2",
			["$envmap"] = "env_cubemap",
			["$phong"] = "1",
			["$envmaptint"] = "[0.85 0.85 0.85]"
		}),
		Pulse = createMaterial(Kefir:RandomString(2) .. Kefir.nameglow, "VertexLitGeneric", {
			["$model"] = "1",
			["$bumpmap"] = "vgui/white_additive",
			["$nocull"] = "0",
			["$selfillum"] = 1,
			["$additive"] = 1,
			["$ignorez"] = 0,
			["$basetexture"] = "vgui/white_additive",
			["$selfIllumFresnelMinMaxExp"] = "[0.1 0.9 0.1]",
			["$selfillumtint"] = "[0.0 0.0 0.0]",
			["$selfIllumFresnel"] = 1
		}),
		Glass = createMaterial(Kefir:RandomString(15), "VertexLitGeneric", {
			["$model"] = 1,
			["$basetexture"] = "models/debug/debugwhite",
			["$translucent"] = 1,
			["$nocull"] = 0,
			["$ignorez"] = 0,
			["$additive"] = 1,
			["$envmap"] = "env_cubemap",
			["$envmaptint"] = "[0.4 0.5 0.6]"
		}),
		Crystal = createMaterial(Kefir:RandomString(16), "VertexLitGeneric", {
			["$model"] = 1,
			["$basetexture"] = "models/debug/debugwhite",
			["$nocull"] = 0,
			["$ignorez"] = 0,
			["$additive"] = 1,
			["$phong"] = 1,
			["$phongboost"] = 5,
			["$phongexponent"] = 8,
			["$envmap"] = "env_cubemap",
			["$envmaptint"] = "[0.7 0.85 1.0]"
		}),
		Gold = createMaterial(Kefir:RandomString(17), "VertexLitGeneric", {
			["$model"] = 1,
			["$basetexture"] = "models/debug/debugwhite",
			["$nocull"] = 1,
			["$ignorez"] = 0,
			["$additive"] = 1,
			["$phong"] = 1,
			["$phongboost"] = 2,
			["$phongexponent"] = 25,
			["$rimlight"] = 1,
			["$rimlightexponent"] = 2,
			["$rimlightboost"] = 1.5,
			["$envmap"] = "env_cubemap",
			["$envmaptint"] = "[1.0 0.72 0.3]"
		}),
		Dark = createMaterial(Kefir:RandomString(18), "UnlitGeneric", {
			["$color"] = "[0.03 0.03 0.03]",
			["$additive"] = 1
		}),
		Plastic = createMaterial(Kefir:RandomString(20), "VertexLitGeneric", {
			["$model"] = 1,
			["$basetexture"] = "models/debug/debugwhite",
			["$nocull"] = 0,
			["$ignorez"] = 0,
			["$additive"] = 1,
			["$phong"] = 1,
			["$phongboost"] = 1,
			["$phongexponent"] = 10,
			["$envmap"] = "env_cubemap",
			["$envmaptint"] = "[0.3 0.3 0.3]"
		}),
		Original = createMaterial("_Original_", "VertexLitGeneric"),
		Flat = createMaterial("_AFlat_", "UnlitGeneric")
	}
}
local tableData = {
	Flat = createMaterial("_kFlat_", "UnlitGeneric", {
		["$vertexcolor"] = "1",
		["$basetexture"] = "vgui/white",
		["$vertexalpha"] = "1",
		["$translucent"] = "1"
	})
}

Kefir.material = {
	blur = Kefir.material("pp/blurscreen", "noclamp"),
	gui_cg = Kefir.material("gui/center_gradient", "noclamp smooth"),
	gui_right = Kefir.material("gui/gradient_right", "noclamp smooth"),
	gui_down = Kefir.material("gui/gradient_down", "noclamp smooth"),
	gui_up = Kefir.material("gui/gradient_up", "noclamp smooth"),
	vgui_bottom = Kefir.material("vgui/gradient_down", "noclamp smooth"),
	vgui_up = Kefir.material("vgui/gradient_up", "noclamp smooth"),
	vgui_up_r = Kefir.material("vgui/gradient-u", "noclamp smooth"),
	vgui_right = Kefir.material("vgui/gradient-r", "noclamp smooth"),
	vgui_left = Kefir.material("vgui/gradient-l", "noclamp smooth"),
	vgui_down_r = Kefir.material("vgui/gradient-d", "noclamp smooth")
}
Kefir.ChamsList = {}
Kefir.LEFT_PANEL = {
	0,
	0
}
Kefir.RIGHT_PANEL = {
	0,
	0
}
Kefir.functions = {
	empty = function()
		AngleCtor(0, 0, 0)
	end
}
Kefir.paint = Kefir.paint or {}
Kefir.paint.__owner = Kefir or {}
Kefir.paint.library = {}
Kefir.iterator = Kefir.iterator or {}
Kefir.iterator.__owner = Kefir or {}
Kefir.aim = Kefir.aim or {}
Kefir.aim.__owner = Kefir or {}
Kefir.rage = Kefir.rage or {}
Kefir.rage.__owner = Kefir or {}
Kefir.glow = Kefir.glow or {}
Kefir.glow.__owner = Kefir or {}
Kefir.jmp = Kefir.jmp or {}
Kefir.jmp.__owner = Kefir or {}
Kefir.jmp.list = Kefir.jmp.list or {}
Kefir.jmp.hooked = Kefir.jmp.hooked or {}
Kefir.toggle_states = {}
Kefir.toggle_states2 = {}

local penetrationModifiers = {
	[85] = 0.2,
	[74] = 0.1,
	[MAT_METAL] = 1,
	[MAT_COMPUTER] = 0.9,
	[MAT_VENT] = 0.9,
	[MAT_GRATE] = 0.9,
	[MAT_FLESH] = 0.5,
	[MAT_ALIENFLESH] = 0.3,
	[MAT_SAND] = 0.1,
	[MAT_DIRT] = 0.9,
	[MAT_WOOD] = 0.5,
	[MAT_FOLIAGE] = 0.5,
	[MAT_CONCRETE] = 0.9,
	[MAT_TILE] = 0.8,
	[MAT_SLOSH] = 0.05,
	[MAT_PLASTIC] = 0.3,
	[MAT_GLASS] = 0.6
}

local function makeSpacerOption(label, value)
	return {
		nil,
		nil,
		"space",
		label,
		value
	}
end

Kefir.choke_packets = Kefir.choke_packets or 0

Kefir.translations = Kefir.translations or {
	RU = {
		Text = "Текст",
		["Main Selection"] = "Основная выборка",
		Class = "Класс",
		["Screengrabed, but protected!"] = "Предотвращен скринграб!",
		["Don't working on 'Always On' bind"] = "Не работает при состоянии 'Всегда включено'",
		["Master Switch"] = "Быстрый Переключатель",
		["No Z-City Organism Effects"] = "Отключить Z-City эффекты организма",
		["Type Dormant"] = "Тип Дорманта",
		Zero = "Нулевой",
		["Add Friend"] = "Добавить друга",
		Ammo = "Патроны",
		["Be carefully! When this feature is enabled, admin get screenshot just BLACK SCREEN, or nothing."] = "Будьте осторожны! При включении этой функции администратор получит скриншот только с ЧЕРНЫМ экраном или ошибку",
		Username = "Юзернейм",
		Down = "Вниз",
		TARGET = "ЦЕЛЬ",
		["Doubletap "] = "Даблтап ",
		Transparent = "Прозрачный",
		Brassknuckles = "Кастет",
		Movement = "Мувмент",
		["Screengrabed!"] = "Скринграбнули!",
		["Filter Team"] = "Фильтровать команду",
		["FOV out Muzzle"] = "ФОВ от дула",
		["Player Info"] = "Информация игрока",
		["Clamp HCR for Original Z-City"] = "Обход АЧ для кручения головы",
		["Entity Types"] = "Типы Энтити",
		Crouching = "В присяди",
		["Silent Type"] = "Тип Сайлента",
		["No Show Logs"] = "Убрать логи",
		Indicator = "Индикатор",
		Additive = "Аддитивный",
		["Filter Enemy"] = "Фильтровать противников",
		UA = "Украинский",
		["Remove Bob / Sway"] = "Убрать покачивание / тряску",
		["Bunny Hop"] = "Банни Хоп",
		["Instant Search"] = "Быстрый поиск",
		["Prevents the aimbot and visuals from reacting to players on your own team."] = "Предотвращает реакцию аимбота и визуалов на игроков вашей собственной команды.",
		Killed = "Убийство",
		["Up Spine"] = "Верхняя спина",
		["Transparent From a Distance"] = "Прозрачный на дистанции",
		["Post Render"] = "Пост Рендер",
		["Discord RPC"] = "Активность в дискорде",
		Name = "Имя",
		["ms."] = "мс.",
		["Scaling from Distance"] = "Уменьшать на дистации",
		Blur = "Размытие",
		["Manual Right"] = "Мануал вправо",
		Neck = "Шея",
		["Rounded Corner"] = "Закругленный угловой",
		Hold = "Удерживать",
		["Log Screengrab"] = "Логировать скринграб",
		["New Message Notify"] = "Уведомление о новых сообщениях",
		["Experimentally!"] = "Экспериментальная!",
		Other = "Другое",
		RU = "Русский",
		["Eye Trace"] = "Направление глаз",
		HIT = "ПОПАЛ",
		["Ignore ESP"] = "Игнорить в ЕСП",
		["A filter to ignore players who are currently unconscious or in a 'downed' state."] = "Фильтр для игнорирования игроков, которые в данный момент без сознания или в состоянии 'нокдауна'.",
		["Config Name"] = "Название конфига",
		["Cloud Save"] = "Облачное сохранение",
		["Cloud Load"] = "Загрузить из облака",
		["@ chefir.vip - swed - 2026 year - universal utility for Garry's Mod"] = "@ чефир.вип - швед - 2026 год - универсальная утилита для Гаррис Мода",
		["Z-Base Crasher"] = "Z-Base Крашер",
		["Z-City Weapons"] = "Z-City Оружия",
		["Thirdperson Distance"] = "Дистанция",
		Original = "Оригинал",
		Unhold = "Отжимать",
		["BoxR Rounding"] = "Радиус закругления",
		["Matrix Reload"] = "Перезагрузка матрицы",
		User = "Юзер",
		["The amount of time to wait before shooting after a target is found."] = "Время ожидания перед выстрелом после обнаружения цели.",
		Distance = "Дистанция",
		["Manual Back"] = "Мануал назад",
		["AA Manual Dir Distance"] = "Дистанция от стрелок",
		["If HP lower than"] = "Если ХП меньше чем",
		Yaw = "Горизонталь",
		["Camera Silent"] = "По камере",
		["On Doubletap"] = "При даблтапе",
		["CUserCmd Clamper - Limit"] = "Лимит клампера CUserCmd",
		["Number, after which force body aiming will work."] = "Число, после которого будет предпочтительно целить в тело.",
		Circle = "Круг",
		["Z-City Attachments"] = "Z-City Обвесы",
		Rounded = "Закругленный полный",
		["Right Forearm"] = "Правое предплечье",
		["Shot Delay"] = "Задержка выстрела",
		BRASSKNUCKLES = "ЕСТЬ КАСТЕТ",
		["Left Upperarm"] = "Левое предплечье",
		["Speed to Aim"] = "Скорость ведения прицела",
		SLING = "ЕСТЬ РЕМЕНЬ",
		Animation = "Анимация",
		["Log Roles"] = "Логировать роли (хомисайд)",
		["Fake Head Pitch"] = "Угол по вертикали",
		["Modifies the game's rendering aspect ratio to stretch or squash the view."] = "Изменяет соотношение сторон рендеринга игры, чтобы растянуть или сжать обзор.",
		Chams = "Чамсы",
		["Specific movement states (Air, Moving, etc.) that trigger fake lag."] = "Определенные состояния движения (в воздухе, движение и т.д.), которые активируют фейклаги.",
		Backward = "Задом",
		Chat = "Чат",
		["Override FOV"] = "ФОВ камеры",
		Team = "Команда",
		Log = "Лог",
		Wireframe = "Сетка",
		["Filter Noclip"] = "Фильтровать ноуклип",
		["Pos X"] = "Позиция X",
		COMBAT = "КОМБАТ",
		FAKING = "РЭГДОЛЛ",
		["Draw FOV"] = "Рисовать ФОВ",
		["Anti-Aim"] = "Анти-попадайки",
		["Right Thigh"] = "Правое бедро",
		["Anti-Screengrab"] = "Обходить скринграб",
		["Aspect Ratio"] = "Растяжение экрана",
		Flags = "Флаги",
		["Menu Hotkey"] = "Кнопка Меню",
		Size = "Размер",
		["AA Chams Material"] = "АА Чамсы Материал",
		PLAYERS = "ИГРОКИ",
		ATTACHMENTS = "ОБВЕСЫ",
		["Fast Zoom"] = "Быстрое прицеливание",
		["Entity Max Distance"] = "Макс. дистанция энтити",
		["In this window, you can add / remove bones, in which aimbot will aiming."] = "В этом окне, вы можете добавить / убрать кости, в которые аимбот будет целиться.",
		["Weapon Chams"] = "Оружейные чамсы",
		Pitch = "Вертикаль",
		["Config "] = "Конфиг ",
		Indicators = "Индикаторы",
		["Copy SteamID64 this player in share buffer."] = "Скопировать SteamID64 этого игрока в буфер обмена.",
		["Left Clavicle"] = "Левая ключица",
		["Connection with servers restored!"] = "Соединение с серверами восстановлено!",
		Select = "Выбор",
		["Right Foot"] = "Правая ступня",
		["On Shot"] = "При выстреле",
		Glow = "Свечение",
		["Hit Logs"] = "Лог попаданий",
		Melee = "Холодное оружие",
		["Footstep Size"] = "Размер",
		Head = "Голова",
		Thirdperson = "Третье лицо",
		["Save User Settings"] = "Сохранять эти настройки?",
		["Thirdperson (FPS?)"] = "Третье лицо (ФПС?)",
		TRAITOR = "ПРЕДАТЕЛЬ",
		["Thirdperson Smooth"] = "Плавность",
		["Weapon Chams Type"] = "Тип оружейных чамсов",
		["No Flash"] = "Не рисовать вспышки",
		Static = "Статический",
		["No Print ConMsg"] = "Убрать консольные логи",
		["Hit Chance"] = "Шанс попадания",
		Standart = "Стандарт",
		["Active Weapon"] = "Оружие в руках",
		Crosshair = "Прицел",
		["Right Calf"] = "Правая ляшка",
		["Right Upperarm"] = "Правое предплечье",
		["FOV Type"] = "Тип ФОВа",
		Save = "Сэйф",
		Metal = "Металл",
		["No Z-City Processing"] = "Отключить Z-City процессинг",
		USER = "ЮЗЕР",
		Matrix = "Матрица",
		["Left Forearm"] = "Левое предплечье",
		["KARMA %d"] = "КАРМА %d",
		["Dynamic FOV"] = "Динамичный ФОВ",
		["Auto Stop"] = "Авто стоп",
		Jitter = "Джиттер",
		Full = "Полный",
		["Auto Stop Type"] = "Тип авто стопа",
		Filter = "Фильтр",
		Adaptive = "Адаптив",
		["Ignore Unconscious"] = "Игнорировать без сознания",
		["No Fade"] = "Не рисовать затемнение",
		dev = "разработчик",
		Reloading = "Перезаряжается",
		["Ignore Player In Fake"] = "Игнорировать игроков в рэгдолле",
		["Pulse Bar Type"] = "Тип пульс бара",
		Assist = "Помощь",
		["Right Peek"] = "Правый Пик",
		["Left Peek"] = "Левый Пик",
		["Auto Reload"] = "Авто перезарядка",
		["Appearance Name"] = "Имя персонажа",
		["Custom Color"] = "Свои цвета",
		stable = "релиз",
		Debug = "Отладка",
		FRIEND = "ДРУГ",
		Load = "Лоад",
		["Aim Target"] = "Цель аимбота",
		Standing = "Стоя",
		["Theme Lighting"] = "Освещение в тему",
		UNCONSCIOUS = "БЕЗ СОЗНАНИЯ",
		["Unsafe Recharge"] = "Небезопасная перезарядка",
		["Kill Text"] = "Текст убийства",
		GUNMAN = "ГАНМЕН",
		["Auto Strafe"] = "Авто Стрейф",
		Flashlight = "Фонарик",
		Pelvis = "Таз",
		["Using [PLAYER_META:GetBonePosition]"] = "Использует [PLAYER_META:GetBonePosition]",
		Health = "Здоровье",
		["Z-City Others"] = "Z-City Другое",
		["Player Glow"] = "Свечение игрока",
		["Box Type"] = "Тип коробки",
		Friend = "Друг",
		["Manual Left"] = "Мануал налево",
		EMPTY = "ПУСТОЙ",
		["Left Foot"] = "Левая ступня",
		["Server Silent"] = "Серверный",
		Accuracy = "Точность",
		["Spin Speed"] = "Скорость вращения",
		["Draw Ricochets"] = "Отображать рикошеты",
		["Filter Distance"] = "Фильтровать дистацию",
		["Chat Spam"] = "Спам в чат",
		Unload = "Выгрузить",
		HP = "ХП",
		Gradient = "Градиент",
		["On Key"] = "На клавишу",
		Quality = "Качество",
		["Perfection Targeting"] = "Улучшенный таргетинг",
		["On Hard Movement"] = "При тяжелых движениях",
		OS = "ПВ",
		["HP Bar Type"] = "Тип хп бара",
		Offensive = "Оффенсив",
		Defensive = "Дефенсив",
		Fakeduck = "Фейкдак",
		["HS Text"] = "Текст хедшота",
		["Wait Attack Snapping"] = "Удерживать атаку до аима",
		["Copy SteamID"] = "Скопировать SteamID",
		Humanizator = "Хуманизатор",
		["RT Valid"] = "Валидировать Рендер-Таргет?",
		["Always On"] = "Всегда включен",
		["Hand Shake"] = "Тряска руки",
		["Z-City Armors"] = "Z-City Броня",
		["Suppress Lighting"] = "Убрать свет у чамсов",
		["Micro-Movement"] = "Микро движения",
		Footstep = "Шаги",
		Line = "Линия",
		["Adaptive Color"] = "Адаптирующийся цвет",
		["Helps you aim at players, works on firearms."] = "Помогает прицеливаться в игроков, работает на огнестрельных оружиях.",
		["Auto Pistol"] = "Авто-пистолеты",
		["Sub Selection"] = "Доп. выборка",
		["Force Bodyaim"] = "Предпочитать тело",
		["Inventory Flags"] = "Инвентарь",
		["Limits the radius within which players will be targeted."] = "Ограничивает в каком радиусе будут браться игроки для прицеливания.",
		["AA Manual Dir Type"] = "Тип рисовки мануального направления",
		["Firearm Aimbot"] = "Аимбот",
		unknown = "неизвестно",
		["Main selection for player targeting."] = "Основная выборка для таргета игрока.",
		Silent = "Сайлент",
		["Priority will be given to selecting a player closer to you."] = "Будет приоритетно выбирать игрока ближе к вам.",
		["It will prioritize selecting the player closest to your crosshair."] = "Будет приоритетно выбирать игрока ближе к вашему прицелу.",
		["Priority will be given to selecting a player with a weapon in hand."] = "Будет приоритетно выбирать игрока с оружием в руках.",
		["[Z-City] It will take the center of the FOV from the muzzle of your weapon."] = "[Z-City] Будет брать центр ФОВ от дула вашего оружия.",
		["The FOV will stick to a target when the aimbot is selected and activated on it."] = "ФОВ будет при выбранном таргете и активации на нем аимбота прилипать к нему.",
		["Set shape FOV to 'Box'"] = "Устаналивает фигуру ФОВа на 'Квадрат'",
		["Preferably, depending on the settings, the utility will target the player's torso / stomach."] = "Предпочтительно от настроек утилита будет целить в торс / живот игрока.",
		["Force body aiming when Health target will lower than 'N'"] = "Предпочтительно целить в тело когда здоровье противника будет меньше чем 'N'",
		["Hard Moving"] = "Сильное движение",
		["Draw Hit"] = "Рисовать попадание",
		["Draw Penetrate"] = "Отображать прострелы",
		Exploits = "Эксплоиты",
		VISUALS = "ВИЗУАЛЫ",
		World = "Общее / Мир",
		Smooth = "Плавность",
		["Fake Head Yaw"] = "Угол по горизонтали",
		["Do this player Invisible for ESP."] = "Сделать этого игрока Невидимым для ЕСП.",
		["Press LMB to setting keybind on this feature. Enable on: (Unhold / Hold / Toggle / Always On / On Shot)"] = "Нажмите ЛКМ что-бы настроить кейбинд на эту функцию. Включение на: (Отжимание / Удержание / Переключатель / Всегда включено / При выстреле)",
		["Copy SteamID64"] = "Скопировать SteamID64",
		Enable = "Включить",
		Language = "Язык",
		["Copy Appearance Name this player in share buffer."] = "Скопировать имя аппириенса этого игрока в буфер обмена.",
		Current = "Текущий",
		["Copy SteamID this player in share buffer."] = "Скопировать SteamID этого игрока в буфер обмена.",
		["Left Calf"] = "Левая ляшка",
		["Remove this player from friend list."] = "Убрать этого игрока из списка друзей.",
		["HAS MELEE"] = "ЕСТЬ ХОЛОДНОЕ ОРУЖИЕ",
		["Weapon Sling"] = "C ремнем",
		["Select any player"] = "Выбери любого игрока.",
		["Enables silent aimbot which redirects bullets to the target without changing your view angles."] = "Включает сайлент аим, который перенаправляет пули в цель, не меняя углы вашего обзора.",
		Box = "Коробка",
		["Do this player Visible for ESP."] = "Сделать этого игрока Видимым для ЕСП.",
		other = "разное",
		["Pulse Bar Width"] = "Ширина пульс бара",
		["Game Name"] = "Имя игровое",
		["Determines whether the silent aim calculation happens on the client camera or server-side."] = "Определяет, где происходит расчет сайлент аима: на стороне камеры клиента или на стороне сервера.",
		["Manipulates your character's network angles to make you harder to hit for other users."] = "Манипулирует сетевыми углами вашего персонажа, чтобы другим пользователям было сложнее по вам попасть.",
		["Sets the vertical angle of your model's head to prevent easy headshots."] = "Устанавливает вертикальный угол головы вашей модели для предотвращения легких хедшотов.",
		["Sets the horizontal rotation of your model (Static, Spinning, or Jittering)."] = "Устанавливает горизонтальное вращение вашей модели (Статичное, Вращение или Джиттер).",
		["esp / wh"] = "есп / вх",
		["Ang P"] = "Угол P",
		["Z-City Lootable Props"] = "Z-City Лутабельные пропы",
		["The constant angle at which your character will face."] = "Постоянный угол, под которым будет стоять ваш персонаж.",
		["The speed at which your character model rotates 360 degrees."] = "Скорость, с которой модель вашего персонажа вращается на 360 градусов.",
		["Pos Z"] = "Позиция Z",
		["Custom Fake Head"] = "Ручной угол головы",
		Player = "Игрок",
		["Auto Fire"] = "Авто Выстрел",
		MISC = "РАЗНОЕ",
		KILLED = "УБИЛ",
		["CUserCmd Clamper"] = "Клампер CUserCmd",
		None = "Нету",
		["All Weapons"] = "Все оружия",
		["Specific delay applied only to the very first shot in a sequence."] = "Специфическая задержка, применяемая только к самому первому выстрелу в серии.",
		["Only Visible"] = "Только видимые",
		["Prevents you from firing your weapon until you finish targeting a player."] = "Не дает вам сделать выстрел из оружия, пока нацеливание на игрока не будет закончено.",
		["Method Get Position"] = "Метод позиции",
		["Allows the aimbot to target enemies behind penetrable surfaces like thin walls."] = "Позволяет аимботу целиться во врагов за простреливаемыми поверхностями, например, тонкими стенами.",
		["With this switch you can quickly toggle the status of all enabled functions in the tab."] = "Этим переключателем вы можете быстро переключать статус всех включенных функций во вкладке.",
		["Logs Seconds Alive Time"] = "Время живности лога в секундах",
		["Head Crazy Rotating"] = "Кручение головы",
		["chefir.vip | %d commit | %d fps | %d ms. |"] = "кефир.ребилд | %d коммит | %d ФПС | %d пинг |",
		["In Air"] = "В воздухе",
		["Chokes outgoing packets to make your movement appear laggy and unpredictable to others."] = "Задерживает исходящие пакеты, чтобы ваше движение казалось лагающим и непредсказуемым для других.",
		["Second selection for player targeting."] = "Дополнительная выборка для таргета игрока.",
		Textured = "Текстура",
		["Z-City Medicines"] = "Z-City Медицина",
		["An experimental feature that attempts to calculate and negate weapon spread."] = "Экспериментальная функция, которая пытается рассчитать и свести на нет разброс оружия.",
		["with Sound"] = "со звуком",
		["BoxR Quality"] = "Качество закругления",
		["The mathematical method used to determine player bone positions (Standart or Matrix)."] = "Математический метод, используемый для определения позиций костей игрока (Стандарт или Матрица).",
		["Eliminates the vertical and horizontal kick of the weapon when firing."] = "Устраняет вертикальную и горизонтальную отдачу оружия при стрельбе.",
		["Semi-Transparent"] = "Полу-прозрачный",
		["Forces your character to stop moving when the aimbot is ready to fire for maximum accuracy."] = "Принудительно останавливает движение вашего персонажа, когда аимбот готов к стрельбе, для максимальной точности.",
		Dormant = "Дормант",
		["Connection to the kefir rework server was lost, after connection attempts expire the cheat will be unloaded! (%d/10)"] = "Соединение с серверами Майрр было потеряно, после истечения попыток подключения к серверам чит будет выгружен! (%d/10)",
		Delete = "Удалить",
		["Automatically forces your character into a crouched position when an enemy is detected."] = "Автоматически заставляет вашего персонажа присесть при обнаружении противника.",
		["Copy Appearance Name"] = "Скопировать имя персонажа",
		["Auto Wall"] = "Авто Прострел",
		Pulse = "Пульсирующий",
		Firearm = "Огнестрел",
		KZ = "Казахский",
		Hotkey = "Кнопка",
		["Ang R"] = "Угол R",
		["No Recharge in Aiming"] = "Не перезаряжать при аимботе",
		["RT Clear"] = "Очищать Рендер-Таргет",
		Corner = "Угловой",
		["kefir rework"] = "Kefir rework",
		Rage = "Рейдж",
		Manual = "Вручную",
		["Filter to ignore players who are detected as faking their position or lag."] = "Фильтр для игнорирования игроков, которые определяются как подделывающие свою позицию или лагающие.",
		["Condition: If you are have charged doubletap."] = "Условие: если у вас заряжен даблтап.",
		["Condition: If the target is far away."] = "Условие: если цель далеко.",
		["Distance, after which force body aiming will work."] = "Дистанция, после которой будет работать бодиаим.",
		["Far Distance"] = "Дальняя дистанция",
		["Baim Distance"] = "Дистанция бодиаима",
		Min = "Мин",
		["Traitor / Gunman"] = "Предатель / Ганмен",
		["Show Ammo"] = "Показать патроны",
		["list players"] = "список игроков",
		["Modifies semi-automatic pistols to fire continuously while the key is held."] = "Модифицирует полуавтоматические пистолеты для непрерывной стрельбы, пока удерживается клавиша.",
		["Anti-Screenshot"] = "Обходить скриншоты",
		["CAN'T BREATH"] = "НЕ ДЫШИТ",
		["Automatically initiates a weapon reload when the magazine is empty."] = "Автоматически инициирует перезарядку оружия, когда магазин пуст.",
		["Displays the last known position of players who have gone out of network range."] = "Отображает последнюю известную позицию игроков, вышедших из радиуса сетевой видимости.",
		["Player Class"] = "Класс игрока",
		["Gradually fades out ESP elements based on how far away the player is."] = "Постепенно скрывает элементы ESP в зависимости от того, как далеко находится игрок.",
		Skeleton = "Скелет",
		["Offscreen"] = "Заэкранные",
		["Offscreen Indicators"] = "Заэкранные индикаторы",
		["Min Distance"] = "Мин. дистанция",
		Search = "Поиск",
		Shape = "Форма",
		["HP Bar Width"] = "Ширина хп бара",
		FOV = "ФОВ",
		["Posture Peek"] = "Постур Пик",
		["Auto Crouch"] = "Авто присед",
		["Viewmodel changer"] = "Вьюмодел ченджер",
		["Pos Y"] = "Позиция Y",
		["Some screengrabs use the screenshot method!"] = "Некоторые скринграбы используют метод скриншота!",
		["Resizes ESP elements relative to distance to prevent screen clutter."] = "Изменяет размер элементов ESP относительно расстояния, чтобы предотвратить загромождение экрана.",
		["Visual indicator of the target's remaining health points."] = "Визуальный индикатор оставшихся очков здоровья цели.",
		Configs = "Конфиги",
		["First Shot Delay"] = "Задержка первого выстрела",
		["legit / rage"] = "легит / рейдж",
		["Applies a custom material or color overlay to player models for visibility."] = "Применяет кастомный материал или цветовое наложение на модели игроков для видимости.",
		["Draws players through walls with a second color."] = "Рисует игроков сквозь стены вторым цветом.",
		["Renders a glowing outline around player models, often visible through walls."] = "Отрисовывает светящийся контур вокруг моделей игроков, часто видимый сквозь стены.",
		Usergroup = "Юзергруппа",
		["Enables custom positioning and rotation of your hands and weapon on screen."] = "Включает кастомное позиционирование и вращение ваших рук и оружия на экране.",
		["The bind used to toggle between first-person and third-person perspectives."] = "Клавиша, используемая для переключения между первым и третьим лицом.",
		["Manipulating your view angles only SERVER, your camera will be in normal position."] = "Манипулируя углами обзора только на СЕРВЕРЕ, ваша камера будет в нормальном положении.",
		["Lower Spine"] = "Нижняя спина",
		["AA Manual Dir"] = "АА Мануал направление",
		Selfillum = "Сельфиум",
		["Manipulating your camera for create (silent) view."] = "Меняет только углы камеры, для создания (сайлент) вида.",
		["Ang Y"] = "Угол Y",
		["Z-City Grenades"] = "Z-City Гранаты",
		["If one of the selected conditions is met, the function will work."] = "Если одно из выбранных условий будет соблюдено, функция будет работать.",
		["Condition: If you are in the air."] = "Условие: если вы находитесь в воздухе.",
		["Condition: If you are standing."] = "Условие: если вы стоите.",
		["Condition: If you are moving so hard and intensive."] = "Условие: если вы двигаетесь очень интенсивно.",
		Aiming = "Прицеливается",
		["FAQ Features"] = "Описание функций",
		["Condition: If you are crouching."] = "Условие: если вы в присяди.",
		["Ignore Team"] = "Игнорировать союзников",
		["Automatically adjusts your character's stance or lean when peeking around corners."] = "Автоматически настраивает стойку или наклон вашего персонажа при выглядывании из-за углов.",
		["Z-Base Crasher Repeater"] = "Повтор Z-Base Крашер",
		["Aimbot Humanizer that makes your aimbot's movements more human-like."] = "Хуманизатор Аимбота делает движения / логику аимбота более человечными.",
		beta = "бета",
		["Draws a direct line to the current target, but may slightly impact frame rate."] = "Рисует прямую линию до текущей цели, но может незначительно повлиять на частоту кадров.",
		["Configures micro-movement in aiming"] = "Настраивает микро-движения в нацеливании",
		["HAS FIREARM"] = "ЕСТЬ ОГНЕСТРЕЛ",
		Karma = "Карма",
		AMMO = "ПАТРОНЫ",
		["Using [PLAYER_META:GetBoneMatrix]"] = "Использует [PLAYER_META:GetBoneMatrix]",
		EN = "Английский",
		["Selects the type of auto-stopping he will do for you."] = "Определяет тип как утилита будет авто-стоппить вас.",
		Details = "Детали",
		["Just make you slide"] = "Просто заставляет вас слайдить на маленьких скоростях",
		Miss = "Промах",
		["The number of simulation ticks to skip per network update."] = "Количество тиков симуляции, пропускаемых за одно сетевое обновление.",
		Keybinds = "Кейбинды",
		["Just hold you in place without moving"] = "Просто удерживает вас на месте без малейшего движения",
		["Ignore player who be in ragdoll."] = "Игнорирует игроков в фейке / рэгдолле.",
		["AA Chams"] = "АА Чамсы",
		Ticks = "Тики",
		["Inline Targeting"] = "Инлайн Таргетинг",
		["Movement Fix Type"] = "Мувмент Фикс",
		["No Recoil"] = "Без отдачи",
		["Condition: If you are moving."] = "Условие: если вы двигаетесь.",
		["Draw Silent Hit"] = "Рисовать попадание (сайлент)",
		Hit = "Попадания",
		Armed = "Вооруженный",
		["Right Clavicle"] = "Правая ключица",
		["Entity ESP"] = "Энтити ЕСП",
		["Sets the model's lighting to match the menu color."] = "Устанавливает освещение у модели в цвет меню.",
		Slide = "Слайд",
		["Fakelag "] = "Фейклаг",
		["Set shape FOV to 'Circle'"] = "Устаналивает фигуру ФОВа на 'Круг'",
		["Branch: "] = "Версия: ",
		["Add this player in friend list."] = "Добавить этого игрока в список друзей.",
		["Left Thigh"] = "Левое бедро",
		Breathing = "Дыхание",
		["Configures Hand Shake in aiming"] = "Настраивает тряску рук при аимботе",
		["Player Chams"] = "Чамсы игрока",
		["No Armor HUD"] = "Не рисовать броню",
		["Put function find target in hook aiming."] = "Перекидывает функцию поиска цели в среду функции аимбота",
		Flat = "Плоский",
		Type = "Тип",
		["s."] = "с.",
		Faking = "В рэгдолле?",
		["t."] = "т.",
		[" UID"] = " ЮИД",
		Ping = "Пинг",
		["Type Ignore Team"] = "Тип игнорирования",
		["Static Angle"] = "Статичный Угол",
		Moving = "Движение",
		[" commit"] = " коммит",
		["Kefir User"] = "Пользователь Кефира",
		Conscious = "Без сознания",
		["Automatically triggers a shot the moment an enemy enters the aimbot's hit-zone."] = "Автоматически производит выстрел в тот момент, когда враг попадает в зону поражения аимбота.",
		["The degree of rapid angle shifting to confuse anti-aim resolvers."] = "Степень быстрого смещения угла для запутывания резольверов анти-аимов.",
		Default = "Обычный",
		["Adjusts how smoothly the utility will guide your crosshair towards the player."] = "Настраивает насколько плавно утилита будет вести ваш прицел к игроку.",
		["Custom Ticks"] = "Установить свои тики",
		["Jitter Range"] = "Джиттер Радиус",
		Refresh = "Обновить",
		["View Render"] = "Вью Рендер",
		Up = "Вверх",
		Spin = "Вращение",
		["Force body aiming on key."] = "Предпочтительно целить в тело при нажатии на кнопку.",
		["Configures how speed you're aiming on target"] = "Настраивает как быстро вы будете нацеливаться на цель",
		["Right Hand"] = "Правая рука",
		Forward = "Передом",
		["Left Hand"] = "Левая рука",
		["No Organism Effects"] = "Убрать эффекты организма",
		AIMING = "ПРИЦЕЛИВАЕТСЯ",
		Misc = "Разное",
		["s.) RELOADING"] = "с.) ПЕРЕЗАРЯДКА",
		["Language changed to: "] = "Язык изменен на: ",
		["Mid Spine"] = "Середина спины",
		Spectators = "Наблюдатели",
		Shape = "Узор",
		Aimbot = "Аимбот",
		["Predict Spread"] = "Предсказание разброса",
		Removals = "Удаление",
		Conditions = "Условие",
		["Double Tap"] = "Дабл Тап",
		Max = "Макс",
		["Full Anti-Screengrab"] = "Полный анти-скринграб",
		["Type shape FOV"] = "Фигура ФОВа",
		Shared = "Общее",
		Watermark = "Ватермарка",
		Fakelag = "Фейклаг",
		Create = "Создать",
		["PING %d"] = "ПИНГ %d",
		Toggle = "Переключать",
		FLASHLIGHT = "ЕСТЬ ФОНАРИК",
		[Kefir.text_sg] = "Скринграбится!"
	},
	EN = {}
}
Kefir.faq_features = Kefir.faq_features or {
	ignoreteam = "Prevents the aimbot and visuals from reacting to players on your own team.",
	X_aimbot_hitbox_preview_X = "In this window, you can add / remove bones, in which aimbot will aiming.",
	autostop_type = "Selects the type of auto-stopping he will do for you.",
	muzzlefov = "[Z-City] It will take the center of the FOV from the muzzle of your weapon.",
	fakelag_ticks = "The number of simulation ticks to skip per network update.",
	X_PLAYERS_removefriend_X = "Remove this player from friend list.",
	silent = "Enables silent aimbot which redirects bullets to the target without changing your view angles.",
	automaticpistol = "Modifies semi-automatic pistols to fire continuously while the key is held.",
	autofire_delay = "The amount of time to wait before shooting after a target is found.",
	X_PLAYERS_restoreesp_X = "Do this player Visible for ESP.",
	X_PLAYERS_ignoreesp_X = "Do this player Invisible for ESP.",
	norecoil = "Eliminates the vertical and horizontal kick of the weapon when firing.",
	sub_selection = "Second selection for player targeting.",
	autofire = "Automatically triggers a shot the moment an enemy enters the aimbot's hit-zone.",
	silent_type_new = "Determines whether the silent aim calculation happens on the client camera or server-side.",
	inlinetargeting = "Put function find target in hook aiming.",
	antiaim_yaw_jitter = "The degree of rapid angle shifting to confuse anti-aim resolvers.",
	X_PLAYERS_copy_appearance_name_X = "Copy Appearance Name this player in share buffer.",
	X_sap_X = "Select any player",
	typefov_Circle = "Set shape FOV to 'Circle'",
	predictspread = "An experimental feature that attempts to calculate and negate weapon spread.",
	dynamicfov = "The FOV will stick to a target when the aimbot is selected and activated on it.",
	X_PLAYERS_copy_steamid_X = "Copy SteamID this player in share buffer.",
	typefov = "Type shape FOV",
	autostop = "Forces your character to stop moving when the aimbot is ready to fire for maximum accuracy.",
	autostop_type_Full = "Just hold you in place without moving",
	ignoreotrub = "A filter to ignore players who are currently unconscious or in a 'downed' state.",
	force_baim_hp_int = "Number, after which force body aiming will work.",
	["silent_type_new_Server Silent"] = "Manipulating your view angles only SERVER, your camera will be in normal position.",
	force_baim_onkey = "Force body aiming on key.",
	tp_key = "The bind used to toggle between first-person and third-person perspectives.",
	viewmodel_change = "Enables custom positioning and rotation of your hands and weapon on screen.",
	calcpos_Matrix = "Using [PLAYER_META:GetBoneMatrix]",
	antiaim_yaw_spin = "The speed at which your character model rotates 360 degrees.",
	["silent_type_new_Camera Silent"] = "Manipulating your camera for create (silent) view.",
	force_baim_conditionsb = "If one of the selected conditions is met, the function will work.",
	["force_baim_conditionsb_In Air"] = "Condition: If you are in the air.",
	antiaim_pitch = "Sets the vertical angle of your model's head to prevent easy headshots.",
	force_baim_conditionsb_Standing = "Condition: If you are standing.",
	["force_baim_conditionsb_Hard Moving"] = "Condition: If you are moving so hard and intensive.",
	fakelag_conditionb_Moving = "Condition: If you are moving.",
	fakelag_conditionb_Crouching = "Condition: If you are crouching.",
	box = "Draws a bounding box around players to show their exact physical boundaries.",
	humanizator = "Aimbot Humanizer that makes your aimbot's movements more human-like.",
	master_switch = "With this switch you can quickly toggle the status of all enabled functions in the tab.",
	typefov_Box = "Set shape FOV to 'Box'",
	humanizator_noise = "Configures Hand Shake in aiming",
	force_baim = "Preferably, depending on the settings, the utility will target the player's torso / stomach.",
	directionallighting_previewesp = "Sets the model's lighting to match the menu color.",
	autocrouch = "Automatically forces your character into a crouched position when an enemy is detected.",
	force_baim_conditionsb_Moving = "Condition: If you are moving.",
	fakelag_conditionb_Standing = "Condition: If you are standing.",
	directionallighting_previewaim = "Sets the model's lighting to match the menu color.",
	autofire_first_delay = "Specific delay applied only to the very first shot in a sequence.",
	sub_selection_Armed = "Priority will be given to selecting a player with a weapon in hand.",
	aim = "Helps you aim at players, works on firearms.",
	fakelag = "Chokes outgoing packets to make your movement appear laggy and unpredictable to others.",
	X_keybind_button_X = "Press LMB to setting keybind on this feature. Enable on: (Unhold / Hold / Toggle / Always On / On Shot)",
	posture_peek = "Automatically adjusts your character's stance or lean when peeking around corners.",
	blockfire_nfr = "Prevents you from firing your weapon until you finish targeting a player.",
	["fakelag_conditionb_In Air"] = "Condition: If you are in the air.",
	humanizator_jitter = "Configures micro-movement in aiming",
	fakelag_conditionb = "If one of the selected conditions is met, the function will work.",
	X_PLAYERS_copy_steamid64_X = "Copy SteamID64 this player in share buffer.",
	fov = "Limits the radius within which players will be targeted.",
	autodraw = "Automatically initiates a weapon reload when the magazine is empty.",
	antiaim_yaw = "Sets the horizontal rotation of your model (Static, Spinning, or Jittering).",
	main_selection_Crosshair = "It will prioritize selecting the player closest to your crosshair.",
	playerchams_enable = "Applies a custom material or color overlay to player models for visibility.",
	playerchams_xqz = "Draws players through walls with a second color.",
	calcpos = "The mathematical method used to determine player bone positions (Standart or Matrix).",
	calcpos_Standart = "Using [PLAYER_META:GetBonePosition]",
	humanizator_spring = "Configures how speed you're aiming on target",
	hp_bar = "Visual indicator of the target's remaining health points.",
	autostop_type_Slide = "Just make you slide",
	force_baim_conditionsb_Crouching = "Condition: If you are crouching.",
	autowall = "Allows the aimbot to target enemies behind penetrable surfaces like thin walls.",
	["force_baim_conditionsb_On Doubletap"] = "Condition: If you are have charged doubletap.",
	["force_baim_conditionsb_Far Distance"] = "Condition: If the target is far away.",
	force_baim_distance = "Distance, after which force body aiming will work.",
	force_baim_hp = "Force body aiming when Health target will lower than 'N'",
	main_selection_Distance = "Priority will be given to selecting a player closer to you.",
	aspectratio = "Modifies the game's rendering aspect ratio to stretch or squash the view.",
	glow = "Renders a glowing outline around player models, often visible through walls.",
	antiaim = "Manipulates your character's network angles to make you harder to hit for other users.",
	["fakelag_conditionb_Hard Moving"] = "Condition: If you are moving so hard and intensive.",
	antiaim_yaw_static = "The constant angle at which your character will face.",
	ignorefakergdl = "Ignore player who be in ragdoll.",
	scaling = "Resizes ESP elements relative to distance to prevent screen clutter.",
	dormant = "Displays the last known position of players who have gone out of network range.",
	main_selection = "Main selection for player targeting.",
	smooth = "Adjusts how smoothly the utility will guide your crosshair towards the player.",
	alphadistance = "Gradually fades out ESP elements based on how far away the player is.",
	X_PLAYERS_addfriend_X = "Add this player in friend list.",
	fakelag_condition = "Specific movement states (Air, Moving, etc.) that trigger fake lag."
}
Kefir.variables = Kefir.variables or {
	AIM_HITBOX = {
		"Head1"
	},
	ESPINTERACTIVE = {
		tab = {
			6,
			""
		},
		data = {
			playername = {
				0,
				0,
				0,
				0,
				0,
				12
			},
			playerhp = {
				2,
				0,
				0,
				0,
				0,
				12
			},
			playerflags = {
				1,
				0,
				0,
				0,
				0,
				10
			},
			playerothers = {
				3,
				0,
				0,
				0,
				0,
				12
			},
			playerweapon = {
				3,
				0,
				0,
				0,
				0,
				12
			}
		}
	},
	USER_CONFIG = {
		LANGUAGE = "EN",
		SHARE = true
	},
	COMBAT = {
		tab = {
			1,
			""
		},
		toggle = {
			false,
			"Master Switch",
			"checkbox"
		},
		{
			name = "Aimbot",
			space_k = makeSpacerOption(1, 10),
			aim = {
				false,
				"Firearm Aimbot",
				"checkbox",
				2,
				{},
				{},
				"aim_hotkey"
			},
			fov = {
				10,
				"FOV",
				"slider",
				3,
				{
					10,
					360,
					0
				}
			},
			smooth = {
				1,
				"Smooth",
				"slider",
				4,
				{
					1,
					10,
					1
				}
			},
			blockfire_nfr = {
				false,
				"Wait Attack Snapping",
				"checkbox",
				5
			},
			space_selections = makeSpacerOption(6, 10),
			main_selection = {
				"Crosshair",
				"Main Selection",
				"combobox",
				7,
				{
					"Distance",
					"Crosshair"
				}
			},
			sub_selection = {
				"None",
				"Sub Selection",
				"combobox",
				8,
				{
					"None",
					"Armed"
				}
			},
			space_selections2 = makeSpacerOption(9, 10),
			typefov = {
				"Box",
				"FOV Type",
				"combobox",
				10,
				{
					"Box",
					"Circle"
				}
			},
			muzzlefov = {
				false,
				"FOV out Muzzle",
				"checkbox",
				11
			},
			dynamicfov = {
				false,
				"Dynamic FOV",
				"checkbox",
				12,
				{
					10,
					color_white,
					"Don't working on 'Always On' bind"
				}
			},
			space_baim = makeSpacerOption(13, 10),
			force_baim = {
				false,
				"Force Bodyaim",
				"checkbox",
				14
			},
			force_baim_onkey = {
				false,
				"On Key",
				"checkbox",
				15,
				{
					6
				},
				{},
				"baim_hotkey"
			},
			force_baim_hp = {
				false,
				"If HP lower than",
				"checkbox",
				16,
				{
					6
				}
			},
			force_baim_hp_int = {
				50,
				"HP",
				"slider",
				17,
				{
					10,
					100,
					0
				},
				30
			},
			force_baim_conditionsb = {
				{},
				"Conditions",
				"mcombobox",
				18,
				{
					"In Air",
					"Standing",
					"Hard Moving",
					"Moving",
					"Crouching",
					"On Doubletap",
					"Far Distance"
				},
				6
			},
			space_humanize = makeSpacerOption(19, 10),
			humanizator = {
				false,
				"Humanizator",
				"checkbox",
				20
			},
			humanizator_noise = {
				1,
				"Hand Shake",
				"slider",
				21,
				{
					0,
					10,
					1
				},
				10
			},
			humanizator_spring = {
				8,
				"Speed to Aim",
				"slider",
				22,
				{
					0,
					11,
					1
				},
				10
			},
			humanizator_jitter = {
				0.1,
				"Micro-Movement",
				"slider",
				24,
				{
					0,
					1,
					1
				},
				10
			},
			force_baim_distance = {
				1500,
				"Baim Distance",
				"slider",
				25,
				{
					100,
					5000,
					0
				},
				30
			},
			aim_hotkey = {
				KEY_B,
				nil,
				"keybind",
				-1,
				0,
				nil,
				false,
				"Hold",
				"Firearm Aimbot"
			},
			baim_hotkey = {
				MOUSE_5,
				nil,
				"keybind",
				-2,
				0,
				nil,
				false,
				"Hold",
				"Force Bodyaim"
			}
		},
		{
			name = "Rage",
			space_k = makeSpacerOption(1, 10),
			silent = {
				false,
				"Silent",
				"checkbox",
				2
			},
			silent_type_new = {
				"Server Silent",
				"Silent Type",
				"combobox",
				3,
				{
					"Camera Silent",
					"Server Silent"
				}
			},
			space_aa = makeSpacerOption(4, 16),
			antiaim = {
				false,
				"Anti-Aim",
				"checkbox",
				5
			},
			antiaim_pitch = {
				"Down",
				"Pitch",
				"combobox",
				6,
				{
					"Down",
					"Zero",
					"Up",
					"Jitter"
				}
			},
			antiaim_yaw = {
				"Static",
				"Yaw",
				"combobox",
				7,
				{
					"Static",
					"Spin",
					"Jitter",
					"Backward",
					"Forward",
					"Manual"
				}
			},
			space_se6xxx = makeSpacerOption(8, 16),
			antiaim_yaw_jitter = {
				0,
				"Jitter Range",
				"slider",
				9,
				{
					0,
					180,
					0,
					Color(255, 255, 255),
					"°"
				}
			},
			antiaim_yaw_static = {
				0,
				"Static Angle",
				"slider",
				10,
				{
					-360,
					360,
					0,
					Color(255, 255, 255),
					"°"
				}
			},
			antiaim_yaw_spin = {
				0,
				"Spin Speed",
				"slider",
				11,
				{
					0,
					360,
					0,
					Color(255, 255, 255),
					"%"
				}
			},
			antiaim_yaw_manual_left = {
				KEY_Z,
				"Manual Left",
				"keybind",
				12
			},
			antiaim_yaw_manual_back = {
				KEY_X,
				"Manual Back",
				"keybind",
				13
			},
			antiaim_yaw_manual_right = {
				KEY_C,
				"Manual Right",
				"keybind",
				14
			},
			space_sexxx = makeSpacerOption(15, 16),
			autofire = {
				false,
				"Auto Fire",
				"checkbox",
				16
			},
			autofire_first_delay = {
				50,
				"First Shot Delay",
				"slider",
				18,
				{
					0,
					1000,
					1,
					Color(255, 255, 255),
					"ms."
				}
			},
			autowall = {
				false,
				"Auto Wall",
				"checkbox",
				19
			},
			space_fakelag = makeSpacerOption(20, 16),
			fakelag = {
				false,
				"Fakelag",
				"checkbox",
				21
			},
			fakelag_ticks = {
				1,
				"Ticks",
				"slider",
				22,
				{
					1,
					24,
					0
				}
			},
			fakelag_conditionb = {
				{},
				"Conditions",
				"mcombobox",
				23,
				{
					"In Air",
					"Standing",
					"Moving",
					"Crouching"
				}
			},
			space_fakeduck = makeSpacerOption(24, 16),
			fakeduck = {
				false,
				"Fakeduck",
				"checkbox",
				25,
				{},
				{},
				"fakeduck_hotkey"
			},
			fakeduck_ticks = {
				1,
				"Ticks",
				"slider",
				26,
				{
					1,
					24,
					0
				}
			},
			space_dt = makeSpacerOption(27, 16),
			doubletap = {
				false,
				"Double Tap",
				"checkbox",
				28,
				{},
				{},
				"doubletap_hotkey"
			},
			doubletap_type = {
				"Offensive",
				"Type",
				"combobox",
				29,
				{
					"Offensive",
					"Defensive"
				},
				10
			},
			doubletap_indicator = {
				false,
				"Indicator",
				"checkbox",
				30,
				{
					10
				}
			},
			doubletap_saferecharge = {
				false,
				"Unsafe Recharge",
				"checkbox",
				31,
				{
					10,
					Kefir.color.is_screengrabing
				}
			},
			doubletap_rechargetargeting = {
				false,
				"No Recharge in Aiming",
				"checkbox",
				32,
				{
					10
				}
			},
			doubletap_customticks = {
				false,
				"Custom Ticks",
				"checkbox",
				33,
				{
					10
				}
			},
			doubletap_ct_ticks = {
				4,
				"Ticks",
				"slider",
				34,
				{
					1,
					64,
					0,
					Color(255, 255, 255),
					"t."
				},
				20
			},
			doubletap_hotkey = {
				MOUSE_LEFT,
				nil,
				"keybind",
				-1,
				0,
				nil,
				false,
				"On Shot",
				"Doubletap"
			},
			fakeduck_hotkey = {
				KEY_L,
				nil,
				"keybind",
				-1,
				0,
				nil,
				false,
				"Hold",
				"Fakeduck"
			}
		},
		{
			name = "Other",
			space_k = makeSpacerOption(1, 10),
			text1 = {
				nil,
				nil,
				"text",
				2,
				{
					"Accuracy",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			inlinetargeting = {
				false,
				"Inline Targeting",
				"checkbox",
				3,
				{
					10
				}
			},
			predictspread = {
				false,
				"Predict Spread",
				"checkbox",
				4,
				{
					10,
					Kefir.color.cfunction,
					"Experimentally!"
				}
			},
			calcpos = {
				"Standart",
				"Method Get Position",
				"combobox",
				5,
				{
					"Standart",
					"Matrix"
				},
				10
			},
			norecoil = {
				false,
				"No Recoil",
				"checkbox",
				6,
				{
					10
				}
			},
			norecoil_type = {
				"Semi",
				"No Recoil Type",
				"combobox",
				6,
				{
					"Semi",
					"Full"
				},
				20
			},
			autostop = {
				false,
				"Auto Stop",
				"checkbox",
				7,
				{
					10
				}
			},
			autostop_type = {
				"Slide",
				"Auto Stop Type",
				"combobox",
				8,
				{
					"Slide",
					"Full"
				},
				16
			},
			autocrouch = {
				false,
				"Auto Crouch",
				"checkbox",
				9,
				{
					10
				}
			},
			text2 = {
				nil,
				nil,
				"text",
				10,
				{
					"Filter",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			ignoreteam = {
				false,
				"Ignore Team",
				"checkbox",
				11,
				{
					10
				}
			},
			type_ignoreteam = {
				"Default",
				"Type Ignore Team",
				"combobox",
				12,
				{
					"Default",
					"Adaptive"
				},
				20
			},
			ignoreotrub = {
				false,
				"Ignore Unconscious",
				"checkbox",
				13,
				{
					10
				}
			},
			ignorefakergdl = {
				false,
				"Ignore Player In Fake",
				"checkbox",
				14,
				{
					10
				}
			},
			text_mskdw2 = {
				nil,
				nil,
				"text",
				15,
				{
					"Assist",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			posture_peek = {
				false,
				"Posture Peek",
				"checkbox",
				16,
				{
					10
				}
			},
			right_posture_peek = {
				KEY_E,
				"Right Peek",
				"keybind",
				17,
				5,
				nil,
				true
			},
			left_posture_peek = {
				KEY_Q,
				"Left Peek",
				"keybind",
				18,
				5,
				nil,
				true
			},
			autodraw = {
				false,
				"Auto Reload",
				"checkbox",
				19,
				{
					10
				}
			},
			automaticpistol = {
				false,
				"Auto Pistol",
				"checkbox",
				20,
				{
					10
				}
			}
		}
	},
	VISUALS = {
		tab = {
			2,
			""
		},
		toggle = {
			false,
			"Master Switch"
		},
		{
			name = "Player",
			space0 = makeSpacerOption(1, 12),
			box = {
				false,
				"Box",
				"checkbox",
				2,
				{},
				{
					Color(255, 255, 255)
				}
			},
			box_type = {
				"Default",
				"Box Type",
				"combobox",
				3,
				{
					"Default",
					"Corner",
					"Rounded",
					"Rounded Corner"
				}
			},
			box_roundint = {
				4,
				"BoxR Quality",
				"slider",
				4,
				{
					1,
					16,
					0
				}
			},
			box_rounding = {
				8,
				"BoxR Rounding",
				"slider",
				5,
				{
					1,
					32,
					0
				}
			},
			dormant = {
				false,
				"Dormant",
				"checkbox",
				6
			},
			typedormant = {
				"Transparent",
				"Type Dormant",
				"combobox",
				7,
				{
					"Transparent",
					"Semi-Transparent"
				}
			},
			alphadistance = {
				false,
				"Transparent From a Distance",
				"checkbox",
				8
			},
			scaling = {
				false,
				"Scaling from Distance",
				"checkbox",
				9
			},
			space1 = makeSpacerOption(10, 5),
			text0 = {
				nil,
				nil,
				"text",
				11,
				{
					"Flags",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			flag_otrub = {
				false,
				"Conscious",
				"checkbox",
				12,
				{
					10
				}
			},
			flag_pulse = {
				false,
				"Pulse",
				"checkbox",
				13,
				{
					10
				},
				{
					Color(255, 255, 255),
					Color(45, 132, 8),
					Color(95, 11, 11)
				}
			},
			flag_pulse_type = {
				"Static",
				"Pulse Bar Type",
				"combobox",
				14,
				{
					"Static",
					"Gradient"
				},
				10
			},
			flag_pulse_width = {
				3.5,
				"Pulse Bar Width",
				"slider",
				15,
				{
					3.5,
					10,
					1
				},
				10
			},
			flag_lungsfunction = {
				false,
				"Breathing",
				"checkbox",
				16,
				{
					10
				}
			},
			flag_isweapon = {
				false,
				"Firearm",
				"checkbox",
				17,
				{
					10
				}
			},
			flag_reload = {
				false,
				"Reloading",
				"checkbox",
				18,
				{
					10
				}
			},
			flag_aiming = {
				false,
				"Aiming",
				"checkbox",
				19,
				{
					10
				}
			},
			flag_target = {
				false,
				"Aim Target",
				"checkbox",
				20,
				{
					10
				}
			},
			flag_friend = {
				false,
				"Friend",
				"checkbox",
				21,
				{
					10
				}
			},
			flag_playerclass = {
				false,
				"Player Class",
				"checkbox",
				22,
				{
					10
				}
			},
			flag_hmcdrole = {
				false,
				"Traitor / Gunman",
				"checkbox",
				23,
				{
					10
				}
			},
			flag_ismelee = {
				false,
				"Melee",
				"checkbox",
				24,
				{
					10
				}
			},
			flag_ammo = {
				false,
				"Ammo",
				"checkbox",
				25,
				{
					10
				}
			},
			flag_user = {
				false,
				"Kefir User",
				"checkbox",
				26,
				{
					10
				}
			},
			flag_user_ug = {
				false,
				"Usergroup",
				"checkbox",
				27,
				{
					17
				}
			},
			flag_user_nick = {
				false,
				"Username",
				"checkbox",
				28,
				{
					17
				}
			},
			flag_infake = {
				false,
				"Faking",
				"checkbox",
				29,
				{
					10
				}
			},
			flag_ping = {
				false,
				"Ping",
				"checkbox",
				30,
				{
					10
				}
			},
			flag_karma = {
				false,
				"Karma",
				"checkbox",
				31,
				{
					10
				}
			},
			flag_defaultteam = {
				false,
				"Team",
				"checkbox",
				32,
				{
					10
				}
			},
			flag_hgteam = {
				false,
				"HG Team",
				"checkbox",
				33,
				{
					10
				}
			},
			spaceinvetoryr = makeSpacerOption(34, 10),
			text_inventory = {
				nil,
				nil,
				"text",
				35,
				{
					"Inventory Flags",
					19,
					Kefir.color.white,
					"ofont",
					4
				}
			},
			flag_flashlight = {
				false,
				"Flashlight",
				"checkbox",
				36,
				{
					10
				}
			},
			flag_sling = {
				false,
				"Weapon Sling",
				"checkbox",
				37,
				{
					10
				}
			},
			flag_brassknuckles = {
				false,
				"Brassknuckles",
				"checkbox",
				38,
				{
					10
				}
			},
			space2 = makeSpacerOption(39, 10),
			text1 = {
				nil,
				nil,
				"text",
				40,
				{
					"Player Info",
					19,
					Kefir.color.white,
					"ofont",
					4
				}
			},
			hp_bar = {
				false,
				"Health",
				"checkbox",
				41,
				{
					10
				},
				{
					Color(255, 255, 255),
					Color(45, 132, 8),
					Color(95, 11, 11)
				}
			},
			hp_bartype = {
				"Static",
				"HP Bar Type",
				"combobox",
				42,
				{
					"Static",
					"Gradient"
				},
				10
			},
			hp_barwidth = {
				3.5,
				"HP Bar Width",
				"slider",
				43,
				{
					3.5,
					10,
					1
				},
				10
			},
			realnick = {
				false,
				"Game Name",
				"checkbox",
				44,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			appearancenick = {
				false,
				"Appearance Name",
				"checkbox",
				45,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			weapon = {
				false,
				"Active Weapon",
				"checkbox",
				46,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			usergroup = {
				false,
				"Usergroup",
				"checkbox",
				47,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			eyetrace = {
				false,
				"Eye Trace",
				"checkbox",
				48,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			skeleton = {
				false,
				"Skeleton",
				"checkbox",
				49,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			inventory = {
				false,
				"Inventory",
				"checkbox",
				50,
				{
					10
				}
			},
			inventory_acolor = {
				false,
				"Adaptive Color",
				"checkbox",
				51,
				{
					17
				}
			},
			inventory_atype = {
				false,
				"Type",
				"checkbox",
				52,
				{
					17
				}
			},
			space233341 = makeSpacerOption(53, 10),
			text2 = {
				nil,
				nil,
				"text",
				54,
				{
					"Player Chams",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			playerchams_enable = {
				false,
				"Chams",
				"checkbox",
				55,
				{
					10
				},
				{
					Color(255, 255, 255),
					Color(255, 0, 0)
				}
			},
			playerchams_light = {
				false,
				"Suppress Lighting",
				"checkbox",
				56,
				{
					10
				}
			},
			playerchams_additive = {
				false,
				"Additive",
				"checkbox",
				57,
				{
					10
				}
			},
			playerchams_type = {
				"Textured",
				"Type",
				"combobox",
				58,
				Kefir.ChamsList,
				10
			},
			space_glow1 = makeSpacerOption(59, 10),
			text_glow = {
				nil,
				nil,
				"text",
				60,
				{
					"Player Glow",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			glow = {
				false,
				"Glow",
				"checkbox",
				61,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			glow_additive = {
				false,
				"Additive",
				"checkbox",
				62,
				{
					10
				}
			},
			glow_passes = {
				2,
				"Quality",
				"slider",
				63,
				{
					1,
					6,
					0
				},
				10
			},
			glow_blur = {
				3,
				"Blur",
				"slider",
				64,
				{
					0,
					5,
					0
				},
				10
			},
			playerchams_xqz = {
				false,
				"XQZ",
				"checkbox",
				65,
				{
					10
				}
			},
			space_offscreen = makeSpacerOption(66, 10),
			text_offscreen = {
				nil,
				nil,
				"text",
				67,
				{
					"Offscreen",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			offscreen = {
				false,
				"Offscreen Indicators",
				"checkbox",
				68,
				{
					10
				},
				{
					Color(255, 255, 255)
				}
			},
			offscreen_shape = {
				"Arrow",
				"Shape",
				"combobox",
				69,
				{
					"Arrow",
					"Dot",
					"Circle"
				}
			},
			offscreen_size = {
				12,
				"Size",
				"slider",
				70,
				{
					6,
					24,
					0
				}
			},
			offscreen_distance = {
				0,
				"Min Distance",
				"slider",
				71,
				{
					0,
					1000,
					0,
					color_white,
					"u."
				}
			},
			filterdistance = {
				0,
				"Filter Distance",
				"slider",
				-1,
				{
					0,
					3000,
					0,
					color_white,
					"u."
				}
			},
			filterteam = {
				false,
				"Filter Team",
				"checkbox",
				-2
			},
			filterenemy = {
				false,
				"Filter Enemy",
				"checkbox",
				-3
			},
			filternoclip = {
				false,
				"Filter Noclip",
				"checkbox",
				-4
			},
			onlyvisible = {
				false,
				"Only Visible",
				"checkbox",
				-5
			},
			directionallighting_previewesp = {
				true,
				"Theme Lighting",
				"checkbox",
				-6
			},
			directionallighting_previewaim = {
				true,
				"Theme Lighting",
				"checkbox",
				-7
			}
		},
		{
			name = "Other",
			space0 = makeSpacerOption(1, 10),
			k_text = {
				false,
				"Kill Text",
				"checkbox",
				2,
				{},
				{
					Color(255, 255, 255)
				}
			},
			k_log = {
				false,
				"Log",
				"checkbox",
				3,
				{
					7
				},
				{
					Color(255, 255, 255)
				}
			},
			hs_text = {
				false,
				"HS Text",
				"checkbox",
				4,
				{},
				{
					Color(255, 255, 255)
				}
			},
			dfov = {
				false,
				"Draw FOV",
				"checkbox",
				5,
				{},
				{
					Color(255, 255, 255),
					Color(0, 0, 0)
				}
			},
			apply_camerafov = {
				false,
				"Override FOV",
				"checkbox",
				6,
				{
					0,
					color_white,
					Kefir.text_sg
				}
			},
			camerafov = {
				75,
				"FOV",
				"slider",
				7,
				{
					75,
					155,
					0
				}
			},
			aspectratio = {
				0.1,
				"Aspect Ratio",
				"slider",
				8,
				{
					0.1,
					5,
					1,
					Kefir.color.white,
					"",
					Kefir.text_sg
				}
			},
			showhits = {
				false,
				"Hit",
				"checkbox",
				9,
				{},
				{
					Color(255, 255, 255)
				}
			},
			showhits_text = {
				false,
				"Text",
				"checkbox",
				10,
				{
					7
				}
			},
			showhits_shape = {
				true,
				"Shape",
				"checkbox",
				11,
				{
					7
				}
			},
			showhits_size = {
				19,
				"Size",
				"slider",
				12,
				{
					14,
					36,
					0
				},
				7
			},
			showhits_line = {
				false,
				"Line",
				"checkbox",
				13,
				{
					7
				},
				{
					Color(255, 255, 255)
				}
			},
			showhits_log = {
				false,
				"Log",
				"checkbox",
				14,
				{
					7
				}
			},
			spacemzulaaa2 = makeSpacerOption(15, 10),
			fakechams = {
				false,
				"AA Chams",
				"checkbox",
				16,
				{},
				{
					Color(15, 41, 187),
					Color(135, 31, 15)
				}
			},
			fakechams_light = {
				false,
				"Suppress Lighting",
				"checkbox",
				17
			},
			fakechams_additive = {
				false,
				"Additive",
				"checkbox",
				18
			},
			fakechams_type = {
				"Textured",
				"AA Chams Material",
				"combobox",
				19,
				Kefir.ChamsList
			},
			spacemzul = makeSpacerOption(20, 10),
			showmuzzle = {
				false,
				"Draw Hit",
				"checkbox",
				21,
				{},
				{
					Color(255, 255, 255)
				}
			},
			showmuzzle_silent = {
				false,
				"Draw Silent Hit",
				"checkbox",
				22,
				{},
				{
					Color(255, 255, 255)
				}
			},
			showmuzzle_type = {
				"Box",
				"Shape",
				"combobox",
				23,
				{
					"Box",
					"Cross",
					"Circle"
				},
				7
			},
			showmuzzle_size = {
				6,
				"Size",
				"slider",
				24,
				{
					1,
					16,
					0
				},
				7
			},
			spacemksmkd = makeSpacerOption(25, 10),
			weaponchams_enable = {
				false,
				"Weapon Chams",
				"checkbox",
				26,
				{},
				{
					Color(255, 255, 255)
				}
			},
			weaponchams_additive = {
				false,
				"Additive",
				"checkbox",
				27,
				{},
				{}
			},
			weaponchams_type = {
				"Textured",
				"Weapon Chams Type",
				"combobox",
				28,
				Kefir.ChamsList
			},
			space_indicators = makeSpacerOption(29, 10),
			text_indicators = {
				nil,
				nil,
				"text",
				30,
				{
					"Indicators",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			indicator_manual = {
				false,
				"AA Manual Dir",
				"checkbox",
				31,
				{
					10
				},
				{
					Color(128, 26, 26),
					Color(255, 255, 255)
				}
			},
			indicator_manual_type = {
				"Current",
				"AA Manual Dir Type",
				"combobox",
				32,
				{
					"Current",
					"Select"
				},
				10
			},
			indicator_manual_dist = {
				0.1,
				"AA Manual Dir Distance",
				"slider",
				33,
				{
					0.1,
					0.5,
					1
				},
				10
			},
			weaponstatus = {
				false,
				"Show Ammo",
				"checkbox",
				34,
				{},
				{
					Color(255, 255, 255)
				}
			}
		},
		{
			name = "World",
			space_k = makeSpacerOption(1, 10),
			footstep = {
				false,
				"Footstep",
				"checkbox",
				2,
				{},
				{
					Color(255, 255, 255)
				}
			},
			footstep_size = {
				16,
				"Footstep Size",
				"slider",
				3,
				{
					6,
					32,
					0
				}
			},
			apply_tperson = {
				false,
				"Thirdperson (FPS?)",
				"checkbox",
				4,
				{
					0,
					Kefir.color.is_screengrabing,
					Kefir.text_sg
				},
				{},
				"tp_key"
			},
			tperson = {
				0,
				"Thirdperson Distance",
				"slider",
				5,
				{
					0,
					180,
					0
				}
			},
			smooth_tperson = {
				1,
				"Thirdperson Smooth",
				"slider",
				6,
				{
					1,
					10,
					1
				}
			},
			text_rendering = {
				nil,
				nil,
				"text",
				7,
				{
					"Removals",
					19,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			noflash = {
				false,
				"No Flash",
				"checkbox",
				8,
				{
					7
				}
			},
			noarmorhud = {
				false,
				"No Armor HUD",
				"checkbox",
				9,
				{
					7
				}
			},
			hzbfade = {
				false,
				"No Fade",
				"checkbox",
				10,
				{
					7
				}
			},
			no_organism_effects = {
				false,
				"No Z-City Organism Effects",
				"checkbox",
				11,
				{
					7
				}
			},
			no_zcity_processing = {
				false,
				"No Z-City Processing",
				"checkbox",
				12,
				{
					7
				}
			},
			viewmodel_removebobsway = {
				false,
				"Remove Bob / Sway",
				"checkbox",
				13,
				{
					7
				}
			},
			space_huy = makeSpacerOption(14, 10),
			drawricochet = {
				false,
				"Draw Ricochets",
				"checkbox",
				15,
				{},
				{
					Color(255, 255, 255),
					Color(255, 0, 0)
				}
			},
			drawwall = {
				false,
				"Draw Penetrate",
				"checkbox",
				16,
				{}
			},
			space_abcd = makeSpacerOption(17, 10),
			text_viewmodel = {
				nil,
				nil,
				"text",
				18,
				{
					"Viewmodel changer",
					18,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			viewmodel_change = {
				false,
				"Enable",
				"checkbox",
				19,
				{
					10,
					color_white,
					Kefir.text_sg
				}
			},
			viewmodel_pos_forward = {
				0,
				"Pos X",
				"slider",
				20,
				{
					-30,
					30,
					0
				},
				20
			},
			viewmodel_pos_right = {
				0,
				"Pos Y",
				"slider",
				21,
				{
					-30,
					30,
					0
				},
				20
			},
			viewmodel_pos_up = {
				0,
				"Pos Z",
				"slider",
				22,
				{
					-30,
					30,
					0
				},
				20
			},
			space_vm = makeSpacerOption(23, 10),
			viewmodel_ang_x = {
				0,
				"Ang P",
				"slider",
				24,
				{
					-360,
					360,
					0
				},
				20
			},
			viewmodel_ang_y = {
				0,
				"Ang Y",
				"slider",
				25,
				{
					-360,
					360,
					0
				},
				20
			},
			viewmodel_ang_z = {
				0,
				"Ang R",
				"slider",
				26,
				{
					-360,
					360,
					0
				},
				20
			},
			space_ent = makeSpacerOption(27, 10),
			text_entity = {
				nil,
				nil,
				"text",
				28,
				{
					"Entity ESP",
					18,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			entity_esp = {
				false,
				"Enable",
				"checkbox",
				29,
				{
					10
				}
			},
			entity_esp_dormant = {
				false,
				"Dormant",
				"checkbox",
				30,
				{
					20
				}
			},
			entity_esp_scaling = {
				false,
				"Scaling from Distance",
				"checkbox",
				31,
				{
					20
				}
			},
			space_ent_settings = makeSpacerOption(32, 10),
			entity_esp_box = {
				false,
				"Box",
				"checkbox",
				33,
				{
					20
				},
				{
					Color(255, 255, 255)
				}
			},
			entity_esp_box_type = {
				"Default",
				"Box Type",
				"combobox",
				34,
				{
					"Default",
					"Corner",
					"Rounded",
					"Rounded Corner"
				},
				20
			},
			entity_esp_name = {
				false,
				"Name",
				"checkbox",
				35,
				{
					20
				},
				{
					Color(255, 255, 255)
				}
			},
			entity_esp_class = {
				false,
				"Class",
				"checkbox",
				36,
				{
					20
				},
				{
					Color(255, 255, 255)
				}
			},
			entity_esp_type = {
				false,
				"Type",
				"checkbox",
				37,
				{
					20
				},
				{
					Color(255, 255, 255)
				}
			},
			entity_esp_type_color = {
				false,
				"Adaptive Color",
				"checkbox",
				38,
				{
					27
				}
			},
			space_ent_type = makeSpacerOption(39, 10),
			text_entity_types = {
				nil,
				nil,
				"text",
				40,
				{
					"Entity Types",
					18,
					Color(255, 255, 255),
					"ofont",
					4
				}
			},
			entity_esp_weapon = {
				false,
				"Z-City Weapons",
				"checkbox",
				41,
				{
					20
				}
			},
			entity_esp_lootable = {
				false,
				"Z-City Lootable Props",
				"checkbox",
				42,
				{
					20
				}
			},
			entity_esp_grenades = {
				false,
				"Z-City Grenades",
				"checkbox",
				43,
				{
					20
				}
			},
			entity_esp_medicine = {
				false,
				"Z-City Medicines",
				"checkbox",
				44,
				{
					20
				}
			},
			entity_esp_atts = {
				false,
				"Z-City Attachments",
				"checkbox",
				45,
				{
					20
				}
			},
			entity_esp_armors = {
				false,
				"Z-City Armors",
				"checkbox",
				46,
				{
					20
				}
			},
			entity_esp_others = {
				false,
				"Z-City Others",
				"checkbox",
				47,
				{
					20
				}
			},
			entity_esp_all_weapons = {
				false,
				"All Weapons",
				"checkbox",
				48,
				{
					20
				}
			},
			entity_esp_maxdistance = {
				0,
				"Entity Max Distance",
				"slider",
				49,
				{
					0,
					10000,
					0
				}
			},
			tp_key = {
				MOUSE_4,
				nil,
				"keybind",
				-1,
				0,
				nil,
				false,
				"Toggle",
				"Thirdperson"
			}
		}
	},
	MISC = {
		tab = {
			3,
			""
		},
		toggle = {
			true,
			"Master Switch"
		},
		{
			name = "Misc",
			space_k = makeSpacerOption(1, 10),
			watermark = {
				false,
				"Watermark",
				"checkbox",
				2
			},
			keybinds = {
				false,
				"Keybinds",
				"checkbox",
				3
			},
			faqz = {
				true,
				"FAQ Features",
				"checkbox",
				4
			},
			faqz_animation = {
				true,
				"Animation",
				"checkbox",
				5,
				{
					7
				}
			},
			msgnotify = {
				false,
				"New Message Notify",
				"checkbox",
				6
			},
			msgnotify_details = {
				false,
				"Details",
				"checkbox",
				7,
				{
					7
				}
			},
			menu_hotkey = {
				KEY_F9,
				"Menu Hotkey",
				"keybind",
				8
			},
			unload = {
				nil,
				"Unload",
				"button",
				9,
				{
					"Unload",
					16,
					false,
					{
						60,
						40
					},
					Kefir.color.kefir_red
				}
			},
			rtnil = {
				true,
				"RT Clear",
				"checkbox",
				10
			},
			anti_fullsg = {
				false,
				"Full Anti-Screengrab",
				"checkbox",
				11,
				{
					0,
					Kefir.color.groupname,
					"Be carefully! When this feature is enabled, admin get screenshot just BLACK SCREEN, or nothing."
				}
			},
			anti_sg = {
				true,
				"Anti-Screengrab",
				"checkbox",
				12
			},
			reloadmatrix = {
				true,
				"Matrix Reload",
				"checkbox",
				13,
				{
					7
				}
			},
			rendertargetcheck = {
				true,
				"RT Valid",
				"checkbox",
				14,
				{
					7
				}
			},
			anti_ss = {
				true,
				"Anti-Screenshot",
				"checkbox",
				15,
				{
					0,
					color_white,
					"Some screengrabs use the screenshot method!"
				}
			},
			notify_sg = {
				true,
				"Log Screengrab",
				"checkbox",
				16
			},
			notify_snd_sg = {
				true,
				"with Sound",
				"checkbox",
				17,
				{
					7
				}
			},
			spaceddddk1nd3rdu0 = makeSpacerOption(18, 10),
			noconmsg = {
				false,
				"No Print ConMsg",
				"checkbox",
				19
			},
			nolog = {
				false,
				"No Show Logs",
				"checkbox",
				20
			},
			logtime = {
				2,
				"Logs Seconds Alive Time",
				"slider",
				21,
				{
					1,
					5,
					0
				}
			},
			rolesnotify = {
				false,
				"Log Roles",
				"checkbox",
				22
			},
			discordrpc = {
				false,
				"Discord RPC",
				"checkbox",
				23
			},
			discordrpc_custom = {
				false,
				"Custom",
				"checkbox",
				24,
				{
					10
				}
			},
			discordrpc_text = {
				"",
				nil,
				"input",
				25,
				{
					100,
					15,
					"RPC Text",
					"chat",
					20,
					10
				}
			},
			discordrpc_details = {
				"",
				nil,
				"input",
				26,
				{
					100,
					15,
					"RPC Details",
					"chat",
					20,
					10
				}
			},
			chatspam = {
				false,
				"Chat Spam",
				"checkbox",
				27
			},
			chatspam_text = {
				"kefir rework top checha123321 -> https://kefir.rip",
				nil,
				"input",
				28,
				{
					210,
					15,
					"Text",
					"chat",
					20
				}
			},
			chatspam_delay = {
				2,
				"Delay",
				"slider",
				29,
				{
					0.1,
					6,
					1,
					Color(255, 255, 255),
					"s."
				}
			}
		},
		{
			name = "Exploits",
			space1 = makeSpacerOption(1, 10),
			limitmv = {
				true,
				"CUserCmd Clamper",
				"checkbox",
				2
			},
			limitmv_amount = {
				5250,
				"CUserCmd Clamper - Limit",
				"slider",
				3,
				{
					0,
					10000,
					0
				}
			},
			space_for_lookaway = makeSpacerOption(4, 10),
			lookaway = {
				false,
				"Head Crazy Rotating",
				"checkbox",
				5
			},
			lookawayclamp = {
				true,
				"Clamp HCR for Original Z-City",
				"checkbox",
				6
			},
			lookaway_custom = {
				false,
				"Custom Fake Head",
				"checkbox",
				7
			},
			lookaway_custom_pitch = {
				0,
				"Fake Head Pitch",
				"slider",
				8,
				{
					-360,
					360,
					0
				}
			},
			lookaway_custom_yaw = {
				0,
				"Fake Head Yaw",
				"slider",
				9,
				{
					-360,
					360,
					0
				}
			},
			space_for_instantsearch = makeSpacerOption(10, 10),
			instsearch = {
				false,
				"Instant Search",
				"checkbox",
				11
			},
			space_for_zbase = makeSpacerOption(12, 10),
			zbase_crasher = {
				false,
				"Z-Base Crasher",
				"checkbox",
				13
			},
			zbase_crasher_repeat = {
				1,
				"Z-Base Crasher Repeater",
				"slider",
				14,
				{
					1,
					4,
					0
				}
			},
			space_for_dance = makeSpacerOption(15, 10),
			actdance = {
				false,
				"Act Dance",
				"checkbox",
				16
			},
			space_for_fastzoom = makeSpacerOption(17, 10),
			fastzoom = {
				false,
				"Fast Zoom",
				"checkbox",
				18
			}
		},
		{
			name = "Movement",
			space_movement1 = makeSpacerOption(1, 10),
			text1241 = {
				nil,
				nil,
				"text",
				2,
				{
					"Movement",
					19,
					Kefir.color.white,
					"ofont",
					4
				}
			},
			bunnyhop = {
				false,
				"Bunny Hop",
				"checkbox",
				3,
				{
					10
				}
			},
			autostrafe = {
				false,
				"Auto Strafe",
				"checkbox",
				4,
				{
					10
				}
			}
		}
	},
	CONFIG = {
		tab = {
			7,
			""
		},
		{
			name = "Configs",
			space1 = makeSpacerOption(1, 10),
			config_list = {
				nil,
				nil,
				"list",
				2,
				{
					238.5,
					150,
					{}
				}
			},
			config_input = {
				"",
				nil,
				"input",
				3,
				{
					238.5,
					15,
					"Config Name",
					"chat",
					20
				}
			},
			config_create = {
				nil,
				"Create",
				"button",
				4,
				{
					"Create",
					16,
					false,
					{
						48,
						40
					},
					Kefir.color.kefir_red,
					nil,
					nil,
					nil,
					false
				}
			},
			config_load = {
				nil,
				"Load",
				"button",
				5,
				{
					"Load",
					16,
					false,
					{
						48,
						40
					},
					Kefir.color.kefir_red,
					nil,
					nil,
					nil,
					true,
					{
						48,
						45
					}
				}
			},
			config_save = {
				nil,
				"Save",
				"button",
				6,
				{
					"Save",
					16,
					false,
					{
						48,
						40
					},
					Kefir.color.kefir_red,
					nil,
					nil,
					nil,
					true,
					{
						96,
						45
					}
				}
			},
			config_remove = {
				nil,
				"Delete",
				"button",
				7,
				{
					"Delete",
					16,
					false,
					{
						48,
						40
					},
					Kefir.color.kefir_red,
					nil,
					nil,
					nil,
					true,
					{
						144,
						45
					}
				}
			},
			config_refresh = {
				nil,
				"Refresh",
				"button",
				8,
				{
					"Refresh",
					16,
					false,
					{
						48,
						40
					},
					Kefir.color.kefir_red,
					nil,
					nil,
					nil,
					true,
					{
						192,
						45
					}
				}
			},
			-- Cloud buttons
			cloud_save = {
				nil,
				"Cloud Save",
				"button",
				10,
				{
					"Cloud Save",
					14,
					false,
					{
						112,
						28
					},
					Kefir.color.kefir_green
				}
			},
			cloud_load = {
				nil,
				"Cloud Load",
				"button",
				11,
				{
					"Cloud Load",
					14,
					false,
					{
						112,
						28
					},
					Kefir.color.kefir_green
				}
			}
		},
		{
			name = "Appearance",
			space1 = makeSpacerOption(1, 10),
			custom_color = {
				false,
				"Custom Color",
				"checkbox",
				2,
				{},
				{
					Color(59, 12, 12),
					Color(135, 31, 15),
					Color(95, 11, 11),
					Color(48, 47, 47),
					Color(234, 100, 100)
				}
			},
			reset_customcolor = {
				nil,
				"Reset",
				"button",
				3,
				{
					"Reset",
					16,
					false,
					{
						60,
						40
					},
					Kefir.color.kefir_red
				}
			}
		},
		{
			name = "Cloud / Info",
			space1 = makeSpacerOption(1, 10),
			cloud_info = {
				nil,
				nil,
				"text",
				2,
				{
					"Cloud: select config -> Save/Load",
					16,
					Kefir.color.white,
					"ofont",
					10
				}
			},
			config_info_text = {
				nil,
				nil,
				"text",
				3,
				{
					"Kefir Config",
					17,
					Kefir.color.white,
					"ofont",
					10
				}
			}
		}
	},
	ATTACHMENTS = {
		tab = {
			4,
			""
		},
		{},
		undraw = true
	},
	PLAYERS = {
		undraw = true,
		tab = {
			5,
			""
		}
	},
	HOME = {
		undraw = true,
		tab = {
			6,
			""
		}
	}
}

Kefir.special_server = {}

local featureServerMap = {
	instsearch = "zcity",
	entity_esp_lootable = "zcity",
	lookaway_custom_yaw = "zcity",
	no_zcity_processing = "zcity",
	flag_sling = "zcity",
	flag_brassknuckles = "zcity",
	lookawayclamp = "zcity",
	noflash = "zcity",
	flag_pulse = "zcity",
	flag_lungsfunction = "zcity",
	flag_pulse_width = "zcity",
	hzbfade = "zcity",
	flag_playerclass = "zcity",
	entity_esp_armors = "zcity",
	entity_esp_medicine = "zcity",
	flag_hgteam = "hgcom",
	posture_peek = "zcity",
	left_posture_peek = "zcity",
	spaceinvetoryr = "zcity",
	ignoreotrub = "zcity",
	entity_esp_atts = "zcity",
	flag_karma = "zcity",
	autowall = "zcity",
	flag_reload = "zcity",
	rolesnotify = "zcity",
	lookaway_custom_pitch = "zcity",
	flag_otrub = "zcity",
	flag_aiming = "zcity",
	noarmorhud = "zcity",
	right_posture_peek = "zcity",
	entity_esp_weapon = "zcity",
	drawwall = "zcity",
	entity_esp_grenades = "zcity",
	no_organism_effects = "zcity",
	entity_esp_others = "zcity",
	ignorefakergdl = "zcity",
	space_for_lookaway = "zcity",
	flag_flashlight = "zcity",
	lookaway_custom = "zcity",
	flag_pulse_type = "zcity",
	flag_hmcdrole = "zcity",
	appearancenick = "zcity",
	lookaway = "zcity",
	space_for_instantsearch = "zcity",
	text_inventory = "zcity",
	drawricochet = "zcity",
	flag_infake = {
		hgcom = true,
		zcity = true
	},
	flag_ismelee = {
		hgcom = true,
		zcity = true
	},
	flag_isweapon = {
		hgcom = true,
		zcity = true
	},
	muzzlefov = {
		hgcom = true,
		zcity = true
	}
}
local combatEnabled = false
local visualsEnabled = false
local miscEnabled = true
local tableDataA = {}

Kefir.previewPly = nil
Kefir.tabs = {}
Kefir.tabs.list = {}

runtimeApi.color = Kefir.color
runtimeApi.fn = Kefir.functions
runtimeApi.var = Kefir.variables
runtimeApi.stime = Kefir.curtime
runtimeApi.material = Kefir.material
runtimeApi.cmd = concommand
runtimeApi.insert = runtimeApi.table.insert
runtimeApi.HasValue = runtimeApi.table.HasValue
runtimeApi.getkeys = runtimeApi.table.GetKeys
runtimeApi.CopyFromTo = runtimeApi.table.CopyFromTo
runtimeApi.GetAll = runtimeApi.player.GetAll
runtimeApi.AngleDifference = math.AngleDifference
runtimeApi.hRun = hook.Run
runtimeApi.hAdd = hook.Add
runtimeApi.hRemove = hook.Remove
runtimeApi.cAdd = runtimeApi.cmd.Add
runtimeApi.cGetTable = runtimeApi.cmd.GetTable
runtimeApi.vCreate = runtimeApi.vgui.Create
runtimeApi.vGetControlTable = runtimeApi.vgui.GetControlTable
runtimeApi.vCreateX = runtimeApi.vgui.CreateX
runtimeApi.clamp = runtimeApi.math.Clamp
runtimeApi.wpGet = runtimeApi.weapons.Get
runtimeApi.wpList = runtimeApi.weapons.GetList
runtimeApi.angnormalize = runtimeApi.math.NormalizeAngle
runtimeApi.sCreateFont = runtimeApi.surface.CreateFont

localCache.setScissorRect = render.SetScissorRect
localCache.updateScreenEffectTexture = render.UpdateScreenEffectTexture
localCache.setDrawColor = runtimeApi.surface.SetDrawColor
localCache.drawSurfaceLine = runtimeApi.surface.DrawLine
localCache.drawRenderLine = runtimeApi.render.DrawLine
localCache.getMousePosition = gui.MousePos
localCache.isGameUiVisible = gui.IsGameUIVisible
localCache.isConsoleVisible = gui.IsConsoleVisible
localCache.getDebugInfo = runtimeApi.debug.getinfo

runtimeApi.CompileString = CompileString
runtimeApi.IsKeyDown = runtimeApi.input.IsButtonDown
runtimeApi.LookupBinding = runtimeApi.input.LookupBinding
runtimeApi.IsMouseDown = runtimeApi.input.IsMouseDown
runtimeApi.GetKeyCode = runtimeApi.input.GetKeyCode
runtimeApi.GetKeyName = runtimeApi.input.GetKeyName
runtimeApi.tSimple = runtimeApi.timer.Simple

localCache.getObbMins = Kefir.meta.entity.OBBMins
localCache.getObbMaxs = Kefir.meta.entity.OBBMaxs
localCache.mathMin = runtimeApi.math.min

runtimeApi.mabs = runtimeApi.math.abs
runtimeApi.mDistance = runtimeApi.math.Distance
runtimeApi.deg = runtimeApi.math.deg
runtimeApi.acos = runtimeApi.math.acos
runtimeApi.asin = runtimeApi.math.asin

localCache.mathMax = runtimeApi.math.max

runtimeApi.tIsEmpty = runtimeApi.table.IsEmpty

localCache.randomTableValue = runtimeApi.table.Random

runtimeApi.RemoveByValue = runtimeApi.table.RemoveByValue
runtimeApi.tremove = runtimeApi.table.remove

localCache.drawOutlinedRect = runtimeApi.surface.DrawOutlinedRect

runtimeApi.Lerp = Lerp

localCache.drawRect = runtimeApi.surface.DrawRect
localCache.drawCircle = runtimeApi.surface.DrawCircle

runtimeApi.sSetTexture = runtimeApi.surface.SetTexture

localCache.drawPoly = runtimeApi.surface.DrawPoly

runtimeApi.sin = runtimeApi.math.sin
runtimeApi.cos = runtimeApi.math.cos
runtimeApi.rad = runtimeApi.math.rad
runtimeApi.tan = runtimeApi.math.tan

localCache.drawTexturedRect = runtimeApi.surface.DrawTexturedRect
localCache.drawTexturedRectUv = runtimeApi.surface.DrawTexturedRectUV

runtimeApi.sorting = runtimeApi.table.sort
runtimeApi.sSetFont = runtimeApi.surface.SetFont
runtimeApi.sTextPos = runtimeApi.surface.SetTextPos
runtimeApi.gmatch = runtimeApi.string.gmatch
runtimeApi.sSetTextColor = runtimeApi.surface.SetTextColor
runtimeApi.sDrawText = runtimeApi.surface.DrawText
runtimeApi.sGetTextSize = runtimeApi.surface.GetTextSize

localCache.getTextureId = runtimeApi.surface.GetTextureID
localCache.setSurfaceMaterial = runtimeApi.surface.SetMaterial
localCache.setRenderMaterial = runtimeApi.render.SetMaterial
localCache.drawBeam = runtimeApi.render.DrawBeam
localCache.getHoveredPanel = vgui.GetHoveredPanel

runtimeApi.sformat = runtimeApi.string.format
runtimeApi.Replace = runtimeApi.string.Replace
runtimeApi.find = runtimeApi.string.find
runtimeApi.startswith = runtimeApi.string.StartsWith
runtimeApi.floor = runtimeApi.math.floor
runtimeApi.GetRenderTarget = runtimeApi.render.GetRenderTarget
runtimeApi.GetMap = game.GetMap
runtimeApi.GetIP = game.GetIPAddress
runtimeApi.GetHostName = GetHostName
runtimeApi.GetScreenEffectTexture = runtimeApi.render.GetScreenEffectTexture
runtimeApi.GetViewSetup = runtimeApi.render.GetViewSetup

localCache.renderView = runtimeApi.render.RenderView

runtimeApi["qX7mP2"] = runtimeApi.net.Start
runtimeApi["vK4rT9"] = runtimeApi.net.SendToServer
runtimeApi["aN8cL5"] = runtimeApi.net.WriteString
runtimeApi["sD3hW6"] = runtimeApi.net.WriteTable
runtimeApi["jR9fB1"] = runtimeApi.net.WriteEntity
runtimeApi["mU5zQ8"] = runtimeApi.net.WriteBool
runtimeApi["pE2yG7"] = runtimeApi.net.WriteFloat
runtimeApi["xC6nH4"] = runtimeApi.net.WriteInt
runtimeApi["bV1kS3"] = runtimeApi.net.ReadUInt
runtimeApi.ServerFrameTime = runtimeApi.engine.ServerFrameTime
runtimeApi.TickInterval = runtimeApi.engine.TickInterval

localCache.tickInterval = runtimeApi.TickInterval()
localCache.concatTable = table.concat

runtimeApi.utilDistanceToLine = runtimeApi.util.DistanceToLine
runtimeApi.receiveStringToID = runtimeApi.util.NetworkStringToID
runtimeApi.slower = runtimeApi.string.lower
runtimeApi.supper = runtimeApi.string.upper
runtimeApi.seteyeangles = Kefir.meta.player.SetEyeAngles
runtimeApi.health = Kefir.meta.player.MetaBaseClass.Health
runtimeApi.maxhealth = Kefir.meta.player.MetaBaseClass.GetMaxHealth
runtimeApi.activeweapon = Kefir.meta.player.GetActiveWeapon
runtimeApi.nick = Kefir.meta.player.Nick
runtimeApi.gev = Kefir.global.gevent
runtimeApi.traceline = runtimeApi.util.TraceLine
runtimeApi.tracequick = runtimeApi.util.QuickTrace
runtimeApi.tracehull = runtimeApi.util.TraceHull
runtimeApi.parse_json = runtimeApi.util.JSONToTable
runtimeApi.parse_table = runtimeApi.util.TableToJSON
runtimeApi.b64_encode = runtimeApi.util.Base64Encode
runtimeApi.b64_decode = runtimeApi.util.Base64Decode
Kefir.bxor = runtimeApi.bit.bxor

localCache.stringChar = string.char
localCache.stringByte = string.byte
localCache.nullMetatable = {
	__index = function(unusedParam, unusedParamA)
		return
	end
}

Kefir.setmetatable(Kefir, localCache.nullMetatable)

function Kefir.AllowedFeature(selfRefA, featureName)
	local valueD = featureServerMap[featureName]

	if valueD == nil then
		return true
	end

	if isstring(valueD) then
		return Kefir.special_server[valueD] == true
	end

	for keyB in next, valueD do
		if Kefir.special_server[keyB] then
			return true
		end
	end

	return false
end

function runtimeApi.u8_strreltoabs(textA, ...)
	local tableDataB = {
		...
	}

	for keyC, itemA in Kefir.ipairs(tableDataB) do
		itemA = itemA > 0 and itemA or math.max(#textA + itemA + 1, 1)

		if itemA < 1 or itemA > #textA + 1 then
			Kefir.error("bad index to string (out of range)", 3)
		end

		tableDataB[keyC] = itemA
	end

	return Kefir.unpack(tableDataB)
end

function runtimeApi.u8_char(...)
	local tableDataC = {}

	for keyD, itemB in Kefir.ipairs({
		...
	}) do
		if itemB < 0 or itemB > 1114111 then
			Kefir.error("bad argument #" .. keyD .. " to char (out of range)", 2)
		end

		local valueE
		local valueF
		local valueG
		local valueH

		if itemB < 128 then
			runtimeApi.insert(tableDataC, localCache.stringChar(itemB))
		elseif itemB < 2048 then
			local valueI = Kefir.bxor(192, bit.band(bit.rshift(itemB, 6), 31))
			local valueJ = Kefir.bxor(128, bit.band(itemB, 63))

			runtimeApi.insert(tableDataC, localCache.stringChar(valueI, valueJ))
		elseif itemB < 65536 then
			local valueK = Kefir.bxor(224, bit.band(bit.rshift(itemB, 12), 15))
			local valueL = Kefir.bxor(128, bit.band(bit.rshift(itemB, 6), 63))
			local valueM = Kefir.bxor(128, bit.band(itemB, 63))

			runtimeApi.insert(tableDataC, localCache.stringChar(valueK, valueL, valueM))
		else
			local valueN = Kefir.bxor(240, bit.band(bit.rshift(itemB, 18), 7))
			local valueO = Kefir.bxor(128, bit.band(bit.rshift(itemB, 12), 63))
			local valueP = Kefir.bxor(128, bit.band(bit.rshift(itemB, 6), 63))
			local valueQ = Kefir.bxor(128, bit.band(itemB, 63))

			runtimeApi.insert(tableDataC, localCache.stringChar(valueN, valueO, valueP, valueQ))
		end
	end

	return localCache.concatTable(tableDataC, "")
end

function runtimeApi.u8_decode(textB, positionA)
	positionA = runtimeApi.u8_strreltoabs(textB, positionA or 1)

	local byteResult = textB:byte(positionA, positionA)

	if not byteResult then
		return nil
	end

	if byteResult < 128 then
		return positionA, positionA, byteResult
	end

	if byteResult > 244 or byteResult < 194 then
		return nil
	end

	local valueR = byteResult >= 240 and 3 or byteResult >= 224 and 2 or byteResult >= 192 and 1
	local valueS = positionA + valueR
	local numberValue = 0

	if valueS > #textB then
		return nil
	end

	for keyE, itemC in Kefir.ipairs({
		textB:byte(positionA + 1, valueS)
	}) do
		if bit.band(itemC, 192) ~= 128 then
			return nil
		end

		numberValue = bit.bor(bit.lshift(numberValue, 6), bit.band(itemC, 63))
		byteResult = bit.lshift(byteResult, 1)
	end

	local valueT = bit.bor(numberValue, bit.lshift(bit.band(byteResult, 127), valueR * 5))

	return positionA, valueS, valueT
end

function runtimeApi.u8_offset(textC, characterOffset, startPosition)
	if startPosition and (startPosition > #textC or -startPosition > #textC or startPosition == 0) then
		Kefir.error("bad index to string (out of range)", 2)
	end

	local valueU = characterOffset >= 0 and 1 or #textC
	local valueV = runtimeApi.u8_strreltoabs(textC, startPosition or valueU)

	if characterOffset == 0 then
		while valueV > 0 and not runtimeApi.u8_decode(textC, valueV) do
			valueV = valueV - 1
		end

		return valueV
	end

	if not runtimeApi.u8_decode(textC, valueV) then
		Kefir.error("initial position is a continuation byte", 2)
	end

	if characterOffset < 0 then
		for indexC = 1, -characterOffset do
			valueV = valueV - 1

			while valueV > 0 and not runtimeApi.u8_decode(textC, valueV) do
				valueV = valueV - 1
			end
		end

		if valueV < 1 then
			return nil
		end

		return valueV
	end

	if characterOffset > 0 then
		for indexD = 1, characterOffset do
			valueV = valueV + 1

			while valueV <= #textC and not runtimeApi.u8_decode(textC, valueV) do
				valueV = valueV + 1
			end
		end

		if valueV > #textC then
			return nil
		end

		return valueV
	end
end

function runtimeApi.u8l(textD, startPositionA, endPosition)
	startPositionA, endPosition = runtimeApi.u8_strreltoabs(textD, startPositionA or 1, endPosition or -1)

	local numberValueA = 0

	while startPositionA <= endPosition and startPositionA <= #textD do
		local valueW, valueX = runtimeApi.u8_decode(textD, startPositionA)

		if not valueW then
			return false, startPositionA
		end

		startPositionA = valueX + 1
		numberValueA = numberValueA + 1
	end

	return numberValueA
end

function runtimeApi.u8_strRelToAbsChar(textE, characterIndex)
	if characterIndex < 0 then
		characterIndex = runtimeApi.max(characterIndex + runtimeApi.u8l(textE) + 1, 0)
	end

	return characterIndex
end

function runtimeApi.u8_codepoint(textF, startPositionB, endPositionA)
	startPositionB, endPositionA = runtimeApi.u8_strreltoabs(textF, startPositionB or 1, endPositionA or startPositionB or 1)

	local tableDataD = {}

	repeat
		local valueY, valueZ, valueAA = runtimeApi.u8_decode(textF, startPositionB)

		if not valueY then
			Kefir.unpack("invalid UTF-8 code", 2)
		end

		startPositionB = valueZ + 1

		runtimeApi.insert(tableDataD, valueAA)
	until endPositionA <= valueZ

	return Kefir.unpack(tableDataD)
end

function runtimeApi.u8_getchar(textG, characterIndexA)
	characterIndexA = runtimeApi.u8_strRelToAbsChar(textG, characterIndexA)

	if characterIndexA == 0 then
		return ""
	end

	if characterIndexA > runtimeApi.u8l(textG) then
		return ""
	end

	local valueAB = runtimeApi.u8_offset(textG, characterIndexA - 1)

	return runtimeApi.u8_char(runtimeApi.u8_codepoint(textG, valueAB))
end

function runtimeApi.u8sub(textH, startCharacter, endCharacter)
	startCharacter = runtimeApi.u8_strRelToAbsChar(textH, startCharacter)
	endCharacter = runtimeApi.u8_strRelToAbsChar(textH, endCharacter or -1)

	local tableDataE = {}

	for indexE = startCharacter, endCharacter do
		tableDataE[#tableDataE + 1] = runtimeApi.u8_getchar(textH, indexE)
	end

	return localCache.concatTable(tableDataE)
end

localCache.startCamera = runtimeApi.cam.Start
localCache.endCamera = runtimeApi.cam.End
localCache.endCamera2D = runtimeApi.cam.End2D
localCache.camera2DData = {
	type = "2D"
}

function localCache.beginCameraMode(param, paramA, paramB, paramC, paramD, paramE, paramF, paramG, paramH, paramI)
	if param == "2D" then
		return localCache.startCamera(localCache.camera2DData)
	end

	if param == "3D" then
		local tableDataF = {}

		tableDataF.type = "3D"
		tableDataF.origin = paramA
		tableDataF.angles = paramB

		if paramC ~= nil then
			tableDataF.fov = paramC
		end

		if paramD ~= nil and paramE ~= nil and paramF ~= nil and paramG ~= nil then
			tableDataF.x = paramD
			tableDataF.y = paramE
			tableDataF.w = paramF
			tableDataF.h = paramG
			tableDataF.aspect = paramF / paramG
		end

		if paramH ~= nil and paramI ~= nil then
			tableDataF.znear = paramH
			tableDataF.zfar = paramI
		end

		return localCache.startCamera(tableDataF)
	end
end

function localCache.endCameraMode(paramJ)
	if paramJ == "2D" then
		return localCache.endCamera2D()
	end

	if paramJ == "3D" then
		return localCache.endCamera()
	end
end

localCache.pushModelMatrix = runtimeApi.cam.PushModelMatrix
localCache.popModelMatrix = runtimeApi.cam.PopModelMatrix
localCache.endCamera3D = runtimeApi.cam.End3D
localCache.ignoreDepth = runtimeApi.cam.IgnoreZ

Kefir.LerpVector = LerpVector
runtimeApi.bitband = runtimeApi.bit.band
runtimeApi.bitbnot = runtimeApi.bit.bnot
runtimeApi.bitbor = runtimeApi.bit.bor
runtimeApi.ply_pos = ZERO_VECTOR
runtimeApi.fWrite = runtimeApi.file.Write
runtimeApi.fDelete = runtimeApi.file.Delete
runtimeApi.fExists = runtimeApi.file.Exists
runtimeApi.fOpen = runtimeApi.file.Open
runtimeApi.ggsub = runtimeApi.string.gsub

localCache.setForwardMove = Kefir.meta.cmd.SetForwardMove
localCache.setSideMove = Kefir.meta.cmd.SetSideMove
localCache.setUpMove = Kefir.meta.cmd.SetUpMove
localCache.getCommandNumber = Kefir.meta.cmd.CommandNumber
localCache.getCommandViewAngles = Kefir.meta.cmd.GetViewAngles
localCache.createClientsideModel = ClientsideModel
localCache.setRenderBlend = runtimeApi.render.SetBlend
localCache.isTakingScreenshot = runtimeApi.render.IsTakingScreenshot
localCache.setColorModulation = runtimeApi.render.SetColorModulation
localCache.overrideMaterial = runtimeApi.render.MaterialOverride
localCache.suppressEngineLighting = runtimeApi.render.SuppressEngineLighting
localCache.setLightingOrigin = runtimeApi.render.SetLightingOrigin
localCache.resetModelLighting = runtimeApi.render.ResetModelLighting
localCache.setModelLighting = runtimeApi.render.SetModelLighting
localCache.findEntitiesInSphere = runtimeApi.ents.FindInSphere
localCache.osTime = runtimeApi.os.time
localCache.osDate = runtimeApi.os.date

Kefir.textureid = {
	gradient = localCache.getTextureId("vgui/gradient-d"),
	gradient_h = localCache.getTextureId("vgui/gradient-l"),
	vguigradient_r = localCache.getTextureId("vgui/gradient-r"),
	center_grad = localCache.getTextureId("gui/center_gradient"),
	texwhite = localCache.getTextureId("vgui/white"),
	tex_corner8 = localCache.getTextureId("gui/corner8"),
	tex_corner16 = localCache.getTextureId("gui/corner16"),
	tex_corner32 = localCache.getTextureId("gui/corner32"),
	tex_corner64 = localCache.getTextureId("gui/corner64"),
	tex_corner512 = localCache.getTextureId("gui/corner512")
}
runtimeApi.tid = Kefir.textureid

function runtimeApi.draw_stext(textI, fontA, xA, yA, colorA, xAlign, yAlign)
	textI = tostring(textI)
	fontA = fontA or "DermaDefault"
	xA = xA or 0
	yA = yA or 0
	xAlign = xAlign or TEXT_ALIGN_LEFT
	yAlign = yAlign or TEXT_ALIGN_TOP

	runtimeApi.sSetFont(fontA)

	local valueAC, valueAD = runtimeApi.sGetTextSize(textI)

	if xAlign == TEXT_ALIGN_CENTER then
		xA = xA - valueAC / 2
	elseif xAlign == TEXT_ALIGN_RIGHT then
		xA = xA - valueAC
	end

	if yAlign == TEXT_ALIGN_CENTER then
		yA = yA - valueAD / 2
	elseif yAlign == TEXT_ALIGN_BOTTOM then
		yA = yA - valueAD
	end

	runtimeApi.sTextPos(runtimeApi.math.ceil(xA), runtimeApi.math.ceil(yA))

	if colorA ~= nil then
		runtimeApi.sSetTextColor(colorA.r, colorA.g, colorA.b, colorA.a)
	else
		runtimeApi.sSetTextColor(color_white)
	end

	runtimeApi.sDrawText(textI)

	return valueAC, valueAD
end

function runtimeApi.draw_text(textJ, fontB, xB, yB, colorB, xAlignA)
	if fontB == nil then
		fontB = "DermaDefault"
	end

	if textJ ~= nil then
		textJ = tostring(textJ)
	end

	if xB == nil then
		xB = 0
	end

	if yB == nil then
		yB = 0
	end

	local valueAE = xB
	local valueAF = yB
	local valueAG = ""
	local numberValueB = 0
	local numberValueC = 0

	runtimeApi.sSetFont(fontB)

	local valueAH, valueAI = runtimeApi.sGetTextSize("\n")
	local numberValueD = 50

	for keyF in runtimeApi.gmatch(textJ, "[^\n]*") do
		if #keyF > 0 then
			if runtimeApi.find(keyF, "\t") then
				for keyG, itemD in runtimeApi.gmatch(keyF, "(\t*)([^\t]*)") do
					valueAE = runtimeApi.math.ceil((valueAE + numberValueD * localCache.mathMax(#keyG - 1, 0)) / numberValueD) * numberValueD

					if #itemD > 0 then
						runtimeApi.draw_stext(itemD, fontB, valueAE, valueAF, colorB, xAlignA)

						local valueAJ, valueAK = runtimeApi.sGetTextSize(itemD)

						valueAE = valueAE + valueAJ
						numberValueB = valueAJ
						numberValueC = valueAK
					end
				end
			else
				return runtimeApi.draw_stext(keyF, fontB, valueAE, valueAF, colorB, xAlignA)
			end
		else
			valueAE = xB
			valueAF = valueAF + valueAI / 2
		end
	end

	return numberValueB, numberValueC
end

function runtimeApi.draw_otext(textK, fontC, xC, yC, colorC, xAlignB, yAlignA, outlineSize, outlineColor)
	local valueAL = outlineSize * 2 / 3

	if valueAL < 1 then
		valueAL = 1
	end

	for indexF = -outlineSize, outlineSize, valueAL do
		for indexG = -outlineSize, outlineSize, valueAL do
			runtimeApi.draw_stext(textK, fontC, xC + indexF, yC + indexG, outlineColor, xAlignB, yAlignA)
		end
	end

	return runtimeApi.draw_stext(textK, fontC, xC, yC, colorC, xAlignB, yAlignA)
end

function runtimeApi.draw_rdboxex(radiusA, xD, yD, widthA, heightA, colorD, topLeft, topRight, bottomLeft, bottomRight)
	localCache.setDrawColor(colorD.r, colorD.g, colorD.b, colorD.a)

	if radiusA <= 0 then
		localCache.drawRect(xD, yD, widthA, heightA)

		return
	end

	xD = runtimeApi.math.Round(xD)
	yD = runtimeApi.math.Round(yD)
	widthA = runtimeApi.math.Round(widthA)
	heightA = runtimeApi.math.Round(heightA)
	radiusA = localCache.mathMin(runtimeApi.math.Round(radiusA), runtimeApi.floor(widthA / 2), runtimeApi.floor(heightA / 2))

	localCache.drawRect(xD + radiusA, yD, widthA - radiusA * 2, heightA)
	localCache.drawRect(xD, yD + radiusA, radiusA, heightA - radiusA * 2)
	localCache.drawRect(xD + widthA - radiusA, yD + radiusA, radiusA, heightA - radiusA * 2)

	local texCorner8 = runtimeApi.tid.tex_corner8

	if radiusA > 8 then
		texCorner8 = runtimeApi.tid.tex_corner16
	end

	if radiusA > 16 then
		texCorner8 = runtimeApi.tid.tex_corner32
	end

	if radiusA > 32 then
		texCorner8 = runtimeApi.tid.tex_corner64
	end

	if radiusA > 64 then
		texCorner8 = runtimeApi.tid.tex_corner512
	end

	runtimeApi.sSetTexture(texCorner8)

	if topLeft then
		localCache.drawTexturedRectUv(xD, yD, radiusA, radiusA, 0, 0, 1, 1)
	else
		localCache.drawRect(xD, yD, radiusA, radiusA)
	end

	if topRight then
		localCache.drawTexturedRectUv(xD + widthA - radiusA, yD, radiusA, radiusA, 1, 0, 0, 1)
	else
		localCache.drawRect(xD + widthA - radiusA, yD, radiusA, radiusA)
	end

	if bottomLeft then
		localCache.drawTexturedRectUv(xD, yD + heightA - radiusA, radiusA, radiusA, 0, 1, 1, 0)
	else
		localCache.drawRect(xD, yD + heightA - radiusA, radiusA, radiusA)
	end

	if bottomRight then
		localCache.drawTexturedRectUv(xD + widthA - radiusA, yD + heightA - radiusA, radiusA, radiusA, 1, 1, 0, 0)
	else
		localCache.drawRect(xD + widthA - radiusA, yD + heightA - radiusA, radiusA, radiusA)
	end
end

function runtimeApi.draw_rdbox(radiusB, xE, yE, widthB, heightB, colorE)
	return runtimeApi.draw_rdboxex(radiusB, xE, yE, widthB, heightB, colorE, true, true, true, true)
end

function runtimeApi.drawNoTexture()
	runtimeApi.sSetTexture(runtimeApi.tid.texwhite)
end

localCache.iteratePlayers = runtimeApi.player.Iterator
localCache.iterateEntities = runtimeApi.ents.Iterator

Kefir.fakeHead = Kefir.fakeHead or {
	0,
	0
}

local boneCache = cache_bones or {}

local function xorDecode(encodedText, xorKey)
	local decodedBytes = {}

	for index = 1, #encodedText do
		decodedBytes[index] = localCache.stringChar(Kefir.bxor(localCache.stringByte(encodedText, index), xorKey))
	end

	return localCache.concatTable(decodedBytes)
end

local accountName = "Vikenti"
local accountPassword = ""
local accountGroup = "premium"
local accountStatus = "6"

if not istable(nativeApi) or not isfunction(nativeApi.engine_isCapture) or not isfunction(nativeApi.service_unload) then
	fallbackMode = true

	Derma_Query("God", "Why are you doing that?", "nope.")

	return
end

function Kefir.we_hvh_server(selfRefB)
	return runtimeApi.GetIP() == "185.97.255.43:27691"
end

local visibleTabs = {
	PLAYERS = true,
	ESPINTERACTIVE = true,
	DRAGMENU = true,
	DRAGKEY = true,
	ATTACHMENTS = true,
	USER_CONFIG = true,
	HOME = true,
	AIM_HITBOX = true
}
local hiddenTabs = {
	USER_CONFIG = true,
	ESPINTERACTIVE = true,
	AIM_HITBOX = true,
	DRAGKEY = true,
	DRAGMENU = true
}

for keyH, itemE in Kefir.pairs(runtimeApi.var) do
	if not hiddenTabs[keyH] and runtimeApi.var[keyH].tab then
		runtimeApi.insert(Kefir.tabs.list, {
			keyH,
			runtimeApi.var[keyH].tab[1],
			runtimeApi.var[keyH].tab[2]
		})
	end
end

if #Kefir.tabs.list > 0 then
	runtimeApi.sorting(Kefir.tabs.list, function(a, b)
		return a[2] < b[2]
	end)

	for keyH, itemE in Kefir.ipairs(Kefir.tabs.list) do
		itemE = {
			itemE[1],
			itemE[3]
		}

		Kefir.tabs.list[keyH] = itemE
	end
end

for keyI, itemF in Kefir.pairs(materialCatalog) do
	if istable(itemF) then
	else
		Kefir.material[keyI] = itemF

		runtimeApi.insert(Kefir.ChamsList, keyI)
	end
end

Kefir.tabs.current = "COMBAT"
Kefir.search_query = ""
Kefir.search_open = false

local screenWidth = Kefir.width()
local screenHeight = Kefir.height()

local function getSetting(category, settingName, settingIndex, subIndex)
	if not Kefir:AllowedFeature(settingName) then
		return {
			[6] = {},
			[7] = {}
		}
	end

	local categorySettings = runtimeApi.var[category]

	if not categorySettings then
		return false
	end

	if settingName == "toggle" then
		local toggleSetting = categorySettings.toggle

		if not toggleSetting then
			return false
		end

		return subIndex and toggleSetting[subIndex] or toggleSetting
	end

	local settingGroup = categorySettings[settingIndex]

	if not settingGroup then
		return false
	end

	return settingGroup[settingName]
end

function Kefir.UnitToMeters(selfRefC, units)
	return units * 0.01905
end

function Kefir.ConMsg(selfRefD, ...)
	if miscEnabled and getSetting("MISC", "noconmsg", 1)[1] then
		return
	end

	local tableDataG = {
		...
	}

	runtimeApi.insert(tableDataG, "\n")
	Kefir.MsgC(runtimeApi.color.white, "[", runtimeApi.color.traitor, "kefir rework", runtimeApi.color.white, "] ", selfRefD.unpack(tableDataG))
end

function Kefir.Request(selfRefE, actionName, payload, callback)
	payload = payload or {}

	if not isstring(actionName) then
		return
	end

	local tableDataH = {}

	if istable(payload) and not runtimeApi.tIsEmpty(payload) then
		for keyJ, itemG in Kefir.pairs(payload) do
			tableDataH[keyJ] = itemG
		end
	end

	tableDataH.doing = actionName
	tableDataH.ip = runtimeApi.GetIP()
	tableDataH.map = runtimeApi.GetMap()
	tableDataH.steamid = "UNKNOWN"
	tableDataH.hostname = runtimeApi.GetHostName()

	if IsValid(localPlayer) and localPlayer.SteamID then
		tableDataH.steamid = localPlayer:SteamID()
	end

	nativeApi.service_request(runtimeApi.parse_table(tableDataH), function(tableValue, paramK)
		if not paramK then
			Kefir:ConMsg(color_white, "Error! - " .. actionName)

			if actionName == "bit1" and not istable(tableValue) then
				requestFailureCount = requestFailureCount + 1

				Kefir.EmitSound("phx/epicmetal_hard.wav", localPlayer:GetPos(), 100, 100, 1, CHAN_AUTO)

				if requestFailureCount >= 10 then
					runtimeApi.tSimple(1, function()
						nativeApi.service_unload()
					end)
				end
			end

			return
		end

		if paramK and tableValue then
			if requestFailureCount > 0 then
				Kefir:Log(Kefir:GetLangText("Connection with servers restored!"))
			end

			requestFailureCount = 0

			local valueAM = runtimeApi.parse_json(tableValue)

			if isfunction(callback) then
				callback(valueAM, paramK)
			end
		end
	end)
end

function Kefir.Log(selfRefF, paramL, paramM, paramN, unusedParamB)
	if not paramL then
		return
	end

	if miscEnabled and getSetting("MISC", "nolog", 1)[1] then
		return
	end

	local valueAN = paramM or color_white
	local valueAO = paramN or 0
	local getSettingResult = getSetting("MISC", "logtime", 1)[1]

	runtimeApi.sSetFont(Kefir:GetName() .. "visuals.16")

	local valueAP, valueAQ = runtimeApi.sGetTextSize(paramL)
	local tableDataI = {
		paramL,
		valueAN,
		nil,
		getSettingResult + valueAO,
		255,
		-333,
		valueAP,
		valueAQ,
		unusedParamB
	}

	runtimeApi.insert(selfRefF.logs, tableDataI)
end

function Kefir.GetLangText(selfRefG, paramO)
	local valueAR = selfRefG.variables.USER_CONFIG.LANGUAGE or "EN"

	if valueAR == "EN" then
		return paramO
	end

	return (valueAR == "EN" or not selfRefG.translations[valueAR][paramO]) and paramO or selfRefG.translations[valueAR][paramO]
end

local unknownText = Kefir:GetLangText("unknown")

local function createMenuFonts(paramP)
	for indexH = 0, 64 do
		local valueAS = indexH
		local valueAT = paramP == "Montserrat" and valueAS or indexH

		runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.font." .. indexH, {
			shadow = false,
			extended = true,
			additive = false,
			antialias = true,
			font = paramP,
			size = valueAT,
			weight = indexH <= 12 and 20 or 444
		})
		runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.ofont." .. indexH, {
			antialias = true,
			extended = true,
			additive = false,
			outline = true,
			font = paramP,
			size = valueAT,
			weight = indexH <= 12 and 20 or 250
		})
		runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.glow." .. indexH, {
			blursize = 2.5,
			antialias = true,
			font = paramP,
			size = valueAT,
			weight = indexH <= 12 and 20 or 444
		})
		runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.blur." .. indexH, {
			blursize = 8,
			antialias = true,
			font = paramP,
			size = valueAT,
			weight = indexH <= 12 and 20 or 444
		})

		if indexH <= 32 then
			runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.flag." .. indexH, {
				shadow = true,
				font = "Tahoma",
				weight = 1,
				outline = false,
				antialias = false,
				size = indexH
			})
		end
	end
end

function Kefir.SetLanguage(selfRefH, paramQ)
	if selfRefH.translations[paramQ] then
		selfRefH.variables.USER_CONFIG.LANGUAGE = paramQ

		selfRefH:Log(selfRefH:GetLangText("Language changed to: ") .. paramQ)
		createMenuFonts("Tahoma")

		if IsValid(Kefir.menu) then
			Kefir.paint:TABUpdate()
		end
	end
end

function Kefir.GetLanguage(selfRefI)
	return selfRefI.variables.USER_CONFIG.LANGUAGE or "EN"
end

function Kefir.jmp.Create(selfRefJ, paramR, paramS, paramT)
	if selfRefJ.hooked[paramR .. paramS] then
		return
	end

	local valueAU = hook.GetTable()[paramR]
	local valueAV = valueAU and valueAU[paramS]

	if not valueAV then
		return
	end

	local valueAW = #selfRefJ.list + 1

	selfRefJ.list[valueAW] = {
		paramR,
		paramS,
		valueAV,
		paramT,
		false
	}
end

function Kefir.jmp.Init(selfRefK)
	for keyK, itemH in Kefir.pairs(selfRefK.list) do
		local valueAX = itemH[1]
		local valueAY = itemH[2]
		local valueAZ = itemH[3]
		local valueBA = itemH[4]

		if selfRefK.hooked[valueAX .. valueAY] then
			itemH[5] = true
		end

		if not itemH[5] then
			hook.Add(valueAX, valueAY, function(...)
				if valueBA() then
					return
				end

				return valueAZ(...)
			end)

			itemH[5] = true
		end

		if itemH[5] then
			selfRefK.list[keyK] = nil
		end
	end
end

function Kefir.iterator.Timer(selfRefL, numberValueE, paramU, ...)
	local owner = selfRefL.__owner
	local tableDataJ = {}

	if ... then
		tableDataJ = {
			...
		}
	end

	Kefir.assert(isnumber(numberValueE), "first argument in TimeIterator not is number!")
	Kefir.assert(isfunction(paramU), "second argument in TimeIterator not is function!")

	local tableDataK = {
		numberValueE,
		paramU,
		tableDataJ
	}

	tableDataK[4] = 0

	runtimeApi.insert(owner.timers, tableDataK)
end

Kefir.errorTime = nil
Kefir.errorMsg = ""

function Kefir.sendPacket(selfRefM, paramV, paramW, ...)
	local valueBB = Kefir.errorTime or 0

	if runtimeApi.stime() - valueBB < 0 then
		selfRefM:ConMsg(runtimeApi.color.is_screengrabing, "Packet Failed: " .. Kefir.errorMsg)

		return
	else
		Kefir.errorTime = nil
		Kefir.errorMsg = ""
	end

	if runtimeApi.receiveStringToID(paramV) == 0 then
		Kefir.errorTime = runtimeApi.stime() + 1
		Kefir.errorMsg = "receiver empty"

		return Kefir.errorMsg
	end

	runtimeApi["qX7mP2"](paramV)

	if paramW and isfunction(paramW) then
		paramW(...)
	end

	runtimeApi["vK4rT9"]()
end

function Kefir.to_justidx(selfRefN, paramX)
	local tableDataL = {}

	for keyL, itemI in Kefir.pairs(paramX) do
		tableDataL[#tableDataL + 1] = keyL
	end

	return tableDataL
end

function Kefir.trim(selfRefO, paramY, paramZ)
	local valueBC = "..."

	if paramZ >= runtimeApi.sGetTextSize(paramY) then
		return paramY
	end

	for indexI = #paramY, 1, -1 do
		local valueBD = string.sub(paramY, 1, indexI)

		if paramZ >= runtimeApi.sGetTextSize(valueBD .. valueBC) then
			return valueBD .. valueBC
		end
	end

	return valueBC
end

function Kefir.concat(selfRefP, paramAA, paramAB)
	paramAB = paramAB or ""

	local valueBE = ""

	for indexJ = 1, #paramAA do
		local valueBF = paramAA[indexJ]

		if isstring(valueBF) then
			valueBF = selfRefP:GetLangText(valueBF)
		end

		valueBE = valueBE .. tostring(valueBF)

		if indexJ < #paramAA then
			valueBE = valueBE .. paramAB
		end
	end

	return valueBE
end

function Kefir.reverseFind(selfRefQ, paramAC, paramAD)
	for keyM, itemJ in Kefir.pairs(paramAC) do
		if itemJ == paramAD then
			return keyM
		end
	end

	return nil
end

function Kefir.getCacheBone(selfRefR, entityRef, paramAE)
	if not IsValid(entityRef) then
		return
	end

	local modelName = entityRef:GetModel()

	if not modelName then
		return
	end

	boneCache[entityRef] = boneCache[entityRef] or {}

	local valueBG = boneCache[entityRef]

	if valueBG.model ~= modelName then
		valueBG.model = modelName
		valueBG.bones = {}
	end

	if valueBG.bones[paramAE] ~= nil then
		return valueBG.bones[paramAE]
	end

	local lookupBoneResult = entityRef:LookupBone(paramAE)

	valueBG.bones[paramAE] = lookupBoneResult

	return lookupBoneResult
end

function Kefir.getPositionBone(selfRefS, paramAF, paramAG, paramAH)
	local valueBH
	local valueBI

	if paramAH == "Matrix" then
		local getBoneMatrixResult = paramAF:GetBoneMatrix(paramAG)

		if not getBoneMatrixResult then
			return
		end

		valueBH = getBoneMatrixResult:GetTranslation()
		valueBI = getBoneMatrixResult:GetAngles()
	else
		valueBH, valueBI = paramAF:GetBonePosition(paramAG)
	end

	return valueBH, valueBI
end

function Kefir.RestartAttachments(selfRefT)
	if not selfRefT.fakeatt_weapons or runtimeApi.tIsEmpty(selfRefT.fakeatt_weapons) then
		return
	end

	for keyN, itemK in Kefir.pairs(selfRefT.fakeatt_weapons) do
		if not IsValid(keyN) then
			selfRefT.fakeatt_weapons[keyN] = nil
		else
			for keyO, itemL in Kefir.pairs(itemK) do
				selfRefT:RemoveAttachment(keyN, keyO)
			end
		end
	end
end

function Kefir.ExportConfig(selfRefU, paramAI)
	local tableDataM = {}

	for keyP, itemM in Kefir.pairs(paramAI) do
		if not visibleTabs[keyP] then
			tableDataM[keyP] = {}

			if itemM.toggle and type(itemM.toggle) == "table" then
				tableDataM[keyP].toggle = itemM.toggle[1]
			end

			for keyQ, itemN in Kefir.pairs(itemM) do
				if type(keyQ) == "number" then
					tableDataM[keyP][keyQ] = {}

					for keyR, itemO in Kefir.pairs(itemN) do
						if type(itemO) == "table" and itemO[3] ~= "button" and itemO[3] ~= "list" and itemO[3] ~= "space" and itemO[3] ~= "text" then
							if itemO[3] == "checkbox" then
								tableDataM[keyP][keyQ][keyR] = {
									itemO[1],
									itemO[6]
								}
							elseif itemO[3] == "keybind" and isstring(itemO[8]) then
								tableDataM[keyP][keyQ][keyR] = {
									itemO[1],
									itemO[8]
								}
							else
								tableDataM[keyP][keyQ][keyR] = itemO[1]
							end
						end
					end
				end
			end
		end
	end

	if paramAI.ATTACHMENTS and paramAI.ATTACHMENTS[1] then
		tableDataM.ATTACHMENTS = tableDataM.ATTACHMENTS or {}
		tableDataM.ATTACHMENTS[1] = paramAI.ATTACHMENTS[1]
	end

	if paramAI.ESPINTERACTIVE and paramAI.ESPINTERACTIVE.data then
		tableDataM.ESPINTERACTIVE = tableDataM.ESPINTERACTIVE or {}
		tableDataM.ESPINTERACTIVE.data = paramAI.ESPINTERACTIVE.data
	end

	if paramAI.DRAGMENU then
		if IsValid(Kefir.menu) then
			local valueBJ, valueBK = Kefir.menu:GetPos()

			paramAI.DRAGMENU = {
				valueBJ,
				valueBK
			}
		end

		tableDataM.DRAGMENU = tableDataM.DRAGMENU or nil
		tableDataM.DRAGMENU = paramAI.DRAGMENU or nil
	end

	if paramAI.DRAGKEY then
		paramAI.DRAGKEY = Kefir.keybindpos
		tableDataM.DRAGKEY = tableDataM.DRAGKEY or nil
		tableDataM.DRAGKEY = paramAI.DRAGKEY or nil
	end

	if paramAI.DRAGSPECT then
		paramAI.DRAGSPECT = Kefir.spectatorpos
		tableDataM.DRAGSPECT = tableDataM.DRAGSPECT or nil
		tableDataM.DRAGSPECT = paramAI.DRAGSPECT or nil
	end

	local uSERCONFIG = paramAI.USER_CONFIG

	tableDataM.USER_CONFIG = tableDataM.USER_CONFIG or {
		LANGUAGE = "EN",
		SHARE = true
	}

	if uSERCONFIG and istable(uSERCONFIG) and uSERCONFIG ~= nil and uSERCONFIG.SHARE then
		for keyS, itemP in Kefir.pairs(uSERCONFIG) do
			if keyS == "SHARE" then
			else
				tableDataM.USER_CONFIG[keyS] = itemP
			end
		end
	end

	if paramAI.AIM_HITBOX then
		tableDataM.AIM_HITBOX = tableDataM.AIM_HITBOX or {
			"Head1"
		}
		tableDataM.AIM_HITBOX = paramAI.AIM_HITBOX or {
			"Head1"
		}
	end

	return tableDataM
end

local flagA = true

function Kefir.ImportConfig(unusedParamC, paramAJ, paramAK)
	for keyT, itemQ in Kefir.pairs(paramAK) do
		if paramAJ[keyT] and not visibleTabs[keyT] then
			if itemQ.toggle ~= nil and paramAJ[keyT].toggle then
				paramAJ[keyT].toggle[1] = itemQ.toggle
			end

			for keyU, itemR in Kefir.pairs(itemQ) do
				if type(keyU) == "number" and paramAJ[keyT][keyU] then
					for keyV, itemS in Kefir.pairs(itemR) do
						local valueBL = paramAJ[keyT][keyU][keyV]

						if valueBL and type(valueBL) == "table" then
							if type(itemS) == "table" and itemS[1] ~= nil then
								valueBL[1] = itemS[1]

								if itemS[2] ~= nil then
									if istable(itemS[2]) then
										for indexK = 1, #itemS[2] do
											valueBL[6][indexK] = itemS[2][indexK]
										end
									end

									if isstring(itemS[2]) then
										valueBL[8] = itemS[2]
									end
								end
							else
								valueBL[1] = itemS
							end
						end
					end
				end
			end
		end
	end

	if paramAK.ATTACHMENTS and paramAK.ATTACHMENTS[1] then
		paramAJ.ATTACHMENTS[1] = paramAK.ATTACHMENTS[1]
	else
		paramAJ.ATTACHMENTS[1] = {}
	end

	flagA = true
	curWeaponAtts = {
		barrel = {},
		sight = {},
		mount = {},
		grip = {},
		underbarrel = {}
	}

	Kefir:RestartAttachments()

	if paramAK.ESPINTERACTIVE and paramAK.ESPINTERACTIVE.data then
		paramAJ.ESPINTERACTIVE.data = paramAK.ESPINTERACTIVE.data
	end

	if paramAK.DRAGMENU then
		paramAJ.DRAGMENU = paramAK.DRAGMENU

		if IsValid(Kefir.menu) then
			Kefir.menu:SetPos(paramAJ.DRAGMENU[1], paramAJ.DRAGMENU[2])
		end
	end

	if paramAK.DRAGKEY then
		paramAJ.DRAGKEY = paramAK.DRAGKEY
		Kefir.keybindpos = {
			paramAJ.DRAGKEY.x,
			paramAJ.DRAGKEY.y
		}
	end

	if paramAK.DRAGSPECT then
		paramAJ.DRAGSPECT = paramAK.DRAGSPECT
		Kefir.spectatorpos = {
			paramAJ.DRAGSPECT.x,
			paramAJ.DRAGSPECT.y
		}
	end

	local uSERCONFIGA = paramAK.USER_CONFIG

	if uSERCONFIGA and istable(uSERCONFIGA) and uSERCONFIGA ~= nil and uSERCONFIGA.SHARE then
		for keyW, itemT in Kefir.pairs(uSERCONFIGA) do
			paramAJ.USER_CONFIG[keyW] = itemT
		end
	end

	local valueBM = paramAJ.USER_CONFIG.LANGUAGE or "EN"

	Kefir:SetLanguage(valueBM)

	if paramAK.AIM_HITBOX then
		paramAJ.AIM_HITBOX = paramAK.AIM_HITBOX or {
			"Head1"
		}
	end
end

function Kefir.GetConfig(selfRefV)
	local exportConfigResult = selfRefV:ExportConfig(selfRefV.variables)
	local valueBN = runtimeApi.parse_table(exportConfigResult)
	local valueBO = runtimeApi.b64_encode(valueBN)

	for indexL = 1, 4 do
		valueBO = runtimeApi.b64_encode(valueBO)
	end

	return valueBO
end

local function importConfigSafely(configData)
	Kefir.offdangerfn = true

	local importOk, importError = Kefir.pcall(Kefir.ImportConfig, Kefir, Kefir.variables, configData)

	runtimeApi.tSimple(3, function()
		Kefir.offdangerfn = false
	end)

	return importOk, importError
end

function Kefir.LoadConfig(selfRefW, paramAL)
	local valueBP = runtimeApi.b64_decode(paramAL)

	for indexM = 1, 4 do
		valueBP = runtimeApi.b64_decode(valueBP)
	end

	local valueBQ = runtimeApi.parse_json(valueBP)
	local valueBR, valueBS = importConfigSafely(valueBQ)

	if not valueBR and valueBS then
		selfRefW:Log("Something wrong, check console!", runtimeApi.color.groupname)
		selfRefW:ConMsg("Problem with loading config: " .. valueBS)

		return false
	end

	return true
end

nativeApi.config_write("default.cvip", Kefir:GetConfig())

function Kefir.PerfInsert(selfRefX, paramAM, paramAN)
	paramAM[paramAN] = true
end

function Kefir.ClassByName(selfRefY, paramAO)
	for keyX, itemU in Kefir.ipairs(runtimeApi.wpList()) do
		if itemU.PrintName == paramAO then
			return itemU.ClassName
		end
	end
end

function Kefir.RussianSymbols(selfRefZ, paramAP)
	return runtimeApi.find(paramAP, "[\xC0-\xFF]") ~= nil
end

runtimeApi.NameStart = not DEBUG_MODE and Kefir:RandomString(10) or ""

local function shouldHideForScreenshot()
	return getSetting("MISC", "anti_ss", 1)[1] and localCache.isTakingScreenshot()
end

function Kefir.ToDraw(selfRefAA, paramAQ)
	if shouldHideForScreenshot() then
		return false
	end

	if paramAQ then
		if Kefir.cam_manipulated then
			return false
		end

		if miscEnabled and getSetting("MISC", "rendertargetcheck", 1)[1] and runtimeApi.GetRenderTarget() ~= nil and runtimeApi.GetRenderTarget() ~= runtimeApi.GetScreenEffectTexture() then
			return false
		end
	end

	return true
end

function Kefir.AddScreenText(selfRefAB, paramAR, paramAS, paramAT, paramAU, paramAV)
	if paramAS == "ph[footstep]" then
		paramAS = ""
	end

	runtimeApi.insert(Kefir.texts, {
		paramAR,
		0,
		0,
		paramAS,
		runtimeApi.stime(),
		paramAT or 32,
		paramAU or runtimeApi.color.white,
		paramAV or "ofont"
	})
end

function Kefir.bBasicCondition(selfRefAC, entityRefA, paramAW, targetRefA)
	local meMovingResult = selfRefAC:meMoving()
	local valueBT = entityRefA.walkinglerp or 0

	paramAW = paramAW or {}

	if paramAW.Moving and meMovingResult then
		return true
	end

	if paramAW["In Air"] and not localPlayer:OnGround() and not selfRefAC:InFake(localPlayer) then
		return true
	end

	if paramAW.Standing and not meMovingResult then
		return true
	end

	if paramAW.Crouching and localPlayer:Crouching() then
		return true
	end

	if paramAW["Hard Moving"] and IsValid(entityRefA) and valueBT > 88 then
		return true
	end

	if paramAW["On Doubletap"] and combatEnabled and getSetting("COMBAT", "doubletap", 2)[1] and nativeApi.tickbase_getCharge() >= selfRefAC.DTInfo[2] then
		return true
	end

	if paramAW["Far Distance"] and IsValid(targetRefA) and IsValid(localPlayer) then
		local distA = getSetting("COMBAT", "force_baim_distance", 1)[1] or 1500

		if targetRefA:GetPos():DistToSqr(EyePos()) > distA * distA then
			return true
		end
	end

	return false
end

function Kefir.GetMaterialChams(selfRefAD, paramAX, paramAY, paramAZ, paramBA)
	paramBA = paramBA or false

	local getSettingResultA = getSetting(paramAX, paramAY .. "_type", paramAZ)[1]

	if paramBA then
		return materialCatalog.Additive[getSettingResultA]
	end

	return runtimeApi.material[getSettingResultA]
end

function Kefir.RemoveAttachment(selfRefAE, entityRefB, tableValueA)
	if not IsValid(entityRefB) or not entityRefB.attachments or tableValueA == "" then
		return
	end

	if tableValueA and istable(tableValueA) then
		for keyY, itemV in Kefir.pairs(tableValueA) do
			selfRefAE:RemoveAttachment(entityRefB, itemV)
		end

		return
	end

	local valueBU

	for keyZ, itemW in Kefir.pairs(hg.attachments) do
		valueBU = itemW[tableValueA] and itemW[tableValueA][1] or valueBU
	end

	if not valueBU then
		return
	end

	if entityRefB:HasAttachment(valueBU, tableValueA) then
		entityRefB.attachments[valueBU] = {}

		if IsValid(entityRefB.modelAtt.mountex) then
			entityRefB.modelAtt.mountex:Remove()

			entityRefB.modelAtt.mountex = nil
		end
	end
end

function Kefir.AddAttachment(selfRefAF, entityRefC, tableValueB)
	if not IsValid(entityRefC) or not entityRefC.attachments or tableValueB == "" then
		return
	end

	if tableValueB and istable(tableValueB) then
		for keyAA, itemX in Kefir.pairs(tableValueB) do
			selfRefAF:AddAttachment(entityRefC, itemX)
		end

		return
	end

	local valueBV

	for keyAB, itemY in Kefir.pairs(hg.attachments) do
		valueBV = itemY[tableValueB] and itemY[tableValueB][1] or valueBV
	end

	if entityRefC:HasAttachment(valueBV, tableValueB) then
		return
	end

	entityRefC.attachments[valueBV] = entityRefC.attachments[valueBV] or {}

	if not entityRefC.attachments[valueBV].noblock then
		local restrictattA = hg.attachments[valueBV][tableValueB].restrictatt

		for keyAC, itemZ in Kefir.pairs(entityRefC.attachments) do
			(function()
				if not itemZ or not istable(itemZ) or runtimeApi.tIsEmpty(itemZ) or itemZ[1] == "empty" then
					return
				end
			end)()
		end
	end

	if not valueBV then
		return
	end

	local valueBW

	if entityRefC.availableAttachments[valueBV] then
		for keyAD, itemAA in Kefir.pairs(entityRefC.availableAttachments[valueBV]) do
			valueBW = istable(itemAA) and itemAA[1] == tableValueB and keyAD or valueBW
		end
	end

	local mountTypeA = entityRefC.availableAttachments[valueBV] and entityRefC.availableAttachments[valueBV].mountType
	local mountTypeB = hg.attachments[valueBV][tableValueB] and hg.attachments[valueBV][tableValueB].mountType

	if not entityRefC.availableAttachments[valueBV] then
		return
	end

	if not entityRefC.availableAttachments[valueBV][valueBW] and not mountTypeA and not mountTypeB then
		return
	end

	if not (istable(mountTypeA) and runtimeApi.HasValue(mountTypeA, hg.attachments[valueBV][tableValueB].mountType) or mountTypeA == mountTypeB) then
		return
	end

	entityRefC.attachments[valueBV] = valueBW and entityRefC.availableAttachments[valueBV][valueBW] or {
		tableValueB,
		{}
	}
end

function Kefir.PosBySize(selfRefAG, paramBB, paramBC, paramBD, paramBE, paramBF)
	local valueBX = paramBF and paramBF or 2

	return {
		(paramBB - paramBD) / valueBX,
		(paramBC - paramBE) / valueBX
	}
end

function Kefir.GetName(selfRefAH)
	return runtimeApi.NameStart .. "kefir."
end

function Kefir.Lerp(selfRefAI, paramBG, paramBH, paramBI)
	return runtimeApi.Lerp(paramBG, paramBH, paramBI)
end

function Kefir.LerpColor(selfRefAJ, paramBJ, colorRef, colorRefA)
	return Color(Kefir:Lerp(paramBJ, colorRef.r, colorRefA.r), Kefir:Lerp(paramBJ, colorRef.g, colorRefA.g), Kefir:Lerp(paramBJ, colorRef.b, colorRefA.b), colorRef.a and colorRefA.a and Kefir:Lerp(paramBJ, colorRef.a, colorRefA.a) or 255)
end

function Kefir.InFake(selfRefAK, entityRefD)
	return IsValid(entityRefD) and entityRefD ~= nil and entityRefD:IsPlayer() and (IsValid(entityRefD.FakeRagdoll) or entityRefD.InFake and entityRefD:InFake())
end

function Kefir.IsSpecialFWeapon(selfRefAL, weaponRef)
	return Kefir.special_server.zcity and (weaponRef.Base == "homigrad_base" or weaponRef.ishgwep or Kefir.zcity_weapons[1][weaponRef:GetClass()]) or Kefir.special_server.hgcom and weaponRef.SetMagazineItem or false
end

function Kefir.IsSpecialMWeapon(selfRefAM, paramBK)
	return Kefir.special_server.zcity and paramBK.Base == "weapon_melee" or Kefir.special_server.hgcom and paramBK.DoInputAttackClient or false
end

function Kefir.IsHGObject(selfRefAN, entityRefE)
	if not IsValid(entityRefE) then
		return false
	end

	if entityRefE:IsWeapon() and Kefir:IsSpecialFWeapon(entityRefE) then
		return true
	end

	return false
end

function Kefir.IsMeleeObject(selfRefAO, entityRefF)
	if not IsValid(entityRefF) then
		return false
	end

	if entityRefF:IsWeapon() and Kefir:IsSpecialMWeapon(entityRefF) then
		return true
	end

	return false
end

function Kefir.CreateHook(selfRefAP, textValue, paramBL, paramBM)
	selfRefAP.assert(isstring(textValue), "first argument in CreateHook not is string!")
	selfRefAP.assert(isfunction(paramBL), "second argument in CreateHook not is function!")

	if not selfRefAP.hooks[textValue] then
		selfRefAP.hooks[textValue] = {}
	end

	local randomStringResult = not DEBUG_MODE and selfRefAP:RandomString(16) or paramBM and paramBM .. "_fvs" .. runtimeApi.NameStart or "devhook_" .. tostring(hookSequence)

	if not DEBUG_MODE then
		repeat
			randomStringResult = selfRefAP:RandomString(16)
		until not istable(selfRefAP.hooks[textValue][randomStringResult])
	else
		hookSequence = hookSequence + 1
	end

	local valueBY = "\xFF" .. randomStringResult
	local randomStringResultA = selfRefAP:RandomString(6)
	local valueBZ, valueCA = Kefir.pcall(function()
		hook.GetTable()[randomStringResultA] = {}
		hook.GetTable()[randomStringResultA].T = function()
			return
		end
	end)

	if valueBZ and valueCA ~= nil then
		hook.GetTable()[textValue] = hook.GetTable()[textValue] or {}
		hook.GetTable()[textValue][valueBY] = paramBL
	else
		hook.Add(textValue, valueBY, paramBL)
	end

	hook.GetTable()[randomStringResultA] = nil

	runtimeApi.insert(selfRefAP.hooks[textValue], valueBY)
end

function Kefir.CreateFile(paramBN, textValueA, paramBO, textValueB, paramBP)
	paramBN.assert(isstring(textValueA), "first argument in CreateFile not is name!")
	paramBN.assert(isstring(textValueB), "second argument in CreateFile not is body!")

	if runtimeApi.fExists(textValueA) then
		repeat
			textValueA = paramBN:RandomString(6)
		until runtimeApi.fExists(textValueA, "DATA")
	end

	if paramBP then
		local valueCB = runtimeApi.fOpen("cfg/mapcycle.txt", "wb")
	end

	runtimeApi.insert(paramBN.files, textValueA .. "." .. paramBO)
end

function Kefir.AddRender(selfRefAQ, paramBQ, numberValueF)
	selfRefAQ.assert(isfunction(paramBQ), "first argument in AddRender not is function!")
	selfRefAQ.assert(isnumber(numberValueF), "second argument in AddRender not is number!")
	runtimeApi.insert(numberValueF == 1 and selfRefAQ.render2d or selfRefAQ.render3d, paramBQ)
end

function Kefir.PlayerByID(unusedParamD, paramBR)
	for keyAE, itemAB in localCache.iteratePlayers() do
		if not IsValid(itemAB) then
			return
		end

		if itemAB:UserID() == paramBR then
			return itemAB
		end
	end

	return nil
end

function Kefir.CreateCommand(paramBS, textValueC, paramBT)
	paramBS.assert(isstring(textValueC), "first argument in CreateCmd not is string!")
	paramBS.assert(isfunction(paramBT), "second argument in CreateCmd not is function!")
	runtimeApi.cAdd(textValueC, paramBT)
	runtimeApi.insert(paramBS.cmds, textValueC)
end

function Kefir.ClearHook(selfRefAR)
	local hooksA = selfRefAR.hooks

	for keyAF, itemAC in Kefir.pairs(hooksA) do
		local textBuffer = hooksA[keyAF]

		for indexN = #textBuffer, 1, -1 do
			local valueCC = textBuffer[indexN]

			runtimeApi.hRemove(keyAF, valueCC)

			if hook.GetTable()[keyAF] then
				hook.GetTable()[keyAF][valueCC] = nil
			end
		end
	end
end

function Kefir.ClearCommand(selfRefAS)
	local cmdsA = selfRefAS.cmds

	for indexO = #cmdsA, 1, -1 do
		local valueCD = cmdsA[indexO]

		runtimeApi.cGetTable()[valueCD] = function()
			MsgC(runtimeApi.color.white, "Unknown command: " .. valueCD .. "\n")
		end
	end
end

function Kefir.ClearFiles(selfRefAT)
	local filesA = selfRefAT.files

	for indexP = #filesA, 1, -1 do
		local valueCE = filesA[indexP]

		runtimeApi.fDelete(valueCE)
	end
end

local tableDataN = {
	weapon_revolver2 = true,
	weapon_akm = true,
	weapon_m4super = true,
	weapon_glock17 = true,
	weapon_doublebarrel_short = true,
	homigrad_base = true,
	weapon_ar15 = true
}

Kefir.DTInfo = {
	0,
	0
}

function Kefir.AutoDT(selfRefAU)
	local tickIntervalA = localCache.tickInterval
	local valueCF = runtimeApi.math.Round(1 / tickIntervalA)
	local numberValueG = 0.22
	local valueCG = runtimeApi.floor(numberValueG / tickIntervalA)
	local valueCH = valueCG - 1

	local valueCI = runtimeApi.clamp(valueCG, 6, 14)
	local valueCJ = runtimeApi.clamp(valueCH, 5, 13)

	selfRefAU.DTInfo[1] = valueCI
	selfRefAU.DTInfo[2] = valueCJ

	nativeApi.tickbase_setMax(valueCI)
	nativeApi.tickbase_setMin(valueCJ)
end

function Kefir._Initialize(selfRefAV)
	if selfRefAV.inited then
		return
	end


	if istable(classFastManager) and istable(oop) and istable(oop.listClass) then
		Kefir.special_server.hgcom = true
	end

	if istable(hg) and istable(hg.armor) then
		Kefir.special_server.zcity = true
		selfRefAV.original_armors = {}

		runtimeApi.CopyFromTo(hg.armor, selfRefAV.original_armors)
	end

	if selfRefAV:we_hvh_server() then
		selfRefAV:sendPacket("paste_reveal", function()
			runtimeApi["aN8cL5"]("cypla0vagine4ok3")
		end)
	end

	selfRefAV:CreateHook(Kefir.special_server.zcity and "HG_PlayerFootstep_Notify" or "PlayerFootstep", function(paramBU, paramBV)
		if fallbackMode then
			return
		end

		if not visualsEnabled then
			return
		end

		if not getSetting("VISUALS", "footstep", 3)[1] then
			return
		end

		if not IsValid(paramBU) or not Kefir.isvector(paramBV) then
			return
		end

		if paramBU:GetNWBool("Fake", false) then
			return
		end

		if isfunction(ParticleEffect) then
			ParticleEffect("blood_impact_red_01", paramBV, Angle(0, 0, 0), nil)
		end

		Kefir:AddScreenText(paramBV, "ph[footstep]", getSetting("VISUALS", "footstep_size", 3)[1] or 16, getSetting("VISUALS", "footstep", 3)[6][1], "oicons")
	end, "footstep")

	if Kefir.special_server.zcity then
		selfRefAV.jmp:Create("Post Post Pre Post Processing", "organism-effects", function()
			return visualsEnabled and getSetting("VISUALS", "no_organism_effects", 3)[1]
		end)
		selfRefAV.jmp:Create("Post Post Pre Post Processing", "ShowScreens", function()
			return visualsEnabled and getSetting("VISUALS", "no_organism_effects", 3)[1]
		end)
		selfRefAV.jmp:Create("Post Post Processing", "ItHurts", function()
			return visualsEnabled and getSetting("VISUALS", "no_organism_effects", 3)[1]
		end)
		selfRefAV.jmp:Create("RenderScreenspaceEffects", "homigrad", function()
			return visualsEnabled and getSetting("VISUALS", "no_zcity_processing", 3)[1]
		end)
		runtimeApi.tSimple(0.1, function()
			selfRefAV.jmp:Init()
		end)
	end

	selfRefAV.branch = nativeApi.service_getbranch()
	selfRefAV.saveinit.max_side = selfRefAV.getconvar("cl_sidespeed"):GetInt()
	selfRefAV.saveinit.max_forward = selfRefAV.getconvar("cl_forwardspeed"):GetInt()

	for keyAG, itemAD in Kefir.ipairs(runtimeApi.wpList()) do
		local base = itemAD.Base
		local className = itemAD.ClassName

		if tableDataN[base] then
			local availableAttachmentsA = itemAD.availableAttachments

			Kefir:PerfInsert(Kefir.zcity_weapons[1], className)

			if availableAttachmentsA ~= nil and not runtimeApi.tIsEmpty(availableAttachmentsA) and istable(availableAttachmentsA) then
				Kefir:PerfInsert(Kefir.zcity_weapons[2], className)
			end
		end
	end

	selfRefAV.inited = true
end

function Kefir.RealAspect(selfRefAW, paramBW, paramBX)
	local getSettingResultB = getSetting("VISUALS", "aspectratio", 2)[1]
	local valueCK = screenWidth
	local valueCL = screenHeight
	local valueCM = valueCK / valueCL
	local numberValueH = 1

	if visualsEnabled and getSettingResultB > 0.1 then
		numberValueH = getSettingResultB / valueCM
	end

	paramBW = paramBW - valueCK * 0.5 + valueCK * 0.5
	paramBX = (paramBX - valueCL * 0.5) * numberValueH + valueCL * 0.5

	return paramBW, paramBX
end

local valueCN = new_view or {}
local flagB = false

function Kefir.GetBox(selfRefAX, paramBY)
	local vectorValue = localCache.getObbMins(paramBY)
	local vectorValueA = localCache.getObbMaxs(paramBY)
	local flagC = true
	local xF = vectorValue.x
	local xG = vectorValueA.x
	local yF = vectorValue.y
	local yG = vectorValueA.y
	local zA = vectorValue.z
	local zB = vectorValueA.z
	local tableDataO = {
		VectorCtor(xF, yF, zA),
		VectorCtor(xF, yF, zB),
		VectorCtor(xF, yG, zA),
		VectorCtor(xF, yG, zB),
		VectorCtor(xG, yF, zA),
		VectorCtor(xG, yF, zB),
		VectorCtor(xG, yG, zA),
		VectorCtor(xG, yG, zB)
	}
	local valueCO = screenWidth
	local valueCP = screenHeight
	local hugeA = math.huge
	local hugeB = math.huge
	local hugeC = -math.huge
	local hugeD = -math.huge
	local numberValueI = 0

	if flagB then
		localCache.beginCameraMode("3D", valueCN.origin, valueCN.angles)
	end

	local valueCQ = #tableDataO

	for indexQ = valueCQ, 1, -1 do
		local valueCR = tableDataO[indexQ]
		local localToWorldResult = paramBY:LocalToWorld(valueCR):ToScreen()

		if localToWorldResult.visible then
			localToWorldResult.x = localToWorldResult.x - valueCO * 0.5 + valueCO * 0.5
			localToWorldResult.y = localToWorldResult.y - valueCP * 0.5 + valueCP * 0.5

			local xH = localToWorldResult.x
			local yH = localToWorldResult.y

			hugeA = localCache.mathMin(hugeA, xH)
			hugeB = localCache.mathMin(hugeB, yH)
			hugeC = localCache.mathMax(hugeC, xH)
			hugeD = localCache.mathMax(hugeD, yH)
		else
			numberValueI = numberValueI + 1
		end
	end

	if flagB then
		localCache.endCameraMode("3D")
	end

	if numberValueI == valueCQ then
		flagC = false
	end

	return hugeA, hugeB, hugeC, hugeD, flagC
end

for indexR = 0, 64 do
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.font." .. indexR, {
		shadow = false,
		font = "Tahoma",
		extended = true,
		additive = false,
		antialias = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 444
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.ofont." .. indexR, {
		antialias = true,
		font = "Tahoma",
		extended = true,
		additive = false,
		outline = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 250
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.chat." .. indexR, {
		antialias = true,
		font = "Tahoma",
		extended = true,
		additive = false,
		outline = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 250
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.chat2." .. indexR, {
		antialias = true,
		font = "Verdana",
		extended = true,
		additive = false,
		outline = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 250
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.visuals." .. indexR, {
		antialias = true,
		font = "Verdana",
		extended = true,
		additive = false,
		outline = false,
		weight = 20,
		size = indexR
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.alias_visuals." .. indexR, {
		antialias = false,
		font = "Verdana",
		extended = true,
		additive = true,
		outline = false,
		weight = 20,
		size = indexR
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.glow." .. indexR, {
		font = "Tahoma",
		blursize = 2.5,
		antialias = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 444
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.blur." .. indexR, {
		font = "Tahoma",
		blursize = 8,
		antialias = true,
		size = indexR,
		weight = indexR <= 12 and 20 or 444
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.icons." .. indexR, {
		antialias = true,
		font = "FontAwesome",
		extended = true,
		weight = 500,
		size = indexR
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.cstrike." .. indexR, {
		antialias = true,
		font = "Counter-Strike",
		extended = true,
		weight = 500,
		size = indexR
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.ocstrike." .. indexR, {
		antialias = true,
		font = "Counter-Strike",
		extended = true,
		outline = true,
		weight = 500,
		size = indexR
	})
	runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.oicons." .. indexR, {
		antialias = true,
		font = "FontAwesome",
		extended = true,
		outline = true,
		weight = 500,
		size = indexR
	})

	if indexR <= 32 then
		runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.flag." .. indexR, {
			shadow = true,
			font = "Tahoma",
			weight = 200,
			outline = false,
			antialias = false,
			size = indexR
		})
	end
end

runtimeApi.sCreateFont(runtimeApi.NameStart .. "kefir.icons.blur.32", {
	weight = 500,
	font = "FontAwesome",
	extended = true,
	blursize = 2.15,
	size = 32,
	antialias = true
})

local mergeFn = table.Merge

function Kefir.paint.RegisterTable(selfRefAY, paramBZ, paramCA)
	PANEL = nil
	paramBZ.Base = paramCA or "Panel"
	paramBZ.Init = paramBZ.Init or function()
		return
	end

	return paramBZ
end

function Kefir.paint.CreateObjectFromTable(selfRefAZ, tableValueC, paramCB, paramCC)
	if not istable(tableValueC) then
		return nil
	end

	local valueCS = runtimeApi.vCreate(tableValueC.Base, paramCB, paramCC)

	mergeFn(valueCS:GetTable(), tableValueC)

	valueCS.BaseClass = runtimeApi.vGetControlTable(tableValueC.Base)

	if valueCS.Init then
		valueCS:Init()
	end

	valueCS:Prepare()

	return valueCS
end

function Kefir.paint.Register(selfRefBA, paramCD, paramCE, paramCF)
	local ownerA = selfRefBA.__owner

	selfRefBA.library[paramCD] = function(paramCG)
		local registerTableResult = selfRefBA:RegisterTable(paramCF, paramCE)
		local createObjectFromTableResult = selfRefBA:CreateObjectFromTable(registerTableResult, paramCG)

		for keyAH, itemAE in Kefir.pairs(paramCF) do
			createObjectFromTableResult[keyAH] = itemAE
		end

		return createObjectFromTableResult
	end
end

function Kefir.paint.CreateObject(selfRefBB, paramCH, paramCI)
	return isfunction(selfRefBB.library[paramCH]) and selfRefBB.library[paramCH](paramCI) or nil
end

function Kefir.paint.IsHovered(selfRefBC, paramCJ, paramCK, paramCL, paramCM)
	local valueCT, valueCU = localCache.getMousePosition()

	return paramCJ <= valueCT and valueCT <= paramCJ + paramCL and paramCK <= valueCU and valueCU <= paramCK + paramCM
end

function Kefir.paint.IBlur(selfRefBD, paramCN, paramCO, paramCP, paramCQ)
	paramCN = paramCN or 2.5
	paramCO = paramCO or 3

	local valueCV = screenWidth
	local valueCW = screenHeight
	local blurA = Kefir.material.blur

	localCache.setDrawColor(color_white)
	localCache.setSurfaceMaterial(blurA)

	for indexS = 1, paramCO do
		blurA:SetFloat("$blur", indexS / paramCO * paramCN)
		blurA:Recompute()
		localCache.updateScreenEffectTexture()
		localCache.drawTexturedRect(-paramCP, -paramCQ, valueCV, valueCW)
	end
end

function Kefir.paint.SBlur(selfRefBE, paramCR, paramCS, paramCT, paramCU, paramCV, paramCW, paramCX)
	paramCV = paramCV or 2.5
	paramCW = paramCW or 3
	paramCX = paramCX or 0

	localCache.setScissorRect(paramCR - paramCX, paramCS, paramCR + paramCT + paramCX, paramCS + paramCU, true)
	selfRefBE:IBlur(paramCV, paramCW, 0, 0)
	localCache.setScissorRect(0, 0, 0, 0, false)
end

function Kefir.paint.VBlur(paramCY, paramCZ, paramDA, paramDB)
	paramDA = paramDA or 2.5
	paramDB = paramDB or 3

	local valueCX, valueCY = paramCZ:LocalToScreen(0, 0)
	local valueCZ, valueDA = paramCZ:GetSize()

	paramCY:IBlur(paramDA, paramDB, valueCX, valueCY)
end

function Kefir.paint.Bloom(unusedParamE, paramDC, paramDD, paramDE, paramDF, colorRefB, paramDG, paramDH, paramDI)
	paramDG = paramDG or 6
	paramDH = paramDH or 10
	paramDI = paramDI or 55

	for indexT = paramDG, 1, -1 do
		local valueDB = indexT / paramDG
		local valueDC = paramDH * valueDB

		localCache.setDrawColor(colorRefB.r, colorRefB.g, colorRefB.b, runtimeApi.floor(paramDI * (1 - valueDB)))
		localCache.drawRect(paramDC - valueDC, paramDD - valueDC, paramDE + valueDC * 2, paramDF + valueDC * 2)
	end
end

function Kefir.paint.Text(selfRefBF, paramDJ, paramDK, paramDL, paramDM, paramDN, paramDO, paramDP)
	local ownerB = selfRefBF.__owner

	return runtimeApi.draw_text(paramDJ, ownerB:GetName() .. (paramDP or "font") .. "." .. paramDK, paramDL, paramDM, paramDN and paramDN or ownerB.color.white, paramDO)
end

function Kefir.paint.EOText(selfRefBG, paramDQ, paramDR, paramDS, paramDT, paramDU, paramDV, paramDW, paramDX, paramDY, paramDZ)
	local getNameResult = selfRefBG.__owner:GetName()
	local valueDD = paramDY
	local valueDE = paramDY and valueDD or "font"

	paramDR = runtimeApi.clamp(paramDR, 1, 64)

	local valueDF = getNameResult .. valueDE .. "." .. paramDR

	paramDZ = paramDZ or 255

	local valueDG, valueDH = runtimeApi.draw_otext(paramDQ, valueDF, paramDS, paramDT, paramDU and paramDU or runtimeApi.color.white, paramDV, paramDW, paramDX or 1, selfRefBG:HColorAlpha(runtimeApi.color.black, paramDZ))

	return valueDG, valueDH
end

local borFn = bit.bor
local lshiftFn = bit.lshift
local floorFn = math.floor

Kefir.paint.cache_alpha = {}

function Kefir.paint.HColorAlpha(selfRefBH, colorRefC, paramEA)
	local rA = colorRefC.r
	local gA = colorRefC.g
	local bA = colorRefC.b

	local alphaA = paramEA or 255

	if alphaA ~= alphaA or alphaA < 0 then
		alphaA = 0
	elseif alphaA > 255 then
		alphaA = 255
	end

	alphaA = floorFn(alphaA)

	local var0111Result = borFn(lshiftFn(rA, 24), lshiftFn(gA, 16), lshiftFn(bA, 8), alphaA)
	local valueDI = selfRefBH.cache_alpha[var0111Result]

	if valueDI then
		return valueDI
	else
		local colorValue = Color(rA, gA, bA, alphaA)

		selfRefBH.cache_alpha[var0111Result] = colorValue

		return colorValue
	end
end

function Kefir.paint.Shadow(paramEB, paramEC, paramED, paramEE, paramEF, paramEG, paramEH)
	for indexU = 1, paramEG do
		runtimeApi.draw_rdbox(0, paramEC - indexU, paramED - indexU, paramEE + indexU * 2, paramEF + indexU * 2, paramEB:HColorAlpha(color_black, paramEH / indexU))
	end
end

function Kefir.paint.HColorContrast(unusedParamF, colorRefD, paramEI)
	local valueDJ = paramEI or 1.2
	local valueDK, valueDL, valueDM = ColorToHSV(colorRefD)
	local valueDN = runtimeApi.clamp(valueDL * valueDJ, 0, 1)

	if valueDM < 0.5 then
		valueDM = runtimeApi.clamp(valueDM * (valueDJ * 1.1), 0, 1)
	else
		valueDM = runtimeApi.clamp(valueDM * (1 / (valueDJ * 0.9)), 0, 1)
	end

	local hSVToColorResult = HSVToColor(valueDK, valueDN, valueDM)

	return Color(hSVToColorResult.r, hSVToColorResult.g, hSVToColorResult.b, colorRefD.a)
end

function Kefir.paint.Circle(selfRefBI, paramEJ, paramEK, paramEL, paramEM, paramEN)
	local tableDataP = {}

	for indexV = 0, paramEM do
		local valueDO = runtimeApi.rad(indexV / paramEM * -360)

		tableDataP[#tableDataP + 1] = {
			x = paramEJ + runtimeApi.sin(valueDO) * paramEL,
			y = paramEK + runtimeApi.cos(valueDO) * paramEL
		}
	end

	runtimeApi.drawNoTexture()
	localCache.setDrawColor(paramEN or runtimeApi.color.white)
	localCache.drawPoly(tableDataP)
end

function Kefir.paint.vCircle(selfRefBJ, paramEO, paramEP, paramEQ, paramER)
	localCache.setDrawColor(paramER or runtimeApi.color.white)
	localCache.drawCircle(paramEO, paramEP, paramEQ, paramER or runtimeApi.color.white)
end

function Kefir.paint.GlowText(selfRefBK, paramES, paramET, paramEU, paramEV, paramEW, paramEX, paramEY)
	paramEY = paramEY or "ofont"

	selfRefBK:Text(paramES, paramET, paramEU, paramEV, paramEW, paramEX, paramEY)
	selfRefBK:Text(paramES, paramET, paramEU, paramEV, paramEW, paramEX, "glow")
end

function Kefir.paint.Box(selfRefBL, paramEZ, paramFA, paramFB, paramFC, paramFD, paramFE, paramFF, paramFG, paramFH)
	if not paramFH then
		paramFG = paramFG or 1

		if paramFD then
			runtimeApi.draw_rdbox(0, paramEZ - paramFG, paramFA - paramFG, paramFB + paramFG * 2, paramFC + paramFG * 2, paramFF)
		end

		runtimeApi.draw_rdbox(0, paramEZ, paramFA, paramFB, paramFC, paramFE)
	else
		paramFG = paramFG or 1

		if paramFD then
			runtimeApi.draw_rdbox(0, paramEZ, paramFA, paramFB, paramFC, paramFF)
		end

		runtimeApi.draw_rdbox(0, paramEZ - -paramFG, paramFA - -paramFG, paramFB + -paramFG * 2, paramFC + -paramFG * 2, paramFE)
	end
end

function Kefir.paint.getCenter(selfRefBM, paramFI, paramFJ, paramFK, paramFL)
	local valueDP = paramFK * 0.5
	local valueDQ = paramFL * 0.5

	return paramFI - valueDP, paramFJ - valueDQ
end

function Kefir.paint.rectBox(selfRefBN, paramFM, paramFN, paramFO, paramFP, paramFQ, paramFR)
	paramFQ = paramFQ or color_white
	paramFM = paramFM or 0
	paramFN = paramFN or 0
	paramFO = paramFO or 0
	paramFP = paramFP or 0

	if paramFR then
		paramFO, paramFP = selfRefBN:getCenter(paramFO, paramFP, paramFM, paramFN)
	end

	localCache.setDrawColor(paramFQ)
	localCache.drawRect(paramFO, paramFP, paramFM, paramFN)
end

function Kefir.paint.Line(selfRefBO, paramFS, paramFT, paramFU, paramFV, paramFW)
	localCache.setDrawColor(paramFW)
	localCache.drawSurfaceLine(paramFS, paramFT, paramFU, paramFV)
end

function Kefir.paint.LineOutlined(selfRefBP, paramFX, paramFY, paramFZ, paramGA, paramGB, paramGC, paramGD)
	paramGC = paramGC or 0.1
	paramGD = paramGD or runtimeApi.color.kefir_black

	localCache.setDrawColor(paramGD)
	localCache.drawSurfaceLine(paramFX - paramGC, paramFY, paramFZ - paramGC, paramGA)
	localCache.drawSurfaceLine(paramFX + paramGC, paramFY, paramFZ + paramGC, paramGA)
	localCache.drawSurfaceLine(paramFX, paramFY - paramGC, paramFZ, paramGA - paramGC)
	localCache.drawSurfaceLine(paramFX, paramFY + paramGC, paramFZ, paramGA + paramGC)
	selfRefBP:Line(paramFX, paramFY, paramFZ, paramGA, paramGB)
end

function Kefir.paint.Gradient(selfRefBQ, paramGE, paramGF, paramGG, paramGH, colorRefE, colorRefF, paramGI, paramGJ, paramGK)
	localCache.setDrawColor(colorRefE.r, colorRefE.g, colorRefE.b, colorRefE.a or 255)
	localCache.drawRect(paramGE, paramGF, paramGG, paramGH)

	local vguiUp = paramGJ and paramGJ or runtimeApi.material.vgui_up

	if paramGI then
		vguiUp = paramGK and paramGK or runtimeApi.material.vgui_bottom
	end

	localCache.setDrawColor(colorRefF.r, colorRefF.g, colorRefF.b, colorRefF.a or 255)
	localCache.setSurfaceMaterial(vguiUp)
	localCache.drawTexturedRect(paramGE, paramGF, paramGG, paramGH)
end

function Kefir.paint.Corner(selfRefBR, paramGL, paramGM, paramGN, paramGO, paramGP, paramGQ, paramGR, paramGS)
	local valueDR
	local valueDS

	for indexW = 0, paramGS do
		local valueDT = runtimeApi.rad(paramGO + (paramGP - paramGO) * (indexW / paramGS))
		local valueDU = paramGL + runtimeApi.cos(valueDT) * paramGN
		local valueDV = paramGM + runtimeApi.sin(valueDT) * paramGN

		if valueDR then
			Kefir.paint:Line(valueDR, valueDS, valueDU, valueDV, paramGQ, paramGR)
		end

		valueDR, valueDS = valueDU, valueDV
	end
end

function Kefir.paint.OutlinedRect(unusedParamG, paramGT, paramGU, paramGV, paramGW, paramGX, paramGY)
	localCache.setDrawColor(paramGX)
	localCache.drawOutlinedRect(paramGT, paramGU, paramGV, paramGW, paramGY)
end

function Kefir.paint.CornerOutline(selfRefBS, paramGZ, paramHA, paramHB, paramHC, paramHD, paramHE, paramHF, paramHG, paramHH)
	if paramHD <= 0 and not paramHH then
		localCache.setDrawColor(paramHE)
		localCache.drawOutlinedRect(paramGZ, paramHA, paramHB, paramHC, paramHF)

		return
	end

	paramHG = paramHG or 4

	if not paramHH then
		selfRefBS:Line(paramGZ + paramHD, paramHA, paramGZ + paramHB - paramHD, paramHA, paramHE, paramHF)
		selfRefBS:Line(paramGZ + paramHD, paramHA + paramHC, paramGZ + paramHB - paramHD, paramHA + paramHC, paramHE, paramHF)
		selfRefBS:Line(paramGZ, paramHA + paramHD, paramGZ, paramHA + paramHC - paramHD, paramHE, paramHF)
		selfRefBS:Line(paramGZ + paramHB, paramHA + paramHD, paramGZ + paramHB, paramHA + paramHC - paramHD, paramHE, paramHF)
	end

	selfRefBS:Corner(paramGZ + paramHD, paramHA + paramHD, paramHD, 180, 270, paramHE, paramHF, paramHG)
	selfRefBS:Corner(paramGZ + paramHB - paramHD, paramHA + paramHD, paramHD, 270, 360, paramHE, paramHF, paramHG)
	selfRefBS:Corner(paramGZ + paramHB - paramHD, paramHA + paramHC - paramHD, paramHD, 0, 90, paramHE, paramHF, paramHG)
	selfRefBS:Corner(paramGZ + paramHD, paramHA + paramHC - paramHD, paramHD, 90, 180, paramHE, paramHF, paramHG)
end

local lineOutlinedFn = Kefir.paint.LineOutlined
local gradientFn = Kefir.paint.Gradient

function Kefir.paint.Delete(selfRefBT, tableValueD)
	if istable(tableValueD) and tableValueD.menu then
		tableValueD = tableValueD.menu
	end

	if tableValueD and tableValueD ~= nil then
		if tableValueD.Remove then
			tableValueD:Remove()
		end

		tableValueD = nil
	end
end

function Kefir.paint.fDelete(selfRefBU, entityRefG)
	if entityRefG ~= "Panel [NULL]" and entityRefG ~= nil and IsValid(entityRefG) then
		entityRefG:AlphaTo(0, 0.1, 0, function()
			if entityRefG ~= "Panel [NULL]" and entityRefG ~= nil and IsValid(entityRefG) then
				selfRefBU:Delete(entityRefG)
			end
		end)
	end
end

local materialValue = Material("pp/blurx")
local materialValueA = Material("pp/blury")
local valueDW = render.GetBloomTex1()
local materialValueB = Material("pp/copy")
local materialValueC = Material("pp/add")
local materialValueD = Material("pp/sub")
local valueDX = render.GetScreenEffectTexture(0)
local valueDY = render.GetScreenEffectTexture(1)

local function applyGlowBlur(paramHI, paramHJ, paramHK, paramHL)
	materialValue:SetTexture("$basetexture", paramHI)
	materialValueA:SetTexture("$basetexture", valueDW)
	materialValue:SetFloat("$size", paramHJ)
	materialValueA:SetFloat("$size", paramHK)

	for indexX = 1, paramHL + 1 do
		render.SetRenderTarget(valueDW)
		render.SetMaterial(materialValue)
		render.DrawScreenQuad()
		render.SetRenderTarget(paramHI)
		render.SetMaterial(materialValueA)
		render.DrawScreenQuad()
	end
end

Kefir.glow.list = {}

function Kefir.glow.Render(selfRefBV, paramHM)
	if localCache.isConsoleVisible() or localCache.isGameUiVisible() then
		return
	end

	local valueDZ = runtimeApi.GetRenderTarget()
	local additiveA = paramHM.Additive
	local entsA = paramHM.Ents

	render.CopyRenderTargetToTexture(valueDX)

	if additiveA then
		render.Clear(0, 0, 0, 255, false, true)
	else
		render.Clear(255, 255, 255, 255, false, true)
	end

	render.UpdateRefractTexture()
	localCache.beginCameraMode("3D")
	render.SetStencilEnable(true)
	localCache.suppressEngineLighting(true)
	localCache.ignoreDepth(paramHM.IgnoreZ)
	render.SetStencilWriteMask(1)
	render.SetStencilTestMask(1)
	render.SetStencilReferenceValue(1)
	render.SetStencilCompareFunction(STENCIL_ALWAYS)
	render.SetStencilPassOperation(STENCIL_REPLACE)
	render.SetStencilFailOperation(STENCIL_KEEP)
	render.SetStencilZFailOperation(STENCIL_KEEP)

	for indexY = #entsA, 1, -1 do
		local entityRefH = entsA[indexY]

		if IsValid(entityRefH) and not entityRefH:GetNoDraw() then
			entityRefH:DrawModel()
		end
	end

	render.SetStencilCompareFunction(STENCIL_EQUAL)
	render.SetStencilPassOperation(STENCIL_KEEP)
	localCache.beginCameraMode("2D")

	local colorF = paramHM.Color

	localCache.setDrawColor(colorF.r, colorF.g, colorF.b, colorF.a)
	localCache.drawRect(0, 0, screenWidth, screenHeight)
	localCache.endCameraMode("2D")
	localCache.ignoreDepth(false)
	localCache.suppressEngineLighting(false)
	render.SetStencilEnable(false)
	localCache.endCameraMode("3D")
	render.CopyRenderTargetToTexture(valueDY)
	applyGlowBlur(valueDY, paramHM.BlurX, paramHM.BlurY, 1)
	render.SetRenderTarget(RT_timurchik)
	materialValueB:SetTexture("$basetexture", valueDX)
	materialValueB:SetString("$color", "1 1 1")
	materialValueB:SetString("$alpha", "1")
	localCache.setRenderMaterial(materialValueB)
	render.DrawScreenQuad()
	render.SetStencilEnable(true)
	render.SetStencilCompareFunction(STENCIL_NOTEQUAL)

	if additiveA then
		materialValueC:SetTexture("$basetexture", valueDY)
		localCache.setRenderMaterial(materialValueC)
	else
		materialValueD:SetTexture("$basetexture", valueDY)
		localCache.setRenderMaterial(materialValueD)
	end

	for indexZ = 0, paramHM.DrawPasses do
		render.DrawScreenQuad()
	end

	render.SetStencilEnable(false)
	render.SetStencilTestMask(0)
	render.SetStencilWriteMask(0)
	render.SetStencilReferenceValue(0)
end

function Kefir.glow.Add(selfRefBW, paramHN, paramHO, paramHP, paramHQ, paramHR, paramHS, paramHT)
	paramHS = paramHS or true
	paramHT = paramHT or false
	paramHP = paramHP or 2
	paramHQ = paramHQ or 2
	paramHR = paramHR or 1

	if runtimeApi.tIsEmpty(paramHN) then
		return
	end

	selfRefBW.list[#selfRefBW.list + 1] = {
		Ents = paramHN,
		Color = paramHO,
		BlurX = paramHP,
		BlurY = paramHQ,
		DrawPasses = paramHR,
		Additive = paramHS,
		IgnoreZ = paramHT
	}
end

function Kefir.glow.Process(selfRefBX)
	local listA = #selfRefBX.list

	if listA == 0 then
		return
	end

	for indexAA = listA, 1, -1 do
		selfRefBX:Render(selfRefBX.list[indexAA])
	end

	selfRefBX.list = {}
end

function Kefir.glow.Send(selfRefBY, paramHU)
	local getSettingResultC = getSetting("VISUALS", "glow", 1)

	if not getSettingResultC[1] then
		return
	end

	local getSettingResultD = getSetting("VISUALS", "glow_blur", 1)[1]

	selfRefBY:Add(paramHU, getSettingResultC[6][1], getSettingResultD, getSettingResultD, getSetting("VISUALS", "glow_passes", 1)[1], getSetting("VISUALS", "glow_additive", 1)[1], true)
end

Kefir:ClearFiles()
Kefir:ClearHook()
Kefir:ClearCommand()

local tableDataQ = {
	PLAYERS = "list players",
	VISUALS = "esp / wh",
	MISC = "other",
	COMBAT = "legit / rage",
	HOME = "user",
	CONFIG = "config",
	ATTACHMENTS = "attachments"
}

Kefir.paint:Register("tabbutton", "DButton", {
	Init = function(paramHV)
		paramHV:SetText("")
	end,
	Paint = function(paramHW, paramHX, paramHY)
		local valueEA, valueEB = paramHW:LocalToScreen(0, 0)

		localCache.setScissorRect(valueEA, valueEB, valueEA + paramHX, valueEB + paramHY, true)

		local valueEC = paramHW.Tab[1]
		local valueED = paramHW.Tab[2]
		local numberValueJ = 20
		local numberValueK = 26
		local valueEE = Kefir.tabs.current == valueEC
		local whiteA = paramHW:IsHovered() and not valueEE and runtimeApi.color.groupbox or valueEE and runtimeApi.color.kefir_red or runtimeApi.color.white
		local getLanguageResult = Kefir:GetLanguage() == "RU" and 11 or 10

		Kefir.paint:Box(1, 8, paramHX - 2, paramHY - 16, true, runtimeApi.color.kefir_black, runtimeApi.color.groupbox)

		local valueEF, valueEG = Kefir.paint:Text(valueED, 26, 16, (paramHY - 26) / 2, whiteA, TEXT_ALIGN_CENTER, "icons")
		local valueEH, valueEI = Kefir.paint:EOText(Kefir:GetLangText(valueEC), 13, valueEF + 10, (paramHY - 6) / 2, Kefir.paint:HColorAlpha(whiteA, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals", 255)
		local valueEJ, valueEK = Kefir.paint:EOText(runtimeApi.slower(Kefir:GetLangText(tableDataQ[valueEC] or valueEC)), getLanguageResult, valueEF + 7, (paramHY + 16) / 2, Kefir.paint:HColorAlpha(whiteA, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "flag", 255)

		localCache.setScissorRect(0, 0, 0, 0, false)
	end,
	DoClick = function(paramHZ)
		Kefir.tabs.current = paramHZ.Tab[1]

		Kefir.paint:TABUpdate()
	end
})
Kefir.paint:Register("button", "DButton", {
	SRoundedColor = function(paramIA, paramIB)
		paramIA.__buttonroundedcolor = paramIB and paramIB or runtimeApi.color.kefir_red

		if not paramIA.__std__brc then
			paramIA.__std__brc = paramIA.__buttonroundedcolor
		end
	end,
	Init = function(paramIC)
		paramIC:SetText("")

		paramIC.__textsize = 6
		paramIC.__text = unknownText
		paramIC.__textfont = "ofont"
		paramIC.__buttonrounded = false

		paramIC:SRoundedColor(paramIC.__buttonroundedcolor)

		paramIC.__buttonroundedcolor = runtimeApi.color.kefir_red
		paramIC.__std__brc = nil
		paramIC.__tocolor = nil
		paramIC.__htab = -30
	end,
	GTextSize = function(paramID)
		return paramID.__textsize ~= nil and paramID.__textsize or 6
	end,
	GText = function(paramIE)
		return paramIE.__text ~= nil and paramIE.__text or unknownText
	end,
	GTextFont = function(paramIF)
		return paramIF.__textfont ~= nil and paramIF.__textfont or "ofont"
	end,
	GRounded = function(paramIG)
		return paramIG.__buttonrounded ~= nil and paramIG.__buttonrounded or false
	end,
	GRoundedColor = function(paramIH)
		return paramIH.__buttonroundedcolor ~= nil and paramIH.__buttonroundedcolor or runtimeApi.color.kefir_red
	end,
	SText = function(paramII, paramIJ)
		paramII.__text = paramIJ or unknownText
	end,
	STextFont = function(paramIK, paramIL)
		paramIK.__textfont = paramIL or "ofont"
	end,
	STextSize = function(paramIM, paramIN)
		paramIM.__textsize = paramIN
	end,
	SRounded = function(paramIO, paramIP)
		paramIO.__buttonrounded = paramIP
	end,
	Paint = function(paramIQ, paramIR, paramIS)
		paramIQ.__tocolor = paramIQ.__std__brc

		if paramIQ.__texttabtext and paramIQ:IsHovered() then
			paramIQ.__tocolor = runtimeApi.color.groupname
		end

		local valueEL, valueEM = paramIQ:LocalToScreen(0, 0)

		localCache.setScissorRect(valueEL, valueEM, valueEL + paramIR, valueEM + paramIS, true)

		local lerpColorResult = Kefir:LerpColor(Kefir.frametime() * 4, paramIQ:GRoundedColor() or paramIQ.__std__brc, paramIQ.__tocolor)

		paramIQ:SRoundedColor(lerpColorResult)
		Kefir.paint:Box(0, 0, paramIR, paramIS, paramIQ:GRounded(), runtimeApi.color.kefir_black, paramIQ:GRoundedColor(), 2, true)

		if paramIQ.__texttabtext then
			Kefir.paint:Text(Kefir:GetLangText(paramIQ:GText()) or "", paramIQ:GTextSize(), paramIR / 2, (paramIS - paramIQ:GTextSize()) / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, paramIQ:GTextFont() .. ".blur")
		end

		Kefir.paint:Text(Kefir:GetLangText(paramIQ:GText()) or "", paramIQ:GTextSize(), paramIR / 2, (paramIS - paramIQ:GTextSize()) / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, paramIQ:GTextFont())

		if paramIQ.__texttabtext then
			paramIQ.__htab = Kefir:Lerp(Kefir.frametime() * 4.5, paramIQ.__htab or -30, paramIQ:IsHovered() and paramIS or -30)

			gradientFn(Kefir.paint, 0, 0, paramIR, paramIQ.__htab + 4, runtimeApi.color.tabbox, runtimeApi.color.kefir_red, true)
			Kefir.paint:Text(Kefir:GetLangText(paramIQ.__texttabtext), 20, paramIR / 2, (paramIQ.__htab - 20) / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end

		localCache.setScissorRect(0, 0, 0, 0, false)
	end
})
Kefir.paint:Register("default_button", "DButton", {
	Paint = function(paramIT, paramIU, paramIV)
		local textsize = paramIT._textsize

		Kefir.paint:Box(0, 0, paramIU, paramIV, paramIT._rounded or false, Kefir.color.kefir_red or runtimeApi.color.kefir_black, paramIT._roundedcolor or Kefir.color.kefir_red, 1, true)
		Kefir.paint:Text(Kefir:GetLangText(paramIT._text) or "", textsize, paramIU / 2, (paramIV - textsize) / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
	end
})

-- available icons for the icon picker preview
Kefir.icon_preview = {
	"", "", "", "", "", "", "", "",
	"", "", "♛", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", "",
	"", "", "", "", "", "", "", ""
}

Kefir.paint:Register("icon_panel", "DFrame", {
	Init = function(panel)
		panel:SetTitle("")
		panel:ShowCloseButton(false)
		panel:SetDraggable(true)
		panel:SetSizable(false)
		panel:SetAlpha(0)
		panel:AlphaTo(255, 0.2, 0)
	end,
	OnRemove = function(panel)
		if Kefir.icon_panel == panel then Kefir.icon_panel = nil end
	end,
	OnKeyCodePressed = function(panel, key)
		if key == KEY_ESCAPE then
			panel:AlphaTo(0, 0.18, 0, function()
				if IsValid(panel) then panel:Remove() end
			end)
		end
end,
	Paint = function(panel, width, height)
		local alpha = panel:GetAlpha()
		local white = Kefir.paint:HColorAlpha(runtimeApi.color.white, alpha)
		local outline = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, alpha)

		Kefir.paint:rectBox(width, height, 0, 0, Kefir.paint:HColorAlpha(color_black, alpha))
		Kefir.paint:rectBox(width - 2, height - 2, 1, 1, outline)
		Kefir.paint:rectBox(width - 4, height - 4, 2, 2, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, alpha))
		Kefir.paint:Text("Icons", 20, width / 2, 12, white, TEXT_ALIGN_CENTER, "ofont")

		for index, icon in ipairs(Kefir.icon_preview) do
			local column = (index - 1) % 6
			local row = math.floor((index - 1) / 6)
			Kefir.paint:Text(icon, 16, 34 + column * 65, 52 + row * 28, white, TEXT_ALIGN_CENTER, index == 11 and "ofont" or "icons")
		end
	end
})

Kefir.paint:Register("info_panel", "DFrame", {
	Init = function(panel)
		panel:SetTitle("")
		panel:ShowCloseButton(false)
		panel:SetDraggable(true)
		panel:SetSizable(false)
		panel:SetAlpha(0)
		panel:AlphaTo(255, 0.2, 0)
	end,
	OnRemove = function(panel)
		local x, y = panel:GetPos()
		Kefir.variables.INFO_PANEL_POS = { x, y }
		Kefir.paint:fDelete(Kefir.icon_panel)
		if Kefir.info_panel == panel then
			Kefir.info_panel = nil
		end
	end,
	OnKeyCodePressed = function(panel, key)
		if key == KEY_ESCAPE then
			panel:AlphaTo(0, 0.18, 0, function()
				if IsValid(panel) then panel:Remove() end
			end)
		end
	end,
	Paint = function(panel, width, height)
		local alpha = panel:GetAlpha()
		local white = Kefir.paint:HColorAlpha(runtimeApi.color.white, alpha)
		local outline = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, alpha)

		Kefir.paint:rectBox(width, height, 0, 0, Kefir.paint:HColorAlpha(color_black, alpha))
		Kefir.paint:rectBox(width - 2, height - 2, 1, 1, outline)
		Kefir.paint:rectBox(width - 4, height - 4, 2, 2, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, alpha))
		Kefir.paint:Text("chefir.vip", 23, width / 2, 15, white, TEXT_ALIGN_CENTER, "ofont")
		Kefir.paint:GlowText("Owner", 18, width / 2, 55, white, TEXT_ALIGN_CENTER)
		Kefir.paint:Text("♛", 16, width / 2 - 44, 77, white, TEXT_ALIGN_LEFT, "ofont")
		Kefir.paint:Text("sweden men", 13, width / 2 - 25, 77, white, TEXT_ALIGN_LEFT, "chat2")
		local commitColor = Kefir.paint:HColorAlpha(runtimeApi.color.footeri, alpha)
		Kefir.paint:Text("", 14, width / 2 - 34, height - 25, commitColor, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text("Commit: " .. tostring(BUILD_NUMBER), 13, width / 2 - 17, height - 25.5, commitColor, TEXT_ALIGN_LEFT, "chat2")
	end
})

local valueEN = ""

Kefir.paint:Register("menuframe", "DFrame", {
	Init = function(unusedParamH)
		if IsValid(Kefir.menu) then
			Kefir.paint:Delete(Kefir)

			return
		end
	end,
	OnRemove = function()
		Kefir.paint:fDelete(Kefir.info_panel)
		Kefir.paint:fDelete(Kefir.previewesp)
		Kefir.paint:fDelete(Kefir.filteresp)
		Kefir.paint:fDelete(Kefir.hitboxaim)
		Kefir.paint:fDelete(Kefir.tab_frame)
	end,
	OnKeyCodePressed = function(paramIW, paramIX)
		local hotkeyChoosing = Kefir.hotkey_choosing

		if not Kefir.search_active and paramIX == KEY_SLASH and hotkeyChoosing[1][1] == "none" then
			Kefir.search_active = true
			Kefir.search_cursor = #(Kefir.search_query or "")
			Kefir.search_blink = 0
			Kefir.search_blink_change = true
			return
		end

		if Kefir.search_active and hotkeyChoosing[1][1] == "none" then
			local sq = Kefir.search_query or ""
			local sc = Kefir.search_cursor or 0
			local sl = #sq

			if paramIX == KEY_BACKSPACE then
				if sc > 0 then
					Kefir.search_query = string.sub(sq, 1, sc - 1) .. string.sub(sq, sc + 1)
					Kefir.search_cursor = sc - 1
					Kefir.search_blink = 0
					Kefir.search_blink_change = true
					Kefir:RebuildSearchGroups()
				end
				return
			end

			if paramIX == KEY_ENTER then
				Kefir.search_active = false
				return
			end

			if paramIX == KEY_ESCAPE then
				Kefir.search_active = false
				return
			end

			if paramIX == KEY_LEFT then
				if sc > 0 then Kefir.search_cursor = sc - 1 end
				Kefir.search_blink = 0
				Kefir.search_blink_change = true
				return
			end

			if paramIX == KEY_RIGHT then
				if sc < sl then Kefir.search_cursor = sc + 1 end
				Kefir.search_blink = 0
				Kefir.search_blink_change = true
				return
			end

			if paramIX == KEY_HOME then
				Kefir.search_cursor = 0
				Kefir.search_blink = 0
				Kefir.search_blink_change = true
				return
			end

			if paramIX == KEY_END then
				Kefir.search_cursor = sl
				Kefir.search_blink = 0
				Kefir.search_blink_change = true
				return
			end

			if paramIX == KEY_TAB then
				local curTab = Kefir.tabs.current
				local curShift = runtimeApi.IsKeyDown(KEY_LSHIFT) or runtimeApi.IsKeyDown(KEY_RSHIFT)
				local dir = curShift and -1 or 1
				local nextTab = nil

				for iTab, tabItem in Kefir.ipairs(Kefir.tabs.list) do
					if tabItem[1] == curTab then
						local niTab = iTab + dir

						if niTab < 1 then
							niTab = #Kefir.tabs.list
						elseif niTab > #Kefir.tabs.list then
							niTab = 1
						end

						nextTab = Kefir.tabs.list[niTab][1]

						break
					end
				end

				if nextTab and nextTab ~= curTab then
					Kefir.tabs.current = nextTab
					Kefir.paint:TABUpdate()
				end

				return
			end

			if sl < 40 then
				local ch = nil
				if paramIX >= KEY_A and paramIX <= KEY_Z then
					local base = string.byte("a") + (paramIX - KEY_A)
					ch = string.char(base)
				elseif paramIX >= KEY_0 and paramIX <= KEY_9 then
					ch = tostring(paramIX - KEY_0)
				elseif paramIX == KEY_SPACE then
					ch = " "
				elseif paramIX == KEY_MINUS then
					ch = "-"
				elseif paramIX == KEY_EQUAL then
					ch = "="
				elseif paramIX == KEY_LEFTBRACKET then
					ch = "["
				elseif paramIX == KEY_RIGHTBRACKET then
					ch = "]"
				elseif paramIX == KEY_BACKSLASH then
					ch = "\\"
				elseif paramIX == KEY_SEMICOLON then
					ch = ";"
				elseif paramIX == KEY_APOSTROPHE then
					ch = "'"
				elseif paramIX == KEY_COMMA then
					ch = ","
				elseif paramIX == KEY_PERIOD then
					ch = "."
				elseif paramIX == KEY_SLASH then
					ch = "/"
				elseif paramIX == KEY_GRAVE then
					ch = "`"
				end

				if ch then
					Kefir.search_query = string.sub(sq, 1, sc) .. ch .. string.sub(sq, sc + 1)
					Kefir.search_cursor = sc + 1
					Kefir.search_blink = 0
					Kefir.search_blink_change = true
					Kefir:RebuildSearchGroups()
				end
			end

			return
		end

		if paramIX == KEY_MINUS and not paramIW.ForceClose then
			paramIW:Remove()

			paramIW = nil

			Kefir.paint:fDelete(Kefir.previewesp)
			Kefir.paint:fDelete(Kefir.filteresp)
			Kefir.paint:fDelete(Kefir.hitboxaim)
			Kefir.paint:fDelete(Kefir.tab_frame)
		end

		if hotkeyChoosing[1][1] ~= "none" then
			if paramIX ~= KEY_ESCAPE then
				runtimeApi.var[hotkeyChoosing[1][2]][hotkeyChoosing[1][3]][hotkeyChoosing[1][1]][1] = paramIX
			end

			hotkeyChoosing[1][1] = "none"
		end
	end,
	Paint = function(paramIY, paramIZ, paramJA)
		local kefirBlack = runtimeApi.color.kefir_black
		local kefirRed = runtimeApi.color.kefir_red

		Kefir.paint:rectBox(paramIZ, paramJA, 0, 0, color_black)
		Kefir.paint:rectBox(paramIZ - 2, paramJA - 2, 1, 1, runtimeApi.color.groupname)
		Kefir.paint:rectBox(paramIZ - 4, paramJA - 4, 2, 2, runtimeApi.color.kefir_black)

		local numberValueL = 75
		local numberValueM = 18
		
		local logoText = "chefir.vip skachat"
		local centerX = paramIZ / 2

		local glowColor = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, 230)
		Kefir.paint:Text(logoText, 42, centerX, numberValueM, glowColor, TEXT_ALIGN_CENTER, "ofont")

		local _, logoH = Kefir.paint:Text(logoText, 40, centerX, numberValueM, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")

		local footerY = numberValueM + logoH

		if miscEnabled and getSetting("MISC", "faqz_animation", 1)[1] then
			paramIY.size_text_update = runtimeApi.floor(Kefir:Lerp(8 * Kefir.frametime(), paramIY.size_text_update or 0, 0))
		else
			paramIY.size_text_update = 0
		end

		local footeriA = Kefir.qfaq ~= "" and runtimeApi.color.white or runtimeApi.color.footeri
		local getLangTextResult = Kefir.qfaq ~= "" and Kefir.qfaq or Kefir:GetLangText(Kefir.qfaq_text)
		local valueEP = paramIZ * 0.025

		if miscEnabled and getSetting("MISC", "faqz_animation", 1)[1] and valueEN ~= getLangTextResult then
			paramIY.size_text_update = 4
			valueEN = getLangTextResult
		end

		Kefir.paint:Text("", 12, valueEP, paramJA - 22.5, footeriA, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(getLangTextResult, 12 + paramIY.size_text_update, valueEP + 14, paramJA - 23, footeriA, TEXT_ALIGN_LEFT, "chat2")
		localCache.setDrawColor(runtimeApi.color.line)
		localCache.drawSurfaceLine(20, numberValueL, paramIZ - 20, numberValueL)

		-- Animated header accents: subtle motion adds depth without obscuring the UI.
		local pulse = (runtimeApi.sin(runtimeApi.stime() * 2.4) + 1) * 0.5
		local accentAlpha = 45 + pulse * 85
		local accentColor = Kefir.paint:HColorAlpha(kefirRed, accentAlpha)
		local accentWidth = 90 + pulse * 70

		localCache.setDrawColor(accentColor)
		localCache.drawRect(20, numberValueL + 2, accentWidth, 1)
		localCache.drawRect(paramIZ - 20 - accentWidth, numberValueL + 2, accentWidth, 1)

		local cornerSize = 9 + pulse * 3
		localCache.setDrawColor(Kefir.paint:HColorAlpha(kefirRed, 120 + pulse * 80))
		localCache.drawSurfaceLine(20, numberValueL - cornerSize, 20, numberValueL - 2)
		localCache.drawSurfaceLine(paramIZ - 20, numberValueL - cornerSize, paramIZ - 20, numberValueL - 2)
	end,
	Think = function(paramJB)
		local hotkeyChoosingA = Kefir.hotkey_choosing

		paramJB.wh = {
			paramJB:GetWide(),
			paramJB:GetTall()
		}

		for indexAB = 107, 112 do
			if runtimeApi.IsKeyDown(indexAB) and hotkeyChoosingA[1][1] ~= "none" then
				runtimeApi.var[hotkeyChoosingA[1][2]][hotkeyChoosingA[1][3]][hotkeyChoosingA[1][1]][1] = indexAB
				hotkeyChoosingA[1][1] = "none"
			end
		end

		if paramJB.ForceClose and paramJB:GetAlpha() < 1 then
			Kefir.paint:Delete(Kefir)
		end
	end
})
Kefir.paint:Register("jframe", "DFrame", {
	Init = function(paramJC)
		paramJC:SetTitle("")
		paramJC:SetZPos(-9999)
		paramJC:ShowCloseButton(false)
		paramJC:SetDraggable(false)
		paramJC:SetAlpha(0)
		paramJC:AlphaTo(255, 0.1, 0, nil)
		paramJC:SetPaintedManually(not nativeApi.standalone_vgui)
	end,
	Paint = function(paramJD, paramJE, paramJF)
		Kefir.paint:rectBox(paramJE, paramJF, 0, 0, Kefir.paint:HColorAlpha(color_black, paramJD:GetAlpha()))
		Kefir.paint:rectBox(paramJE - 2, paramJF - 2, 1, 1, Kefir.paint:HColorAlpha(runtimeApi.color.groupname, paramJD:GetAlpha()))
		Kefir.paint:rectBox(paramJE - 4, paramJF - 4, 2, 2, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, paramJD:GetAlpha()))
	end
})
Kefir.paint:Register("color_picker", "DFrame", {
	Init = function(paramJG)
		paramJG:ShowCloseButton(false)
		paramJG:SetTitle("")
	end,
	Paint = function(unusedParamI, paramJH, paramJI)
		Kefir.paint:Box(0, 0, paramJH, paramJI, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 2, true)
	end
})

Kefir.buffer_color = nil

Kefir.paint:Register("color_selector", "DButton", {
	Init = function(paramJJ)
		paramJJ.__var = runtimeApi.color.white
		paramJJ.stackvar = {}

		paramJJ:SetText("")
	end,
	SetVar = function(paramJK, paramJL)
		paramJK.__var = paramJL
	end,
	PushVar = function(paramJM, paramJN)
		runtimeApi.insert(paramJM.stackvar, paramJN)
	end,
	GetStack = function(paramJO)
		return paramJO.stackvar or {}
	end,
	GetVar = function(paramJP)
		return paramJP.__var
	end,
	Paint = function(paramJQ, paramJR, paramJS)
		Kefir.paint:Box(0, 0, paramJR, paramJS, true, paramJQ:GetVar(), runtimeApi.color.picker_clr, 1, true)
	end,
	DoClick = function(paramJT)
		local getVarResult = paramJT:GetVar()
		local getStackResult = paramJT:GetStack()

		Kefir.cpick_act = true

		local valueEQ, valueER = localCache.getMousePosition()

		Kefir.cpickl = Kefir.paint:CreateObject("color_picker")

		Kefir.cpickl:SetPos(valueEQ + 25, valueER)
		Kefir.cpickl:SetSize(200, 0)
		Kefir.cpickl:MakePopup()
		Kefir.cpickl:SetPaintedManually(not nativeApi.standalone_vgui)
		runtimeApi.tSimple(0.01, function()
			if IsValid(Kefir.cpickl) then
				function Kefir.cpickl.Think(paramJU)
					if not paramJU:HasFocus() or not IsValid(Kefir.menu) or Kefir.menu == nil then
						paramJU:Remove()

						Kefir.cpick_act = false
					end
				end

				Kefir.cpickl:SizeTo(200, 200, 0.09, 0, 0.9, nil)
			end
		end)

		function Kefir.cpickl.OnRemove(unusedParamJ)
			Kefir.cpick_act = false
		end

		local entityRefI = runtimeApi.vCreate("DColorMixer", Kefir.cpickl)

		entityRefI:SetPos(5, 5)
		entityRefI:SetSize(190, 190)
		entityRefI:SetPalette(false)
		entityRefI:SetAlphaBar(true)
		entityRefI:SetWangs(false)
		entityRefI:SetColor(runtimeApi.var[Kefir.tabs.current][getStackResult[1]][getStackResult[2]][6][getStackResult[3]])

		entityRefI.parent = Kefir.cpickl

		function entityRefI.ValueChanged(unusedParamK, paramJV)
			runtimeApi.var[Kefir.tabs.current][getStackResult[1]][getStackResult[2]][6][getStackResult[3]] = paramJV

			if paramJT ~= nil then
				paramJT:SetVar(paramJV)
			end
		end

		function entityRefI.OnRemove(unusedParamL)
			Kefir.cpick_act = false
		end

		for keyAI, itemAF in Kefir.ipairs(entityRefI:GetChildren()) do
			for keyAJ, itemAG in Kefir.ipairs(itemAF:GetChildren()) do
				if itemAG:GetName() == "DButton" then
					itemAG:SetSize(16, 16)

					function itemAG.Paint()
						return
					end

					function itemAG.PaintOver(unusedParamM, paramJW, paramJX)
						Kefir.paint:Box(0, 0, paramJW, paramJX, true, runtimeApi.color.kefir_red, runtimeApi.color.kefir_black, 1, true)
					end
				end
			end
		end
	end,
	DoRightClick = function(paramJY)
		paramJY.itemsList = Kefir.buffer_color and {
			"Copy Color",
			"Paste Color"
		} or {
			"Copy Color"
		}

		Kefir.drawlist.derma(paramJY, function(paramJZ)
			if paramJZ == "Copy Color" then
				Kefir.buffer_color = paramJY:GetVar()
			elseif paramJZ == "Paste Color" and Kefir.buffer_color then
				paramJY:SetVar(Kefir.buffer_color)

				local getStackResultA = paramJY:GetStack()

				runtimeApi.var[Kefir.tabs.current][getStackResultA[1]][getStackResultA[2]][6][getStackResultA[3]] = Kefir.buffer_color
			end
		end, nil, "")
	end
})
Kefir.paint:Register("panelcontent", "DPanel", {
	Paint = function(unusedParamN, paramKA, paramKB)
		Kefir.paint:Box(0, 0, paramKA, paramKB, true, runtimeApi.color.kefir_black, runtimeApi.color.groupbox, 1, true)
	end,
	PaintOver = function(paramKC, paramKD, unusedParamO)
		runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.ofont.16")

		local getLangTextResultA = Kefir:GetLangText(paramKC.__groupname)
		local valueES, valueET = runtimeApi.sGetTextSize(getLangTextResultA)
		local valueEU = valueES + 25.5
		local numberValueN = -5.5

		Kefir.paint:Box((paramKD - (valueEU + 2)) / 2, numberValueN + 5, valueEU + 2, valueET, true, runtimeApi.color.groupname, runtimeApi.color.groupname, 0, true)
		Kefir.paint:Box((paramKD - valueEU) / 2, numberValueN + 5, valueEU, valueET - 1, true, runtimeApi.color.kefir_black, runtimeApi.color.groupname, 0, true)
		Kefir.paint:Text(getLangTextResultA, 16, paramKD / 2, numberValueN + 4, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
	end
})
Kefir.paint:Register("checkbox", "DCheckBox", {
	DoClick = function(paramKE)
		if not paramKE.adata.lang333 then
			if paramKE.__var ~= "toggle" then
				if isbool(runtimeApi.var[paramKE.__tab][paramKE.__group][paramKE.__var][1]) then
					runtimeApi.var[paramKE.__tab][paramKE.__group][paramKE.__var][1] = not runtimeApi.var[paramKE.__tab][paramKE.__group][paramKE.__var][1]
				end
			elseif isbool(runtimeApi.var[paramKE.__tab][paramKE.__var][1]) then
				runtimeApi.var[paramKE.__tab][paramKE.__var][1] = not runtimeApi.var[paramKE.__tab][paramKE.__var][1]
			end
		else
			runtimeApi.var.USER_CONFIG.SHARE = not runtimeApi.var.USER_CONFIG.SHARE
		end
	end,
	AnimationThink = function(paramKF)
		if paramKF._glow then
			paramKF._glow = Kefir:Lerp(Kefir.frametime() * 4, paramKF._glow or 0, paramKF:IsHovered() and 90 or 0)
		end
	end,
	Paint = function(paramKG, paramKH, paramKI)
		paramKG.adata = paramKG.adata or {}

		local valueEV = paramKG.__widget or {
			0,
			runtimeApi.color.white
		}
		local valueEW = valueEV[1] or 0
		local whiteB = valueEV[2] or runtimeApi.color.white
		local valueEX = paramKH - (paramKH - 15)
		local valueEY = valueEX + 22
		local numberValueO = 20
		local valueEZ

		if not paramKG.adata.lang333 then
			valueEZ = getSetting(paramKG.__tab, paramKG.__var, paramKG.__group)[1]
		else
			valueEZ = runtimeApi.var.USER_CONFIG.SHARE
		end

		if paramKG.bgl then
			Kefir.paint:Box(0, -paramKI, 247, 20, true, color_black, color_black, 1)
		end

		local getLangTextResultB = Kefir:GetLangText(paramKG.__cachetext)

		Kefir.paint:Box(0 + valueEW, 0, paramKH, paramKI, false, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, paramKG._glow or 0))
		Kefir.paint:Box(0 + valueEW, 0, valueEX, paramKI, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
		Kefir.paint:Text(getLangTextResultB, numberValueO, valueEY / 2 + valueEW, paramKI - (numberValueO - 2), whiteB, TEXT_ALIGN_LEFT, "ofont")

		local numberValueP = 2
		local numberValueQ = 2

		paramKG.clickanim = Kefir:Lerp(12 * Kefir.frametime(), paramKG.clickanim or 0, valueEZ and 1.1 or 0)

		Kefir.paint:Gradient(numberValueP + valueEW, numberValueQ, (valueEX - numberValueP * 2) * paramKG.clickanim - 1, paramKI - numberValueQ * 2, runtimeApi.color.kefir_red, runtimeApi.color.groupname, true, nil, runtimeApi.material.gui_up)
	end
})
Kefir.paint:Register("slider", "DNumSlider", {
	Init = function(paramKJ)
		paramKJ.Label:SetColor(Color(200, 200, 200))
		paramKJ.TextArea:SetVisible(false)

		function paramKJ.Paint()
			return
		end

		function paramKJ.Slider.Knob.Paint()
			return
		end

		paramKJ.initialize = false
		paramKJ.stackvar = {}
	end,
	PushVar = function(paramKK, paramKL)
		runtimeApi.insert(paramKK.stackvar, paramKL)
	end,
	GetStack = function(paramKM)
		return paramKM.stackvar or {}
	end,
	OnValueChanged = function(paramKN, paramKO)
		if paramKN.initialize then
			local getStackResultB = paramKN:GetStack()
			local valueFA = paramKN.wdata[3] == 0 and runtimeApi.floor(paramKO) or runtimeApi.math.Round(paramKO, 1)

			runtimeApi.var[Kefir.tabs.current][getStackResultB[1]][getStackResultB[2]][1] = valueFA
		end
	end
})
Kefir.paint:Register("text", "DLabel", {
	Init = function(paramKP)
		paramKP.__data = {
			unknownText,
			16,
			runtimeApi.color.white,
			"ofont"
		}

		paramKP:SetText("")
	end,
	Paint = function(paramKQ, unusedParamP, unusedParamQ)
		local dataA = paramKQ.__data

		Kefir.paint:Text(Kefir:GetLangText(dataA[1]), dataA[2], 0, 0, dataA[3], TEXT_ALIGN_LEFT, dataA[4])
	end
})

local tableDataR = {
	otrub = {
		"UNCONSCIOUS",
		Color(107, 110, 115),
		true,
		false
	},
	lungsfunction = {
		"CAN'T BREATH",
		Color(228, 14, 14),
		false,
		false
	}
}
local numberValueR = 6
local numberValueS = 0

function Kefir.KB_State(selfRefBZ, paramKR, paramKS, paramKT, commandRef)
	local getSettingResultE = getSetting(paramKR, paramKS, paramKT)
	local valueFB = getSettingResultE[1]
	local valueFC = getSettingResultE[8]
	local flagD = false
	local valueFD = runtimeApi.IsKeyDown(valueFB)

	if valueFC == "Always On" then
		flagD = true
	elseif valueFC == "Hold" then
		flagD = valueFD
	elseif valueFC == "Unhold" then
		flagD = not valueFD
	elseif valueFC == "On Shot" then
		flagD = commandRef ~= nil and commandRef:KeyDown(IN_ATTACK) or localPlayer:KeyDown(IN_ATTACK)
	elseif valueFC == "Toggle" then
		flagD = Kefir.toggle_states[valueFB] or false
	end

	local getLangTextResultC = runtimeApi.sformat("%s [%s]", Kefir:GetLangText(getSettingResultE[9]), Kefir:GetLangText(valueFC))

	Kefir.keystates[getLangTextResultC] = {
		active = flagD,
		time = runtimeApi.stime()
	}

	return flagD, valueFB
end

function Kefir.GetEntityType(selfRefCA, paramKU, paramKV)
	local valueFE = paramKU.Base or ""

	if valueFE == "weapon_base" then
		return "Standard", selfRefCA.color.white
	end

	if valueFE == "weapon_hg_grenade_tpik" or paramKV == "weapon_hg_grenade_tpik" then
		return "Grenade", selfRefCA.color.consumable
	end

	if valueFE == "armor_base" then
		return "Armor", selfRefCA.color.armor
	end

	if valueFE == "attachment_base" then
		return "Attachment", selfRefCA.color.attachment
	end

	if istable(paramKU.FoodModels) or istable(paramKU.WaterModel) then
		return "Consumable", selfRefCA.color.consumable
	end

	if selfRefCA:IsHGObject(paramKU) then
		return "Firearm Weapon", selfRefCA.color.firearment
	end

	if selfRefCA:IsMeleeObject(paramKU) then
		return "Melee Weapon", selfRefCA.color.is_melee
	end

	if paramKU.Category == "ZCity Medicine" then
		return "Medicine", selfRefCA.color.groupname
	end

	if paramKV == "hg_flashlight" then
		return "Flashlight", selfRefCA.color.flashlight
	end

	if paramKV == "hg_sling" then
		return "Sling", selfRefCA.color.sling
	end

	if paramKV == "ent_hg_cyanide_canister" then
		return "Cyanide", selfRefCA.color.red
	end

	return "unknown", color_white
end

local valueFF = HPPlayers or {}

Kefir.drawlist = {
	derma_opened = false,
	pElements = {
		[0] = 0,
		0,
		0,
		0
	},
	elA = function(paramKW, paramKX)
		Kefir.drawlist.pElements[paramKW] = Kefir.drawlist.pElements[paramKW] + paramKX
	end,
	elG = function(paramKY)
		return Kefir.drawlist.pElements[paramKY]
	end,
	space = function(unusedParamR, paramKZ)
		if not Kefir:AllowedFeature(paramKZ.index) then
			return 0
		end

		return paramKZ.data_var[5]
	end,
	text = function(paramLA, paramLB, paramLC)
		if not Kefir:AllowedFeature(paramLB.index) then
			return 0
		end

		local valueFG = paramLB.data_var[5]
		local valueFH = valueFG[1]
		local valueFI = valueFG[2]
		local valueFJ = valueFG[3]
		local valueFK = valueFG[4]
		local valueFL = valueFG[5] or 0
		local createObjectResult = Kefir.paint:CreateObject("text", paramLC or paramLA.menu_scroll)

		createObjectResult:SetPos(paramLB.object_x, paramLB.object_y)
		createObjectResult:SetSize(240, 15 + valueFL)

		createObjectResult.__data = {
			valueFH,
			valueFI,
			valueFJ,
			valueFK
		}

		return valueFG[2] + 2
	end,
	list = function(paramLD, paramLE, paramLF)
		local textBufferA = paramLE.data_var[5][3]
		local getLangTextResultD = Kefir:GetLangText("Config Name")

		Kefir.configlist = runtimeApi.vCreate("DListView", paramLF or paramLD.menu_scroll)

		Kefir.configlist:SetSize(238, 200)
		Kefir.configlist:SetPos(paramLE.object_x, paramLE.object_y)
		Kefir.configlist:SetMultiSelect(false)
		Kefir.configlist:AddColumn(getLangTextResultD)

		Kefir.configlist.origAddLine = Kefir.configlist.AddLine

		function Kefir.configlist.AddLine(selfRefCB, ...)
			local origAddLineResult = selfRefCB:origAddLine(...)
			local valueFM = ({
				...
			})[1]
			local valueFN = string.Replace(valueFM, ".cvip", "")

			origAddLineResult.Columns[1]:SetText("")

			origAddLineResult.txt2 = valueFN

			function origAddLineResult.Paint()
				return
			end

			function origAddLineResult.PaintOver(paramLG, paramLH, paramLI)
				local kefirRedA = paramLG:IsSelected() and runtimeApi.color.groupname or runtimeApi.color.kefir_red
				local kefirBlackA = paramLG:IsSelected() and runtimeApi.color.picker_clr or runtimeApi.color.kefir_black
				local whiteC = paramLG:IsSelected() and runtimeApi.color.selectedline or runtimeApi.color.white

				Kefir.paint:Box(0, 0, paramLH, paramLI, true, kefirBlackA, kefirRedA, 1, true)
				Kefir.paint:EOText(valueFN, 18, paramLH / 2, 10, whiteC, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "ofont", 255)
			end

			return origAddLineResult
		end

		function Kefir.configlist.Paint(unusedParamS, paramLJ, paramLK)
			Kefir.paint:Box(0, 0, paramLJ, paramLK, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
		end

		function Kefir.configlist.Think(paramLL)
			local getSelectedLineResult = paramLL:GetSelectedLine()
			local getLineResult = paramLL:GetLine(getSelectedLineResult)

			paramLE.data_var[1] = getSelectedLineResult and getLineResult.txt2 or nil
		end

		for indexAC = 1, #textBufferA do
			Kefir.configlist:AddLine(textBufferA[indexAC])
		end

		local valueFO = Kefir.configlist.Columns[1]
		local vBar = Kefir.configlist.VBar

		vBar:SetSize(12, 15)

		vBar.tPos = 0
		vBar.nPos = 0

		function vBar.Paint(unusedParamT, paramLM, paramLN)
			Kefir.paint:rectBox(paramLM, paramLN, 0, 0, color_black)
			Kefir.paint:rectBox(paramLM - 2, paramLN - 2, 1, 1, runtimeApi.color.groupname)
			Kefir.paint:rectBox(paramLM - 4, paramLN - 4, 2, 2, runtimeApi.color.kefir_black)
		end

		function vBar.btnGrip.Paint(paramLO, paramLP, paramLQ)
			local groupboxA = paramLO:IsHovered() and runtimeApi.color.kefir_red or runtimeApi.color.groupbox

			Kefir.paint:rectBox(paramLP - 8, paramLQ, 4, 0, groupboxA)
			Kefir.paint:rectBox(paramLP - 10, paramLQ - 2, 5, 1, color_black)
		end

		function vBar.btnUp.Paint()
			return
		end

		function vBar.btnDown.Paint()
			return
		end

		function valueFO.PaintOver(unusedParamU, paramLR, paramLS)
			Kefir.paint:Box(0, 0, paramLR, paramLS, true, runtimeApi.color.picker_clr, runtimeApi.color.kefir_red, 1, true)
			Kefir.paint:Text(getLangTextResultD, 18, (paramLR + 6) / 2, 0, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end

		return 205
	end,
	derma = function(entityRefJ, paramLT, paramLU, paramLV)
		if Kefir.drawlist.derma_opened then
			CloseDermaMenus()

			return
		end

		local dermaMenuResult = DermaMenu(false, entityRefJ)
		local itemsListA = entityRefJ.itemsList

		dermaMenuResult:SetDrawBorder(false)
		dermaMenuResult:SetDrawOnTop(false)

		dermaMenuResult.Paint = nil
		dermaMenuResult.PaintOver = nil

		for indexAD = 1, #itemsListA do
			local valueFP = itemsListA[indexAD]
			local addOptionResult = dermaMenuResult:AddOption(indexAD, function()
				if IsValid(entityRefJ) then
					if not isfunction(paramLT) then
						entityRefJ:ChooseOption(valueFP)
					else
						paramLT(valueFP)
					end
				end
			end)

			function addOptionResult.OnMouseReleased(paramLW, paramLX)
				DButton.OnMouseReleased(paramLW, paramLX)

				if paramLW.m_MenuClicking and paramLX == MOUSE_LEFT and paramLW:IsEnabled() then
					paramLW.m_MenuClicking = false
				end
			end

			addOptionResult:SetText("")

			addOptionResult._choice = valueFP
			addOptionResult.PerformLayout = nil
			addOptionResult.Paint = nil
			addOptionResult.FAQ_INDEX = paramLV .. "_" .. valueFP

			function addOptionResult.PaintOver(paramLY, paramLZ, paramMA)
				Kefir.paint:Box(2, 2, paramLZ - 3, paramMA - 3, false, runtimeApi.color.kefir_black)

				local choice = paramLY._choice
				local isHoveredResult = paramLY:IsHovered()

				paramLY._alpha = Kefir:Lerp(Kefir.frametime() * 6, paramLY._alpha or 0, isHoveredResult and 255 or 0)
				paramLY._alpha1 = Kefir:Lerp(Kefir.frametime() * 20, paramLY._alpha1 or 0, 255)

				local alphaA = paramLY._alpha
				local hColorAlphaResult = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, alphaA)
				local hColorAlphaResultA = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, alphaA)
				local hColorAlphaResultB = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, alphaA - 200)
				local hColorAlphaResultC = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, alphaA - 200)

				Kefir.paint:Box(0, 0, paramLZ, paramMA, true, hColorAlphaResult, hColorAlphaResultA, 1, true)
				Kefir.paint:Gradient(0, 0, paramLZ, paramMA, hColorAlphaResultB, hColorAlphaResultC, runtimeApi.material.blur)

				local getLangTextResultE = Kefir:GetLangText(choice)
				local russianSymbolsResult = Kefir:RussianSymbols(getLangTextResultE) and "chat" or "ofont"

				Kefir.paint:Text(getLangTextResultE, 16, paramLZ / 2, 4, Kefir.paint:HColorAlpha(runtimeApi.color.white, paramLY._alpha1), TEXT_ALIGN_CENTER, russianSymbolsResult)

				if isfunction(paramLU) and paramLU(choice) then
					Kefir.paint:Text("", 12, 4, (paramMA - 12) / 2, Kefir.paint:HColorAlpha(runtimeApi.color.white, paramLY._alpha1), TEXT_ALIGN_LEFT, "icons")
				end
			end
		end

		local valueFQ, valueFR = entityRefJ:LocalToScreen(0, entityRefJ:GetTall())

		dermaMenuResult:Open(valueFQ, valueFR, false, entityRefJ)

		function dermaMenuResult.OnRemove()
			Kefir.drawlist.derma_opened = false
		end

		function dermaMenuResult.Paint(unusedParamV, paramMB, paramMC)
			Kefir.paint:Box(0, 0, paramMB, paramMC, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
		end

		Kefir.drawlist.derma_opened = true
		Kefir.drawlist.dermacurrent = dermaMenuResult

		dermaMenuResult:SetPaintedManually(not nativeApi.standalone_vgui)

		return dermaMenuResult
	end,
	input = function(paramMD, paramME, paramMF)
		local valueFS = paramME.data_var[5]
		local entityRefK = runtimeApi.vCreate("DTextEntry", paramMF or paramMD.menu_scroll)
		local customEnvFn = paramME.custom_env
		local valueFT = valueFS[2]

		entityRefK:SetPos(paramME.object_x + (valueFS[6] or 0), paramME.object_y)
		entityRefK:SetSize(valueFS[1], valueFT)
		entityRefK:SetValue(paramME.data_var[1])
		entityRefK:SetText(paramME.data_var[1])
		entityRefK:SetPlaceholderText(valueFS[3])

		entityRefK.font2 = valueFS[4] or "ofont"
		entityRefK.blink = 0
		entityRefK.blink_change = true
		entityRefK.caretx = 0
		entityRefK.iMaxLen = valueFS[5] or 14

		function entityRefK.Paint(paramMG, paramMH, paramMI)
			local getCaretPosResult = paramMG:GetCaretPos()
			local settingValue = paramMG:GetValue()
			local valueFU = runtimeApi.u8sub(settingValue, 0, getCaretPosResult)

			if paramMG.blink_change then
				if paramMG.blink >= 0.99 then
					paramMG.blink_change = false
				end
			elseif paramMG.blink <= 0.01 then
				paramMG.blink_change = true
			end

			paramMG.blink = runtimeApi.Lerp(Kefir.frametime() * 9, paramMG.blink, paramMG.blink_change and 1 or 0)

			local font2A = paramMG.font2

			Kefir.paint:Box(0, 0, paramMH, paramMI, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
			Kefir.paint:Text(#settingValue <= 0 and valueFS[3] or settingValue, 14, paramMH / 2, 0, Kefir.paint:HColorAlpha(runtimeApi.color.white, #settingValue <= 0 and 55 or 255), TEXT_ALIGN_CENTER, font2A)

			if paramMG:HasFocus() then
				runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir." .. font2A .. ".14")

				local valueFV, valueFW = runtimeApi.sGetTextSize(settingValue)
				local valueFX, valueFY = runtimeApi.sGetTextSize(valueFU)
				local valueFZ = paramMH / 2 - valueFV / 2 + valueFX
				local valueGA = (paramMI - valueFW) / 2

				paramMG.caretx = runtimeApi.Lerp(Kefir.frametime() * 7.7, paramMG.caretx or 0, valueFZ)

				localCache.setDrawColor(Kefir.paint:HColorAlpha(runtimeApi.color.white, paramMG.blink * 255))
				localCache.drawRect(paramMG.caretx, valueGA, 2, valueFW)
			end
		end

		function entityRefK.OnTextChanged(paramMJ, unusedParamW)
			local settingValueA = paramMJ:GetValue()
			local iMaxLenA = paramMJ.iMaxLen
			local valueGB = runtimeApi.u8sub(settingValueA, 1, iMaxLenA)

			if iMaxLenA < runtimeApi.u8l(settingValueA) then
				paramMJ:SetText(valueGB)
				paramMJ:SetCaretPos(iMaxLenA)
			end

			paramME.data_var[1] = valueGB
		end

		if customEnvFn and isfunction(customEnvFn) then
			customEnvFn(entityRefK)
		end

		return valueFT + 2
	end,
	button = function(paramMK, paramML, paramMM)
		if not Kefir:AllowedFeature(paramML.index) then
			return 0
		end

		local valueGC = paramML.data_var[5]
		local valueGD = valueGC[1]
		local valueGE = valueGC[2]
		local valueGF = valueGC[3]
		local valueGG = valueGC[4]
		local valueGH = valueGC[5]
		local valueGI = valueGC[6]
		local valueGJ = valueGC[7]
		local valueGK = valueGC[8]
		local valueGL = valueGC[9] or false
		local valueGM = valueGC[10] or {
			0,
			0
		}
		local tableDataS = {
			0,
			0
		}

		if valueGL then
			tableDataS = valueGM or {
				0,
				0
			}
		end

		local createObjectResultA = Kefir.paint:CreateObject("default_button", paramMM or paramMK.menu_scroll)

		createObjectResultA:SetPos(paramML.object_x + tableDataS[1], paramML.object_y - tableDataS[2])
		createObjectResultA:SetSize(valueGG[1], valueGG[2])
		createObjectResultA:SetText("")

		createObjectResultA._text = valueGD
		createObjectResultA._textsize = valueGE
		createObjectResultA._rounded = valueGF
		createObjectResultA._maincolor = valueGH
		createObjectResultA._roundedcolor = valueGI
		createObjectResultA._sizebtn = valueGG

		function createObjectResultA.Think(paramMN)
			if paramMN._text == "Settings" then
				local getSettingResultF = getSetting("COMBAT", "antiaim_yaw", 2)[1]

				if not Kefir.settingable_yaw[getSettingResultF] then
					paramMN:SetSize(0, 0)
				else
					paramMN:SetSize(paramMN._sizebtn[1], paramMN._sizebtn[2])
				end
			end
		end

		function createObjectResultA.DoClick(unusedParamX)
			if valueGK ~= nil and not runtimeApi.tIsEmpty(valueGK) then
				valueGJ(Kefir.unpack(valueGK))
			else
				valueGJ()
			end
		end

		local valueGN = valueGG[2] + 5

		if valueGL and not valueGC[11] then
			valueGN = 0
		end

		return valueGN
	end,
	keybindadd = function(unusedParamY, unusedParamZ)
		local createObjectResultB = Kefir.paint:CreateObject("color_picker")

		createObjectResultB:SetPos((screenWidth - 400) / 2, (screenHeight - 400) / 1.1)
		createObjectResultB:SetSize(400, 400)
		createObjectResultB:MakePopup()
		runtimeApi.tSimple(0.01, function()
			if IsValid(createObjectResultB) then
				function createObjectResultB.Think(paramMO)
					if not paramMO:HasFocus() or not IsValid(Kefir.menu) or Kefir.menu == nil then
						paramMO:Remove()
					end
				end
			end
		end)
	end,
	checkbox = function(paramMP, paramMQ, paramMR)
		if not Kefir:AllowedFeature(paramMQ.index) then
			return 0
		end

		local dataVar = paramMQ.data_var
		local menuScroll = paramMR or paramMP.menu_scroll
		local objectY = paramMQ.object_y
		local istableResult = istable(dataVar[5]) and dataVar[5] or {}

		runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.ofont.20")

		local valueGO, valueGP = runtimeApi.sGetTextSize(Kefir:GetLangText(dataVar[2]))
		local valueGQ = dataVar[7]
		local createObjectResultC = Kefir.paint:CreateObject("checkbox", menuScroll)

		createObjectResultC:SetPos(paramMQ.object_x, objectY)
		createObjectResultC:SetSize(valueGQ ~= nil and 190 or 235, 15)

		createObjectResultC._glow = 0
		createObjectResultC.adata = paramMQ
		createObjectResultC.__var = paramMQ.index
		createObjectResultC.__tab = paramMQ.current_
		createObjectResultC.__group = paramMQ.group
		createObjectResultC.__cachetext = dataVar[2]
		createObjectResultC.__widget = istableResult
		createObjectResultC.__hoveredtext = istableResult[3] or ""
		createObjectResultC.FAQ_INDEX = paramMQ.index

		function createObjectResultC.DoRightClick(unusedParamAA)
			return
		end

		local valueGR = istableResult[1] and istableResult[1] or 0
		local textBufferB = dataVar[6]

		if textBufferB ~= nil and istable(textBufferB) and not runtimeApi.tIsEmpty(textBufferB) then
			local valueGS = paramMQ.object_x + valueGR
			local valueGT = objectY
			local valueGU = valueGS + valueGO + 26

			for indexAE = 1, #textBufferB do
				local valueGV = textBufferB[indexAE]
				local createObjectResultD = Kefir.paint:CreateObject("color_selector", menuScroll)

				createObjectResultD:SetPos(valueGU, valueGT)
				createObjectResultD:SetSize(15, 15)
				createObjectResultD:PushVar(paramMQ.group)
				createObjectResultD:PushVar(paramMQ.index)
				createObjectResultD:PushVar(indexAE)
				createObjectResultD:SetVar(valueGV)

				valueGU = valueGU + 19
			end
		end

		if valueGQ ~= nil and valueGQ ~= "" then
			local entityRefL = runtimeApi.vCreate("DButton", menuScroll)

			entityRefL:SetPos(paramMQ.object_x + 192, objectY)
			entityRefL:SetSize(50, 15)
			entityRefL:SetText("")
			entityRefL:SetCursor("arrow")

			entityRefL.FAQ_INDEX = "X_keybind_button_X"
			entityRefL.var1 = {
				valueGQ,
				paramMQ.group
			}
			entityRefL.itemsList = {
				"Always On",
				"Toggle",
				"Hold",
				"Unhold",
				"On Shot"
			}

			function entityRefL.Paint(paramMS, unusedParamAB, unusedParamAC)
				local getSettingResultG = getSetting(Kefir.tabs.current, paramMS.var1[1], paramMS.var1[2])
				local valueGW = getSettingResultG[8]
				local valueGX = runtimeApi.supper(runtimeApi.GetKeyName(getSettingResultG[1]))

				if valueGW == "On Shot" then
					valueGX = Kefir:GetLangText("OS")
				end

				Kefir.paint:EOText(runtimeApi.sformat("[%s]", Kefir.hotkey_choosing[1][1] == paramMS.var1[1] and "..." or valueGX), 10, 0, 6, paramMS:IsHovered() and Kefir.color.keybindhov or Kefir.color.keybind, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals")
			end

			function entityRefL.DoClick(paramMT)
				Kefir.hotkey_choosing[1][1] = paramMT.var1[1]
				Kefir.hotkey_choosing[1][2] = Kefir.tabs.current
				Kefir.hotkey_choosing[1][3] = paramMT.var1[2]
			end

			function entityRefL.DoRightClick(paramMU)
				Kefir.drawlist.derma(paramMU, function(paramMV)
					runtimeApi.var[Kefir.tabs.current][paramMU.var1[2]][paramMU.var1[1]][8] = paramMV
				end, function(paramMW)
					return paramMW == runtimeApi.var[Kefir.tabs.current][paramMU.var1[2]][paramMU.var1[1]][8]
				end, "")
			end
		end

		return 20
	end,
	mcombobox = function(paramMX, paramMY, paramMZ)
		if not Kefir:AllowedFeature(paramMY.index) then
			return 0
		end

		local dataVarA = paramMY.data_var
		local valueGY = dataVarA[5]
		local valueGZ = dataVarA[6] or 0

		if not dataVarA[7] then
			local flagE = false
		end

		if not dataVarA[1] then
			return 0, nil
		end

		local entityRefM = runtimeApi.vCreate("DComboBox", paramMZ or paramMX.menu_scroll)

		entityRefM:SetPos(paramMY.object_x + valueGZ, paramMY.object_y)
		entityRefM:SetSize(100, 20)
		entityRefM:SetValue(dataVarA[2])

		entityRefM.itemsList = valueGY
		entityRefM.FAQ_INDEX = paramMY.index

		function entityRefM.PaintOver(unusedParamAD, paramNA, paramNB)
			local toJustidxResult = Kefir:to_justidx(runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1])
			local valueHA = ""
			local concatResult = Kefir:concat(toJustidxResult, ", ")

			runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.ofont.20")

			local valueHB, valueHC = runtimeApi.sGetTextSize(concatResult)
			local trimResult = Kefir:trim(concatResult, paramNA)

			Kefir.paint:Box(0, 0, paramNA, paramNB, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
			Kefir.paint:Text(trimResult, 18, paramNA / 2, 0, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end

		function entityRefM.OnSelect(paramNC, unusedParamAE, paramND)
			if paramNC.addfn then
				paramNC:addfn(paramND)
			end
		end

		function entityRefM.DoClick(paramNE)
			Kefir.drawlist.derma(paramNE, function(paramNF)
				runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1][paramNF] = not runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1][paramNF]

				if runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1][paramNF] == false then
					runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1][paramNF] = nil
				end
			end, function(paramNG)
				return runtimeApi.var[Kefir.tabs.current][paramMY.group][paramMY.index][1][paramNG] ~= nil
			end, paramMY.index)
		end

		local createObjectResultE = Kefir.paint:CreateObject("text", paramMZ or paramMX.menu_scroll)

		createObjectResultE:SetPos(paramMY.object_x + 105 + valueGZ, paramMY.object_y)
		createObjectResultE:SetSize(240, 20)

		createObjectResultE.__data = {
			dataVarA[2],
			20,
			runtimeApi.color.white,
			"ofont"
		}
		entityRefM._istext = createObjectResultE

		function entityRefM.OnRemove(paramNH)
			if IsValid(paramNH._istext) then
				paramNH._istext:Remove()
			end
		end

		return 22, entityRefM
	end,
	combobox = function(paramNI, paramNJ, paramNK)
		if not Kefir:AllowedFeature(paramNJ.index) then
			return 0
		end

		local valueHD = paramNJ.data_var[5]
		local dataVarB = paramNJ.data_var
		local valueHE = dataVarB[6] or 0
		local valueHF = dataVarB[7] or false

		if not dataVarB[1] then
			return 0, nil
		end

		local entityRefN = runtimeApi.vCreate("DComboBox", paramNK or paramNI.menu_scroll)

		entityRefN:SetPos(paramNJ.object_x + valueHE, paramNJ.object_y)
		entityRefN:SetSize(100, 20)
		entityRefN:SetValue(dataVarB[1])

		entityRefN.itemsList = valueHD
		entityRefN.FAQ_INDEX = paramNJ.index

		function entityRefN.PaintOver(paramNL, paramNM, paramNN)
			Kefir.paint:Box(0, 0, paramNM, paramNN, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
			Kefir.paint:Text(Kefir:GetLangText(paramNL:GetValue()), 20, paramNM / 2, 0, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end

		function entityRefN.OnSelect(paramNO, unusedParamAF, paramNP)
			if not valueHF then
				runtimeApi.var[Kefir.tabs.current][paramNJ.group][paramNJ.index][1] = paramNP
			end

			if paramNO.addfn then
				paramNO:addfn(paramNP)
			end
		end

		function entityRefN.DoClick(paramNQ)
			Kefir.drawlist.derma(paramNQ, nil, nil, paramNJ.index)
		end

		local createObjectResultF = Kefir.paint:CreateObject("text", paramNK or paramNI.menu_scroll)

		createObjectResultF:SetPos(paramNJ.object_x + 105 + valueHE, paramNJ.object_y)
		createObjectResultF:SetSize(240, 20)

		createObjectResultF.__data = {
			dataVarB[2],
			20,
			runtimeApi.color.white,
			"ofont"
		}
		entityRefN._istext = createObjectResultF

		function entityRefN.OnRemove(paramNR)
			if IsValid(paramNR._istext) then
				paramNR._istext:Remove()
			end
		end

		return 22, entityRefN
	end,
	slider = function(paramNS, paramNT, paramNU)
		if not Kefir:AllowedFeature(paramNT.index) then
			return 0
		end

		local valueHG = paramNT.data_var[5]
		local valueHH = paramNT.data_var[6] or 0
		local menuScrollA = paramNS.menu_scroll

		if paramNU then
			menuScrollA = paramNU
		end

		local valueHI = paramNU and 90 or 0
		local valueHJ = paramNU and 10 or 0
		local valueHK = paramNU and 4 or 0
		local createObjectResultG = Kefir.paint:CreateObject("slider", menuScrollA)

		createObjectResultG.wdata = valueHG
		createObjectResultG.adata = paramNT

		createObjectResultG:SetSize(100 + valueHI, 20 + valueHJ)
		createObjectResultG:PushVar(paramNT.group)
		createObjectResultG:PushVar(paramNT.index)
		createObjectResultG:SetPos(paramNT.object_x - 41.5 + valueHH, paramNT.object_y)
		createObjectResultG:SetMin(valueHG[1])
		createObjectResultG:SetMax(valueHG[2])
		createObjectResultG:SetDecimals(valueHG[3])
		createObjectResultG:SetText("")
		createObjectResultG:SetValue(getSetting(paramNT.current_, paramNT.index, paramNT.group)[1])

		createObjectResultG.FAQ_INDEX = paramNT.index
		createObjectResultG.col_text = valueHG[4] or runtimeApi.color.white
		createObjectResultG.sub2 = valueHG[5] or ""
		createObjectResultG.initialize = true
		createObjectResultG.a3 = 0
		createObjectResultG.a4 = 4
		createObjectResultG.a5 = 2
		createObjectResultG.__hoveredtext = valueHG[6] or ""

		local getChildrenResult = createObjectResultG:GetChildren()

		createObjectResultG:GetParent().__hoveredtext = valueHG[6] or ""
		createObjectResultG.Slider.__hoveredtext = valueHG[6] or ""
		createObjectResultG.Slider.Knob.__hoveredtext = valueHG[6] or ""
		createObjectResultG:GetParent().FAQ_INDEX = paramNT.index
		createObjectResultG.Slider.FAQ_INDEX = paramNT.index
		createObjectResultG.Slider.Knob.FAQ_INDEX = paramNT.index

		for indexAF = 1, #getChildrenResult do
			getChildrenResult[indexAF].__hoveredtext = valueHG[6] or ""
			getChildrenResult[indexAF].FAQ_INDEX = paramNT.index
		end

		createObjectResultG.Slider.__owner = createObjectResultG

		function createObjectResultG.Slider.Paint(paramNV, paramNW, paramNX)
			local getSettingResultH = getSetting(paramNT.current_, paramNV.__owner.adata.index, paramNV.__owner.adata.group)[1]
			local valueHL = paramNV.__owner.wdata[3] == 0 and runtimeApi.floor(getSettingResultH) or runtimeApi.math.Round(getSettingResultH, 1)
			local valueHM = (getSettingResultH - paramNV.__owner.wdata[1]) / (paramNV.__owner.wdata[2] - paramNV.__owner.wdata[1])
			local isEditingResult = paramNV:IsEditing()

			paramNV.a3 = Kefir:Lerp(Kefir.frametime() * 4.5, paramNV.a3 or 0, valueHM)

			Kefir.paint:Box(0, 0, paramNW, paramNX, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
			Kefir.paint:Box(3, isEditingResult and 4 or 2, (paramNW - 6) * paramNV.a3, paramNX - (isEditingResult and 8 or 4), false, isEditingResult and runtimeApi.color.groupbox or runtimeApi.color.kefir_red)

			local sub2A = paramNV.__owner.sub2

			if paramNV.__owner.sub2 ~= "" then
				valueHL = valueHL .. Kefir:GetLangText(sub2A)
				paramNW = paramNW + 4
			end

			Kefir.paint:Text(valueHL, 18, paramNW / 2, (paramNX - 18) / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end

		local createObjectResultH = Kefir.paint:CreateObject("text", menuScrollA)

		createObjectResultH:SetPos(paramNT.object_x + 65 + valueHH + valueHI, paramNT.object_y + valueHK)
		createObjectResultH:SetSize(240, 15)

		createObjectResultH.__data = {
			paramNT.data_var[2],
			16,
			valueHG[4] or runtimeApi.color.white,
			"ofont"
		}

		return 25
	end,
	keybind = function(paramNY, paramNZ, paramOA)
		if not Kefir:AllowedFeature(paramNZ.index) then
			return 0
		end

		local dataVarC = paramNZ.data_var
		local tableDataT = {
			60,
			20
		}
		local valueHN = dataVarC[5] or 0
		local valueHO = dataVarC[6] or {}
		local valueHP = dataVarC[7]
		local createObjectResultI = Kefir.paint:CreateObject("default_button", paramOA or paramNY.menu_scroll)

		createObjectResultI:SetPos(paramNZ.object_x + valueHN * 6.15, paramNZ.object_y - (not valueHP and valueHN or 0))
		createObjectResultI:SetSize(tableDataT[1], tableDataT[2])
		createObjectResultI:SetText("")

		local valueHQ = runtimeApi.supper(runtimeApi.GetKeyName(dataVarC[1]))

		createObjectResultI.apollon = {
			paramNZ.object_x + valueHN * 6.15,
			paramNZ.object_y - (not valueHP and valueHN or 0)
		}
		createObjectResultI.dep = valueHO
		createObjectResultI._text = valueHQ
		createObjectResultI._stdtext = valueHQ
		createObjectResultI._textsize = 16
		createObjectResultI._rounded = true
		createObjectResultI._maincolor = runtimeApi.color.kefir_black
		createObjectResultI._roundedcolor = runtimeApi.color.kefir_red
		createObjectResultI._sizebtn = tableDataT
		createObjectResultI._hotkeyvar = dataVarC[2]
		createObjectResultI._group = paramNZ.group
		createObjectResultI._indx = paramNZ.index

		function createObjectResultI.DoClick(paramOB)
			Kefir.hotkey_choosing[1][1] = paramOB._indx
			Kefir.hotkey_choosing[1][2] = paramNY.tabs.current
			Kefir.hotkey_choosing[1][3] = paramOB._group
		end

		function createObjectResultI.Think(paramOC)
			local valueHR = runtimeApi.GetKeyName(getSetting(paramNY.tabs.current, paramOC._indx, paramNZ.group)[1])

			if Kefir.hotkey_choosing[1][1] == paramOC._indx then
				valueHR = "PRESS"

				createObjectResultI:SetSize(40, paramOC._sizebtn[2])
			else
				createObjectResultI:SetSize(paramOC._sizebtn[1], paramOC._sizebtn[2])
			end

			createObjectResultI._text = runtimeApi.supper(valueHR)

			local valueHS
			local depA = paramOC.dep

			if depA and not runtimeApi.tIsEmpty(depA) then
				if getSetting(depA[1], depA[2], depA[3])[1] == depA[4] then
					paramOC:SetPos(Kefir.unpack(paramOC.apollon))
				else
					paramOC:SetPos(131313, 0)
				end
			end
		end

		local createObjectResultJ = Kefir.paint:CreateObject("text", paramOA or paramNY.menu_scroll)

		createObjectResultJ:SetPos(paramNZ.object_x + valueHN * 6.15 + (createObjectResultI:GetWide() + 3), paramNZ.object_y - (not valueHP and valueHN or 0))
		createObjectResultJ:SetSize(240, 20)

		createObjectResultJ.widget2 = dataVarC[2]
		createObjectResultJ.dep = valueHO
		createObjectResultJ.indx = paramNZ.index
		createObjectResultJ.apollon = {
			paramNZ.object_x + valueHN * 6.15 + (createObjectResultI:GetWide() + 3),
			paramNZ.object_y - (not valueHP and valueHN or 0)
		}

		function createObjectResultJ.Think(paramOD)
			local valueHT
			local depB = paramOD.dep

			paramOD.__data = {
				paramOD.widget2,
				20,
				runtimeApi.color.white,
				"ofont"
			}

			if depB and not runtimeApi.tIsEmpty(depB) then
				if getSetting(depB[1], depB[2], depB[3])[1] == depB[4] then
					paramOD:SetPos(Kefir.unpack(paramOD.apollon))
				else
					paramOD:SetPos(131313, 0)
				end
			end
		end

		return tableDataT[2] + 5
	end,
	esp = {
		box = {
			Corner = function(paramOE, paramOF, paramOG, paramOH, paramOI, paramOJ, paramOK, paramOL, unusedParamAG)
				lineOutlinedFn(Kefir.paint, paramOG, paramOH, paramOE + paramOI * 0.7, paramOH, paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOE, paramOH, paramOE + paramOI * 0.3, paramOH, paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOG, paramOH, paramOG, paramOF + paramOJ * nativeApi.util_calcWeekend(0.0011432926829268), paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOG, paramOF, paramOG, paramOF + paramOJ * 0.25, paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOE, paramOF, paramOG - paramOI * 0.7, paramOF, paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOG, paramOF, paramOG - paramOI * 0.3, paramOF, paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOE, paramOF, paramOE, paramOH - paramOJ * nativeApi.util_calcWeekend(0.0011432926829268), paramOK, 1, paramOL)
				lineOutlinedFn(Kefir.paint, paramOE, paramOH, paramOE, paramOH - paramOJ * 0.25, paramOK, 1, paramOL)
			end,
			Default = function(paramOM, paramON, unusedParamAH, unusedParamAI, paramOO, paramOP, paramOQ, paramOR, unusedParamAJ)
				localCache.setDrawColor(paramOR)
				localCache.drawOutlinedRect(paramOM - 1, paramON - 1, paramOO + 2, paramOP + 2, 3)
				localCache.setDrawColor(paramOQ)
				localCache.drawOutlinedRect(paramOM, paramON, paramOO, paramOP, 1)
			end,
			Rounded = function(paramOS, paramOT, unusedParamAK, unusedParamAL, paramOU, paramOV, paramOW, paramOX, paramOY, paramOZ, paramPA, paramPB)
				paramPA = tableDataA[27] or 4
				paramOZ = tableDataA[28] or 8

				local isRagdollResult = (paramOY:IsRagdoll() or paramPB) and 8 or 1.9
				local valueHU = runtimeApi.floor(localCache.mathMin(paramOZ, paramOU / isRagdollResult))

				if valueHU < 2 then
					valueHU = 0
				end

				Kefir.paint:CornerOutline(paramOS - 1, paramOT - 1, paramOU + 2, paramOV + 2, valueHU, paramOX, 1, paramPA, false)
				Kefir.paint:CornerOutline(paramOS + 1, paramOT + 1, paramOU - 2, paramOV - 2, valueHU, paramOX, 1, paramPA, false)
				Kefir.paint:CornerOutline(paramOS, paramOT, paramOU, paramOV, valueHU, paramOW, 1, paramPA, false)
			end,
			["Rounded Corner"] = function(paramPC, paramPD, unusedParamAM, unusedParamAN, paramPE, paramPF, paramPG, paramPH, paramPI, paramPJ, paramPK, paramPL)
				paramPK = tableDataA[27] or 4
				paramPJ = tableDataA[28] or 8

				local isRagdollResultA = (paramPI:IsRagdoll() or paramPL) and 3.3 or 2
				local valueHV = runtimeApi.floor(localCache.mathMin(paramPJ, paramPE / isRagdollResultA))

				Kefir.paint:CornerOutline(paramPC - 1, paramPD - 1, paramPE + 2, paramPF + 2, valueHV, paramPH, 1, paramPK, true)
				Kefir.paint:CornerOutline(paramPC + 1, paramPD + 1, paramPE - 2, paramPF - 2, valueHV, paramPH, 1, paramPK, true)
				Kefir.paint:CornerOutline(paramPC, paramPD, paramPE, paramPF, valueHV, paramPG, 1, paramPK, true)
			end
		},
		entitybox = function(paramPM, paramPN, paramPO, paramPP, paramPQ, paramPR)
			local valueHW = tableDataA[34]

			if not istable(valueHW) or not valueHW[1] then
				return
			end

			local valueHX = tableDataA[44]
			local valueHY = valueHW[6][1]
			local kefirBlackB = runtimeApi.color.kefir_black
			local hColorAlphaResultD = Kefir.paint:HColorAlpha(valueHY, paramPQ)
			local hColorAlphaResultE = Kefir.paint:HColorAlpha(kefirBlackB, paramPQ)
			local valueHZ = paramPO - paramPM
			local valueIA = paramPP - paramPN

			Kefir.drawlist.esp.box[valueHX](paramPM, paramPN, paramPO, paramPP, valueHZ, valueIA, hColorAlphaResultD, hColorAlphaResultE, paramPR, 4, 8, true)
		end,
		entitymain = function(paramPS, paramPT, paramPU, paramPV, paramPW, paramPX, paramPY, paramPZ, paramQA)
			local valueIB = (paramPS + paramPU) / 2
			local valueIC = paramPT - 9
			local valueID = paramPV + 7
			local numberValueT = 0
			local numberValueU = 0
			local valueIE = tableDataA[35]
			local valueIF = tableDataA[36]
			local valueIG = tableDataA[46]

			if valueIE[1] then
				Kefir.paint:EOText(paramPX.PrintName or "unknown", 12, valueIB, valueIC - numberValueT, Kefir.paint:HColorAlpha(valueIE[6][1], paramPW), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "visuals", paramPW)

				numberValueT = numberValueT + 12
			end

			if valueIF[1] then
				Kefir.paint:EOText(paramPY, 12, valueIB, valueIC - numberValueT, Kefir.paint:HColorAlpha(valueIF[6][1], paramPW), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "visuals", paramPW)

				local valueIH = numberValueT + 12
			end

			if valueIG[1] then
				local valueII = tableDataA[47] and paramQA or valueIG[6][1]

				Kefir.paint:EOText(Kefir:GetLangText(paramPZ), 12, valueIB, valueID + numberValueU, Kefir.paint:HColorAlpha(valueII, paramPW), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "visuals", paramPW)

				local valueIJ = numberValueU + 12
			end
		end,
		playerbox = function(paramQB, paramQC, paramQD, paramQE, paramQF, paramQG)
			Kefir.drawlist.pElements[0] = 0
			Kefir.drawlist.pElements[1] = 0
			Kefir.drawlist.pElements[2] = 0
			Kefir.drawlist.pElements[3] = 0

			local valueIK = tableDataA[25] or getSetting("VISUALS", "box", 1)

			if not istable(valueIK) or not valueIK[1] then
				return
			end

			local valueIL = tableDataA[26] or getSetting("VISUALS", "box_type", 1)[1]
			local valueIM = valueIK[6][1]
			local kefirBlackC = runtimeApi.color.kefir_black
			local hColorAlphaResultF = Kefir.paint:HColorAlpha(valueIM, paramQF)
			local hColorAlphaResultG = Kefir.paint:HColorAlpha(kefirBlackC, paramQF)
			local valueIN = paramQD - paramQB
			local valueIO = paramQE - paramQC

			Kefir.drawlist.esp.box[valueIL](paramQB, paramQC, paramQD, paramQE, valueIN, valueIO, hColorAlphaResultF, hColorAlphaResultG, paramQG, tableDataA[28] or getSetting("VISUALS", "box_rounding", 1)[1], tableDataA[27] or getSetting("VISUALS", "box_roundint", 1)[1])
		end,
		playerhp = function(paramQH, paramQI, unusedParamAO, paramQJ, paramQK, paramQL, paramQM, paramQN, entityRefO)
			paramQK = runtimeApi.clamp(paramQK, 0, paramQL)
			paramQN = 12

			local valueIP = tableDataA[1] or getSetting("VISUALS", "hp_bartype", 1)[1]
			local valueIQ = tableDataA[2] or getSetting("VISUALS", "hp_barwidth", 1)[1]
			local valueIR = tableDataA[3] or getSetting("VISUALS", "hp_bar", 1)

			if not istable(valueIR) or not IsValid(entityRefO) and not istable(entityRefO) then
				return
			end

			if valueIR[1] then
				local hpColors = valueIR[6] or {}
				local colorValueA = hpColors[3] or color_white
				local colorValueB = hpColors[2] or color_white
				local valueIS = hpColors[1] or color_white
				local valueIT = paramQH - (valueIQ + 1.5)
				local valueIU = paramQJ - paramQI - 1
				local valueIV = paramQK / paramQL

				if valueIP == "Static" then
					local valueIW = runtimeApi.Lerp(1 - valueIV, colorValueB.r, colorValueA.r)
					local valueIX = runtimeApi.Lerp(1 - valueIV, colorValueB.g, colorValueA.g)
					local valueIY = runtimeApi.Lerp(1 - valueIV, colorValueB.b, colorValueA.b)

					gradientFn(Kefir.paint, valueIT, paramQI, valueIQ, valueIV * valueIU, Color(valueIW, valueIX, valueIY, paramQM), Color(valueIW, valueIX, valueIY, paramQM))
				elseif valueIP == "Gradient" then
					gradientFn(Kefir.paint, valueIT, paramQI, valueIQ, valueIV * valueIU, Kefir.paint:HColorAlpha(colorValueB, paramQM), Kefir.paint:HColorAlpha(colorValueA, paramQM))
				end

				localCache.setDrawColor(0, 0, 0, paramQM)
				localCache.drawOutlinedRect(valueIT, paramQI, valueIQ, valueIU)

				valueFF[entityRefO] = runtimeApi.floor(Kefir:Lerp(0.7, valueFF[entityRefO] or paramQK, paramQK))

				Kefir.paint:EOText((valueFF[entityRefO] or paramQK) .. "%", paramQN, paramQH - 5 - valueIQ, paramQI - 5, Kefir.paint:HColorAlpha(valueIS, paramQM), TEXT_ALIGN_RIGHT, TEXT_ALIGN_RIGHT, 1, "visuals", paramQM)
			end
		end,
		flag = function(paramQO, paramQP, paramQQ, paramQR, paramQS, unusedParamAP, paramQT, paramQU, paramQV, paramQW, paramQX)
			local valueIZ = paramQU
			local valueJA = paramQT

			if paramQQ == 1 or paramQQ == 2 then
				valueIZ = paramQU + paramQW(paramQQ)
			elseif paramQQ == 0 then
				valueIZ = paramQU - paramQW(paramQQ)
			elseif paramQQ == 3 then
				valueIZ = paramQU + paramQW(paramQQ)
			end

			paramQP = runtimeApi.floor(paramQP)

			Kefir.paint:EOText(paramQO, paramQP, valueJA, valueIZ, Kefir.paint:HColorAlpha(paramQR, paramQS), paramQX[1], paramQX[2], 0.45, "flag", paramQS)
			paramQV(paramQQ, paramQP - 2)
		end,

		playerskeleton = function(unusedParamAP0, unusedParamAP1, unusedParamAP2, unusedParamAP3, paramQX, entityRefAP)
			local valueJA = tableDataA[50]

			if not valueJA[1] then
				return
			end

			if not IsValid(entityRefAP) then
				return
			end

			entityRefAP:SetupBones()

			local getSettingResultV0 = getSetting("COMBAT", "calcpos", 3)[1]
			local colorValueSK = Kefir.paint:HColorAlpha(valueJA[6][1], paramQX)
			local activebonesD = Kefir.activebones
			local tableDataSK = {}

			for indexSK = 1, #activebonesD do
				local valueSK = activebonesD[indexSK]
				local getCacheBoneResultSK = Kefir:getCacheBone(entityRefAP, "ValveBiped.Bip01_" .. valueSK)

				if getCacheBoneResultSK then
					local getPositionBoneResultSK = Kefir:getPositionBone(entityRefAP, getCacheBoneResultSK, getSettingResultV0)

					if getPositionBoneResultSK then
						local toScreenResultSK = getPositionBoneResultSK:ToScreen()

						if toScreenResultSK.visible then
							tableDataSK[valueSK] = toScreenResultSK
						end
					end
				end
			end

			local skeletonlinksA = Kefir.skeletonlinks

			for indexSL = 1, #skeletonlinksA do
				local valueSL = skeletonlinksA[indexSL]
				local valueSM = tableDataSK[valueSL[1]]
				local valueSN = tableDataSK[valueSL[2]]

				if valueSM and valueSN then
					Kefir.paint:LineOutlined(valueSM.x, valueSM.y, valueSN.x, valueSN.y, colorValueSK, 1)
				end
			end
		end,
		playereyetrace = function(unusedParamAQ, unusedParamAR, unusedParamAS, unusedParamAT, paramQY, paramQZ)
			local valueJB = tableDataA[51]

			if not valueJB[1] then
				return
			end

			local getAttachmentResult = paramQZ:GetAttachment(paramQZ:LookupAttachment("eyes"))
			local posA = getAttachmentResult.Pos
			local valueJC = runtimeApi.traceline({
				start = posA,
				endpos = posA + getAttachmentResult.Ang:Forward() * 56352,
				filter = paramQZ
			})

			if not valueJC.Hit then
				return
			end

			local toScreenResult = valueJC.StartPos:ToScreen()
			local toScreenResultA = valueJC.HitPos:ToScreen()

			Kefir.paint:LineOutlined(toScreenResult.x, toScreenResult.y, toScreenResultA.x, toScreenResultA.y, Kefir.paint:HColorAlpha(valueJB[6][1], paramQY), 1)
		end,
		playerweapon = function(paramRA, paramRB, paramRC, paramRD, paramRE, unusedParamAU, paramRF, paramRG)
			if not tableDataA[56] then
				return 0, 0, 0, 0, false
			end

			local tableDataU = {
				TEXT_ALIGN_LEFT,
				TEXT_ALIGN_CENTER
			}
			local numberValueV = 0
			local numberValueW = 0
			local playerweaponA = runtimeApi.var.ESPINTERACTIVE.data.playerweapon
			local elAA = Kefir.drawlist.elA
			local elGFn = Kefir.drawlist.elG
			local valueJD = playerweaponA[1]
			local valueJE = (paramRA + paramRC) / 2
			local valueJF = runtimeApi.floor(playerweaponA[6]) or 10

			if valueJD == 0 then
				numberValueV, numberValueW = valueJE, paramRB - elGFn(valueJD) - (9 + valueJF / 5) - 5
			elseif valueJD == 1 then
				numberValueV, numberValueW = paramRC + 6 + Kefir.RIGHT_PANEL[1], paramRB + elGFn(valueJD) + 2 + Kefir.RIGHT_PANEL[2] + 5
			elseif valueJD == 2 then
				numberValueV, numberValueW = paramRA - 8 + Kefir.LEFT_PANEL[1], paramRB + elGFn(valueJD) + Kefir.LEFT_PANEL[2] + 5
			elseif valueJD == 3 then
				numberValueV, numberValueW = valueJE, paramRD + elGFn(valueJD) + 15
			end

			tableDataU[1] = valueJD == 1 and TEXT_ALIGN_LEFT or valueJD == 2 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_CENTER
			tableDataU[2] = valueJD == 3 and TEXT_ALIGN_BOTTOM or valueJD == 0 and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER

			if paramRF then
				local numberValueX = 0

				for indexAG = #paramRG, 1, -1 do
					local entityRefP = paramRG[indexAG]
					local getPrintNameResult = entityRefP.PrintName and entityRefP.PrintName or entityRefP:GetPrintName()
					local valueJG = ""
					local valueJH = color_white
					local valueJI = getPrintNameResult
					local valueJJ = color_white
					local valueJK = tableDataA[57]
					local valueJL = tableDataA[58]

					if valueJK or valueJL then
						local valueJM, valueJN = Kefir:GetEntityType(entityRefP, entityRefP:GetClass())

						if valueJL then
							valueJI = runtimeApi.sformat("%s [%s]", getPrintNameResult, valueJM)
						end

						if valueJK then
							valueJH = valueJN
						end
					end

					local valueJO = valueJD == 0 and -numberValueX or numberValueX

					Kefir.paint:EOText(valueJI, 12, numberValueV, numberValueW + valueJO, Kefir.paint:HColorAlpha(valueJH, paramRE), tableDataU[1], tableDataU[2], 1, "visuals", paramRE)

					numberValueX = numberValueX + 13
				end
			else
				Kefir.paint:EOText("Inventory", 12, numberValueV, numberValueW, Kefir.paint:HColorAlpha(color_white, paramRE), tableDataU[1], tableDataU[2], 1, "visuals", paramRE)

				local numberValueY = 50
				local numberValueZ = 15
				local valueJP = numberValueV
				local valueJQ = numberValueW

				if tableDataU[1] == TEXT_ALIGN_RIGHT then
					valueJP = numberValueV - numberValueY / 2
					valueJQ = numberValueW + numberValueZ / 4
				elseif tableDataU[1] == TEXT_ALIGN_LEFT then
					valueJP = numberValueV + numberValueY / 2
					valueJQ = numberValueW + numberValueZ / 4
				end

				if tableDataU[2] == TEXT_ALIGN_BOTTOM then
					valueJP = numberValueV
					valueJQ = numberValueW - numberValueZ / 4
				elseif tableDataU[2] == TEXT_ALIGN_TOP then
					valueJP = numberValueV
					valueJQ = numberValueW + numberValueZ / 2
				end

				return valueJP, valueJQ, 50, 15, true
			end
		end,
		playerflags = function(paramRH, paramRI, paramRJ, paramRK, paramRL, paramRM, unusedParamAV, playerRef, paramRN)
			local flagF = false
			local playerflagsA = runtimeApi.var.ESPINTERACTIVE.data.playerflags
			local valueJR = playerflagsA[1]
			local elAB = Kefir.drawlist.elA
			local elGFnA = Kefir.drawlist.elG
			local flagFn = Kefir.drawlist.esp.flag
			local valueJS = paramRJ - paramRH
			local valueJT = paramRK - paramRI
			local numberValueAA = 0
			local numberValueAB = 0
			local numberValueAC = 1
			local tableDataV = {
				TEXT_ALIGN_LEFT,
				TEXT_ALIGN_CENTER
			}
			local valueJU = (paramRH + paramRJ) / 2
			local numberValueAD = 0
			local numberValueAE = 0
			local numberValueAF = -11.5
			local valueJV = tableDataA[4] or ""
			local valueJW = tableDataA[5] or 0
			local valueJX = tableDataA[6] or getSetting("VISUALS", "flag_pulse", 1) or {}
			local flagPulseColors = valueJX[6] or {}
			local valueJY = paramRM and paramRM or col.a and col.a or 255

			if not valueJX[1] then
				local flagG = false
			end

			local valueJZ = flagPulseColors[3] or color_white
			local valueKA = flagPulseColors[2] or color_white
			local valueKB = paramRJ + valueJW * 0.5
			local valueKC = runtimeApi.floor(playerflagsA[6]) or 10

			if elGFnA(valueJR) > 0 then
				local numberValueAG = 0
			end

			if valueJR == 0 then
				numberValueAD, numberValueAE = valueJU, paramRI + elGFnA(valueJR) - (9 + valueKC / 5)
			elseif valueJR == 1 then
				numberValueAD, numberValueAE = paramRJ + 6 + Kefir.RIGHT_PANEL[1], paramRI + elGFnA(valueJR) + 2 + Kefir.RIGHT_PANEL[2]
			elseif valueJR == 2 then
				numberValueAD, numberValueAE = paramRH - 8 + Kefir.LEFT_PANEL[1], paramRI + elGFnA(valueJR) + 2 + Kefir.LEFT_PANEL[2]
			elseif valueJR == 3 then
				numberValueAD, numberValueAE = valueJU, paramRK + elGFnA(valueJR) + 10
			end

			tableDataV[1] = valueJR == 1 and TEXT_ALIGN_LEFT or valueJR == 2 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_CENTER
			tableDataV[2] = valueJR == 3 and TEXT_ALIGN_BOTTOM or valueJR == 0 and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER
			paramRL = paramRL or {}

			if valueJX[1] then
				flagF = true

				local colorValueC = valueJZ
				local colorValueD = valueKA
				local valueKD = paramRK - paramRI - 1
				local valueKE = (paramRL.pulse or 0) / 135
				local valueKF = runtimeApi.clamp(valueKE or 0, 0, 1)
				local whiteD = runtimeApi.color.white

				if valueJV == "Static" then
					local valueKG = runtimeApi.Lerp(1 - valueKF, colorValueD.r, colorValueC.r)
					local valueKH = runtimeApi.Lerp(1 - valueKF, colorValueD.g, colorValueC.g)
					local valueKI = runtimeApi.Lerp(1 - valueKF, colorValueD.b, colorValueC.b)

					gradientFn(Kefir.paint, valueKB, paramRI, valueJW, valueKF * valueKD, Color(valueKG, valueKH, valueKI, paramRM), Color(valueKG, valueKH, valueKI, paramRM))
				elseif valueJV == "Gradient" then
					gradientFn(Kefir.paint, valueKB, paramRI, valueJW, valueKF * valueKD, Kefir.paint:HColorAlpha(colorValueD, paramRM), Kefir.paint:HColorAlpha(colorValueC, paramRM))
				end

				localCache.setDrawColor(0, 0, 0, paramRM)
				localCache.drawOutlinedRect(valueKB, paramRI, valueJW, valueKD)
				Kefir.paint:EOText(runtimeApi.floor(paramRL.pulse or 0), 12, valueKB + valueJW * 1.15, paramRI, Kefir.paint:HColorAlpha(flagPulseColors[1] or color_white, paramRM), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals", paramRM)
			end

			local previewPlyA = playerRef == Kefir.previewPly
			local istableResultA = istable(playerRef)
			local valueKJ = Kefir.traitors[playerRef]
			local valueKK = Kefir.gunmans[playerRef]
			local valueKL = Kefir.hasfirearm[playerRef]
			local valueKM = Kefir.hasmelee[playerRef]
			local getCharacterResult = Kefir.aimtarget == Kefir:getCharacter(playerRef) or previewPlyA
			local valueKN = runtimeApi.stime() % 2

			if previewPlyA then
				if valueKN < 1 then
					valueKK = true
					valueKJ = false
				else
					valueKK = false
					valueKJ = true
				end
			end

			if tableDataA[11] or tableDataA[12] then
				flagF = true

				for keyAK, itemAH in Kefir.pairs(tableDataR) do
					if getSetting("VISUALS", "flag_" .. keyAK, 1)[1] and paramRL[keyAK] ~= nil then
						local valueKO = itemAH[1]

						if itemAH[4] then
							valueKO = runtimeApi.sformat(valueKO, paramRL[keyAK])
						end

						if paramRL[keyAK] == itemAH[3] then
							local valueKP = keyAK == "lungsfunction" and runtimeApi.random(-numberValueAC, numberValueAC) or 0
							local valueKQ = keyAK == "lungsfunction" and runtimeApi.random(-numberValueAC, numberValueAC) or 0
							local valueKR = itemAH[2]

							flagFn(Kefir:GetLangText(valueKO), valueKC, valueJR, valueKR, paramRM, valueJY, numberValueAD + valueKP, numberValueAE + valueKQ, elAB, elGFnA, tableDataV)
						end
					end
				end
			end

			if tableDataA[54] then
				flagF = true

				local pingResult = istableResultA and "67" or playerRef:Ping()
				local pingA = runtimeApi.color.ping

				flagFn(Kefir:GetLangText("PING %d"):format(pingResult), valueKC, valueJR, pingA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[55] then
				flagF = true

				local getNetVarResult = istableResultA and "100" or isfunction(playerRef.GetNetVar) and playerRef:GetNetVar("Karma", 100) or "?"
				local karmaA = runtimeApi.color.karma

				flagFn(Kefir:GetLangText("KARMA %d"):format(getNetVarResult), valueKC, valueJR, karmaA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[53] and isfunction(playerRef.GetTeamStatus) then
				flagF = true

				local valueKS, valueKT = playerRef:GetTeamStatus()
				local isfunctionResult = isfunction(L) and L(valueKS) or valueKS

				flagFn(isfunctionResult, valueKC, valueJR, valueKT or color_white, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[52] and isfunction(playerRef.Team) then
				flagF = true

				local teamResult = playerRef:Team()
				local valueKU = runtimeApi.teamGetName(teamResult) or "HOMICIDERS"
				local valueKV = runtimeApi.teamGetColor(teamResult) or color_white

				flagFn(valueKU, valueKC, valueJR, valueKV or color_white, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[13] and (valueKJ or valueKK) then
				flagF = true

				local valueKW = valueKJ and "TRAITOR" or valueKK and "GUNMAN" or "IDK"
				local whiteE = valueKJ and runtimeApi.color.traitor or valueKK and runtimeApi.color.gunman or runtimeApi.color.white

				flagFn(Kefir:GetLangText(valueKW), valueKC, valueJR, whiteE, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[14] and valueKL then
				flagF = true

				local isScreengrabing = runtimeApi.color.is_screengrabing

				flagFn(Kefir:GetLangText("HAS FIREARM"), valueKC, valueJR, isScreengrabing, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[15] and valueKM then
				flagF = true

				local isMelee = runtimeApi.color.is_melee

				flagFn(Kefir:GetLangText("HAS MELEE"), valueKC, valueJR, isMelee, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			local activeWeaponRef = istableResultA and playerRef:GetActiveWeapon() or paramRN
			if not IsValid(activeWeaponRef) then
				return
			end

			local isZoomResult = activeWeaponRef.IsZoom and activeWeaponRef:IsZoom() or false
			local reloadA = activeWeaponRef.reload

			if tableDataA[16] and reloadA ~= nil then
				flagF = true

				local valueKX = runtimeApi.floor(runtimeApi.stime() % 1.2 / 0.4)
				local valueKY = runtimeApi.string.rep(".", valueKX + 1)
				local reloadingA = runtimeApi.color.reloading
				local valueKZ = reloadA - runtimeApi.stime()
				local getLangTextResultF = runtimeApi.sformat("(%d " .. Kefir:GetLangText("s.) RELOADING") .. valueKY, valueKZ)

				flagFn(getLangTextResultF, valueKC, valueJR, reloadingA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[17] and isZoomResult then
				flagF = true

				local aimingA = runtimeApi.color.aiming

				flagFn(Kefir:GetLangText("AIMING"), valueKC, valueJR, aimingA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[18] and getCharacterResult then
				flagF = true

				local kefirGreen = runtimeApi.color.kefir_green

				flagFn(Kefir:GetLangText("TARGET"), valueKC, valueJR, kefirGreen, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if tableDataA[19] and (runtimeApi.HasValue(Kefir.friendlist, playerRef) or previewPlyA) then
				flagF = true

				local friendlusheA = runtimeApi.color.friendlushe

				flagFn(Kefir:GetLangText("FRIEND"), valueKC, valueJR, friendlusheA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			local valueLA = playerRef.PlayerClassName or "NONE"

			if tableDataA[20] and valueLA ~= nil and isstring(valueLA) then
				flagF = true

				local groupnameA = runtimeApi.color.groupname
				local valueLB = runtimeApi.Replace(runtimeApi.supper(valueLA), "_", "")
				local valueLC = runtimeApi.slower(valueLA)

				if Kefir.pclass_color[valueLC] then
					groupnameA = Kefir.pclass_color[valueLC]
				end

				if Kefir.pclass_transform[valueLC] then
					valueLB = Kefir.pclass_transform[valueLC]
				end

				flagFn(Kefir:GetLangText(valueLB), valueKC, valueJR, groupnameA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			local clip1Result = activeWeaponRef.Clip1 and activeWeaponRef:Clip1() or -1
			local getNetVarResultA = istableResultA and playerRef.Inventory or playerRef.GetNetVar and playerRef:GetNetVar("Inventory", {}) or {}
			local istableResultB = istable(getNetVarResultA.Weapons) and getNetVarResultA.Weapons or {}

			if tableDataA[21] and clip1Result > -1 then
				flagF = true

				local ammoA = runtimeApi.color.ammo
				local getLangTextResultG = clip1Result == 0 and Kefir:GetLangText("EMPTY") or clip1Result .. " / " .. activeWeaponRef:GetMaxClip1()

				flagFn("[" .. getLangTextResultG .. "] " .. Kefir:GetLangText("AMMO"), valueKC, valueJR, ammoA, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			local steamId = istableResultA and "YES1" or playerRef:SteamID()
			local valueLD = Kefir.users[steamId]

			if tableDataA[29] and (istableResultA or valueLD ~= nil) then
				local valueLE = tableDataA[30]
				local valueLF = tableDataA[31]
				local usergroupA = istableResultA and "admin" or valueLD.usergroup
				local usernameA = istableResultA and "sadsalat" or valueLD.username
				local groupnameB = runtimeApi.color.groupname
				local valueLG = tableDataV[1]
				local valueLH = valueLG == 0 and 6 or -6

				if valueLG == 1 then
					if valueLE then
						flagFn(usergroupA, valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
					end

					if valueLF then
						flagFn(usernameA, valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
					end

					flagFn(Kefir:GetLangText("USER"), valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
				else
					flagFn(Kefir:GetLangText("USER"), valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)

					if valueLE then
						flagFn(usergroupA, valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD + valueLH, numberValueAE, elAB, elGFnA, tableDataV)
					end

					if valueLF then
						flagFn(usernameA, valueKC, valueJR, groupnameB, paramRM, valueJY, numberValueAD + valueLH, numberValueAE, elAB, elGFnA, tableDataV)
					end
				end
			end

			if tableDataA[32] and (istableResultA or Kefir:InFake(playerRef)) then
				flagFn(Kefir:GetLangText("FAKING"), valueKC, valueJR, runtimeApi.color.faking, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
			end

			if not runtimeApi.tIsEmpty(getNetVarResultA) and getNetVarResultA.Weapons ~= nil then
				if tableDataA[22] and istableResultB.hg_flashlight then
					flagF = true

					flagFn(Kefir:GetLangText("FLASHLIGHT"), valueKC, valueJR, runtimeApi.color.flashlight, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
				end

				if tableDataA[23] and istableResultB.hg_sling then
					flagF = true

					flagFn(Kefir:GetLangText("SLING"), valueKC, valueJR, runtimeApi.color.sling, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
				end

				if tableDataA[24] and istableResultB.hg_brassknuckles then
					flagF = true

					flagFn(Kefir:GetLangText("BRASSKNUCKLES"), valueKC, valueJR, runtimeApi.color.white, paramRM, valueJY, numberValueAD, numberValueAE, elAB, elGFnA, tableDataV)
				end
			end

			local numberValueAH = 72
			local var2554Result = elGFnA(valueJR) + 6
			local valueLI = numberValueAD
			local valueLJ = numberValueAE

			if tableDataV[1] == TEXT_ALIGN_RIGHT then
				valueLI = numberValueAD - numberValueAH / 2
				valueLJ = numberValueAE - 10 + elGFnA(valueJR) / 2
			elseif tableDataV[1] == TEXT_ALIGN_LEFT then
				valueLI = numberValueAD - 10 + numberValueAH / 2
				valueLJ = numberValueAE - 10 + elGFnA(valueJR) / 2
			end

			if tableDataV[2] == TEXT_ALIGN_BOTTOM then
				valueLI = numberValueAD - 8
				valueLJ = numberValueAE - 15 + elGFnA(valueJR) / 2
			elseif tableDataV[2] == TEXT_ALIGN_TOP then
				valueLI = numberValueAD - 8
				valueLJ = numberValueAE + 5.5 - elGFnA(valueJR) / 2
			end

			return valueLI, valueLJ, numberValueAH, elGFnA(valueJR), flagF
		end,
		playername = function(paramRO, paramRP, paramRQ, paramRR, paramRS, paramRT, paramRU, unusedParamAW)
			local flagH = false
			local numberValueAI = 0
			local playernameA = runtimeApi.var.ESPINTERACTIVE.data.playername
			local valueLK = playernameA[1]
			local elGFnB = Kefir.drawlist.elG
			local elAFn = Kefir.drawlist.elA
			local valueLL = (paramRO + paramRQ) / 2
			local valueLM = tableDataA[7] or getSetting("VISUALS", "realnick", 1) or {}
			local valueLN = tableDataA[8] or getSetting("VISUALS", "appearancenick", 1) or {}
			local realNickColors = valueLM[6] or {}
			local appearanceNickColors = valueLN[6] or {}
			local numberValueAJ = 0
			local numberValueAK = 0
			local valueLO = TEXT_ALIGN_CENTER
			local valueLP = TEXT_ALIGN_CENTER

			if valueLK == 0 then
				numberValueAJ, numberValueAK = valueLL, paramRP - elGFnB(valueLK) - 3
			elseif valueLK == 1 then
				numberValueAJ, numberValueAK = paramRQ + 5 + Kefir.RIGHT_PANEL[1], paramRP + elGFnB(valueLK) + 2 + Kefir.RIGHT_PANEL[2]
			elseif valueLK == 2 then
				numberValueAJ, numberValueAK = paramRO - 5 + Kefir.LEFT_PANEL[1], paramRP + elGFnB(valueLK) + 2 + Kefir.LEFT_PANEL[2]
			elseif valueLK == 3 then
				numberValueAJ, numberValueAK = valueLL, paramRR + elGFnB(valueLK) + 1.5
			end

			local valueLQ = valueLK == 3 and TEXT_ALIGN_TOP or valueLK == 0 and TEXT_ALIGN_BOTTOM or TEXT_ALIGN_CENTER
			local valueLR = valueLK == 1 and TEXT_ALIGN_LEFT or valueLK == 2 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_CENTER
			local valueLS = runtimeApi.floor(playernameA[6]) or 12

			if valueLM[1] then
				Kefir.paint:EOText(paramRS, valueLS, numberValueAJ, numberValueAK, Kefir.paint:HColorAlpha(realNickColors[1] or color_white, paramRU), valueLR, valueLQ, 1, "visuals", paramRU)
				elAFn(valueLK, 9)

				numberValueAI = numberValueAI + 9
				flagH = true
			end

			if valueLK == 0 then
				numberValueAJ, numberValueAK = valueLL, paramRP - elGFnB(valueLK) - 3
			elseif valueLK == 1 then
				numberValueAJ, numberValueAK = paramRQ + 5 + Kefir.RIGHT_PANEL[1], paramRP + elGFnB(valueLK) + 2 + Kefir.RIGHT_PANEL[2]
			elseif valueLK == 2 then
				numberValueAJ, numberValueAK = paramRO - 5 + Kefir.LEFT_PANEL[1], paramRP + elGFnB(valueLK) + 2 + Kefir.LEFT_PANEL[2]
			elseif valueLK == 3 then
				numberValueAJ, numberValueAK = valueLL, paramRR + elGFnB(valueLK) + 1.5
			end

			if valueLN[1] then
				Kefir.paint:EOText(paramRT, valueLS, numberValueAJ, numberValueAK, Kefir.paint:HColorAlpha(appearanceNickColors[1] or color_white, paramRU), valueLR, valueLQ, 1, "visuals", paramRU)
				elAFn(valueLK, 9)

				numberValueAI = numberValueAI + 9
				flagH = true
			end

			local numberValueAL = 50
			local valueLT = numberValueAI + 6
			local valueLU = numberValueAJ
			local valueLV = numberValueAK

			if valueLR == TEXT_ALIGN_RIGHT then
				valueLU = numberValueAJ - numberValueAL / 2
				valueLV = numberValueAK + 5
			elseif valueLR == TEXT_ALIGN_LEFT then
				valueLU = numberValueAJ + numberValueAL / 2
				valueLV = numberValueAK + 5
			end

			if valueLQ == TEXT_ALIGN_BOTTOM then
				valueLV = numberValueAK + 10
			elseif valueLQ == TEXT_ALIGN_TOP then
				valueLV = numberValueAK + valueLT / 2
			end

			return valueLU, valueLV, numberValueAL, valueLT, flagH
		end,
		playerothers = function(paramRV, paramRW, paramRX, paramRY, paramRZ, paramSA, unusedParamAX)
			local flagI = false
			local numberValueAM = 0
			local playerothersA = runtimeApi.var.ESPINTERACTIVE.data.playerothers
			local valueLW = playerothersA[1]
			local elGFnC = Kefir.drawlist.elG
			local elAFnA = Kefir.drawlist.elA
			local valueLX = (paramRV + paramRX) / 2
			local numberValueAN = 0
			local numberValueAO = 0
			local valueLY = TEXT_ALIGN_CENTER
			local valueLZ = TEXT_ALIGN_CENTER

			if valueLW == 0 then
				numberValueAN, numberValueAO = valueLX, paramRW - elGFnC(valueLW) - 3
			elseif valueLW == 1 then
				numberValueAN, numberValueAO = paramRX + 5 + Kefir.RIGHT_PANEL[1], paramRW + elGFnC(valueLW) + 2 + Kefir.RIGHT_PANEL[2]
			elseif valueLW == 2 then
				numberValueAN, numberValueAO = paramRV - 5 + Kefir.LEFT_PANEL[1], paramRW + elGFnC(valueLW) + 2 + Kefir.LEFT_PANEL[2]
			elseif valueLW == 3 then
				numberValueAN, numberValueAO = valueLX, paramRY + elGFnC(valueLW) + 1.5
			end

			local valueMA = valueLW == 3 and TEXT_ALIGN_TOP or valueLW == 0 and TEXT_ALIGN_BOTTOM or TEXT_ALIGN_CENTER
			local valueMB = valueLW == 1 and TEXT_ALIGN_LEFT or valueLW == 2 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_CENTER
			local valueMC = tableDataA[9] or getSetting("VISUALS", "weapon", 1) or {}
			local valueMD = tableDataA[10] or getSetting("VISUALS", "usergroup", 1) or {}
			local weaponColors = valueMC[6] or {}
			local usergroupColors = valueMD[6] or {}
			local valueME = weaponColors[1] or color_white
			local valueMF = usergroupColors[1] or color_white
			local valueMG = paramRZ[1]
			local valueMH = paramRZ[2]
			local valueMI = runtimeApi.floor(playerothersA[6]) or 12

			if valueMD[1] then
				local valueMJ = valueMH or unknownText

				Kefir.paint:EOText(valueMJ, valueMI, numberValueAN, numberValueAO, Kefir.paint:HColorAlpha(valueMF, paramSA), valueMB, valueMA, 1, "visuals", paramSA)
				elAFnA(valueLW, 9)

				numberValueAM = numberValueAM + 9
				flagI = true
			end

			if valueLW == 0 then
				numberValueAN, numberValueAO = valueLX, paramRW - elGFnC(valueLW) - 3
			elseif valueLW == 1 then
				numberValueAN, numberValueAO = paramRX + 5 + Kefir.RIGHT_PANEL[1], paramRW + elGFnC(valueLW) + 2 + Kefir.RIGHT_PANEL[2]
			elseif valueLW == 2 then
				numberValueAN, numberValueAO = paramRV - 5 + Kefir.LEFT_PANEL[1], paramRW + elGFnC(valueLW) + 2 + Kefir.LEFT_PANEL[2]
			elseif valueLW == 3 then
				numberValueAN, numberValueAO = valueLX, paramRY + elGFnC(valueLW) + 1.5
			end

			if valueMC[1] and valueMG then
				local valueMK = valueMG.PrintName and valueMG.PrintName or unknownText

				Kefir.paint:EOText(valueMK, valueMI, numberValueAN, numberValueAO, Kefir.paint:HColorAlpha(valueME, paramSA), valueMB, valueMA, 1, "visuals", paramSA)
				elAFnA(valueLW, 9)

				numberValueAM = numberValueAM + 9
				flagI = true
			end

			local numberValueAP = 50
			local valueML = numberValueAM + 6
			local valueMM = numberValueAN
			local valueMN = numberValueAO

			if valueMB == TEXT_ALIGN_RIGHT then
				valueMM = numberValueAN - numberValueAP / 2
				valueMN = numberValueAO + 50
			elseif valueMB == TEXT_ALIGN_LEFT then
				valueMM = numberValueAN + numberValueAP / 2
				valueMN = numberValueAO + 50
			end

			if valueMA == TEXT_ALIGN_BOTTOM then
				valueMN = numberValueAO + 50
			elseif valueMA == TEXT_ALIGN_TOP then
				valueMN = numberValueAO + 50
			end

			return valueMM, valueMN, numberValueAP, valueML, flagI
		end
	}
}
Kefir.paint.__list = Kefir.drawlist

local tableDataW = {
	0,
	0
}

function Kefir.playerlistbutton(selfRefCC, paramSB, paramSC, paramSD)
	local createObjectResultK = Kefir.paint:CreateObject("default_button", paramSB)

	createObjectResultK:SetPos(paramSC[1][1], paramSC[1][2])
	createObjectResultK:SetSize(paramSC[2][1], paramSC[2][2])
	createObjectResultK:SetText("")

	createObjectResultK._text = paramSC[3]
	createObjectResultK._textsize = 16
	createObjectResultK._rounded = true
	createObjectResultK._maincolor = runtimeApi.color.kefir_black
	createObjectResultK._roundedcolor = runtimeApi.color.kefir_red
	createObjectResultK._sizebtn = paramSC[2]

	paramSD(createObjectResultK)

	tableDataW = {
		paramSC[1][1],
		paramSC[1][2]
	}

	return createObjectResultK
end

function Kefir.AttachmentMuzzle(selfRefCD, paramSE, paramSF, paramSG, paramSH)
	local tableDataX = {
		Pos = Vector(0, 0, 0),
		Ang = Angle(0, 0, 0)
	}
	local entityRefQ = paramSE

	if not IsValid(entityRefQ) then
		return tableDataX
	end

	local worldModelFake = paramSH.WorldModelFake
	local getAttachmentResultA = entityRefQ:GetAttachment(entityRefQ:LookupAttachment(worldModelFake and paramSH.FakeAttachment or "muzzle"))
	local getAttachmentResultB = getAttachmentResultA ~= nil and getAttachmentResultA or entityRefQ:GetAttachment(entityRefQ:LookupAttachment("muzzle_flash"))
	local attPosA = paramSH.attPos
	local attAngA = paramSH.attAng

	if not getAttachmentResultB then
		local anglesA = entityRefQ:GetAngles()
		local positionB = entityRefQ:GetPos()

		anglesA:RotateAroundAxis(anglesA:Forward(), 90)

		local valueMO, valueMP = LocalToWorld(ZERO_VECTOR, attAngA, ZERO_VECTOR, anglesA)

		positionB:Add(valueMP:Up() * attPosA[1] + valueMP:Right() * attPosA[2] + valueMP:Forward() * attPosA[3])

		if supressorAdd and selfRefCD:HasAttachment(paramSG, "barrel", "supressor") then
			positionB:Add(valueMP:Forward() * 10)
		end

		if worldModelFake then
			positionB, valueMP = LocalToWorld(paramSH.AttachmentPos, paramSH.AttachmentAng, positionB, valueMP)
		end

		tableDataX.Pos = positionB
		tableDataX.Ang = valueMP

		return tableDataX
	end

	if paramSF then
		local posB = getAttachmentResultB.Pos
		local angA = getAttachmentResultB.Ang

		if not attPosA or not attAngA then
			return
		end

		local valueMQ, valueMR = LocalToWorld(attPosA, attAngA, posB, angA)

		getAttachmentResultB.Pos = valueMQ
		getAttachmentResultB.Ang = valueMR

		valueMR:RotateAroundAxis(valueMR:Forward(), paramSH.rotatehuy or 0)

		if worldModelFake then
			valueMQ, valueMR = LocalToWorld(paramSH.AttachmentPos, paramSH.AttachmentAng, valueMQ, valueMR)
		end

		if supressorAdd and selfRefCD:HasAttachment(paramSG, "barrel", "supressor") then
			valueMQ:Add(valueMR:Forward() * 10)
		end
	end

	if worldModelFake then
		getAttachmentResultB.Pos, getAttachmentResultB.Ang = LocalToWorld(paramSH.AttachmentPos, paramSH.AttachmentAng, getAttachmentResultB.Pos, getAttachmentResultB.Ang)
	end

	return getAttachmentResultB
end

function Kefir.HasAttachment(selfRefCE, paramSI, paramSJ, paramSK)
	if paramSJ == "sight" and paramSK == "optic" then
		return true, false
	end

	if not paramSI then
		return false
	end

	local valueMS = paramSI[paramSJ]

	if not valueMS or runtimeApi.tIsEmpty(valueMS) then
		return false
	end

	if paramSK then
	end

	return valueMS and paramSI[paramSJ], valueMS and hg.attachments[paramSJ][paramSI[paramSJ][1]]
end

function Kefir.RenderAttachments(selfRefCF, paramSL, paramSM, paramSN)
	local entityRefR = paramSL
	local attachmentMuzzleResult = selfRefCF:AttachmentMuzzle(paramSL, true, paramSM, paramSN)

	if not attachmentMuzzleResult then
		return
	end

	local posC = attachmentMuzzleResult.Pos
	local angB = attachmentMuzzleResult.Ang
	local availableAttachmentsB = paramSN.availableAttachments

	if not IsValid(entityRefR) or not attachmentMuzzleResult then
		return
	end

	if paramSN.availableAttachments.mount and paramSN.availableAttachments.mount then
		if not paramSM then
			return
		end

		if paramSM.sight and paramSM.sight[1] ~= nil or paramSM.underbarrel and paramSM.underbarrel[1] ~= nil then
			local valueMT = hg.attachments.sight[paramSM.sight[1]] or hg.attachments.underbarrel[paramSM.underbarrel[1]]

			if valueMT then
				paramSM.mount = paramSN.availableAttachments.mount[valueMT.mountType]
			end
		end
	end

	paramSL.modelAtt = paramSL.modelAtt or {}

	local flagJ = false

	for keyAL, itemAI in Kefir.pairs(paramSM) do
		local valueMU = hg.attachments[keyAL][itemAI[1]]
		local hasAttachmentResult = selfRefCF:HasAttachment(paramSM, keyAL) and availableAttachmentsB[keyAL] and (availableAttachmentsB[keyAL][itemAI[1]] and istable(availableAttachmentsB[keyAL][itemAI[1]]) and availableAttachmentsB[keyAL][itemAI[1]][2] or istable(availableAttachmentsB[keyAL].removehuy) and availableAttachmentsB[keyAL].removehuy[valueMU.mountType] or availableAttachmentsB[keyAL].removehuy)

		if hasAttachmentResult then
			flagJ = true
		end

		if not hasAttachmentResult and not flagJ then
			hasAttachmentResult = itemAI[2]
		end

		if istable(hasAttachmentResult) and not table.IsEmpty(hasAttachmentResult) then
			for keyAM, itemAJ in Kefir.pairs(hasAttachmentResult) do
				if entityRefR:GetSubMaterial(keyAM) ~= (itemAJ or "null") then
					entityRefR:SetSubMaterial(keyAM, itemAJ or "null")
				end
			end
		end

		if selfRefCF:HasAttachment(paramSM, keyAL, itemAI[1]) and istable(valueMU) and valueMU[2] ~= nil then
			local entityRefS = paramSL.modelAtt[keyAL]

			if not IsValid(entityRefS) and valueMU[2] and valueMU[2] ~= "" then
				paramSL.modelAtt[keyAL] = ClientsideModel(valueMU[2])
				entityRefS = paramSL.modelAtt[keyAL]

				entityRefS:SetNoDraw(true)
			end

			if IsValid(entityRefS) then
				if valueMU[4] and not runtimeApi.tIsEmpty(valueMU[4]) then
					for keyAN, itemAK in Kefir.pairs(valueMU[4]) do
						local getSubMaterialResult = entityRefS:GetSubMaterial(keyAN)

						getSubMaterialResult = #getSubMaterialResult > 0 and getSubMaterialResult or entityRefS:GetMaterials()[keyAN]

						if getSubMaterialResult ~= (itemAK or "null") then
							entityRefS:SetSubMaterial(keyAN, itemAK or "null")
						end
					end
				end

				selfRefCF:transformAtt(paramSL, entityRefS, posC, angB, keyAL, itemAI, valueMU, availableAttachmentsB)
			end
		end
	end
end

function Kefir.transformAtt(selfRefCG, paramSO, paramSP, paramSQ, paramSR, paramSS, paramST, paramSU, paramSV)
	local vectorValueB = Vector(0, 0, 0)

	vectorValueB:Zero()

	if paramST[2] and Kefir.isvector(paramST[2]) then
		vectorValueB:Add(paramST[2])
	end

	if paramSV[paramSS] and paramSV[paramSS].mount and Kefir.isvector(paramSV[paramSS].mount) then
		vectorValueB:Add(paramSV[paramSS].mount)
	end

	if paramSV[paramSS] and istable(paramSV[paramSS].mount) and paramSV[paramSS].mount[paramSU.mountType] and Kefir.isvector(paramSV[paramSS].mount[paramSU.mountType]) then
		vectorValueB:Add(paramSV[paramSS].mount[paramSU.mountType])
	end

	if paramSU.offset and Kefir.isvector(paramSU.offset) then
		vectorValueB:Add(paramSU.offset)
	end

	local valueMV = paramSU[3] + (paramSV[paramSS] and (isangle(paramSV[paramSS].mountAngle) and paramSV[paramSS].mountAngle or istable(paramSV[paramSS].mountAngle) and paramSV[paramSS].mountAngle[paramSU.mountType] or ZERO_ANGLE) or ZERO_ANGLE)

	vectorValueB:Rotate(paramSR)
	vectorValueB:Add(paramSQ)

	local valueMW, valueMX = LocalToWorld(ZERO_VECTOR, valueMV, ZERO_VECTOR, paramSR)

	if paramSU.bBonemerge and not paramSP.bBonemerged then
		paramSP:SetParent(paramSO)
		paramSP:AddEffects(EF_BONEMERGE)

		paramSP.bBonemerged = true
	end

	if paramSU.fScale and not paramSP.bScaled then
		paramSP:SetModelScale(paramSU.fScale, 0)
	end

	paramSP:SetModel(paramSU[2])
	paramSP:SetRenderOrigin(vectorValueB)
	paramSP:SetRenderAngles(valueMX)
	paramSP:SetPos(vectorValueB)
	paramSP:SetAngles(valueMX)
	paramSP:SetupBones()
	localCache.setColorModulation(1, 1, 1)
	paramSP:DrawModel()
	localCache.setColorModulation(1, 1, 1)

	if paramSU.mount then
		if not IsValid(paramSO.modelAtt.mountex) then
			paramSO.modelAtt.mountex = ClientsideModel(paramSU.mount)

			paramSO.modelAtt.mountex:SetNoDraw(true)
		end

		local mountexA = paramSO.modelAtt.mountex
		local valueMY = ZERO_VECTOR

		valueMY:Set(paramSU.mountVec)
		valueMY:Rotate(paramSP:GetAngles())
		valueMY:Add(paramSP:GetPos())

		local valueMZ, valueNA = LocalToWorld(ZERO_VECTOR, paramSU.mountAng, ZERO_VECTOR, paramSP:GetAngles())

		mountexA:SetRenderOrigin(valueMY)
		mountexA:SetRenderAngles(valueNA)
		mountexA:SetPos(valueMY)
		mountexA:SetAngles(valueNA)
		mountexA:SetupBones()
		mountexA:DrawModel()
	end
end

function Kefir.ClearAttachmentModels(selfRefCH, paramSW)
	if not paramSW.attachmentModels then
		return
	end

	for keyAO, itemAL in Kefir.pairs(paramSW.attachmentModels) do
		if IsValid(itemAL) then
			itemAL:Remove()
		end
	end

	paramSW.attachmentModels = nil
end

local tableDataY = {
	weapon_tmp = Vector(30, 0, -1),
	weapon_flintlock = Vector(15, 0, 0),
	weapon_glock18c = Vector(15, 0, -1),
	weapon_px4beretta = Vector(40, 3, -3),
	weapon_sg552 = Vector(42, 0, 5),
	weapon_fn45 = Vector(30, 0, 0),
	weapon_ags_30_handheld = Vector(55, 0, 20),
	weapon_saiga12 = Vector(35, 0, 5),
	weapon_cz75 = Vector(35, 0, 1),
	weapon_pm9 = Vector(35, 0, -2),
	weapon_m98b = Vector(40, 0, 7),
	weapon_ak74 = Vector(55, 2, -3),
	weapon_hk_usp = Vector(20, 0, 1.5),
	weapon_p90 = Vector(30, 0, -6),
	weapon_m249 = Vector(60, 0, -5),
	weapon_revolver2 = Vector(30, 0, -2),
	weapon_spas12 = Vector(60, 0, -4),
	weapon_mac11 = Vector(50, 0, -5),
	weapon_svd = Vector(60, 0, -1),
	weapon_glock17 = Vector(30, 0, -3.5),
	weapon_deagle = Vector(30, 0, -3),
	weapon_kar98 = Vector(90, 2, 0),
	weapon_m1911 = Vector(40, 0, -3),
	weapon_ar_pistol = Vector(45, 0, -5),
	weapon_pkm = Vector(50, 0, -3),
	weapon_sr25 = Vector(30, 0, 0),
	weapon_remington870 = Vector(65, 4, -4)
}
local tableDataZ = {
	["models/weapons/arccw/c_ur_ak.mdl"] = Vector(55, -1, -4.5)
}
local numberValueAQ = 0
local aKM = "AKM"
local tableDataAA = {
	barrel = {},
	sight = {},
	mount = {},
	grip = {},
	underbarrel = {}
}
local tableDataAB = {
	supressor2 = "Silencerco Saker 556 ASR",
	holo9 = "Leapers \"UTG\"",
	laser4 = "TAC ANPEQ2",
	grip3 = "Magpul AFG Tactical Grip",
	laser5 = "AccuBow Laser",
	holo7 = "BelOMO PK-06",
	supressor1 = "PBS-1",
	optic5 = "Vortex Razor HD Gen.2 1-6x24",
	holo13 = "Valday Krechet",
	optic9 = "Trijicon \"ACOG TA01NSN 4x32\"",
	holo12 = "Valday PK-120",
	holo8 = "Holosun \"HS401G5\"",
	holo15 = "SIG Sauer \"ROMEO4\"",
	grip2 = "ASh-12 Vertical Grip",
	optic3 = "Валдай ПС-320 1x/6x",
	holo16 = "Trijicon \"RMR\"",
	laser3 = "Olight \"Baldr Pro\"",
	holo1 = "EOTech 552",
	supressor8 = "SilencerCo Hybrid 46",
	optic8 = "Leupold \"Mark 4 HAMR 4x24mm DeltaPoint\"",
	grip1_ak74 = "Grip Handle AK-74",
	grip_ak74 = "Standart Handle AK-74",
	supressor3 = "KAC HK USP-T",
	grip1 = "RK-2",
	optic2 = "Fullfield TAC 30",
	supressor7 = "SIG Sauer \"SRD762-QD\" 7.62x51",
	holo11 = "Trijicon\"SRS-02\"",
	holo3 = "ROMEO8T",
	supressor5 = "Ротор 43 12К",
	ironsight3 = "M4A1 Foreiron",
	ironsight1 = "MBUS backiron and foreiron",
	optic7 = "SIG Sauer \"BRAVO4 4X30\"",
	holo2 = "KOBRA ЭКП-8-18",
	holo5 = "\"ОКП-7\"",
	ironsight2 = "M4A1 Iron Sights",
	optic6 = "Leupold Mark 4 LR 6.5-20x50",
	supressor6 = "Homemade Suppressor",
	optic11 = "ПСО-1М2",
	holo4 = "Walther \"MRS\"",
	supressor4 = "Gemtech TUNDRA-SV 9mm Supressor",
	holo17 = "Aimpoint COMP M2",
	optic12 = "Sight for kar98k",
	mag1 = "Rounded mag Glock18 32 Bullets",
	optic4 = "ПСО-1",
	laser1 = "TBL Blue Laser",
	holo14 = "EOTech \"XPS3-0\"",
	laser2 = "Klesch Laser + Flashlight",
	holo6 = "\"ОКП-7\" Dovetail"
}
local numberValueAR = 190
local tableDataAC = {}

function Kefir.addComboBox(selfRefCI, paramSX, paramSY, paramSZ)
	if runtimeApi.tIsEmpty(paramSX) or #paramSX < 2 then
		return nil
	end

	local tableDataAD = {
		current_ = "ATTACHMENTS",
		group = 1,
		index = "",
		data_var = {
			paramSY[1],
			paramSY[2],
			nil,
			nil,
			paramSX,
			0,
			true
		},
		object_x = paramSZ[1],
		object_y = numberValueAR
	}
	local valueNB, valueNC = Kefir.drawlist.combobox(Kefir, tableDataAD)

	function valueNC.addfn(selfRefCJ, paramTA)
		local valueND

		valueND = (valueND ~= "none" and valueND ~= "empty" or nil) and {
			Kefir:reverseFind(tableDataAB, paramTA) or valueND
		}
		tableDataAA[runtimeApi.slower(paramSY[2])] = valueND
	end

	numberValueAR = numberValueAR + 24

	return valueNC
end

local tableDataAE = {
	supressor0 = true,
	optic0 = true,
	holo0 = true
}

function Kefir.getIndexAttachments(selfRefCK, paramTB, paramTC)
	local tableDataAF = {}

	if not hg then
		return
	end

	if not hg.attachments then
		return
	end

	if not hg.attachments[paramTB] then
		return {}
	end

	if paramTC[paramTB] == nil or not istable(paramTC[paramTB]) or runtimeApi.tIsEmpty(paramTC[paramTB]) then
		return {}
	end

	for keyAP, itemAM in Kefir.pairs(hg.attachments[paramTB]) do
		if not tableDataAE[keyAP] then
			if keyAP == "empty" then
				keyAP = "none"
				keyAP = tableDataAB[keyAP] or keyAP

				runtimeApi.insert(tableDataAF, keyAP)
			else
				local valueNE

				if paramTC[paramTB] then
					for keyAQ, itemAN in Kefir.pairs(paramTC[paramTB]) do
						valueNE = istable(itemAN) and itemAN[1] == keyAP and keyAQ or valueNE
					end
				end

				local mountTypeC = paramTC[paramTB] and paramTC[paramTB].mountType
				local mountTypeD = hg.attachments[paramTB][keyAP] and hg.attachments[paramTB][keyAP].mountType

				if not paramTC[paramTB] then
				elseif not paramTC[paramTB][valueNE] and not mountTypeC and not mountTypeD then
				elseif not (istable(mountTypeC) and runtimeApi.HasValue(mountTypeC, hg.attachments[paramTB][keyAP].mountType) or mountTypeC == mountTypeD) then
				else
					keyAP = tableDataAB[keyAP] or keyAP

					runtimeApi.insert(tableDataAF, keyAP)
				end
			end
		end
	end

	if not runtimeApi.HasValue(tableDataAF, "none") then
		runtimeApi.insert(tableDataAF, "none")
	end

	return tableDataAF
end

function Kefir.TrackMenu(selfRefCL, entityRefT, paramTD, paramTE)
	paramTD = paramTD or 0
	paramTE = paramTE or 0

	local menuA = Kefir.menu

	if IsValid(entityRefT) and entityRefT ~= nil and IsValid(menuA) and menuA ~= nil then
		local valueNF, valueNG = menuA:GetPos()

		entityRefT:SetPos(valueNF + paramTD, valueNG + paramTE)
	end
end

local function var28815Handler(paramTF, paramTG, unusedParamAY)
	local entityRefU = runtimeApi.vCreate("DFrame", paramTF)

	entityRefU:SetSize(800, 200)
	entityRefU:SetTitle("")
	entityRefU:SetPos((screenWidth - 800) / 2, (screenHeight - 200) / 1.1)
	entityRefU:MakePopup()
	entityRefU:SetVisible(false)
	entityRefU:ShowCloseButton(false)

	function entityRefU.Think(paramTH)
		Kefir:TrackMenu(paramTH, 0, 510)

		if Kefir.tabs.current ~= "ATTACHMENTS" or Kefir.menu == nil or not IsValid(Kefir.menu) then
			paramTH:Remove()
		end
	end

	function entityRefU.Paint(unusedParamAZ, paramTI, paramTJ)
		Kefir.paint:Gradient(0, -8, paramTI, paramTJ + 16, Kefir.paint:HColorAlpha(runtimeApi.color.black, 200), Kefir.paint:HColorAlpha(runtimeApi.color.groupname, 55), false, runtimeApi.material.gui_cg)
	end

	local valueNH = runtimeApi.vCreate("DScrollPanel", entityRefU)

	valueNH:Dock(FILL)

	valueNH:GetCanvas().OnMouseWheeled = function(unusedParamBA, unusedParamBB)
		return Kefir.drawlist.derma_opened
	end

	local numberValueAS = 10
	local numberValueAT = 10
	local numberValueAU = 120

	for keyAR, itemAO in Kefir.ipairs(paramTG) do
		local classByNameResult = runtimeApi.wpGet(Kefir:ClassByName(itemAO))

		if classByNameResult then
			local worldModelA = classByNameResult.WorldModel
			local entityRefV = runtimeApi.vCreate("DModelPanel", valueNH)

			entityRefV:SetPos(numberValueAS, numberValueAT)
			entityRefV:SetSize(100, 100)
			entityRefV:SetModel(worldModelA)
			entityRefV:SetFOV(30)

			entityRefV.wep = classByNameResult

			function entityRefV.LayoutEntity(selfRefCM, paramTK)
				if paramTK:GetModel() ~= worldModelA then
					selfRefCM:SetModel(worldModelA)
				end

				if not selfRefCM.wep.LocalMuzzlePos then
					return
				end

				local vectorValueC = Vector(10, 0, 0)
				local valueNI, valueNJ = paramTK:GetRenderBounds()
				local localMuzzlePos = selfRefCM.wep.LocalMuzzlePos

				vectorValueC[1] = (localMuzzlePos[1] + localMuzzlePos[2] + localMuzzlePos[3]) * 2

				local valueNK = tableDataY[selfRefCM.wep.ClassName]

				vectorValueC = valueNK ~= nil and valueNK or vectorValueC

				selfRefCM:SetLookAt(vectorValueC)
				selfRefCM:SetCamPos(vectorValueC - Vector(-12, 0, 0))
				paramTK:SetAngles(Angle(0, 5 * RealTime(), 0))
			end

			function entityRefV.PaintOver(paramTL, paramTM, paramTN)
				local valueNL = paramTL.wep.PrintName or unknownText

				if not paramTL.wep.LocalMuzzlePos then
					valueNL = unknownText
				end

				if paramTL:IsHovered() or valueNL == unknownText then
					Kefir.paint:Box(1, 1, paramTM - 2, paramTN - 2, false, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, 155))
					Kefir.paint:Text(valueNL, 16, paramTM / 2, paramTN / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
				end
			end

			function entityRefV.DoClick(paramTO)
				aKM = paramTO.wep.ClassName

				local tableDataAG = {
					barrel = {},
					sight = {},
					mount = {},
					grip = {},
					underbarrel = {}
				}

				if runtimeApi.var.ATTACHMENTS[1][aKM] ~= nil then
					tableDataAG = runtimeApi.var.ATTACHMENTS[1][aKM]
				end

				tableDataAA = tableDataAG

				local getIndexAttachmentsResult = Kefir:getIndexAttachments("sight", paramTO.wep.availableAttachments)
				local getIndexAttachmentsResultA = Kefir:getIndexAttachments("barrel", paramTO.wep.availableAttachments)
				local getIndexAttachmentsResultB = Kefir:getIndexAttachments("grip", paramTO.wep.availableAttachments)
				local getIndexAttachmentsResultC = Kefir:getIndexAttachments("underbarrel", paramTO.wep.availableAttachments)
				local valueNM = tableDataAA.sight and tableDataAA.sight[1] or "none"
				local valueNN = tableDataAA.barrel and tableDataAA.barrel[1] or "none"
				local valueNO = tableDataAA.grip and tableDataAA.grip[1] or "none"
				local valueNP = tableDataAA.underbarrel and tableDataAA.underbarrel[1] or "none"

				valueNM = tableDataAB[valueNM] or valueNM
				valueNN = tableDataAB[valueNN] or valueNN
				valueNO = tableDataAB[valueNO] or valueNO
				valueNP = tableDataAB[valueNP] or valueNP
				numberValueAR = 190

				for indexAH = 1, #tableDataAC do
					local entityRefW = tableDataAC[indexAH]

					if IsValid(entityRefW) and entityRefW ~= nil then
						entityRefW:Remove()
					end
				end

				tableDataAC[1] = Kefir:addComboBox(getIndexAttachmentsResult, {
					valueNM,
					"Sight"
				}, {
					12
				})
				tableDataAC[2] = Kefir:addComboBox(getIndexAttachmentsResultA, {
					valueNN,
					"Barrel"
				}, {
					12
				})
				tableDataAC[3] = Kefir:addComboBox(getIndexAttachmentsResultB, {
					valueNO,
					"Grip"
				}, {
					12
				})
				tableDataAC[4] = Kefir:addComboBox(getIndexAttachmentsResultC, {
					valueNP,
					"Underbarrel"
				}, {
					12
				})
				numberValueAQ = 5

				entityRefU:SetVisible(false)
			end

			numberValueAS = numberValueAS + numberValueAU

			if numberValueAS > 680 then
				numberValueAS = 10
				numberValueAT = numberValueAT + numberValueAU
			end
		end
	end

	return entityRefU
end

Kefir.chatinput = ""
Kefir.chatlog = {}
Kefir.missmessage = 0
Kefir.chatboxup = nil
Kefir.cloud_cooldown = 0
Kefir.cloud_status = ""
Kefir.cloud_status_color = Kefir.color.white

function runtimeApi.var.HOME.drawfunction(paramTP)
	Kefir.missmessage = 0

	function paramTP.Paint(unusedParamBC, unusedParamBD, paramTQ)
		local numberValueAV = 15
		local numberValueAW = 10

		Kefir.paint:Text("", 20, numberValueAV, numberValueAW, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(accountName, 16, numberValueAV + 22, numberValueAW + 2, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")

		local valueNQ = numberValueAW + 24

		Kefir.paint:Text("", 20, numberValueAV - 4, valueNQ, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(accountGroup, 16, numberValueAV + 22, valueNQ + 4, Kefir.color.ug[accountGroup], TEXT_ALIGN_LEFT, "ofont")

		local valueNR = valueNQ + 24

		Kefir.paint:Text("", 20, numberValueAV, valueNR, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(accountStatus .. Kefir:GetLangText(" UID"), 16, numberValueAV + 22, valueNR + 2, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")

		local valueNS = valueNR + 24

		Kefir.paint:Text("", 20, numberValueAV - 4, valueNS, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(Kefir:GetLangText("Branch: ") .. Kefir:GetLangText(Kefir.branch), 16, numberValueAV + 22, valueNS + 2, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")
		Kefir.paint:Text("", 20, numberValueAV, paramTQ - 210, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:Text(Kefir:GetLangText("Chat"), 16, numberValueAV + 24, paramTQ - 208, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")
	end

	local tableDataAH = {
		current_ = "LANGUAGE",
		group = 1,
		index = "",
		object_x = 15,
		object_y = 115,
		data_var = {
			Kefir:GetLanguage(),
			"Language",
			nil,
			nil,
			{
				"EN",
				"RU"
			},
			0,
			true
		}
	}
	local valueNT, valueNU = Kefir.drawlist.combobox(Kefir, tableDataAH, paramTP)

	function valueNU.addfn(selfRefCN, paramTR)
		Kefir:SetLanguage(paramTR)
	end

	function valueNU.Think(paramTS)
		paramTS:SetValue(Kefir:GetLanguage())
	end

	local tableDataAI = {
		current_ = "USER_CONFIG",
		group = 1,
		lang333 = true,
		index = "",
		object_x = 15,
		data_var = {
			false,
			"Save User Settings",
			"checkbox",
			1
		},
		object_y = 130 + valueNT
	}

	Kefir.drawlist.checkbox(Kefir, tableDataAI, paramTP)

	Kefir.chatboxup = runtimeApi.vCreate("DScrollPanel", paramTP)

	Kefir.chatboxup:SetPos(15, 210)
	Kefir.chatboxup:SetSize(paramTP:GetWide() - 30, paramTP:GetTall() - 255)

	function Kefir.chatboxup.Paint(unusedParamBE, unusedParamBF, unusedParamBG)
		return
	end

	local getVBarResult = Kefir.chatboxup:GetVBar()

	getVBarResult:SetWide(2)

	function getVBarResult.Paint(unusedParamBH)
		return
	end

	function getVBarResult.btnGrip.Paint(unusedParamBI, paramTT, paramTU)
		localCache.setDrawColor(runtimeApi.color.kefir_red)
		localCache.drawRect(0, 0, paramTT, paramTU)
	end

	function Kefir.chatboxup.UpdateMessages(selfRefCO)
		selfRefCO:Clear()

		for indexAI = 1, #Kefir.chatlog do
			local valueNV = Kefir.chatlog[indexAI]
			local whiteF = Kefir.color.ug[valueNV.group] or runtimeApi.color.white
			local addResult = selfRefCO:Add("DLabel")

			addResult:SetFont(runtimeApi.NameStart .. "kefir.chat.14")
			addResult:SetText("")
			addResult:Dock(TOP)
			addResult:DockMargin(5, 2, 5, 2)
			addResult:SetAutoStretchVertical(true)
			addResult:SetWrap(true)
			addResult:SetMouseInputEnabled(true)

			function addResult.Paint(unusedParamBJ, unusedParamBK, unusedParamBL)
				Kefir.paint:Text(valueNV.nick .. ":", 14, 0, 0, whiteF, TEXT_ALIGN_LEFT, "chat2")
				runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.chat2.14")

				local valueNW, valueNX = runtimeApi.sGetTextSize(valueNV.nick .. ": ")

				Kefir.paint:Text(valueNV.text, 14, valueNW, 0, runtimeApi.color.white, TEXT_ALIGN_LEFT, "chat2")
			end
		end

		runtimeApi.tSimple(0.1, function()
			if IsValid(getVBarResult) then
				getVBarResult:SetScroll(getVBarResult.CanvasSize)
			end
		end)
	end

	local tableDataAJ = {
		current_ = "CHAT_INPUT_FIELD",
		group = 1,
		object_x = 15,
		data_var = {
			Kefir.chatinput or "",
			"Chat Input",
			[5] = {
				paramTP:GetWide() - 30,
				25,
				"Write message",
				"chat2",
				50
			}
		},
		object_y = paramTP:GetTall() - 40,
		custom_env = function(paramTV)
			function paramTV.OnEnter(paramTW)
				local settingValueB = paramTW:GetValue()

				if settingValueB:Trim() == "" then
					return
				end

				Kefir:Request("send_msg", {
					message = settingValueB
				}, function(paramTX, paramTY)
					if paramTY then
						Kefir.chatlog = paramTX.chat

						if IsValid(Kefir.chatboxup) and isfunction(Kefir.chatboxup.UpdateMessages) then
							Kefir.chatboxup:UpdateMessages()
						end
					end
				end)
				paramTW:SetText("")
				paramTW:RequestFocus()
			end
		end
	}

	Kefir.drawlist.input(Kefir, tableDataAJ, paramTP)
	Kefir.chatboxup:UpdateMessages()
end

function runtimeApi.var.ATTACHMENTS.drawfunction(paramTZ)
	numberValueAR = 190

	local valueNY = justWepAtt or {}

	for keyAS, itemAP in Kefir.pairs(Kefir.zcity_weapons[2]) do
		runtimeApi.insert(valueNY, runtimeApi.wpGet(keyAS).PrintName)
	end

	if not localPlayer then
		return
	end

	if aKM == "AKM" then
		aKM = Kefir:ClassByName(aKM)
	end

	local valueNZ = runtimeApi.wpGet(aKM)
	local worldModelB = valueNZ.WorldModelFake or valueNZ.WorldModel
	local getIndexAttachmentsResultD = Kefir:getIndexAttachments("sight", valueNZ.availableAttachments)
	local getIndexAttachmentsResultE = Kefir:getIndexAttachments("barrel", valueNZ.availableAttachments)
	local getIndexAttachmentsResultF = Kefir:getIndexAttachments("grip", valueNZ.availableAttachments)
	local getIndexAttachmentsResultG = Kefir:getIndexAttachments("underbarrel", valueNZ.availableAttachments)
	local valueOA = tableDataAA.sight and tableDataAA.sight[1] or "none"
	local valueOB = tableDataAA.barrel and tableDataAA.barrel[1] or "none"
	local valueOC = tableDataAA.grip and tableDataAA.grip[1] or "none"
	local valueOD = tableDataAA.underbarrel and tableDataAA.underbarrel[1] or "none"
	local valueOE

	valueOE = tableDataAB[valueOA] or "none"

	local valueOF

	valueOF = tableDataAB[valueOB] or "none"

	local valueOG

	valueOG = tableDataAB[valueOC] or "none"

	local valueOH

	valueOH = tableDataAB[valueOD] or "none"
	tableDataAC[1] = Kefir:addComboBox(getIndexAttachmentsResultD, {
		valueOE,
		"Sight"
	}, {
		12
	})
	tableDataAC[2] = Kefir:addComboBox(getIndexAttachmentsResultE, {
		valueOF,
		"Barrel"
	}, {
		12
	})
	tableDataAC[3] = Kefir:addComboBox(getIndexAttachmentsResultF, {
		valueOG,
		"Grip"
	}, {
		12
	})
	tableDataAC[4] = Kefir:addComboBox(getIndexAttachmentsResultG, {
		valueOH,
		"Underbarrel"
	}, {
		12
	})

	local var0140Result = var28815Handler(nil, valueNY, tableDataAC)
	local entityRefX = runtimeApi.vCreate("DPanel", paramTZ)

	entityRefX:SetPos(12, 30)
	entityRefX:SetSize(740, 150)

	function entityRefX.Paint(unusedParamBM, paramUA, paramUB)
		Kefir.paint:Box(0, 0, paramUA, paramUB, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 1, true)
		Kefir.paint:Gradient(2, 2, paramUA - 4, paramUB - 4, Kefir.paint:HColorAlpha(runtimeApi.color.groupbox, 35), Kefir.paint:HColorAlpha(runtimeApi.color.aiming, 100))
	end

	function entityRefX.Think()
		valueNZ = runtimeApi.wpGet(aKM)
		worldModelB = valueNZ.WorldModelFake or valueNZ.WorldModel
	end

	local valueOI = runtimeApi.vCreate("DModelPanel", entityRefX)

	valueOI:SetSize(740, 150)
	valueOI:SetModel(worldModelB)

	function valueOI.LayoutEntity(selfRefCP, paramUC)
		if paramUC:GetModel() ~= worldModelB then
			selfRefCP:SetModel(worldModelB)
		end

		if not valueNZ.LocalMuzzlePos then
			return
		end

		local vectorValueD = Vector(10, 0, 0)
		local valueOJ, valueOK = paramUC:GetRenderBounds()
		local localMuzzlePosA = valueNZ.LocalMuzzlePos

		vectorValueD[1] = (localMuzzlePosA[1] + localMuzzlePosA[2] + localMuzzlePosA[3]) * 2

		local valueOL = tableDataY[valueNZ.ClassName]

		vectorValueD = valueOL ~= nil and valueOL or vectorValueD

		local valueOM = tableDataZ[worldModelB]

		vectorValueD = valueOM ~= nil and valueOM or vectorValueD

		local valueON = runtimeApi.sin(runtimeApi.stime() * numberValueAQ) * numberValueAQ

		numberValueAQ = runtimeApi.Lerp(Kefir.frametime() * 2, numberValueAQ or 0, 0)

		selfRefCP:SetLookAt(vectorValueD)
		selfRefCP:SetCamPos(vectorValueD - Vector(-12, 0, 0))
		paramUC:SetAngles(Angle(5 * numberValueAQ, 90 * RealTime(), -16))
	end

	function valueOI.PostDrawModel(selfRefCQ, entityRefY)
		if not IsValid(entityRefY) then
			return
		end

		if valueNZ.FakeBodyGroups then
			entityRefY:SetBodyGroups(valueNZ.FakeBodyGroups)
		end

		Kefir:ClearAttachmentModels(entityRefY)
		entityRefY:DrawModel()
		Kefir:RenderAttachments(entityRefY, tableDataAA, valueNZ)
	end

	function valueOI.PaintOver(paramUD, paramUE, paramUF)
		local valueOO = valueNZ.PrintName or unknownText

		if not valueNZ.LocalMuzzlePos then
			valueOO = unknownText
		end

		if paramUD:IsHovered() or valueOO == unknownText then
			Kefir.paint:Box(1, 1, paramUE - 2, paramUF - 2, false, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, 155))
			Kefir.paint:Text(valueOO, 16, paramUE / 2, paramUF / 2, runtimeApi.color.white, TEXT_ALIGN_CENTER, "ofont")
		end
	end

	function valueOI.DoClick(unusedParamBN)
		var0140Result:SetVisible(true)
	end

	local createObjectResultL = Kefir.paint:CreateObject("default_button", paramTZ)

	createObjectResultL:SetPos(320, 365)
	createObjectResultL:SetSize(100, 30)
	createObjectResultL:SetText("")

	createObjectResultL._text = "Apply"
	createObjectResultL._textsize = 16
	createObjectResultL._maincolor = runtimeApi.color.kefir_red

	function createObjectResultL.AnimationThink(unusedParamBO)
		createObjectResultL._maincolor = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, (1 + numberValueAQ) * 155)
	end

	function createObjectResultL.DoClick(unusedParamBP)
		runtimeApi.var.ATTACHMENTS[1][aKM] = runtimeApi.var.ATTACHMENTS[1][aKM] or {}

		for keyAT, itemAQ in Kefir.pairs(tableDataAA) do
			runtimeApi.var.ATTACHMENTS[1][aKM][keyAT] = itemAQ
		end

		if localPlayer:Alive() then
			local getWeaponsResult = localPlayer:GetWeapons()

			for indexAJ = 1, #getWeaponsResult do
				local entityRefZ = getWeaponsResult[indexAJ]

				if IsValid(entityRefZ) then
					entityRefZ:SetNWBool("Supressor", false)
				end
			end
		end

		Kefir:RestartAttachments()

		numberValueAQ = 2
	end

	-- select the weapon currently in hands
	local createObjectResultM = Kefir.paint:CreateObject("default_button", paramTZ)

	createObjectResultM:SetPos(430, 365)
	createObjectResultM:SetSize(100, 30)
	createObjectResultM:SetText("")

	createObjectResultM._text = "In Hands"
	createObjectResultM._textsize = 16
	createObjectResultM._maincolor = runtimeApi.color.kefir_red

	function createObjectResultM.DoClick()
		local handWeapon = localPlayer:GetActiveWeapon()

		if not IsValid(handWeapon) or not Kefir.zcity_weapons[2][handWeapon:GetClass()] then
			return
		end

		aKM = handWeapon:GetClass()

		local tableDataPlacingM = {
			barrel = {},
			sight = {},
			mount = {},
			grip = {},
			underbarrel = {}
		}

		if runtimeApi.var.ATTACHMENTS[1][aKM] ~= nil then
			tableDataPlacingM = runtimeApi.var.ATTACHMENTS[1][aKM]
		end

		tableDataAA = tableDataPlacingM

		local getIndexAttachmentsResultX1 = Kefir:getIndexAttachments("sight", handWeapon.availableAttachments)
		local getIndexAttachmentsResultX2 = Kefir:getIndexAttachments("barrel", handWeapon.availableAttachments)
		local getIndexAttachmentsResultX3 = Kefir:getIndexAttachments("grip", handWeapon.availableAttachments)
		local getIndexAttachmentsResultX4 = Kefir:getIndexAttachments("underbarrel", handWeapon.availableAttachments)
		local valueNW1 = tableDataAA.sight and tableDataAA.sight[1] or "none"
		local valueNW2 = tableDataAA.barrel and tableDataAA.barrel[1] or "none"
		local valueNW3 = tableDataAA.grip and tableDataAA.grip[1] or "none"
		local valueNW4 = tableDataAA.underbarrel and tableDataAA.underbarrel[1] or "none"

		valueNW1 = tableDataAB[valueNW1] or valueNW1
		valueNW2 = tableDataAB[valueNW2] or valueNW2
		valueNW3 = tableDataAB[valueNW3] or valueNW3
		valueNW4 = tableDataAB[valueNW4] or valueNW4
		numberValueAR = 190

		for indexAHM = 1, #tableDataAC do
			local entityRefWM = tableDataAC[indexAHM]

			if IsValid(entityRefWM) and entityRefWM ~= nil then
				entityRefWM:Remove()
			end
		end

		tableDataAC[1] = Kefir:addComboBox(getIndexAttachmentsResultX1, {
			valueNW1,
			"Sight"
		}, {
			12
		})
		tableDataAC[2] = Kefir:addComboBox(getIndexAttachmentsResultX2, {
			valueNW2,
			"Barrel"
		}, {
			12
		})
		tableDataAC[3] = Kefir:addComboBox(getIndexAttachmentsResultX3, {
			valueNW3,
			"Grip"
		}, {
			12
		})
		tableDataAC[4] = Kefir:addComboBox(getIndexAttachmentsResultX4, {
			valueNW4,
			"Underbarrel"
		}, {
			12
		})
		numberValueAQ = 5
	end

	if flagA then
		local tableDataAK = {
			sight,
			barrel,
			grip,
			underbarrel
		}
		local valueOP = valueNZ

		aKM = valueOP.ClassName

		local tableDataAL = {
			barrel = {},
			sight = {},
			mount = {},
			grip = {},
			underbarrel = {}
		}

		if runtimeApi.var.ATTACHMENTS[1][aKM] ~= nil then
			tableDataAL = runtimeApi.var.ATTACHMENTS[1][aKM]
		end

		tableDataAA = tableDataAL

		local getIndexAttachmentsResultH = Kefir:getIndexAttachments("sight", valueOP.availableAttachments)
		local getIndexAttachmentsResultI = Kefir:getIndexAttachments("barrel", valueOP.availableAttachments)
		local getIndexAttachmentsResultJ = Kefir:getIndexAttachments("grip", valueOP.availableAttachments)
		local getIndexAttachmentsResultK = Kefir:getIndexAttachments("underbarrel", valueOP.availableAttachments)
		local valueOQ = tableDataAA.sight and tableDataAA.sight[1] or "none"
		local valueOR = tableDataAA.barrel and tableDataAA.barrel[1] or "none"
		local valueOS = tableDataAA.grip and tableDataAA.grip[1] or "none"
		local valueOT = tableDataAA.underbarrel and tableDataAA.underbarrel[1] or "none"

		valueOQ = tableDataAB[valueOQ] or valueOQ
		valueOR = tableDataAB[valueOR] or valueOR
		valueOS = tableDataAB[valueOS] or valueOS
		valueOT = tableDataAB[valueOT] or valueOT
		numberValueAR = 190

		for indexAK = 1, #tableDataAC do
			local entityRefAA = tableDataAC[indexAK]

			if IsValid(entityRefAA) and entityRefAA ~= nil then
				entityRefAA:Remove()
			end
		end

		tableDataAC[1] = Kefir:addComboBox(getIndexAttachmentsResultH, {
			valueOQ,
			"Sight"
		}, {
			12
		})
		tableDataAC[2] = Kefir:addComboBox(getIndexAttachmentsResultI, {
			valueOR,
			"Barrel"
		}, {
			12
		})
		tableDataAC[3] = Kefir:addComboBox(getIndexAttachmentsResultJ, {
			valueOS,
			"Grip"
		}, {
			12
		})
		tableDataAC[4] = Kefir:addComboBox(getIndexAttachmentsResultK, {
			valueOT,
			"Underbarrel"
		}, {
			12
		})
		numberValueAQ = 5
		flagA = false
	end
end

function runtimeApi.var.PLAYERS.drawfunction(paramUG)
	local entityRefAB = runtimeApi.vCreate("DListBox", paramUG)

	entityRefAB:SetPos(5, 5)
	entityRefAB:SetSize(245, 380)

	for keyAU, itemAR in localCache.iteratePlayers() do
		if localPlayer ~= itemAR then
			local addItemResult = entityRefAB:AddItem(runtimeApi.nick(itemAR))

			addItemResult:SetText("")

			addItemResult._text = runtimeApi.nick(itemAR)
			addItemResult._handle = itemAR
			addItemResult._kefiruser = false

			function addItemResult.Paint(paramUH, paramUI, unusedParamBQ)
				local whiteG = runtimeApi.color.white
				local valueOU = ""

				if runtimeApi.HasValue(entityRefAB:GetSelectedItems(), paramUH) then
					whiteG = runtimeApi.color.kefir_red
				end

				runtimeApi.draw_text((addItemResult._text .. " - " .. ((paramUH._handle.GetPlayerName and paramUH._handle:GetPlayerName() or "") ~= "" and (paramUH._handle.GetPlayerName and paramUH._handle:GetPlayerName() or "") or unknownText)) .. valueOU, "DebugOverlay", paramUI / 2, 6, Kefir.paint:HColorAlpha(whiteG, paramUH.status ~= "" and 55 or 255), TEXT_ALIGN_CENTER)
			end

			function addItemResult.Think(paramUJ)
				if not paramUJ._handle or not IsValid(paramUJ._handle) then
					paramUJ:Remove()

					paramUJ = nil
				else
					paramUJ._kefiruser = Kefir.users[paramUJ._handle:SteamID()] ~= nil
				end
			end

			function addItemResult.PaintOver(paramUK, paramUL, unusedParamBR)
				if paramUK:IsHovered() then
					local valueOV = ""

					if runtimeApi.HasValue(Kefir.friendlist, paramUK._handle) then
						valueOV = valueOV .. "FRIEND; "
					end

					if Kefir.espignore[paramUK._handle] then
						valueOV = valueOV .. "ESP IGNORED; "
					end

					paramUK.status = valueOV

					runtimeApi.draw_text(paramUK.status, "BudgetLabel", paramUL / 2, 6, color, TEXT_ALIGN_CENTER)
				else
					paramUK.status = ""
				end
			end
		end
	end

	entityRefAB:SetMultiple(false)

	function entityRefAB.Paint(unusedParamBS, paramUM, paramUN)
		Kefir.paint:Box(0, 0, paramUM, paramUN, true, runtimeApi.color.kefir_black, runtimeApi.color.kefir_red, 2, true)
	end

	Kefir:playerlistbutton(paramUG, {
		{
			255,
			5
		},
		{
			80,
			30
		},
		"Add Friend"
	}, function(paramUO)
		function paramUO.DoClick()
			local getSelectedItemsResult = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResult then
				if not runtimeApi.HasValue(Kefir.friendlist, getSelectedItemsResult._handle) then
					runtimeApi.insert(Kefir.friendlist, getSelectedItemsResult._handle)
				else
					runtimeApi.table.RemoveByValue(Kefir.friendlist, getSelectedItemsResult._handle)
				end
			end
		end

		function paramUO.Think(paramUP)
			local getSelectedItemsResultA = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultA then
				local valueOW = runtimeApi.HasValue(Kefir.friendlist, getSelectedItemsResultA._handle)

				paramUP._text = valueOW and "Remove Friend" or "Add Friend"
				paramUP.FAQ_INDEX = valueOW and "X_PLAYERS_removefriend_X" or "X_PLAYERS_addfriend_X"
			else
				paramUP.FAQ_INDEX = "X_sap_X"
			end
		end
	end)
	Kefir:playerlistbutton(paramUG, {
		{
			255,
			40
		},
		{
			80,
			30
		},
		"Copy SteamID"
	}, function(paramUQ)
		function paramUQ.DoClick()
			local getSelectedItemsResultB = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultB then
				SetClipboardText(getSelectedItemsResultB._handle:SteamID())
			end
		end

		paramUQ.FAQ_INDEX = "X_PLAYERS_copy_steamid_X"
	end)
	Kefir:playerlistbutton(paramUG, {
		{
			255,
			75
		},
		{
			80,
			30
		},
		"Copy SteamID64"
	}, function(paramUR)
		function paramUR.DoClick()
			local getSelectedItemsResultC = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultC then
				SetClipboardText(getSelectedItemsResultC._handle:SteamID64())
			end
		end

		paramUR.FAQ_INDEX = "X_PLAYERS_copy_steamid64_X"
	end)
	Kefir:playerlistbutton(paramUG, {
		{
			255,
			110
		},
		{
			120,
			30
		},
		"Copy Appearance Name"
	}, function(paramUS)
		function paramUS.DoClick()
			local getSelectedItemsResultD = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultD then
				SetClipboardText(getSelectedItemsResultD._handle.GetPlayerName and getSelectedItemsResultD._handle:GetPlayerName() or "")
			end
		end

		paramUS.FAQ_INDEX = "X_PLAYERS_copy_appearance_name_X"
	end)
	Kefir:playerlistbutton(paramUG, {
		{
			255,
			145
		},
		{
			80,
			30
		},
		"Ignore ESP"
	}, function(paramUT)
		function paramUT.DoClick()
			local getSelectedItemsResultE = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultE then
				if not Kefir.espignore[getSelectedItemsResultE._handle] then
					Kefir.espignore[getSelectedItemsResultE._handle] = true
				else
					Kefir.espignore[getSelectedItemsResultE._handle] = nil
				end
			end
		end

		function paramUT.Think(paramUU)
			local getSelectedItemsResultF = entityRefAB:GetSelectedItems()[1]

			if getSelectedItemsResultF then
				local valueOX = Kefir.espignore[getSelectedItemsResultF._handle]

				paramUU._text = valueOX and Kefir:GetLangText("Restore ESP") or Kefir:GetLangText("Ignore ESP")
				paramUU.FAQ_INDEX = valueOX and "X_PLAYERS_restoreesp_X" or "X_PLAYERS_ignoreesp_X"
			else
				paramUU.FAQ_INDEX = "X_sap_X"
			end
		end
	end)

	paramUG.oPaint = paramUG.Paint

	function paramUG.Paint(paramUV, paramUW, paramUX)
		paramUV:oPaint(paramUW, paramUX)

		local getSelectedItemsResultG = entityRefAB:GetSelectedItems()[1]

		if getSelectedItemsResultG ~= nil and getSelectedItemsResultG._kefiruser then
			local handle = getSelectedItemsResultG._handle
			local steamIdA = Kefir.users[handle:SteamID()]

			if steamIdA ~= nil then
				Kefir.paint:Text("", 20, tableDataW[1] + 10, tableDataW[2] + 40, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
				Kefir.paint:Text(Kefir:GetLangText("It's Kefir.VIP User:"), 20, tableDataW[1] + 24, tableDataW[2] + 40, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")
				Kefir.paint:Text("", 20, tableDataW[1] + 22, tableDataW[2] + 62, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
				Kefir.paint:Text(steamIdA.username or "", 20, tableDataW[1] + 44, tableDataW[2] + 62, runtimeApi.color.white, TEXT_ALIGN_LEFT, "ofont")

				local valueOY = steamIdA.usergroup or ""

				Kefir.paint:Text("", 20, tableDataW[1] - 2 + 22, tableDataW[2] + 84, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
				Kefir.paint:Text(valueOY, 20, tableDataW[1] + 46, tableDataW[2] + 84, Kefir.color.ug[valueOY], TEXT_ALIGN_LEFT, "ofont")
			end
		end
	end
end

Kefir.tab_update = {
	VISUALS = function()
		Kefir.paint:fDelete(Kefir.previewesp)
		Kefir.paint:fDelete(Kefir.filteresp)
		Kefir.paint:fDelete(Kefir.hitboxaim)
		Kefir.paint:espPreview()
		Kefir.paint:espFilter()
	end,
	COMBAT = function()
		Kefir.paint:fDelete(Kefir.previewesp)
		Kefir.paint:fDelete(Kefir.filteresp)
		Kefir.paint:fDelete(Kefir.hitboxaim)
		Kefir.paint:aimHitbox()
	end
}

function Kefir.paint.TABUpdate(selfRefCR)
	local ownerC = selfRefCR.__owner

	if not runtimeApi.tIsEmpty(ownerC.menu_groups) then
		for keyAV, itemAS in Kefir.ipairs(ownerC.menu_groups) do
			ownerC.menu_groups[keyAV]:Remove()

			ownerC.menu_groups[keyAV] = nil
		end

		ownerC.menu_groups = {}
	end

	if ownerC.menu_scroll then
		ownerC.menu_scroll:Remove()

		ownerC.menu_scroll = nil
	else
		ownerC.menu_scroll = nil
	end

	local valueOZ = Kefir.tab_update[ownerC.tabs.current]

	if isfunction(valueOZ) then
		valueOZ()
	else
		selfRefCR:fDelete(Kefir.previewesp)
		selfRefCR:fDelete(Kefir.filteresp)
		selfRefCR:fDelete(Kefir.hitboxaim)
	end

	if runtimeApi.var[ownerC.tabs.current].undraw then
		local textBufferC = runtimeApi.slower(ownerC.tabs.current)
		local subResult = textBufferC:sub(1, 1):upper() .. textBufferC:sub(2)

		ownerC.menu_scroll = Kefir.paint:CreateObject("panelcontent", ownerC.menu)

		ownerC.menu_scroll:SetPos(20, 80)
		ownerC.menu_scroll:SetSize(760, 390)

		ownerC.menu_scroll.__groupname = subResult

		if runtimeApi.var[ownerC.tabs.current].drawfunction and isfunction(runtimeApi.var[ownerC.tabs.current].drawfunction) then
			runtimeApi.var[ownerC.tabs.current].drawfunction(ownerC.menu_scroll)
		end

		return
	end

	selfRefCR:BuildMenuGroups()
end

function Kefir.paint.BuildMenuGroups(selfRefCR)
	local ownerC = selfRefCR.__owner

	if not runtimeApi.tIsEmpty(ownerC.menu_groups) then
		for keyAV, itemAS in Kefir.ipairs(ownerC.menu_groups) do
			ownerC.menu_groups[keyAV]:Remove()

			ownerC.menu_groups[keyAV] = nil
		end

		ownerC.menu_groups = {}
	end

	ownerC.menu_scroll = nil

	local numberValueAX = 20
	local numberValueAY = 80
	local numberValueAZ = 247
	local valuePA = runtimeApi.stime()
	local searchLowerT = runtimeApi.slower(Kefir.search_query or "")
	local searchingT = searchLowerT ~= ""

	local function itemMatchesSearch(itemDataT, itemKeyT)
		local labelT = itemDataT[2]

		if type(labelT) == "string" and labelT ~= "" then
			local labelLow = runtimeApi.slower(Kefir:GetLangText(labelT))

			if runtimeApi.find(labelLow, searchLowerT, 1, true) then
				return true
			end
		end

		if itemDataT[3] == "button" or itemDataT[3] == "text" then
			local subT = itemDataT[5]

			if istable(subT) and subT[1] then
				if runtimeApi.find(runtimeApi.slower(tostring(subT[1])), searchLowerT, 1, true) then
					return true
				end
			end
		end

		if runtimeApi.find(runtimeApi.slower(tostring(itemKeyT)), searchLowerT, 1, true) then
			return true
		end

		return false
	end

	for indexAL = 1, 3 do
		local valuePB = indexAL == 1 and 365 or 390

		ownerC.menu_groups[indexAL] = Kefir.paint:CreateObject("panelcontent", ownerC.menu)

		ownerC.menu_groups[indexAL]:SetPos(numberValueAX, indexAL == 1 and numberValueAY + (390 - valuePB) or numberValueAY)
		ownerC.menu_groups[indexAL]:SetSize(numberValueAZ, valuePB)

		ownerC.menu_groups[indexAL].__groupname = runtimeApi.var[ownerC.tabs.current] ~= nil and runtimeApi.var[ownerC.tabs.current][indexAL] ~= nil and runtimeApi.var[ownerC.tabs.current][indexAL].name or unknownText
		numberValueAX = numberValueAX + (numberValueAZ + 10)

		ownerC.menu_groups[indexAL]:SetZPos(30999)
		ownerC.menu_groups[indexAL]:NoClipping(true)

		local paintFn = ownerC.menu_groups[indexAL].Paint

		ownerC.menu_groups[indexAL].Paint = function(paramUY, paramUZ, paramVA)
			local valuePC = runtimeApi.stime() - valuePA
			local valuePD = runtimeApi.math.min(valuePC / 0.35, 1)
			local numberValueBA = 1 - (1 - valuePD) * (1 - valuePD)
			local valuePE = runtimeApi.math.floor(paramVA * numberValueBA)
			local valuePF, valuePG = paramUY:LocalToScreen(0, 0)

			localCache.setScissorRect(valuePF, valuePG, valuePF + paramUZ, valuePG + valuePE, true)

			if paintFn then
				paintFn(paramUY, paramUZ, paramVA)
			end

			localCache.setScissorRect(0, 0, 0, 0, false)

			if numberValueBA < 1 then
				Kefir.paint:Gradient(0, valuePE - 2, paramUZ, runtimeApi.clamp(paramVA - valuePE + 2, 0, 250), selfRefCR:HColorAlpha(Kefir.color.kefir_red, 155 * (1 - numberValueBA)), selfRefCR:HColorAlpha(Kefir.color.kefir_black, 255), true)
			end
		end

		local valuePH = runtimeApi.vCreate("DScrollPanel", ownerC.menu_groups[indexAL])

		valuePH:Dock(FILL)
		valuePH:SetZPos(30999)
		valuePH:NoClipping(true)

		local getVBarResultA = valuePH:GetVBar()

		getVBarResultA:SetSize(12, 15)

		getVBarResultA.tPos = 0
		getVBarResultA.nPos = 0

		function getVBarResultA.Paint(unusedParamBT, paramVB, paramVC)
			selfRefCR:rectBox(paramVB, paramVC, 0, 0, color_black)
			selfRefCR:rectBox(paramVB - 2, paramVC - 2, 1, 1, runtimeApi.color.groupname)
			selfRefCR:rectBox(paramVB - 4, paramVC - 4, 2, 2, runtimeApi.color.kefir_black)
		end

		function getVBarResultA.btnGrip.Paint(paramVD, paramVE, paramVF)
			local groupboxB = paramVD:IsHovered() and runtimeApi.color.kefir_red or runtimeApi.color.groupbox

			selfRefCR:rectBox(paramVE - 8, paramVF, 4, 0, groupboxB)
			selfRefCR:rectBox(paramVE - 10, paramVF - 2, 5, 1, color_black)
		end

		function getVBarResultA.btnUp.Paint()
			return
		end

		function getVBarResultA.btnDown.Paint()
			return
		end

		ownerC.menu_scroll = valuePH

		if runtimeApi.var[ownerC.tabs.current or "COMBAT"][indexAL] then
			local currentA = ownerC.tabs.current
			local valuePI = runtimeApi.var[currentA or "COMBAT"][indexAL]
			local numberValueBB = 5
			local numberValueBC = 11
			local tableDataAM = {}

			for keyAW, itemAT in Kefir.pairs(valuePI) do
				if keyAW ~= "name" then
					if not searchingT or itemMatchesSearch(itemAT, keyAW) then
						runtimeApi.insert(tableDataAM, {
							keyAW,
							itemAT
						})
					end
				end
			end

			runtimeApi.sorting(tableDataAM, function(paramVG, paramVH)
				return (paramVG[2][4] or 0) < (paramVH[2][4] or 0)
			end)

			for indexAM = 1, #tableDataAM do
				local valuePJ = tableDataAM[indexAM]
				local valuePK = valuePJ[1]
				local valuePL = valuePJ[2]
				local tableDataAN = {
					data_var = valuePL,
					index = valuePK,
					object_x = numberValueBB,
					object_y = numberValueBC,
					current_ = currentA,
					group = indexAL
				}

				if isnumber(valuePL[4]) and valuePL[4] > 0 and selfRefCR.__list[valuePL[3]] then
					numberValueBC = numberValueBC + selfRefCR.__list[valuePL[3]](ownerC, tableDataAN)
				end
			end
		end
	end
end

local numberValueBD = 800
local numberValueBE = 500
local tableDataAO = {
	def = {
		x = numberValueBD,
		y = numberValueBE
	}
}

function Kefir.paint.TABs(selfRefCS)
	if IsValid(Kefir.tab_frame) then
		Kefir.tab_frame:Remove()

		Kefir.tab_frame = nil

		return
	end

	local numberValueBF = 60

	Kefir.tab_frame = selfRefCS:CreateObject("jframe")

	Kefir.tab_frame:SetPos(0, 0)
	Kefir.tab_frame:SetSize(0, numberValueBF)

	Kefir.tab_frame.XD = 0
	Kefir.tab_frame.OFFSET_Y = 305
	Kefir.tab_frame.ALPHA = 0

	Kefir.tab_frame:SetAlpha(0)

	function Kefir.tab_frame.Think(paramVI)
		if not IsValid(Kefir.menu) then
			return
		end

		paramVI.OFFSET_Y = Kefir:Lerp(Kefir.frametime() * 8, paramVI.OFFSET_Y or 305, Kefir.menu:GetAlpha() >= 220 and 505 or 405)
		paramVI.ALPHA = Kefir:Lerp(Kefir.frametime() * 8, paramVI.ALPHA or 0, Kefir.menu:GetAlpha() >= 254 and 255 or 0)

		paramVI:SetAlpha(Kefir.menu:GetAlpha() <= 254 and 0 or runtimeApi.clamp(paramVI.ALPHA, 0, 255))
		Kefir:TrackMenu(paramVI, (numberValueBD - paramVI.XD) / 2, paramVI.OFFSET_Y)
	end

	local numberValueBG = 100
	local numberValueBH = 3

	for keyAX, itemAU in Kefir.pairs(Kefir.tabs.list) do
		local createObjectResultM = selfRefCS:CreateObject("tabbutton", Kefir.tab_frame)

		createObjectResultM:SetSize(numberValueBG + 3, numberValueBF + 9)
		createObjectResultM:SetPos(numberValueBH, -4)

		createObjectResultM.Tab = {
			itemAU[1],
			itemAU[2]
		}
		numberValueBH = numberValueBH + (numberValueBG + 5)
	end

	Kefir.tab_frame:SetSize(numberValueBH, numberValueBF)

	Kefir.tab_frame.XD = numberValueBH
end

function Kefir.paint.ToggleMenu(selfRefCT)
	local ownerD = selfRefCT.__owner

	Kefir:_Initialize()

	if ownerD.menu == nil or not IsValid(ownerD.menu) or ownerD.type(ownerD.menu) ~= "Panel" then
		ownerD.menu = Kefir.paint:CreateObject("menuframe")

		local posBySizeResult = Kefir:PosBySize(screenWidth, screenHeight, tableDataAO.def.x, tableDataAO.def.y)

		runtimeApi.tSimple(0.01, function()
			if IsValid(ownerD.menu) then
				ownerD.menu:SetSize(tableDataAO.def.x, tableDataAO.def.y)
				ownerD.menu:SetPos(posBySizeResult[1], posBySizeResult[2])
				ownerD.menu:SetAlpha(0)
				ownerD.menu:SetTitle("")
				ownerD.menu:ShowCloseButton(false)
				ownerD.menu:AlphaTo(255, nativeApi.util_calcWeekend(0.0003048780487804878), 0)

				ownerD.menu.ForceClose = false
			end
		end)
		ownerD.menu:SetPaintedManually(not nativeApi.standalone_vgui)

		local dRAGMENU = Kefir.variables.DRAGMENU

		if dRAGMENU ~= nil and dRAGMENU[1] and dRAGMENU[2] then
			ownerD.menu:SetPos(dRAGMENU[1], dRAGMENU[2])
		end

		ownerD.menu:MakePopup()
		nativeApi.util_setMenuPanel(ownerD.menu)

		local infoButton = runtimeApi.vCreate("DButton", ownerD.menu)
		infoButton:SetText("?")
		infoButton:SetFont(Kefir:GetName() .. "ofont.16")
		infoButton:SetTextColor(runtimeApi.color.white)
		infoButton:SetSize(20, 20)
		infoButton:SetPos(36, tableDataAO.def.y - 31)
		infoButton:SetZPos(32000)
		infoButton.Paint = function(button, width, height)
			local alpha = button:IsHovered() and 255 or 180
			Kefir.paint:Box(0, 0, width, height, true, Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, 230), Kefir.paint:HColorAlpha(runtimeApi.color.kefir_red, alpha), 1, true)
		end
		infoButton.DoClick = function()
			if IsValid(Kefir.info_panel) then
				Kefir.info_panel:AlphaTo(0, 0.15, 0, function()
					if IsValid(Kefir.info_panel) then Kefir.info_panel:Remove() end
				end)
				if IsValid(Kefir.icon_panel) then
					Kefir.icon_panel:AlphaTo(0, 0.15, 0, function()
						if IsValid(Kefir.icon_panel) then Kefir.icon_panel:Remove() end
					end)
				end
				return
			end

			local panel = Kefir.paint:CreateObject("info_panel")
			panel:SetSize(230, 260)
			local savedPosition = Kefir.variables.INFO_PANEL_POS
			if savedPosition then
				panel:SetPos(savedPosition[1], savedPosition[2])
			else
				panel:Center()
				panel:SetY(math.max(30, panel:GetY() - 80))
			end
			panel:MakePopup()
Kefir.info_panel = panel

			local iconPanel = Kefir.paint:CreateObject("icon_panel")
			iconPanel:SetSize(380, 52 + math.ceil(#Kefir.icon_preview / 6) * 28 + 6)
			iconPanel:SetPos(panel:GetX() + panel:GetWide() + 12, panel:GetY())
			iconPanel:MakePopup()
			Kefir.icon_panel = iconPanel

		end

		local createObjectResultN = Kefir.paint:CreateObject("checkbox", ownerD.menu)

		createObjectResultN:SetPos(25, 82)
		createObjectResultN:SetSize(240, 15)
		createObjectResultN:SetZPos(31000)

		createObjectResultN.bgl = true
		createObjectResultN.__var = "toggle"
		createObjectResultN.__tab = ownerD.tabs.current
		createObjectResultN.__cachetext = "Master Switch"
		createObjectResultN.originalthink = createObjectResultN.Think
		createObjectResultN.FAQ_INDEX = "master_switch"

		function createObjectResultN.Think(paramVJ)
			if runtimeApi.var[ownerD.tabs.current].undraw then
				paramVJ:SetPos(-10000, -10000)
			else
				paramVJ:SetPos(25, 82)
			end

			paramVJ.__tab = ownerD.tabs.current

			paramVJ.originalthink(paramVJ)
		end

		selfRefCT:TABs()

		Kefir.search_query = Kefir.search_query or ""
		Kefir.search_cursor = Kefir.search_cursor or 0
		Kefir.search_active = false
		Kefir.search_blink = 0
		Kefir.search_blink_change = true
		Kefir.search_placeholder = Kefir:GetLangText("Search")

		function Kefir:RebuildSearchGroups()
			if Kefir.tabs.current and runtimeApi.var[Kefir.tabs.current] and not runtimeApi.var[Kefir.tabs.current].undraw and IsValid(Kefir.menu) then
				Kefir.paint:BuildMenuGroups()
			end
		end

		selfRefCT:TABUpdate()

		local searchFocusButton = runtimeApi.vCreate("DButton", ownerD.menu)

		searchFocusButton:SetText("")
		searchFocusButton:SetZPos(99999)

		if IsValid(Kefir.menu) and IsValid(Kefir.tab_frame) then
			local tabX, tabY = Kefir.tab_frame:GetPos()
			local tabW = Kefir.tab_frame:GetWide()
			local tabH = Kefir.tab_frame:GetTall()
			local menuX, menuY = Kefir.menu:GetPos()

			searchFocusButton:SetPos(tabX - menuX, tabY - menuY + tabH + 9)
			searchFocusButton:SetSize(tabW, tabH)
		end

		function searchFocusButton.Paint(panel)
			return true
		end

		function searchFocusButton:DoClick()
			if not Kefir.search_active and Kefir.hotkey_choosing and Kefir.hotkey_choosing[1] and Kefir.hotkey_choosing[1][1] == "none" then
				Kefir.search_active = true
				Kefir.search_cursor = #(Kefir.search_query or "")
				Kefir.search_blink = 0
				Kefir.search_blink_change = true
			end
		end

		function searchFocusButton:Think()
			if IsValid(Kefir.menu) and IsValid(Kefir.tab_frame) then
				local tabX, tabY = Kefir.tab_frame:GetPos()
				local tabW = Kefir.tab_frame:GetWide()
				local tabH = Kefir.tab_frame:GetTall()
				local menuX, menuY = Kefir.menu:GetPos()

				self:SetPos(tabX - menuX, tabY - menuY + tabH + 9)
				self:SetSize(tabW, tabH)
			end
		end
	else
		local valuePM, valuePN = Kefir.menu:GetPos()

		Kefir.variables.DRAGMENU = {
			valuePM,
			valuePN
		}

		selfRefCT:fDelete(Kefir.menu)
		selfRefCT:fDelete(Kefir.previewesp)
		selfRefCT:fDelete(Kefir.filteresp)
		selfRefCT:fDelete(Kefir.hitboxaim)
		selfRefCT:fDelete(Kefir.tab_frame)

		Kefir.search_active = false
		Kefir.search_cursor = 0
		Kefir.search_mousedown_prev = false

		Kefir.menu.ForceClose = true
	end
end

function Kefir.TimerIterator(selfRefCU)
	local timersA = selfRefCU.timers

	if not timersA or runtimeApi.tIsEmpty(timersA) then
		return
	end

	for indexAN = #timersA, 1, -1 do
		local valuePO = timersA[indexAN]

		if runtimeApi.stime() - (valuePO[4] or 0) >= valuePO[1] then
			valuePO[2](Kefir.unpack(valuePO[3]))

			valuePO[4] = runtimeApi.stime()
		end
	end
end

local flagK = false

function Kefir.GetHandle(selfRefCV)
	local valuePP = Kefir.width()
	local valuePQ = Kefir.height()

	if screenWidth ~= valuePP or screenHeight ~= valuePQ then
		selfRefCV:OnScreenSizeChanged(valuePP, valuePQ)
	end

	if hg then
		if not runtimeApi.fn.currentcharacter and hg.GetCurrentCharacter then
			runtimeApi.fn.currentcharacter = hg.GetCurrentCharacter
		end

		if not runtimeApi.fn.ragdollowner and hg.RagdollOwner then
			runtimeApi.fn.ragdollowner = hg.RagdollOwner
		end
	end

	if Kefir.special_server.hgcom then
		if not runtimeApi.fn.currentcharacter then
			function runtimeApi.fn.currentcharacter(paramVK)
				return paramVK.GetDummy and paramVK:GetDummy()
			end
		end

		if not runtimeApi.fn.ragdollowner then
			function runtimeApi.fn.ragdollowner(paramVL)
				return paramVL.GetController and paramVL:GetController()
			end
		end
	end

	if LocalPlayer and LocalPlayer() and IsValid(LocalPlayer()) then
		localPlayer = LocalPlayer()
		local currentWeapon = runtimeApi.activeweapon(localPlayer)
		activeWeapon = IsValid(currentWeapon) and currentWeapon or nil
		runtimeApi.ply_pos = localPlayer:GetPos()
	end
end

function Kefir.getCharacter(selfRefCW, paramVM)
	if runtimeApi.fn.currentcharacter then
		return runtimeApi.fn.currentcharacter(paramVM)
	end

	return paramVM
end

local flagL = false
local flagM = false
local flagN = false
local recoilBackups = setmetatable({}, { __mode = "k" })
local numberValueBI = 35
local numberValueBJ = -35
local numberValueBK = 25
local numberValueBL = -25

function Kefir.CrazyHead(selfRefCX)
	if getSetting("MISC", "lookaway", 2)[1] then
		local getSettingResultI = getSetting("MISC", "lookawayclamp", 2)[1]

		Kefir.fakeHead[1] = runtimeApi.random(-360, 360)
		Kefir.fakeHead[2] = runtimeApi.random(-360, 360)

		if getSetting("MISC", "lookaway_custom", 2)[1] then
			local getSettingResultJ = getSetting("MISC", "lookaway_custom_pitch", 2)[1]
			local getSettingResultK = getSetting("MISC", "lookaway_custom_yaw", 2)[1]

			Kefir.fakeHead[1] = getSettingResultJ
			Kefir.fakeHead[2] = getSettingResultK
		end

		if getSettingResultI then
			Kefir.fakeHead[1] = runtimeApi.clamp(Kefir.fakeHead[1], numberValueBJ, numberValueBI)
			Kefir.fakeHead[2] = runtimeApi.clamp(Kefir.fakeHead[2], numberValueBL, numberValueBK)
		end

		selfRefCX:sendPacket("LookAway", function(paramVN, paramVO)
			runtimeApi["pE2yG7"](paramVN)
			runtimeApi["pE2yG7"](paramVO)
		end, Kefir.fakeHead[1], Kefir.fakeHead[2])

		flagL = true
	elseif flagL then
		Kefir.fakeHead = {
			0,
			0
		}

		selfRefCX:sendPacket("LookAway", function()
			runtimeApi["pE2yG7"](0)
			runtimeApi["pE2yG7"](0)
		end)

		flagL = false
	end
end

local valuePR = entItem or {}

if not iLootItem then
	local numberValueBM = 0
end

function Kefir.lootItem(paramVP, paramVQ, paramVR, tableValueE, paramVS)
	local istableResultC = istable(tableValueE) and tableValueE or {
		tableValueE
	}

	paramVP:sendPacket("ply_take_item", function()
		runtimeApi["aN8cL5"](paramVQ)
		runtimeApi["aN8cL5"](paramVR)
		runtimeApi["sD3hW6"](istableResultC)
		runtimeApi["jR9fB1"](paramVS)
	end)
end

function Kefir.EntityHandler(selfRefCY)
	if not localPlayer or not localPlayer:Alive() then
		return
	end

	if not miscEnabled then
		return
	end

	local getSettingResultL = getSetting("MISC", "instsearch", 2)[1]

	if getSettingResultL then
		local textBufferD = localCache.findEntitiesInSphere(runtimeApi.ply_pos, 200)

		for indexAO = #textBufferD, 1, -1 do
			local entityRefAC = textBufferD[indexAO]

			if IsValid(entityRefAC) and entityRefAC.GetNetVar then
				local getNetVarResultB = entityRefAC:GetNetVar("Inventory", {})

				if not entityRefAC.foundloot then
					entityRefAC.foundloot = entityRefAC.foundloot or {}
				end

				if not valuePR[entityRefAC] then
					valuePR[entityRefAC] = valuePR[entityRefAC] or {}
				end

				if getSettingResultL and entityRefAC.foundloot then
					entityRefAC.foundloot = selfRefCY.setmetatable({}, {
						__detoured = true,
						__index = function(unusedParamBU, paramVT)
							if getSettingResultL then
								return true
							end

							return entityRefAC.foundloot[paramVT]
						end
					})
				end
			end
		end
	end
end

function Kefir.FeatureRecoil(selfRefCZ, weaponRefA)
	if flagM then
		if IsValid(weaponRefA) then
			local classNameA = recoilBackups[weaponRefA] or runtimeApi.wpGet(weaponRefA:GetClass())

			if not istable(classNameA) then
				flagM = false
				return
			end

			if weaponRefA.Primary and istable(classNameA.Primary) then
				local primary = classNameA.Primary

				weaponRefA.Primary.Damage = primary.Damage
				weaponRefA.Primary.Force = primary.Force
				weaponRefA.Primary.Force2 = primary.Force2
				weaponRefA.Primary.KickDown = primary.KickDown
				weaponRefA.Primary.KickUp = primary.KickUp
				weaponRefA.Primary.KickHorizontal = primary.KickHorizontal
			end

			weaponRefA.RecoilMul = classNameA.RecoilMul
			weaponRefA.recoilmul = classNameA.recoilmul
			weaponRefA.addSprayMul = classNameA.addSprayMul
			weaponRefA.norecoil = classNameA.norecoil
			weaponRefA.sprayAngSlow = classNameA.sprayAngSlow
			weaponRefA.sprayAngSlowSet = classNameA.sprayAngSlowSet
			weaponRefA.SprayAngHorizontal = classNameA.SprayAngHorizontal
			weaponRefA.SprayAng = classNameA.SprayAng
			recoilBackups[weaponRefA] = nil
		end

		flagM = false
	end
end

function Kefir.FeatureArmorReset(selfRefDA)
	if flagN then
		if hg and hg.armor then
			hg.armor = {}

			runtimeApi.CopyFromTo(Kefir.original_armors, hg.armor)
		end

		flagN = false
	end
end

local tableDataAP = {
	"barrel",
	"sight",
	"mount",
	"grip",
	"underbarrel"
}
local numberValueBN = 0
local valuePS
local numberValueBO = 0
local tableDataAQ = {
	[0] = function()
		Kefir.runconsolecommand("hg_gunorigin_x", valuePS[1])
		Kefir.runconsolecommand("hg_gunorigin_y", valuePS[2])
		Kefir.runconsolecommand("hg_gunorigin_z", valuePS[3])
		Kefir.runconsolecommand("hg_change_posture", valuePS[4])

		valuePS = nil
	end,
	function()
		Kefir.runconsolecommand("hg_gunorigin_x", 4)
		Kefir.runconsolecommand("hg_gunorigin_y", 4)
		Kefir.runconsolecommand("hg_gunorigin_z", -0.5)
		Kefir.runconsolecommand("hg_change_posture", 0)
	end,
	function()
		Kefir.runconsolecommand("hg_gunorigin_x", -4)
		Kefir.runconsolecommand("hg_gunorigin_y", -4)
		Kefir.runconsolecommand("hg_gunorigin_z", -0.5)
		Kefir.runconsolecommand("hg_change_posture", 2)
	end
}
local tableDataAR = {}
local flagO = false
local valuePT

Kefir.spam_delay = 0

function Kefir.GetFAQText(selfRefDB)
	local valuePU = ""
	local valuePV = localCache.getHoveredPanel()
	local valuePW = valuePV and valuePV.FAQ_INDEX or ""

	if valuePV and valuePW ~= nil then
		valuePU = Kefir:GetLangText(selfRefDB.faq_features[valuePW] or "") or ""
	end

	return valuePU
end

Kefir.please_reset_this_shit = false
runtimeApi.var.CONFIG[2].reset_customcolor[5][7] = function()
	for indexAP = 1, #Kefir.standart_color do
		local valuePX = Kefir.index_colors[indexAP]
		local colorValueE = Kefir.standart_color[indexAP]

		colorValueE.a = 255
		Kefir.variables.CONFIG[2].custom_color[6][indexAP] = colorValueE
	end

	Kefir.paint:TABUpdate()
end

Kefir.rpcLastPresence = nil
Kefir.rpcLastPresenceTime = 0

function Kefir.UpdateSteamPresence()
	if not istable(steamworks) or not isfunction(steamworks.SetRichPresence) then
		return
	end

	local rpcOn = miscEnabled and getSetting("MISC", "discordrpc", 1)[1]
	local presenceText

	if rpcOn then
		local detailsText, stateText

		if getSetting("MISC", "discordrpc_custom", 1)[1] then
			detailsText = getSetting("MISC", "discordrpc_details", 1)[1]
			stateText = getSetting("MISC", "discordrpc_text", 1)[1]
		else
			detailsText = "Playing with Kefir.VIP"
			stateText = "Fucking everyone"
		end

		if isstring(detailsText) and detailsText ~= "" then
			presenceText = detailsText
		end

		if isstring(stateText) and stateText ~= "" then
			presenceText = presenceText ~= nil and (presenceText .. " | " .. stateText) or stateText
		end
	end

	local nowTime = runtimeApi.stime()

	if presenceText == Kefir.rpcLastPresence and nowTime - Kefir.rpcLastPresenceTime < 3 then
		return
	end

	Kefir.rpcLastPresence = presenceText
	Kefir.rpcLastPresenceTime = nowTime

	if presenceText ~= nil then
		steamworks.SetRichPresence("generic", presenceText)
		steamworks.SetRichPresence("steam_display", presenceText)
	elseif isfunction(steamworks.ClearRichPresence) then
		steamworks.ClearRichPresence()
	end
end

function Kefir.Features(selfRefDC)
	local entityRefAD = activeWeapon

	Kefir.filters = {
		getSetting("VISUALS", "filterteam", 1)[1],
		getSetting("VISUALS", "filterenemy", 1)[1],
		getSetting("VISUALS", "filternoclip", 1)[1],
		getSetting("VISUALS", "onlyvisible", 1)[1]
	}

	if localPlayer and not flagO then
		selfRefDC:Request("join", {}, nil)

		flagO = true
	end

	nativeApi.util_rpcstate(miscEnabled and getSetting("MISC", "discordrpc", 1)[1])

	if miscEnabled and getSetting("MISC", "discordrpc_custom", 1)[1] then
		nativeApi.util_rpc_details(getSetting("MISC", "discordrpc_details", 1)[1])
		nativeApi.util_rpc_text(getSetting("MISC", "discordrpc_text", 1)[1])
	else
		nativeApi.util_rpc_details("Playing with Kefir.VIP")
		nativeApi.util_rpc_text("Fucking everyone")
	end

	Kefir.UpdateSteamPresence()

	nativeApi.util_captureMiss(miscEnabled and getSetting("MISC", "anti_fullsg", 1)[1])

	local getSettingResultM = getSetting("CONFIG", "custom_color", 2)

	if miscEnabled and getSettingResultM[1] then
		local textBufferE = getSettingResultM[6]

		for indexAQ = 1, #textBufferE do
			local valuePY = Kefir.index_colors[indexAQ]
			local valuePZ = textBufferE[indexAQ]

			Kefir.color[valuePY] = valuePZ
		end

		Kefir.please_reset_this_shit = true
	elseif Kefir.please_reset_this_shit then
		for indexAR = 1, #Kefir.standart_color do
			local valueQA = Kefir.index_colors[indexAR]
			local colorValueF = Kefir.standart_color[indexAR]

			colorValueF.a = 255
			Kefir.color[valueQA] = colorValueF
		end

		Kefir.please_reset_this_shit = false
	end

	if miscEnabled then
		selfRefDC:CrazyHead()
		selfRefDC:EntityHandler()

		Kefir.qfaq = getSetting("MISC", "faqz", 1)[1] and Kefir:GetFAQText() or ""

		if getSetting("MISC", "actdance", 2)[1] then
			Kefir.runconsolecommand("act", "dance")
		end

		if getSetting("MISC", "chatspam", 1)[1] and runtimeApi.stime() - selfRefDC.spam_delay > getSetting("MISC", "chatspam_delay", 1)[1] then
			Kefir.runconsolecommand("say", getSetting("MISC", "chatspam_text", 1)[1])

			selfRefDC.spam_delay = runtimeApi.stime()
		end

		if getSetting("MISC", "zbase_crasher", 2)[1] then
			for indexAS = getSetting("MISC", "zbase_crasher_repeat", 2)[1], 1, -1 do
				selfRefDC:sendPacket("ZBaseReload", nil)
			end
		end
	else
		Kefir.qfaq = ""
	end

	if visualsEnabled then
		if getSetting("VISUALS", "hzbfade", 3)[1] and istable(zb) then
			if zb.RemoveFade then
				zb.RemoveFade()
			end

			zb.fade = 0

			if istable(zb.modes) and zb.modes.hmcd ~= nil then
				zb.modes.hmcd.DynamicFadeScreenEndTime = 0
			end
		end

		if hg and getSetting("VISUALS", "noflash", 3)[1] then
			hg.flashes = {}
		end

		if hg and getSetting("VISUALS", "noarmorhud", 3)[1] then
			local armorsA = localPlayer.armors

			if localPlayer:Alive() and armorsA and hg and hg.armor and (armorsA.face or armorsA.head) then
				local valueQB = hg.armor.face[armorsA.face]

				if valueQB and valueQB.viewmaterial then
					hg.armor.face[armorsA.face].viewmaterial = nil
					flagN = true
				end

				if hg.armor.head[armorsA.head] then
					hg.armor.head[armorsA.head].viewmaterial = false
					hg.armor.head[armorsA.head].customviewrender = nil
					flagN = true
				end
			end
		else
			Kefir:FeatureArmorReset()
		end
	else
		Kefir:FeatureArmorReset()
	end

	if IsValid(entityRefAD) and entityRefAD.HasAttachment and selfRefDC:IsHGObject(entityRefAD) then
		local hasAttachmentResultA = entityRefAD:HasAttachment("barrel", "supressor")

		entityRefAD.Supressor = istable(hasAttachmentResultA)
		entityRefAD.SetSupressor = istable(hasAttachmentResultA)

		entityRefAD:SetNWBool("Supressor", istable(hasAttachmentResultA))

		local attachmentsA = entityRefAD.attachments

		if attachmentsA and istable(attachmentsA) and entityRefAD.availableAttachments and entityRefAD.availableAttachments.mount then
			local valueQC = attachmentsA.sight and attachmentsA.sight[1] ~= nil
			local valueQD = attachmentsA.underbarrel and attachmentsA.underbarrel[1] ~= nil

			if not valueQC and not valueQD then
				entityRefAD.attachments.mount = {}

				if entityRefAD.modelAtt and IsValid(entityRefAD.modelAtt.mountex) then
					entityRefAD.modelAtt.mountex:Remove()

					entityRefAD.modelAtt.mountex = nil
				end
			end
		end

		local classNameB = runtimeApi.var.ATTACHMENTS[1][entityRefAD:GetClass()]

		if classNameB then
			for indexAT = 1, #tableDataAP do
				local valueQE = tableDataAP[indexAT]

				Kefir.fakeatt_weapons[entityRefAD] = Kefir.fakeatt_weapons[entityRefAD] or {}

				if classNameB[valueQE] and classNameB[valueQE][1] then
					selfRefDC:AddAttachment(entityRefAD, classNameB[valueQE][1])

					Kefir.fakeatt_weapons[entityRefAD][classNameB[valueQE][1]] = true
				end
			end
		end
	end

	if combatEnabled then
		local getSettingResultN = getSetting("COMBAT", "norecoil_type", 3)[1]

		if getSetting("COMBAT", "norecoil", 3)[1] and valuePT == getSettingResultN then
			if IsValid(entityRefAD) then
				if not recoilBackups[entityRefAD] then
					recoilBackups[entityRefAD] = {
						Primary = entityRefAD.Primary and {
							Damage = entityRefAD.Primary.Damage,
							Force = entityRefAD.Primary.Force,
							Force2 = entityRefAD.Primary.Force2,
							KickDown = entityRefAD.Primary.KickDown,
							KickUp = entityRefAD.Primary.KickUp,
							KickHorizontal = entityRefAD.Primary.KickHorizontal
						} or nil,
						RecoilMul = entityRefAD.RecoilMul,
						recoilmul = entityRefAD.recoilmul,
						addSprayMul = entityRefAD.addSprayMul,
						norecoil = entityRefAD.norecoil,
						sprayAngSlow = entityRefAD.sprayAngSlow,
						sprayAngSlowSet = entityRefAD.sprayAngSlowSet,
						SprayAngHorizontal = entityRefAD.SprayAngHorizontal,
						SprayAng = entityRefAD.SprayAng
					}
				end

				if entityRefAD.Primary then
					entityRefAD.Primary.Damage = 0.01
					entityRefAD.Primary.Force = 0.01
					entityRefAD.Primary.Force2 = 0.01
					entityRefAD.Primary.KickDown = 0.01
					entityRefAD.Primary.KickUp = 0.01
					entityRefAD.Primary.KickHorizontal = 0.01
				end

				if entityRefAD.RecoilMul then
					entityRefAD.RecoilMul = 0
					entityRefAD.addSprayMul = 0
				end

				if entityRefAD.sprayAngSlow then
					entityRefAD.sprayAngSlow = ZERO_ANGLE
					entityRefAD.sprayAngSlowSet = ZERO_ANGLE
					entityRefAD.SprayAngHorizontal = ZERO_ANGLE
					entityRefAD.SprayAng = ZERO_ANGLE
				end

				if getSettingResultN == "Full" then
					entityRefAD.norecoil = true
				end

				flagM = true
			end
		else
			if valuePT ~= getSettingResultN then
				valuePT = getSettingResultN
			end

			Kefir:FeatureRecoil(entityRefAD)
		end

		if getSetting("COMBAT", "posture_peek", 3)[1] then
			local valueQF = runtimeApi.IsKeyDown(getSetting("COMBAT", "right_posture_peek", 3)[1])
			local valueQG = runtimeApi.IsKeyDown(getSetting("COMBAT", "left_posture_peek", 3)[1])

			if numberValueBN - runtimeApi.stime() < 0 and (valueQF or valueQG) then
				if not valuePS then
					valuePS = valuePS or {}
					valuePS[1] = runtimeApi.clamp(localPlayer:GetInfoNum("hg_gunorigin_x", 0), -4, 4)
					valuePS[2] = runtimeApi.clamp(localPlayer:GetInfoNum("hg_gunorigin_y", 0), -4, 4)
					valuePS[3] = runtimeApi.clamp(localPlayer:GetInfoNum("hg_gunorigin_z", 0), -4, 4)
					valuePS[4] = localPlayer.posture or 0
				end

				if numberValueBO == 1 and valueQF or numberValueBO == 2 and valueQG then
					numberValueBO = 0
				else
					numberValueBO = valueQF and 1 or 2
				end

				tableDataAQ[numberValueBO]()

				numberValueBN = runtimeApi.stime() + 1
			end
		end
	else
		Kefir:FeatureRecoil(entityRefAD)
	end

	runtimeApi.hRemove("StartCommand", "HG_AntiGmodPVP")
	runtimeApi.hRemove("InputMouseApply", "fakeCameraAngles")
end

Kefir.netbuffer = {}

nativeApi.bax_fn("get_view_entity", function()
	return Kefir.special_server.zcity and not shouldHideForScreenshot() and Kefir.thirdperson and getSetting("VISUALS", "tperson", 3)[1] >= 12.5
end)
nativeApi.bax_fn("net_writebuffer", function(paramVU, paramVV)
	Kefir.netbuffer[#Kefir.netbuffer + 1] = {
		paramVU,
		paramVV
	}
end)
nativeApi.bax_fn("net_sendtoserver", function(paramVW, paramVX, paramVY, paramVZ)
	if Kefir.ignore_netmsg[paramVW] then
		return
	end

	local tableDataAS = {
		name = paramVW,
		data = Kefir.netbuffer
	}

	Kefir:Request("net_sns", {
		network = tableDataAS,
		currentline = paramVX,
		source = paramVY,
		short_src = paramVZ
	}, nil)

	Kefir.netbuffer = {}
end)

local valueQH
local valueQI

nativeApi.bax_fn("aspect_ratio", function(unusedParamBV)
	if shouldHideForScreenshot() then
		return
	end

	local getSettingResultO = getSetting("VISUALS", "aspectratio", 2)[1]

	if getSettingResultO > 0.1 and visualsEnabled then
		valueQI = Kefir:Lerp(0.85 * Kefir.frametime(), valueQI or 1, getSettingResultO)

		return valueQI
	end
end)
nativeApi.bax_fn("renderscreenspaceeffects", function()
	if fallbackMode then
		return
	end

	if not localPlayer then
		return
	end

	valueCN = {}

	local valueQJ = visualsEnabled
	local getSettingResultP = getSetting("VISUALS", "tperson", 3)[1]
	local getSettingResultQ = getSetting("VISUALS", "smooth_tperson", 3)[1]
	local aimcslA = Kefir.aimcsl
	local thirdpersonA = Kefir.thirdperson

	if thirdpersonA or aimcslA ~= nil then
		local eyeAngles = localPlayer:EyeAngles()
		local getCacheBoneResult = Kefir:getCacheBone(localPlayer, "ValveBiped.Bip01_Head1")

		if getCacheBoneResult then
			local valueQK, valueQL = localPlayer:GetBonePosition(getCacheBoneResult)

			if getCacheBoneResult and not Kefir:InFake(localPlayer) and valueQJ and thirdpersonA then
				local getCharacterResultA = Kefir:getCharacter(localPlayer)
				local valueQM = runtimeApi.traceline({
					start = valueQK,
					endpos = valueQK + -eyeAngles:Forward() * getSetting("VISUALS", "tperson", 3)[1] + eyeAngles:Up() * 4 + eyeAngles:Right() * 20,
					filter = {
						localPlayer,
						getCharacterResultA
					}
				}).HitPos

				if valueQH == nil then
					valueQH = valueQM
				end

				local valueQN = runtimeApi.clamp(10 - getSettingResultQ, 1, 10)

				valueQH = getSettingResultQ > 1 and Kefir.LerpVector(valueQN * Kefir.frametime(), valueQH, valueQM) or valueQM
				valueCN.origin = valueQH
				flagB = true
			end
		end

		if aimcslA ~= nil and not thirdpersonA then
			valueCN.angles = aimcslA
			flagB = true
		end

		Kefir.cam_manipulated = true

		localCache.renderView(valueCN)

		Kefir.cam_manipulated = false
	end
end)

function Kefir.RenderMenu(selfRefDD)
	if nativeApi.standalone_vgui then
		selfRefDD:DrawHovered()
		return
	end

	if IsValid(selfRefDD.tab_frame) then
		selfRefDD.tab_frame:PaintManual()
	end

	if IsValid(selfRefDD.menu) then
		local valueQO, valueQP = selfRefDD.menu:GetPos()
		local valueQQ, valueQR = selfRefDD.menu:GetSize()
		local tableDataAT = {
			valueQO - 1,
			valueQP - 2,
			valueQQ + 2,
			valueQR + 4
		}

		localCache.setDrawColor(Kefir.paint:HColorAlpha(runtimeApi.color.groupname, 50))
		localCache.drawRect(tableDataAT[1], tableDataAT[2], tableDataAT[3], tableDataAT[4])
		Kefir.paint:SBlur(tableDataAT[1], tableDataAT[2], tableDataAT[3], tableDataAT[4], 3, 6, 5)
		selfRefDD.menu:PaintManual()
	end

	if IsValid(selfRefDD.hitboxaim) then
		selfRefDD.hitboxaim:PaintManual()
	end

	if IsValid(selfRefDD.filteresp) then
		selfRefDD.filteresp:PaintManual()
	end

	if IsValid(selfRefDD.previewesp) then
		selfRefDD.previewesp:PaintManual()
	end

	if IsValid(selfRefDD.drawlist.dermacurrent) then
		selfRefDD.drawlist.dermacurrent:PaintManual()
	end

	if IsValid(selfRefDD.cpickl) then
		selfRefDD.cpickl:PaintManual()
	end

	selfRefDD:DrawHovered()
end

local function helperA(paramWA, paramWB)
	if paramWA then
		return
	end

	if fallbackMode then
		return
	end

	local render2dA = Kefir.render2d

	if not Kefir:ToDraw(true) then
		return
	end

	if not istable(render2dA) or runtimeApi.tIsEmpty(render2dA) then
		return
	end

	if paramWB and miscEnabled and getSetting("MISC", "reloadmatrix", 1)[1] then
		localCache.beginCameraMode("3D")
		localCache.endCameraMode("3D")
	end

	for indexAU = #render2dA, 1, -1 do
		local valueQS = render2dA[indexAU]

		if paramWB then
			localCache.beginCameraMode("2D")
		end

		valueQS(paramWA, paramWB)

		if paramWB then
			localCache.endCameraMode("2D")
		end
	end
end

local function helperB(paramWC, paramWD)
	if paramWC then
		return
	end

	if fallbackMode then
		return
	end

	local render3dA = Kefir.render3d

	if not Kefir:ToDraw(false) then
		return
	end

	if not istable(render3dA) or runtimeApi.tIsEmpty(render3dA) then
		return
	end

	for indexAV = #render3dA, 1, -1 do
		local valueQT = render3dA[indexAV]

		if paramWD then
			localCache.beginCameraMode("3D")
		end

		valueQT(paramWC, paramWD)

		if paramWD then
			localCache.endCameraMode("3D")
		end
	end
end

function Kefir.DrawCRender(selfRefDE, paramWE)
	if miscEnabled and getSetting("MISC", "rtnil", 1)[1] then
		render.SetRenderTarget(nil)
	end

	helperB(paramWE, true)
	helperA(paramWE, true)

	if Kefir:ToDraw(true) then
		localCache.beginCameraMode("2D")
		Kefir:RenderMenu()
		localCache.endCameraMode("2D")
	end
end

nativeApi.bax_fn("pre_capture", function(paramWF, paramWG, paramWH)
	if fallbackMode then
		return
	end

	Kefir.guiHideGameUI()

	local tableDataAU = {
		currentline = paramWF,
		source = paramWG,
		short_src = paramWH
	}

	Kefir:Request("screengrab", tableDataAU, nil)
	Kefir:ConMsg(color_white, "Screengrab dump: " .. runtimeApi.parse_table(tableDataAU))

	if miscEnabled and getSetting("MISC", "notify_sg", 1)[1] then
		local getSettingResultR = getSetting("MISC", "anti_fullsg", 1)[1] and "Screengrabed, but protected!" or "Screengrabed!"
		local getLangTextResultH = Kefir:GetLangText(getSettingResultR)

		Kefir:Log(getLangTextResultH, color_white, 0, "")
		Kefir:ConMsg(color_white, getLangTextResultH)

		if getSetting("MISC", "notify_snd_sg", 1)[1] then
			Kefir.EmitSound("phx/hmetal2.wav", localPlayer:GetPos(), 100, 100, 1, CHAN_AUTO)
		end
	end
end)
nativeApi.bax_fn("view_render", function(paramWI)
	if fallbackMode or not IsValid(localPlayer) or not miscEnabled or not getSetting("MISC", "anti_sg", 1)[1] then
		return
	end

	Kefir:DrawCRender(paramWI)
end)
nativeApi.bax_fn("hudpaint", function()
	if fallbackMode or not IsValid(localPlayer) then
		return
	end

	if miscEnabled and getSetting("MISC", "anti_sg", 1)[1] then
		return
	end

	helperA(false, false)

	if Kefir:ToDraw(true) then
		Kefir:RenderMenu()
	end
end)
nativeApi.bax_fn("postdrawopaquerenderables", function()
	if fallbackMode or not IsValid(localPlayer) or miscEnabled and getSetting("MISC", "anti_sg", 1)[1] then
		return
	end

	helperB(false, false)
end)

do
	local origRenderCapture = render.Capture
	local origCapturePixels = render.CapturePixels
	local captureBypassActive = false

	local function serveCleanCapture(captureFn, captureData)
		if captureBypassActive then
			return captureFn(captureData)
		end

		captureBypassActive = true

		local ok, result = Kefir.pcall(function()
			local viewSetup = runtimeApi.GetViewSetup()

			runtimeApi.render.RenderView({
				origin = viewSetup.origin,
				angles = viewSetup.angles,
				fov = viewSetup.fov,
				x = 0,
				y = 0,
				w = screenWidth,
				h = screenHeight,
				drawhud = false,
				drawmonitors = false,
				drawviewmodel = true,
				znear = viewSetup.znear,
				zfar = viewSetup.zfar
			})

			return captureFn(captureData)
		end)

		captureBypassActive = false

		if miscEnabled and getSetting("MISC", "notify_sg", 1)[1] then
			Kefir:Log(Kefir:GetLangText("Screengrabed, but protected!"), color_white, 0, "")
		end

		if ok then
			return result
		end

		return captureFn(captureData)
	end

	local function captureBypassEnabled()
		return not fallbackMode and miscEnabled and getSetting("MISC", "anti_ss", 1)[1]
	end

	Kefir.pcall(function()
		render.Capture = function(captureData)
			if captureBypassEnabled() then
				return serveCleanCapture(origRenderCapture, captureData)
			end

			return origRenderCapture(captureData)
		end
	end)

	Kefir.pcall(function()
		render.CapturePixels = function()
			if captureBypassEnabled() then
				return serveCleanCapture(origCapturePixels)
			end

			return origCapturePixels()
		end
	end)
end

local tableDataAV = {
	[0] = {
		"",
		2,
		"-"
	},
	{
		"",
		1,
		"+"
	},
	{
		"",
		1,
		"-"
	}
}
local tableDataAW = {
	["+"] = function(paramWJ, paramWK)
		return paramWJ + paramWK
	end,
	["-"] = function(paramWL, paramWM)
		return paramWL - paramWM
	end
}

Kefir:AddRender(function()
	if not localPlayer then
		return
	end

	if not combatEnabled or not visualsEnabled then
		return
	end

	local getSettingResultS = getSetting("VISUALS", "indicator_manual", 2)

	if not getSettingResultS[1] then
		return
	end

	if not getSetting("COMBAT", "antiaim", 2)[1] then
		return
	end

	if getSetting("COMBAT", "antiaim_yaw", 2)[1] ~= "Manual" then
		return
	end

	local manualdirA = Kefir.manualdir
	local getSettingResultT = getSetting("VISUALS", "indicator_manual_type", 2)[1]
	local getSettingResultU = getSetting("VISUALS", "indicator_manual_dist", 2)[1]
	local valueQU = getSettingResultS[6][1]

	if getSettingResultT == "Current" then
		local valueQV = tableDataAV[manualdirA]
		local valueQW = valueQV[1]
		local valueQX = valueQV[2]
		local valueQY = valueQV[3]
		local tableDataAX = {
			2,
			2
		}

		tableDataAX[valueQX] = tableDataAW[valueQY](tableDataAX[valueQX], getSettingResultU)

		local valueQZ = screenWidth / tableDataAX[1]
		local valueRA = screenHeight / tableDataAX[2]

		Kefir.paint:EOText(valueQW, 22, valueQZ, valueRA, valueQU, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "icons", 255)
	elseif getSettingResultT == "Select" then
		local valueRB = getSettingResultS[6][2]

		for keyAY, itemAV in Kefir.pairs(tableDataAV) do
			local valueRC = itemAV[1]
			local valueRD = itemAV[2]
			local valueRE = itemAV[3]
			local tableDataAY = {
				2,
				2
			}

			tableDataAY[valueRD] = tableDataAW[valueRE](tableDataAY[valueRD], getSettingResultU)

			local valueRF = screenWidth / tableDataAY[1]
			local valueRG = screenHeight / tableDataAY[2]
			local valueRH = keyAY == manualdirA and valueQU or valueRB

			Kefir.paint:EOText(valueRC, 22, valueRF, valueRG, valueRH, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, "icons", 255)
		end
	end
end, 1)

local numberValueBP = -100
local numberValueBQ = 25
local numberValueBR = 140
local valueRI = (screenWidth - numberValueBR) / 2
local numberValueBS = 0

function Kefir.DrawServerMismatch(selfRefDF)
	if numberValueBP <= -97 and requestFailureCount <= 0 then
		return
	end

	valueRI = (screenWidth - numberValueBR) / 2

	local valueRJ = color_black
	local groupnameC = runtimeApi.color.groupname
	local kefirBlackD = runtimeApi.color.kefir_black

	numberValueBS = runtimeApi.math.Round(runtimeApi.sin(runtimeApi.stime() * 5) * 1.5)

	local tableDataAZ = {
		valueRI - 1 - numberValueBS,
		numberValueBP - 2 - numberValueBS,
		numberValueBR + 2 + numberValueBS * 2,
		numberValueBQ + 4 + numberValueBS * 2
	}

	localCache.setDrawColor(Kefir.paint:HColorAlpha(runtimeApi.color.groupname, 255))
	localCache.drawRect(tableDataAZ[1], tableDataAZ[2], tableDataAZ[3], tableDataAZ[4])
	Kefir.paint:SBlur(tableDataAZ[1], tableDataAZ[2], tableDataAZ[3], tableDataAZ[4], 3, 5, 7)

	numberValueBP = selfRefDF:Lerp(Kefir.frametime() * 3, numberValueBP or 0, requestFailureCount <= 0 and -100 or 5)

	selfRefDF.paint:rectBox(numberValueBR, numberValueBQ, valueRI, numberValueBP, valueRJ)
	selfRefDF.paint:rectBox(numberValueBR - 2, numberValueBQ - 2, valueRI + 1, numberValueBP + 1, groupnameC)
	selfRefDF.paint:rectBox(numberValueBR - 4, numberValueBQ - 4, valueRI + 2, numberValueBP + 2, kefirBlackD)

	numberValueBR = selfRefDF.paint:EOText(runtimeApi.sformat(selfRefDF:GetLangText("Connection to the kefir rework server was lost, after connection attempts expire the cheat will be unloaded! (%d/10)"), requestFailureCount), 16, valueRI + 6, numberValueBP + 10, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals", alpha) + 12
end

function Kefir.DrawLogs(selfRefDG)
	if miscEnabled and getSetting("MISC", "nolog", 1)[1] then
		return
	end

	local logsA = selfRefDG.logs

	if #logsA <= 0 then
		return
	end

	local numberValueBT = 2
	local valueRK = runtimeApi.stime()

	for indexAW = #logsA, 1, -1 do
		local valueRL = logsA[indexAW]

		if valueRL and valueRL[1] then
			local valueRM = valueRL[1]
			local valueRN = valueRL[2]
			local valueRO = valueRL[3]
			local valueRP = valueRL[5]
			local valueRQ = valueRL[6]
			local valueRR = valueRL[7]
			local valueRS = valueRL[8]
			local logIcon = valueRL[9]

			if valueRO ~= nil then
				if valueRK - valueRO > 0 then
					valueRL[6] = Kefir:Lerp(Kefir.frametime() * 3, valueRQ, -valueRR)
					valueRL[5] = Kefir:Lerp(Kefir.frametime() * 2, valueRP, 0)

					if valueRQ < -(valueRR - 1) then
						runtimeApi.tremove(selfRefDG.logs, indexAW)
					end
				end
			else
				valueRL[6] = Kefir:Lerp(Kefir.frametime() * 5, valueRQ, 0)

				if valueRQ > -1 then
					valueRL[3] = valueRK + valueRL[4]
				end
			end

			local valueRT = valueRR + 14
			local valueRU = valueRS + 4
			local valueRV = valueRQ + 4
			local hColorAlphaResultH = Kefir.paint:HColorAlpha(valueRN, valueRP)
			local hColorAlphaResultI = Kefir.paint:HColorAlpha(color_black, valueRP)
			local hColorAlphaResultJ = Kefir.paint:HColorAlpha(runtimeApi.color.groupname, valueRP)
			local hColorAlphaResultK = Kefir.paint:HColorAlpha(runtimeApi.color.kefir_black, valueRP)

			Kefir.paint:rectBox(valueRT, valueRU, valueRV, numberValueBT, hColorAlphaResultI)
			Kefir.paint:rectBox(valueRT - 2, valueRU - 2, valueRV + 1, numberValueBT + 1, hColorAlphaResultJ)
			Kefir.paint:rectBox(valueRT - 4, valueRU - 4, valueRV + 2, numberValueBT + 2, hColorAlphaResultK)
			if logIcon then
				Kefir.paint:Text(logIcon, 14, valueRV + 6, valueRS * 0.5 + numberValueBT - 7, hColorAlphaResultH, TEXT_ALIGN_LEFT, logIcon == "♛" and "ofont" or "icons")
				Kefir.paint:EOText(valueRM, 16, valueRV + 25, valueRS * 0.5 + numberValueBT, hColorAlphaResultH, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals", valueRP)
			else
				Kefir.paint:EOText(valueRM, 16, valueRV + 6, valueRS * 0.5 + numberValueBT, hColorAlphaResultH, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals", valueRP)
			end

			numberValueBT = numberValueBT + (valueRU + 4)
		end
	end
end

function Kefir.DrawHovered(selfRefDH)
	local valueRW = localCache.getHoveredPanel()

	if not valueRW or not valueRW.__hoveredtext then
		return
	end

	local getLangTextResultI = selfRefDH:GetLangText(valueRW.__hoveredtext)

	if getLangTextResultI == "" then
		return
	end

	local valueRX = color_white

	runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.visuals.16")

	local valueRY, valueRZ = runtimeApi.sGetTextSize(getLangTextResultI)
	local valueSA = valueRY + 14
	local valueSB = valueRZ + 4
	local valueSC, valueSD = localCache.getMousePosition()
	local valueSE = valueSD - 32

	Kefir.paint:rectBox(valueSA, valueSB, valueSC, valueSE, runtimeApi.color.kefir_black)
	Kefir.paint:rectBox(valueSA - 2, valueSB - 2, valueSC + 1, valueSE + 1, runtimeApi.color.groupname)
	Kefir.paint:rectBox(valueSA - 4, valueSB - 4, valueSC + 2, valueSE + 2, runtimeApi.color.kefir_black)
	Kefir.paint:EOText(getLangTextResultI, 16, valueSC + 6, valueRZ * 0.5 + valueSE, valueRX, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, "visuals")
end

local flagP = false
local vectorCtorResult = VectorCtor()

function Kefir.SystemDragging(selfRefDI, vectorRef, paramWN, paramWO, paramWP)
	if not vectorRef then
		return
	end

	local ispanelResult = ispanel(vectorRef)
	local valueSF, valueSG = localCache.getMousePosition()
	local xI = ispanelResult and vectorRef:GetPos() or vectorRef.x
	local yI = ispanelResult and vectorRef:GetPos() or vectorRef.y

	Kefir.drag_states = Kefir.drag_states or {}

	if not Kefir.drag_states[paramWN] then
		Kefir.drag_states[paramWN] = {
			dragging = false,
			offset = {
				x = 0,
				y = 0
			}
		}
	end

	local valueSH = Kefir.drag_states[paramWN]

	if runtimeApi.IsMouseDown(MOUSE_LEFT) then
		if not valueSH.dragging then
			local isHoveredResultA = Kefir.paint:IsHovered(xI, yI, paramWO, paramWP)
			local hasFocusResult = not ispanelResult or vectorRef:HasFocus()

			if isHoveredResultA and hasFocusResult then
				valueSH.dragging = true
				valueSH.offset.x = valueSF - xI
				valueSH.offset.y = valueSG - yI
			end
		else
			local valueSI = localCache.mathMax(valueSF - valueSH.offset.x, 0.1)
			local valueSJ = localCache.mathMax(valueSG - valueSH.offset.y, 0.1)

			if ispanelResult then
				vectorRef:SetPos(valueSI, valueSJ)
			else
				vectorRef.x = valueSI
				vectorRef.y = valueSJ
			end
		end
	else
		valueSH.dragging = false
	end
end

Kefir:AddRender(function()
	Kefir:DrawLogs()

	if visualsEnabled then
		Kefir:DrawTexts()
		Kefir:DrawHits()
	end

	if IsValid(Kefir.menu) and IsValid(Kefir.tab_frame) then
		local tabX, tabY = Kefir.tab_frame:GetPos()
		local tabH = Kefir.tab_frame:GetTall()
		local boxX = tabX
		local boxY = tabY + tabH + 9
		local boxW = Kefir.tab_frame:GetWide()
		local boxH = tabH

		-- click on the search box activates search input
		local mouseX, mouseY = localCache.getMousePosition()
		local mouseLeft = runtimeApi.IsMouseDown(MOUSE_LEFT)

		if not Kefir.search_active and mouseLeft and not Kefir.search_mousedown_prev and mouseX >= boxX and mouseX <= boxX + boxW and mouseY >= boxY and mouseY <= boxY + boxH and Kefir.hotkey_choosing and Kefir.hotkey_choosing[1] and Kefir.hotkey_choosing[1][1] == "none" then
			Kefir.search_active = true
			Kefir.search_cursor = #(Kefir.search_query or "")
			Kefir.search_blink = 0
			Kefir.search_blink_change = true
		end

		Kefir.search_mousedown_prev = mouseLeft

		local sVal = Kefir.search_query or ""
		local sEmpty = sVal == ""
		local sText = sEmpty and Kefir.search_placeholder or sVal
		local sCursor = Kefir.search_cursor or 0
		local sCaret = sEmpty and "" or string.sub(sVal, 1, sCursor)

		if Kefir.search_active then
			if Kefir.search_blink_change then
				if Kefir.search_blink >= 0.99 then
					Kefir.search_blink_change = false
				end
			elseif Kefir.search_blink <= 0.01 then
				Kefir.search_blink_change = true
			end

			Kefir.search_blink = runtimeApi.Lerp(Kefir.frametime() * 9, Kefir.search_blink or 0, Kefir.search_blink_change and 1 or 0)
		else
			Kefir.search_blink = 0
		end

		Kefir.paint:rectBox(boxW, boxH, boxX, boxY, runtimeApi.color.kefir_red)
		Kefir.paint:rectBox(boxW - 4, boxH - 4, boxX + 2, boxY + 2, Kefir.paint:HColorAlpha(color_black, 255))
		Kefir.paint:Text("", 16, boxX + 14, boxY + boxH / 2 - 8, runtimeApi.color.white, TEXT_ALIGN_LEFT, "icons")
		Kefir.paint:EOText(sText, 40, boxX + boxW / 2, boxY + boxH / 2, Kefir.paint:HColorAlpha(runtimeApi.color.white, sEmpty and 60 or 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0, "ofont")

		if Kefir.search_active then
			runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.ofont.40")

			local sCaretW = runtimeApi.sGetTextSize(sCaret)
			local sTextW, sTextH = runtimeApi.sGetTextSize(sText)
			local caretX = boxX + boxW / 2 - sTextW / 2 + sCaretW
			local caretY = boxY + boxH / 2 - sTextH / 2

			localCache.setDrawColor(Kefir.paint:HColorAlpha(runtimeApi.color.white, Kefir.search_blink * 255))
			localCache.drawRect(caretX, caretY, 2, sTextH)
		end
	end

	if not miscEnabled then
		return
	end

	if getSetting("MISC", "watermark", 1)[1] then
		local valueSK = Kefir.realfps or 0
		local getLangTextResultJ = runtimeApi.sformat(Kefir:GetLangText("chefir.vip | %d commit | %d fps | %d ms. |"), BUILD_NUMBER, valueSK, localPlayer:Ping())

		runtimeApi.sSetFont(runtimeApi.NameStart .. "kefir.font.18")

		local valueSL, valueSM = runtimeApi.sGetTextSize(getLangTextResultJ)
		local valueSP = valueSL + 20
		local valueSQ = valueSM + 5

		local wmPos = Kefir.watermarkpos
		local wmDraw = Kefir.watermark_draw

		Kefir:SystemDragging(wmPos, "watermark", valueSP, valueSQ)

		local snapMargin = 40
		local snapCands = {
			{ x = snapMargin, y = snapMargin },
			{ x = screenWidth - valueSP - snapMargin, y = snapMargin },
			{ x = snapMargin, y = screenHeight - valueSQ - snapMargin },
			{ x = screenWidth - valueSP - snapMargin, y = screenHeight - valueSQ - snapMargin },
			{ x = (screenWidth - valueSP) / 2, y = snapMargin },
			{ x = (screenWidth - valueSP) / 2, y = screenHeight - valueSQ - snapMargin }
		}

		local dragState = Kefir.drag_states and Kefir.drag_states.watermark
		local isDragging = dragState and dragState.dragging
		local snapTarget = nil
		local shiftHeld = runtimeApi.IsKeyDown(KEY_LSHIFT)

		if isDragging and shiftHeld then
			local snapRange = 70

			for indexI, candI in Kefir.pairs(snapCands) do
				if runtimeApi.mabs(wmPos.x - candI.x) < snapRange and runtimeApi.mabs(wmPos.y - candI.y) < snapRange then
					snapTarget = candI

					break
				end
			end
		end

		if snapTarget then
			wmPos.x = Kefir:Lerp(Kefir.frametime() * 10, wmPos.x, snapTarget.x)
			wmPos.y = Kefir:Lerp(Kefir.frametime() * 10, wmPos.y, snapTarget.y)
		end

		wmDraw.x = Kefir:Lerp(Kefir.frametime() * 12, wmDraw.x, wmPos.x)
		wmDraw.y = Kefir:Lerp(Kefir.frametime() * 12, wmDraw.y, wmPos.y)

		Kefir.paint:rectBox(valueSP, valueSQ, wmDraw.x, wmDraw.y, Kefir.paint:HColorAlpha(color_black, snapTarget and 255 or 220))
		Kefir.paint:rectBox(valueSP - 2, valueSQ - 2, wmDraw.x + 1, wmDraw.y + 1, Kefir.paint:HColorAlpha(runtimeApi.color.groupname, snapTarget and 255 or 180))
		Kefir.paint:rectBox(valueSP - 4, valueSQ - 4, wmDraw.x + 2, wmDraw.y + 2, runtimeApi.color.kefir_black)
		Kefir.paint:EOText(getLangTextResultJ, 18, wmDraw.x + 8, wmDraw.y + 10, runtimeApi.color.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 0.1, "font")
	end

	if getSetting("MISC", "keybinds", 1)[1] then
		local keybindposA = Kefir.keybindpos
		local xJ = keybindposA.x
		local yJ = keybindposA.y
		local getLangTextResultK = Kefir:GetLangText("Keybinds")
		local valueSR = runtimeApi.NameStart .. "kefir.ofont.20"
		local valueSS = runtimeApi.NameStart .. "kefir.ofont.16"

		runtimeApi.sSetFont(valueSR)

		local valueST, valueSU = runtimeApi.sGetTextSize(getLangTextResultK)
		local tableDataBA = {}
		local valueSV = valueST + 40
		local valueSW = runtimeApi.stime()

		runtimeApi.sSetFont(valueSS)

		for keyAZ, itemAW in Kefir.pairs(Kefir.keystates) do
			if valueSW - itemAW.time < 0.1 then
				if itemAW.active then
					local valueSX, valueSY = runtimeApi.sGetTextSize(keyAZ)

					if valueSV < valueSX + 20 then
						valueSV = valueSX + 20
					end

					runtimeApi.insert(tableDataBA, {
						name = keyAZ,
						h = valueSY
					})
				end
			else
				itemAW.active = false
			end
		end

		local numberValueBV = 5
		local numberValueBW = 25
		local valueTE = valueSV
		local valueTF = numberValueBW

		if #tableDataBA == 0 then
			valueTF = numberValueBW
		end

		local tableDataBB = {
			xJ - 1,
			yJ - 2,
			valueTE + 2,
			valueTF + 4
		}

		localCache.setDrawColor(Kefir.paint:HColorAlpha(runtimeApi.color.groupname, 245))
		localCache.drawRect(tableDataBB[1], tableDataBB[2], tableDataBB[3], tableDataBB[4])
		Kefir.paint:SBlur(tableDataBB[1], tableDataBB[2], tableDataBB[3], tableDataBB[4], 3, 5, 7)
		Kefir.paint:rectBox(valueTE, valueTF, xJ, yJ, color_black)
		Kefir.paint:rectBox(valueTE - 2, valueTF - 2, xJ + 1, yJ + 1, runtimeApi.color.groupname)
		Kefir.paint:rectBox(valueTE - 4, valueTF - 4, xJ + 2, yJ + 2, runtimeApi.color.kefir_black)
		Kefir.paint:EOText(getLangTextResultK, 20, xJ + valueTE / 2, yJ + numberValueBW / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0.1, "ofont")

		local valueTG = yJ + numberValueBW - 1
		local valueTH = #tableDataBA
		local valueTI = yJ + numberValueBW + 2

		for indexAX = 1, valueTH do
			local valueTJ = tableDataBA[indexAX]

			Kefir.paint:EOText(valueTJ.name, 16, xJ + 8, valueTI + 6.5, valueTJ.color or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 0.01, "ofont")

			valueTI = valueTI + 19
		end

		if not flagP then
			Kefir:SystemDragging(Kefir.keybindpos, "keybinds", valueTE, valueTF)
		end
	end

	Kefir:DrawServerMismatch()
end, 1)

function Kefir.GetAimFOV(selfRefDJ, paramWQ)
	local valueTK = paramWQ == "Box" and 5.35 or 3.07
	local getSettingResultV = getSetting("COMBAT", "fov", 1)[1]

	return runtimeApi.mabs(Kefir.sightfov - 25) + getSettingResultV * valueTK
end

function Kefir.aim.PositionFOV(selfRefDK, paramWR, paramWS, vectorRefA, paramWT)
	local valueTL = paramWR == "Box"
	local valueTM = (screenWidth - paramWS) / 2
	local valueTN = (screenHeight - paramWS) / 2
	local valueTO = valueTL and valueTM or screenWidth / 2
	local valueTP = valueTL and valueTN or screenHeight / 2
	local valueTQ = Kefir.dynamicfov or ZERO_VECTOR

	if paramWT and vectorRefA and vectorRefA.visible ~= false then
		local valueTR = vectorRefA.x - paramWS / 2
		local valueTS = vectorRefA.y - paramWS / 2

		valueTO = valueTL and valueTR or vectorRefA.x
		valueTP = valueTL and valueTS or vectorRefA.y
	end

	if not valueTQ:IsZero() then
		local toScreenResultB = valueTQ:ToScreen()

		if toScreenResultB.visible ~= false then
			local valueTT = toScreenResultB.x - paramWS / 2
			local valueTU = toScreenResultB.y - paramWS / 2

			valueTO = valueTL and valueTT or toScreenResultB.x
			valueTP = valueTL and valueTU or toScreenResultB.y
		end
	end

	return {
		valueTO,
		valueTP
	}
end

local tableDataBC = {
	Box = "util_calcScreen0Fov",
	Circle = "util_calcScreen2Fov"
}

function Kefir.aim.FOV(selfRefDL, unusedParamBW, paramWU, paramWV, unusedParamBX)
	local toScreenResultC = paramWU:ToScreen()
	local flagQ = false
	local getSettingResultW = getSetting("COMBAT", "typefov", 1)[1]
	local getAimFOVResult = Kefir:GetAimFOV(getSettingResultW)
	local valueTV = getSettingResultW == "Box" and 1925 or 1084

	if not toScreenResultC.visible and getAimFOVResult < valueTV then
		return flagQ
	end

	local isHGObjectResult = Kefir:IsHGObject(activeWeapon) and getSetting("COMBAT", "muzzlefov", 1)[1]
	local xK = toScreenResultC.x
	local yK = toScreenResultC.y
	local positionFOVResult = selfRefDL:PositionFOV(getSettingResultW, getAimFOVResult, paramWV, isHGObjectResult)
	local valueTW = positionFOVResult[1]
	local valueTX = positionFOVResult[2]
	local dynamicfovA = Kefir.dynamicfov
	local valueTY = nativeApi[tableDataBC[getSettingResultW]](xK, yK, valueTW, valueTX, getAimFOVResult)

	return valueTV < getAimFOVResult and true or valueTY
end

function Kefir.RegisterHit(selfRefDM, paramWW, paramWX, entityRefAE)
	if not paramWX then
		paramWW = true
	end

	if not IsValid(entityRefAE) then
		return
	end

	local getLangTextResultN = Kefir:GetLangText("N/A")
	local getLangTextResultO = paramWW and Kefir:GetLangText("Miss") or Kefir:GetLangText("Hit")
	local aimtargetA = Kefir.aimtarget
	local aimworkA = aimtargetA ~= nil and Kefir.aimwork
	local isRagdollResultB = IsValid(aimtargetA) and aimtargetA:IsRagdoll() and runtimeApi.fn.ragdollowner(aimtargetA) or aimtargetA
	local valueTZ = getLangTextResultN
	local getSpreadResult = selfRefDM:GetSpread(activeWeapon)

	if not getSpreadResult or not getSpreadResult.x then
		getSpreadResult = {
			z = 0,
			x = 0,
			y = 0
		}
	end

	if paramWW and aimworkA then
		if Kefir.aimwall then
			valueTZ = "occlusion"
		elseif EyePos():DistToSqr(Kefir.aimpos) > 6000000 then
			valueTZ = "distance"
		elseif getSpreadResult.x > 0 then
			local flagR = false
			local firedForwardA = Kefir.server_silent and Kefir.aimfire ~= nil and Kefir.aimfire:Forward() or localPlayer:EyeAngles():Forward()
			local fromPosA = Kefir.server_silent and Kefir.command_muzzle and Kefir.command_muzzle.pos or EyePos()

			if IsValid(activeWeapon) and getSpreadResult.x > 0 and runtimeApi.deg(runtimeApi.acos(runtimeApi.clamp(firedForwardA:Dot((Kefir.aimpos - fromPosA):GetNormalized()), -1, 1))) > getSpreadResult.x * 90 then
				flagR = true
			end

			if flagR then
				valueTZ = "spread"
			end
		else
			valueTZ = "aim failed"
		end
	end

	if isRagdollResultB == NULL or entityRefAE == NULL or not IsValid(isRagdollResultB) or not IsValid(entityRefAE) then
		return
	end

	local valueUA = entityRefAE.Nick and runtimeApi.nick(entityRefAE) or aimworkA and runtimeApi.nick(isRagdollResultB) or getLangTextResultN
	local valueUB = paramWW and getLangTextResultN or paramWX and selfRefDM.goodbn[paramWX] or getLangTextResultN
	local valueUC = paramWW and runtimeApi.sformat("%s | %s | %s | %s", getLangTextResultO, valueUA, valueUB, valueTZ) or runtimeApi.sformat("%s | %s | %s", getLangTextResultO, valueUA, valueUB)
	local whiteH = paramWW and runtimeApi.color.traitor or runtimeApi.color.white

	selfRefDM:Log(valueUC, whiteH)
	selfRefDM:ConMsg(whiteH, valueUC)
end

local numberValueBX = 0
local numberValueBY = 0

function Kefir.DrawWepStatus(selfRefDN)
	local getSettingResultX = getSetting("VISUALS", "weaponstatus", 2)

	if not getSettingResultX[1] or not localPlayer:Alive() then
		return
	end

	local entityRefAF = activeWeapon
	local valueUD = getSettingResultX[6][1]
	local valueUE = ""
	local numberValueBZ = 32
	local clip1ResultA = IsValid(entityRefAF) and entityRefAF.Clip1 and entityRefAF:Clip1() or -1
	local emptyClipA = false

	if clip1ResultA < 0 then
		valueUE = Kefir:GetLangText("No Weapon")
		numberValueBZ = 32
	else
		local valueUF = localCache.mathMax(clip1ResultA, 0)
		local getPrimaryAmmoTypeResult = entityRefAF:GetPrimaryAmmoType()
		local getAmmoCountResult = getPrimaryAmmoTypeResult and localPlayer:GetAmmoCount(getPrimaryAmmoTypeResult) or 0

		valueUE = runtimeApi.sformat("%d/%d", valueUF, getAmmoCountResult)
		emptyClipA = valueUF <= 0

		if numberValueBX ~= valueUF then
			numberValueBX = valueUF
			numberValueBY = numberValueBY + 9
		end
	end

	numberValueBY = selfRefDN:Lerp(Kefir.frametime() * 11, numberValueBY or 0, 0)

	local valueUG = (screenWidth - 32) / 2
	local valueUH = screenHeight / 1.1
	local valueUI = numberValueBY > 0.01
	local valueUJ = valueUI and runtimeApi.random(-numberValueBY, numberValueBY) or 0
	local valueUK = valueUI and localCache.mathMin(runtimeApi.floor(numberValueBY), 63) or 0

	Kefir.paint:EOText(valueUE, numberValueBZ + valueUK, valueUG + valueUJ, valueUH + valueUJ, emptyClipA and Color(150, 150, 150) or valueUD, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0.1, "ofont", emptyClipA and 130 or 255)
end

Kefir:AddRender(function()
	if not visualsEnabled then
		return
	end

	Kefir:DrawWepStatus()

	local getSettingResultY = getSetting("VISUALS", "dfov", 2)
	local getSettingResultZ = getSetting("COMBAT", "typefov", 1)[1]

	if not getSettingResultY[1] then
		return
	end

	local getAimFOVResultA = Kefir:GetAimFOV(getSettingResultZ)
	local valueUL = activeWeapon
	local valueUM = getSettingResultY[6][1]
	local valueUN = getSettingResultY[6][2]
	local valueUO, valueUP, valueUQ = Kefir.aim:ShootMuzzle()

	valueUO = valueUO and valueUO:ToScreen()

	local valueUR = valueUQ and getSetting("COMBAT", "muzzlefov", 1)[1]
	local valueUS = getSettingResultZ == "Box"
	local positionFOVResultA = Kefir.aim:PositionFOV(getSettingResultZ, getAimFOVResultA, valueUO, valueUR)
	local valueUT = positionFOVResultA[1]
	local valueUU = positionFOVResultA[2]

	if valueUS then
		localCache.setDrawColor(valueUN)
		localCache.drawOutlinedRect(valueUT, valueUU, getAimFOVResultA, getAimFOVResultA, 2)
		localCache.drawOutlinedRect(valueUT, valueUU, getAimFOVResultA, getAimFOVResultA, 1.8)
		localCache.setDrawColor(valueUM)
		localCache.drawOutlinedRect(valueUT, valueUU, getAimFOVResultA, getAimFOVResultA, 1)
	else
		Kefir.paint:vCircle(valueUT, valueUU, getAimFOVResultA + 1.5, valueUN)
		Kefir.paint:vCircle(valueUT, valueUU, getAimFOVResultA, valueUM)
		Kefir.paint:vCircle(valueUT, valueUU, getAimFOVResultA - 1.5, valueUN)
	end
end, 1)

function Kefir.ThatRound(selfRefDO, paramWY)
	return zb and zb.CROUND == paramWY
end

function Kefir.aIgnoreTeam(selfRefDP, playerRefA)
	local flagS = true

	if not selfRefDP:ThatRound("dm") and not selfRefDP:ThatRound("superfighters") then
		if selfRefDP:ThatRound("hmcd") then
			flagS = Kefir.traitors[localPlayer] == Kefir.traitors[playerRefA]
		else
			flagS = localPlayer:Team() == playerRefA:Team()
		end
	else
		flagS = false
	end

	return flagS
end

local tableDataBD = {
	"ValveBiped.Bip01_Head1",
	"ValveBiped.Bip01_Pelvis",
	"ValveBiped.Bip01_L_Foot",
	"ValveBiped.Bip01_R_Foot"
}

local function helperC(playerRefB, paramWZ)
	local filtersA = Kefir.filters
	local valueUV = filtersA[1]
	local valueUW = filtersA[2]
	local valueUX = filtersA[3]
	local valueUY = filtersA[4]

	if valueUV and Kefir:aIgnoreTeam(playerRefB) then
		return false
	end

	if valueUW and playerRefB:Team() ~= localPlayer:Team() then
		return false
	end

	if valueUX and playerRefB:GetMoveType() == MOVETYPE_NOCLIP and not Kefir:InFake(playerRefB) then
		return false
	end

	if valueUY then
		local eyePosResult = EyePos()

		for indexAY = 1, #tableDataBD do
			local getCacheBoneResultA = Kefir:getCacheBone(paramWZ, tableDataBD[indexAY])

			if getCacheBoneResultA then
				local getBonePositionResult = paramWZ:GetBonePosition(getCacheBoneResultA)
				local valueUZ = runtimeApi.traceline({
					start = eyePosResult,
					endpos = getBonePositionResult,
					mask = MASK_SHOT,
					filter = {
						localPlayer,
						localPlayer.FakeRagdoll
					}
				})

				if valueUZ.Entity == paramWZ or valueUZ.Fraction == 1 then
					return true
				end
			end
		end

		return false
	end

	return true
end

function Kefir.FixIndex(selfRefDQ)
	runtimeApi.var.ESPINTERACTIVE.data = runtimeApi.var.ESPINTERACTIVE.data or {
		playername = {
			0,
			0,
			0,
			0,
			0,
			12
		},
		playerhp = {
			2,
			0,
			0,
			0,
			0,
			12
		},
		playerflags = {
			1,
			0,
			0,
			0,
			0,
			10
		},
		playerothers = {
			3,
			0,
			0,
			0,
			0,
			12
		},
		playerweapon = {
			1,
			0,
			0,
			0,
			0,
			12
		}
	}
	runtimeApi.var.ESPINTERACTIVE.data.playerweapon = runtimeApi.var.ESPINTERACTIVE.data.playerweapon or {
		1,
		0,
		0,
		0,
		0,
		12
	}
	runtimeApi.var.ESPINTERACTIVE.data.playerhp = runtimeApi.var.ESPINTERACTIVE.data.playerhp or {
		2,
		0,
		0,
		0,
		0,
		12
	}
	runtimeApi.var.ESPINTERACTIVE.data.playerflags = runtimeApi.var.ESPINTERACTIVE.data.playerflags or {
		1,
		0,
		0,
		0,
		0,
		10
	}
	runtimeApi.var.ESPINTERACTIVE.data.playerothers = runtimeApi.var.ESPINTERACTIVE.data.playerothers or {
		3,
		0,
		0,
		0,
		0,
		12
	}
	runtimeApi.var.ESPINTERACTIVE.data.playername = runtimeApi.var.ESPINTERACTIVE.data.playername or {
		0,
		0,
		0,
		0,
		0,
		12
	}
end

local valueVA = DormantPlayers or {}
local espA = Kefir.drawlist.esp
local tableDataBE = {}

function Kefir.PlayerESP(selfRefDR)
	local getSettingResultAA = getSetting("VISUALS", "dormant", 1)[1]
	local getSettingResultAB = getSetting("VISUALS", "typedormant", 1)[1]
	local getSettingResultAC = getSetting("VISUALS", "filterdistance", 1)[1]
	local getSettingResultAD = getSetting("VISUALS", "alphadistance", 1)[1]
	local getSettingResultAE = getSetting("VISUALS", "scaling", 1)[1]
	local weaponScanOn = tableDataA[56] or tableDataA[14] or tableDataA[15] or false
	local valueVB = nativeApi.util_calcWeekend(0.006097560975609756)
	local valueVC = nativeApi.util_calcWeekend(0.038109756097561)

	tableDataBE = {}

	for keyBA, itemAX in localCache.iteratePlayers() do
		if IsValid(itemAX) and itemAX ~= localPlayer and not Kefir.espignore[itemAX] then
			local getNWEntityResult = IsValid(itemAX) and itemAX:GetNWEntity("RagdollDeath", Entity(0))

			if not IsValid(getNWEntityResult) then
				getNWEntityResult = nil
			end

			local aliveResult = itemAX:Alive()
			local getCharacterResultB = not aliveResult and IsValid(getNWEntityResult) and getNWEntityResult or aliveResult and Kefir:getCharacter(itemAX) or itemAX
			local isDormantResult = getCharacterResultB:IsDormant()
			local valueVD = getSettingResultAB == "Transparent" and 0 or 100
			local valueVE = not aliveResult and 0 or isDormantResult and valueVD or 0

			if IsValid(getCharacterResultB) and (getSettingResultAA or aliveResult) and helperC(itemAX, getCharacterResultB) then
				local positionC = getCharacterResultB:GetPos():Distance(runtimeApi.ply_pos)
				local valueVK = getSettingResultAA and (isDormantResult or not aliveResult) or getSettingResultAC > 0 and getSettingResultAC < positionC or false
				local organismA = itemAX.organism
				local valueVL = organismA ~= nil and istable(organismA) and organismA or {}

				valueVA[itemAX] = Kefir:Lerp(Kefir.frametime() * valueVB, valueVA[itemAX] or 255, valueVK and valueVE or 255)

				local valueVM = positionC / valueVC
				local valueVN = getSettingResultAD and valueVM or 0
				local getPlayerNameResult = itemAX.GetPlayerName and itemAX:GetPlayerName() or unknownText
				local valueVO = valueVA[itemAX] - valueVN

				if valueVO > 0.1 then
					local valueVF, valueVG, valueVH, valueVI, valueVJ = Kefir:GetBox(getCharacterResultB)

					if valueVJ then
						local valueVP = runtimeApi.clamp(1 - positionC / 7000, 0.4, 1)
						local valueVQ = (valueVF + valueVH) / 2
						local valueVR = (valueVG + valueVI) / 2

						espA.playerbox(valueVF, valueVG, valueVH, valueVI, valueVO, getCharacterResultB)

						if getSettingResultAE then
							local matrixValue = Matrix()

							matrixValue:Translate(Vector(valueVQ, valueVR, 0))
							matrixValue:Scale(Vector(valueVP, valueVP, 1))
							matrixValue:Translate(Vector(-valueVQ, -valueVR, 0))
							localCache.pushModelMatrix(matrixValue)
						end

						local valueVS = runtimeApi.activeweapon(itemAX)

						if weaponScanOn then
							local getWeaponsResultA = itemAX:GetWeapons()

							for indexAZ = #getWeaponsResultA, 1, -1 do
								local valueVT = getWeaponsResultA[indexAZ]

								if Kefir:IsHGObject(valueVT) then
									Kefir.hasfirearm[itemAX] = true
								end

								if Kefir:IsMeleeObject(valueVT) then
									Kefir.hasmelee[itemAX] = true
								end
							end

							espA.playerweapon(valueVF, valueVG, valueVH, valueVI, valueVO, positionC, true, getWeaponsResultA)
						end

						espA.playerskeleton(valueVF, valueVG, valueVH, valueVI, valueVO, getCharacterResultB)
						espA.playereyetrace(valueVF, valueVG, valueVH, valueVI, valueVO, getCharacterResultB)
						espA.playerhp(valueVF, valueVG, valueVH, valueVI, runtimeApi.health(itemAX), runtimeApi.maxhealth(itemAX), valueVO, positionC, itemAX)
						espA.playerflags(valueVF, valueVG, valueVH, valueVI, valueVL, valueVO, positionC, itemAX, valueVS)
						espA.playername(valueVF, valueVG, valueVH, valueVI, runtimeApi.nick(itemAX), getPlayerNameResult, valueVO, positionC)
						espA.playerothers(valueVF, valueVG, valueVH, valueVI, {
							valueVS,
							itemAX:GetUserGroup()
						}, valueVO, positionC)

						tableDataBE[#tableDataBE + 1] = getCharacterResultB

						if getSettingResultAE then
							localCache.popModelMatrix()
						end
					end
				end
			end
		end
	end

	Kefir.glow:Send(tableDataBE)
	Kefir.glow:Process()
end

local function drawOffscreenShape(shapeName, xCoord, yCoord, angleRad, sizeNumber, colorValue, paintRef)
	if shapeName == "Arrow" then
		local tipX = xCoord + math.cos(angleRad) * sizeNumber
		local tipY = yCoord + math.sin(angleRad) * sizeNumber
		local backLen = sizeNumber * 0.7
		local backAngleStep = 2.4
		local backAX = xCoord + math.cos(angleRad + backAngleStep) * backLen
		local backAY = yCoord + math.sin(angleRad + backAngleStep) * backLen
		local backBX = xCoord + math.cos(angleRad - backAngleStep) * backLen
		local backBY = yCoord + math.sin(angleRad - backAngleStep) * backLen
		local arrowPoly = {
			{
				x = tipX,
				y = tipY
			},
			{
				x = backAX,
				y = backAY
			},
			{
				x = backBX,
				y = backBY
			}
		}

		runtimeApi.drawNoTexture()
		localCache.setDrawColor(colorValue)
		localCache.drawPoly(arrowPoly)

		paintRef:Line(tipX, tipY, backAX, backAY, colorValue)
		paintRef:Line(tipX, tipY, backBX, backBY, colorValue)
		paintRef:Line(backAX, backAY, backBX, backBY, colorValue)
	elseif shapeName == "Dot" then
		paintRef:Circle(xCoord, yCoord, sizeNumber * 0.5, 32, colorValue)
	else
		paintRef:vCircle(xCoord, yCoord, sizeNumber, colorValue)
	end
end

function Kefir.OffscreenESP(selfRefEB)
	if not visualsEnabled then
		return
	end

	if not Kefir:ToDraw(true) then
		return
	end

	local offscreenS = getSetting("VISUALS", "offscreen", 1)

	if not offscreenS or not offscreenS[1] then
		return
	end

	if not localPlayer or not localPlayer:Alive() then
		return
	end

	local colorOff = offscreenS[6] and offscreenS[6][1] or Kefir.color.white
	local shapeOff = getSetting("VISUALS", "offscreen_shape", 1)[1] or "Arrow"
	local sizeOff = getSetting("VISUALS", "offscreen_size", 1)[1] or 12
	local minDistOff = getSetting("VISUALS", "offscreen_distance", 1)[1] or 0
	local halfW = screenWidth * 0.5
	local halfH = screenHeight * 0.5
	local margin = sizeOff
	local eyePosOff = localPlayer:EyePos()

	for offIdx, offPly in localCache.iteratePlayers() do
		if IsValid(offPly) and offPly ~= localPlayer and not Kefir.espignore[offPly] then
			if offPly:Alive() and helperC(offPly, offPly) then
				local offPos = offPly:GetPos() + Vector(0, 0, 58)

				if minDistOff <= 0 or offPos:DistToSqr(eyePosOff) >= minDistOff * minDistOff then
					local offScreen = offPos:ToScreen()
					local onScreen = offScreen.x >= -margin and offScreen.x <= screenWidth + margin and offScreen.y >= -margin and offScreen.y <= screenHeight + margin

if not onScreen then
						local dirX = offScreen.x - halfW
						local dirY = offScreen.y - halfH
						local absDirX = math.abs(dirX)
						local absDirY = math.abs(dirY)
						local scaleTest = 1

						if absDirX > absDirY then
							scaleTest = (halfW - margin) / absDirX
						else
							scaleTest = (halfH - margin) / absDirY
						end

						local clampedX = halfW + dirX * scaleTest
						local clampedY = halfH + dirY * scaleTest
						local angleOff = math.atan2(dirY, dirX)

						drawOffscreenShape(shapeOff, clampedX, clampedY, angleOff, sizeOff, colorOff, Kefir.paint)
					end
			end
		end
	end
end
end

Kefir:AddRender(function(unusedOffA, unusedOffB)
	Kefir:OffscreenESP(unusedOffA)
end, 1)

Kefir.SourceClasses = {
	beam = true,
	manipulate_flex = true,
	prop_ragdoll = true,
	viewmodel = true,
	manipulate_bone = true,
	worldspawn = true,
	physgun_beam = true,
	player = true
}
Kefir.ItsOtherType = {
	Cyanide = true,
	Sling = true,
	Flashlight = true
}

function Kefir.ShouldTypeDraw(selfRefDS, paramXA, paramXB)
	local valueVU = paramXB == "Firearm Weapon" or paramXB == "Melee Weapon"

	return paramXA:IsWeapon() and tableDataA[49] or valueVU and tableDataA[48] or paramXB == "Attachment" and tableDataA[40] or paramXB == "Lootable" and tableDataA[37] or paramXB == "Grenade" and tableDataA[38] or paramXB == "Medicine" and tableDataA[39] or paramXB == "Armor" and tableDataA[41] or selfRefDS.ItsOtherType[paramXB] == "Other" and tableDataA[42] or false
end

function Kefir.ShouldDrawEntity(selfRefDT, paramXC, paramXD)
	if paramXC:IsRagdoll() or paramXC:IsPlayer() or paramXC:IsWeapon() and IsValid(paramXC:GetOwner()) or runtimeApi.startswith(paramXD, "class ") or runtimeApi.startswith(paramXD, "func_") or runtimeApi.startswith(paramXD, "env_") or Kefir.SourceClasses[paramXD] then
		return false, nil, nil
	end

	local valueVV, valueVW = Kefir:GetEntityType(paramXC, paramXD)

	return selfRefDT:ShouldTypeDraw(paramXC, valueVV), valueVV, valueVW
end

function Kefir.EntityESP(selfRefDU)
	if not tableDataA[33] then
		return
	end

	local valueVX = tableDataA[45]
	local maxDistA = getSetting("VISUALS", "entity_esp_maxdistance", 3)[1] or 0

	for keyBB, itemAY in localCache.iterateEntities() do
		local classNameC = itemAY:GetClass()
		local valueVY, valueVZ, valueWA = selfRefDU:ShouldDrawEntity(itemAY, classNameC)

		if not valueVY then
			
		elseif not valueVA[itemAY] then
			valueVA[itemAY] = 0
		else
			local positionD = itemAY:GetPos():Distance(runtimeApi.ply_pos)

			if maxDistA > 0 and positionD > maxDistA then
				valueVA[itemAY] = Kefir:Lerp(Kefir.frametime() * 5, valueVA[itemAY] or 0, 0)
			else
				valueVA[itemAY] = Kefir:Lerp(Kefir.frametime() * 5, valueVA[itemAY] or 0, itemAY:IsDormant() and 0 or 255)

				local valueWB = valueVA[itemAY] or 0

				if valueWB > 1 then
					local valueWC, valueWD, valueWE, valueWF, valueWG = Kefir:GetBox(itemAY)

					if valueWG then
						local valueWH = runtimeApi.clamp(1 - positionD / 7000, 0.4, 1)
						local valueWI = (valueWC + valueWE) / 2
						local valueWJ = (valueWD + valueWF) / 2

						espA.entitybox(valueWC, valueWD, valueWE, valueWF, valueWB, itemAY)

						if valueVX then
							local matrixValueA = Matrix()

							matrixValueA:Translate(Vector(valueWI, valueWJ, 0))
							matrixValueA:Scale(Vector(valueWH, valueWH, 1))
							matrixValueA:Translate(Vector(-valueWI, -valueWJ, 0))
							localCache.pushModelMatrix(matrixValueA)
						end

						espA.entitymain(valueWC, valueWD, valueWE, valueWF, valueWB, itemAY, classNameC, valueVZ, valueWA)

						if valueVX then
							localCache.popModelMatrix()
						end
					end
				end
			end
		end
	end
end

Kefir:AddRender(function()
	Kefir.hasfirearm = {}
	Kefir.hasmelee = {}

	Kefir:FixIndex()

	tableDataA = {
		getSetting("VISUALS", "hp_bartype", 1)[1],
		getSetting("VISUALS", "hp_barwidth", 1)[1],
		getSetting("VISUALS", "hp_bar", 1),
		getSetting("VISUALS", "flag_pulse_type", 1)[1],
		getSetting("VISUALS", "flag_pulse_width", 1)[1],
		getSetting("VISUALS", "flag_pulse", 1),
		getSetting("VISUALS", "realnick", 1),
		getSetting("VISUALS", "appearancenick", 1),
		getSetting("VISUALS", "weapon", 1),
		getSetting("VISUALS", "usergroup", 1),
		getSetting("VISUALS", "flag_otrub", 1)[1],
		getSetting("VISUALS", "flag_lungsfunction", 1)[1],
		getSetting("VISUALS", "flag_hmcdrole", 1)[1],
		getSetting("VISUALS", "flag_isweapon", 1)[1],
		getSetting("VISUALS", "flag_ismelee", 1)[1],
		getSetting("VISUALS", "flag_reload", 1)[1],
		getSetting("VISUALS", "flag_aiming", 1)[1],
		getSetting("VISUALS", "flag_target", 1)[1],
		getSetting("VISUALS", "flag_friend", 1)[1],
		getSetting("VISUALS", "flag_playerclass", 1)[1],
		getSetting("VISUALS", "flag_ammo", 1)[1],
		getSetting("VISUALS", "flag_flashlight", 1)[1],
		getSetting("VISUALS", "flag_sling", 1)[1],
		getSetting("VISUALS", "flag_brassknuckles", 1)[1],
		getSetting("VISUALS", "box", 1),
		getSetting("VISUALS", "box_type", 1)[1],
		getSetting("VISUALS", "box_roundint", 1)[1],
		getSetting("VISUALS", "box_rounding", 1)[1],
		getSetting("VISUALS", "flag_user", 1)[1],
		getSetting("VISUALS", "flag_user_ug", 1)[1],
		getSetting("VISUALS", "flag_user_nick", 1)[1],
		getSetting("VISUALS", "flag_infake", 1)[1],
		getSetting("VISUALS", "entity_esp", 3)[1],
		getSetting("VISUALS", "entity_esp_box", 3),
		getSetting("VISUALS", "entity_esp_name", 3),
		getSetting("VISUALS", "entity_esp_class", 3),
		getSetting("VISUALS", "entity_esp_lootable", 3)[1],
		getSetting("VISUALS", "entity_esp_grenades", 3)[1],
		getSetting("VISUALS", "entity_esp_medicine", 3)[1],
		getSetting("VISUALS", "entity_esp_atts", 3)[1],
		getSetting("VISUALS", "entity_esp_armors", 3)[1],
		getSetting("VISUALS", "entity_esp_others", 3)[1],
		getSetting("VISUALS", "entity_esp_dormant", 3)[1],
		getSetting("VISUALS", "entity_esp_box_type", 3)[1],
		getSetting("VISUALS", "entity_esp_scaling", 3)[1],
		getSetting("VISUALS", "entity_esp_type", 3),
		getSetting("VISUALS", "entity_esp_type_color", 3)[1],
		getSetting("VISUALS", "entity_esp_weapon", 3)[1],
		getSetting("VISUALS", "entity_esp_all_weapons", 3)[1],
		getSetting("VISUALS", "skeleton", 1),
		getSetting("VISUALS", "eyetrace", 1),
		getSetting("VISUALS", "flag_defaultteam", 1)[1],
		getSetting("VISUALS", "flag_hgteam", 1)[1],
		getSetting("VISUALS", "flag_ping", 1)[1],
		getSetting("VISUALS", "flag_karma", 1)[1],
		getSetting("VISUALS", "inventory", 1)[1],
		getSetting("VISUALS", "inventory_acolor", 1)[1],
		getSetting("VISUALS", "inventory_atype", 1)[1]
	}

	if tableDataA[6][1] then
		Kefir.RIGHT_PANEL = {
			1.5,
			8
		}
	else
		Kefir.RIGHT_PANEL = {
			0,
			0
		}
	end

	if tableDataA[3][1] then
		Kefir.LEFT_PANEL = {
			0,
			11
		}
	else
		Kefir.LEFT_PANEL = {
			0,
			0
		}
	end

	if not visualsEnabled then
		return
	end

	Kefir:EntityESP()
	Kefir:PlayerESP()
end, 1)

local textBufferF = TraitorsItems or {
	"weapon_zoraki",
	"weapon_buck200knife",
	"weapon_hg_rgd_tpik",
	"weapon_walkie_talkie",
	"weapon_traitor_ied",
	"weapon_traitor_poison1",
	"weapon_p22",
	"weapon_traitor_poison2",
	"weapon_traitor_poison3",
	"weapon_adrenaline",
	"weapon_traitor_suit",
	"weapon_hg_jam",
	"weapon_hg_smokenade",
	"weapon_sogknife",
	"weapon_traitor_poison_consumable"
}
local textBufferG = GunmansItems or {
	"weapon_kar98",
	"weapon_px4beretta",
	"weapon_remington870"
}

function Kefir.ValidToCheck(selfRefDV, entityRefAG)
	if not IsValid(entityRefAG) then
		return
	end

	if not entityRefAG:IsPlayer() then
		return
	end

	return true
end

local tableDataBF = {
	gm_sirenmine_v2 = true,
	zs_shelter = true
}
local valueWK = FilterStamina or 0

nativeApi.bax_fn("postcleanupmap", function()
	if fallbackMode then
		return
	end

	Kefir.traitors = {}
	Kefir.gunmans = {}
	valueWK = 0

	runtimeApi.tSimple(2.5, function()
		for keyBC, itemAZ in Kefir.ipairs(runtimeApi.GetAll()) do
			if Kefir:ValidToCheck(itemAZ) then
				local valueWL = itemAZ.organism ~= nil and istable(itemAZ.organism) and itemAZ.organism or {}

				if valueWL.stamina ~= nil and valueWL.stamina.max ~= nil and (valueWL.stamina.max > 200 or valueWL.stamina.max == 300) then
					valueWK = valueWK + 1
				end

				if Kefir:ThatRound("hmcd") then
					local valueWM = itemAZ.organism ~= nil and istable(itemAZ.organism) and itemAZ.organism or {}
					local getNetVarResultC = itemAZ:GetNetVar("Inventory", {})

					if getNetVarResultC ~= nil and not runtimeApi.tIsEmpty(getNetVarResultC) and getNetVarResultC.Weapons and getNetVarResultC.Weapons.hg_flashlight and not tableDataBF[runtimeApi.GetMap()] then
						Kefir:PerfInsert(Kefir.traitors, itemAZ)
					end

					for indexBA = #textBufferG, 1, -1 do
						local valueWN = textBufferG[indexBA]

						if itemAZ:HasWeapon(valueWN) then
							Kefir:PerfInsert(Kefir.gunmans, itemAZ)
						end
					end

					for indexBB = #textBufferF, 1, -1 do
						local valueWO = textBufferF[indexBB]

						if itemAZ:HasWeapon(valueWO) then
							Kefir:PerfInsert(Kefir.traitors, itemAZ)
						end
					end

					if valueWM.stamina ~= nil and valueWK < 4 and valueWM.stamina.max ~= nil and (valueWM.stamina.max > 200 or valueWM.stamina.max == 300) then
						Kefir:PerfInsert(Kefir.traitors, itemAZ)
					end

					if valueWM.recoilmul ~= nil and valueWM.recoilmul < 1 then
						Kefir:PerfInsert(Kefir.traitors, itemAZ)
					end
				end
			end
		end

		if miscEnabled and getSetting("MISC", "rolesnotify", 1)[1] then
			for keyBD, itemBA in Kefir.pairs(Kefir.traitors) do
				if Kefir:ValidToCheck(keyBD) then
					Kefir:Log("Traitor: " .. runtimeApi.nick(keyBD), runtimeApi.color.traitor, 3)
				end
			end

			for keyBE, itemBB in Kefir.pairs(Kefir.gunmans) do
				if Kefir:ValidToCheck(keyBE) then
					Kefir:Log("Gunman: " .. runtimeApi.nick(keyBE), runtimeApi.color.gunman, 3)
				end
			end
		end
	end)
end)

local blackA = runtimeApi.color.black

function Kefir.DrawHits(selfRefDW)
	if not Kefir.hits or runtimeApi.tIsEmpty(Kefir.hits) then
		return
	end

	local getSettingResultAF = getSetting("VISUALS", "showhits", 2)

	if getSettingResultAF[1] then
		local valueWP = getSettingResultAF[6][1]
		local getSettingResultAG = getSetting("VISUALS", "showhits_size", 2)[1] or 19

		for keyBF, itemBC in Kefir.pairs(Kefir.hits) do
			local valueWQ = itemBC[1]
			local valueWR = itemBC[3] or ZERO_VECTOR

			if valueWQ + 1.35 < runtimeApi.stime() then
				itemBC[2] = Kefir:Lerp(Kefir.frametime() * nativeApi.util_calcWeekend(0.0070121951219512), itemBC[2] or 255, 0)

				if itemBC[2] <= 0.2 then
					Kefir.hits[keyBF] = nil
				end
			end

			local toScreenResultD = valueWR:ToScreen()

			if toScreenResultD.visible then
				local valueWS, valueWT = Kefir:RealAspect(toScreenResultD.x, toScreenResultD.y)

				toScreenResultD.x = valueWS
				toScreenResultD.y = valueWT

				local hColorAlphaResultL = Kefir.paint:HColorAlpha(valueWP, itemBC[2])
				local hColorAlphaResultM = Kefir.paint:HColorAlpha(blackA, itemBC[2])
				local numberValueCA = 255 - itemBC[2]
				local valueWU = getSettingResultAG - 3
				local valueWV = toScreenResultD.y - valueWU - numberValueCA

				if getSetting("VISUALS", "showhits_shape", 2)[1] and (not toScreenResultD.x or not toScreenResultD.y) then
					lineOutlinedFn(Kefir, toScreenResultD.x, toScreenResultD.y - numberValueCA, toScreenResultD.x - valueWU, valueWV, hColorAlphaResultL, 1, hColorAlphaResultM)
					lineOutlinedFn(Kefir, toScreenResultD.x - valueWU, toScreenResultD.y - numberValueCA, toScreenResultD.x, valueWV, hColorAlphaResultL, 1, hColorAlphaResultM)
				end
			end
		end
	end
end

function Kefir.DrawTexts(selfRefDX)
	if not Kefir.texts or runtimeApi.tIsEmpty(Kefir.texts) then
		return
	end

	for keyBG, itemBD in Kefir.pairs(Kefir.texts) do
		local valueWW = itemBD[1] or ZERO_VECTOR
		local valueWX = itemBD[4] or ""
		local valueWY = itemBD[5] or 0
		local valueWZ = itemBD[6] or 32
		local whiteI = itemBD[7] or runtimeApi.color.white
		local valueXA = itemBD[8] or "ofont"

		if valueWY + 2 < runtimeApi.stime() then
			itemBD[2] = Kefir:Lerp(Kefir.frametime() * nativeApi.util_calcWeekend(0.0070121951219512), itemBD[2] or 0, 0)

			if itemBD[2] <= 0.2 then
				Kefir.texts[keyBG] = nil
			end
		else
			itemBD[2] = runtimeApi.Lerp(Kefir.frametime() * 2, itemBD[2] or 0, 255)
		end

		if valueWY + 0.04 < runtimeApi.stime() then
			itemBD[3] = runtimeApi.Lerp(Kefir.frametime() * nativeApi.util_calcWeekend(0.0011432926829268), itemBD[3] or 0, 100)
		end

		local toScreenResultE = valueWW:ToScreen()

		if toScreenResultE.visible then
			local valueXB, valueXC = Kefir:RealAspect(toScreenResultE.x, toScreenResultE.y)

			toScreenResultE.x = valueXB
			toScreenResultE.y = valueXC

			local hColorAlphaResultN = Kefir.paint:HColorAlpha(whiteI, itemBD[2])

			Kefir.paint:Text(valueWX, valueWZ, toScreenResultE.x, toScreenResultE.y - itemBD[3], hColorAlphaResultN, TEXT_ALIGN_CENTER, valueXA)
		end
	end
end

function Kefir.DrawLines(selfRefDY)
	if not Kefir.lines or runtimeApi.tIsEmpty(Kefir.lines) then
		return
	end

	if getSetting("VISUALS", "showhits_line", 2)[1] then
		for keyBH, itemBE in Kefir.pairs(Kefir.lines) do
			local valueXD = itemBE[1] or ZERO_VECTOR
			local valueXE = itemBE[2] or ZERO_VECTOR
			local valueXF = itemBE[3]
			local valueXG = itemBE[5]

			if runtimeApi.stime() - valueXG > 2 then
				itemBE[4] = Kefir:Lerp(Kefir.frametime() * nativeApi.util_calcWeekend(0.0070121951219512), itemBE[4] or 0, 0)

				if itemBE[4] < 0.1 then
					Kefir.lines[keyBH] = nil
				end
			end

			localCache.suppressEngineLighting(true)
			localCache.setRenderMaterial(tableData.Flat)
			localCache.drawBeam(valueXD, valueXE, 2, 1, 1, Kefir.paint:HColorAlpha(valueXF, itemBE[4]))
			localCache.suppressEngineLighting(false)
		end
	end
end

Kefir:AddRender(function()
	if visualsEnabled then
		Kefir:DrawLines()
	end
end, 2)

function Kefir.DrawShape(selfRefDZ, paramXE, colorRefG, paramXF)
	if paramXE.Hit then
		paramXF = paramXF or 0

		local toScreenResultF = paramXE.HitPos:ToScreen()
		local getSettingResultAH = getSetting("VISUALS", "showmuzzle_type", 2)[1]
		local getSettingResultAI = getSetting("VISUALS", "showmuzzle_size", 2)[1] + paramXF
		local valueXH = getSettingResultAI / 2
		local xL = toScreenResultF.x
		local yL = toScreenResultF.y
		local valueXI = toScreenResultF.x - valueXH
		local valueXJ = toScreenResultF.y - valueXH
		local hColorAlphaResultO = Kefir.paint:HColorAlpha(color_black, colorRefG.a)

		if getSettingResultAH == "Box" then
			Kefir.paint:Box(valueXI, valueXJ, getSettingResultAI, getSettingResultAI, true, colorRefG, hColorAlphaResultO, 1)
		elseif getSettingResultAH == "Circle" then
			Kefir.paint:Circle(valueXI, valueXJ, getSettingResultAI + 1.5, 32, hColorAlphaResultO)
			Kefir.paint:Circle(valueXI, valueXJ, getSettingResultAI, 32, colorRefG)
		elseif getSettingResultAH == "Cross" then
			Kefir.paint:LineOutlined(xL - getSettingResultAI, yL, xL + getSettingResultAI, yL, colorRefG, 1, hColorAlphaResultO)
			Kefir.paint:LineOutlined(xL, yL - getSettingResultAI, xL, yL + getSettingResultAI, colorRefG, 1, hColorAlphaResultO)
		end
	end
end

Kefir:AddRender(function()
	if not visualsEnabled then
		return
	end

	local getSettingResultAJ = getSetting("VISUALS", "showmuzzle", 2)
	local getSettingResultAK = getSetting("VISUALS", "showmuzzle_silent", 2)
	local getSettingResultAL = getSetting("VISUALS", "drawwall", 3)[1]
	local posD = Kefir.relative_muzzle.pos
	local angC = Kefir.relative_muzzle.ang
	local valueXK = runtimeApi.traceline({
		start = posD,
		endpos = posD + angC:Forward() * 56756,
		mask = MASK_SHOT,
		filter = localPlayer
	})

	if getSettingResultAJ[1] then
		Kefir:DrawShape(valueXK, getSettingResultAJ[6][1])
	end

	if getSettingResultAK[1] then
		local posE = Kefir.command_muzzle.pos
		local angD = Kefir.command_muzzle.ang

		if posE and angD then
			local valueXL = runtimeApi.traceline({
				start = posE,
				endpos = posE + angD:Forward() * 56756,
				mask = MASK_SHOT,
				filter = localPlayer
			})

			Kefir:DrawShape(valueXL, getSettingResultAK[6][1])
		end
	end

	if getSettingResultAL then
		local autoWallResult = Kefir.aim:AutoWall(valueXK, activeWeapon, function()
			return true
		end, false) and runtimeApi.color.green or runtimeApi.color.red
		local toScreenResultG = valueXK.HitPos:ToScreen()
		local numberValueCB = 4
		local valueXM = numberValueCB / 2
		local xM = toScreenResultG.x
		local yM = toScreenResultG.y
		local valueXN = toScreenResultG.x - valueXM
		local valueXO = toScreenResultG.y - valueXM

		Kefir.paint:Box(valueXN, valueXO, numberValueCB, numberValueCB, true, autoWallResult, color_black, 1)
	end
end, 1)
Kefir.iterator:Timer(20, function()
	if not Kefir.imenu then
		Kefir.imenu = true
	end
end)
Kefir.iterator:Timer(0.5, function()
	Kefir.realfps = runtimeApi.math.Round(1 / Kefir.frametime(), 0)
end)

local tableDataBG = {
	weapon_flechettegun = true,
	gmod_tool = true,
	weapon_357 = true,
	weapon_bugbait = true,
	weapon_frag = true,
	weapon_medkit = true,
	weapon_slam = true,
	weapon_stunstick = true,
	gmod_camera = true,
	weapon_physgun = true,
	weapon_ar2 = true,
	weapon_physcannon = true,
	weapon_crossbow = true,
	weapon_shotgun = true,
	manhack_welder = true,
	weapon_smg1 = true,
	weapon_pistol = true,
	weapon_fists = true,
	weapon_crowbar = true,
	weapon_rpg = true
}
local valueXP = Kefir.convarexists("hg_aiminganim") and Kefir.getconvar("hg_aiminganim") or Kefir.createclientconvar("hg_aiminganim", "0", false, false, "change the way you aim your gun")
local valueXQ = Kefir.createclientconvar("hg_fov", "70", true, false, "changes fov to value", 75, 100)

Kefir:CreateHook("CalcViewModelView", function(paramXG, unusedParamBY, paramXH, paramXI, paramXJ, paramXK)
	if fallbackMode or shouldHideForScreenshot() then
		return
	end

	local removeBobSway = visualsEnabled and getSetting("VISUALS", "viewmodel_removebobsway", 3)[1]
	local sourcePos = removeBobSway and paramXH or paramXJ
	local sourceAng = removeBobSway and paramXI or paramXK
	local valueXV = VectorCtor(sourcePos.x, sourcePos.y, sourcePos.z)
	local valueXW = AngleCtor(sourceAng.p, sourceAng.y, sourceAng.r)

	if removeBobSway and isfunction(paramXG.GetViewModelPosition) then
		local weaponPos, weaponAng = paramXG:GetViewModelPosition(valueXV, valueXW)

		if Kefir.isvector(weaponPos) then
			valueXV = weaponPos
		end

		if isangle(weaponAng) then
			valueXW = weaponAng
		end
	end

	if visualsEnabled and getSetting("VISUALS", "viewmodel_change", 3)[1] then
		valueXV = valueXV + valueXW:Forward() * getSetting("VISUALS", "viewmodel_pos_forward", 3)[1] + valueXW:Right() * getSetting("VISUALS", "viewmodel_pos_right", 3)[1] + valueXW:Up() * getSetting("VISUALS", "viewmodel_pos_up", 3)[1]
		valueXW:RotateAroundAxis(valueXW:Right(), getSetting("VISUALS", "viewmodel_ang_x", 3)[1])
		valueXW:RotateAroundAxis(valueXW:Up(), getSetting("VISUALS", "viewmodel_ang_y", 3)[1])
		valueXW:RotateAroundAxis(valueXW:Forward(), getSetting("VISUALS", "viewmodel_ang_z", 3)[1])
	end

	return valueXV, valueXW
end, "calcviewmodel")

local zcityDrawWorldModelOriginal
local zcityDrawWorldModelWrapper
local zcityDrawWorldModelDepth = 0

local function installZCityViewmodelChanger()
	if not Kefir.special_server.zcity or not istable(hg) or not isfunction(hg.DrawWorldModel) then
		return
	end

	if hg.DrawWorldModel == zcityDrawWorldModelWrapper then
		return
	end

	zcityDrawWorldModelOriginal = hg.DrawWorldModel
	zcityDrawWorldModelWrapper = function(weaponRef, ...)
		if zcityDrawWorldModelDepth > 1 then
			return
		end

		zcityDrawWorldModelDepth = zcityDrawWorldModelDepth + 1

		local currentLocalPlayer = IsValid(localPlayer) and localPlayer or LocalPlayer()
		local changerEnabled = not fallbackMode and not shouldHideForScreenshot() and visualsEnabled and not Kefir.thirdperson and getSetting("VISUALS", "viewmodel_change", 3)[1]

		if not changerEnabled or not IsValid(weaponRef) or weaponRef:GetOwner() ~= currentLocalPlayer or not Kefir.isvector(weaponRef.WorldPos) or not isangle(weaponRef.WorldAng) then
			zcityDrawWorldModelDepth = zcityDrawWorldModelDepth - 1

			return zcityDrawWorldModelOriginal(weaponRef, ...)
		end

		local originalWorldPos = weaponRef.WorldPos
		local originalWorldAng2 = weaponRef.WorldAng2
		local originalDesiredPos = weaponRef.desiredPos
		local originalDesiredAng = weaponRef.desiredAng
		local baseWorldAng2 = isangle(originalWorldAng2) and originalWorldAng2 or ZERO_ANGLE

		weaponRef.WorldPos = VectorCtor(
			originalWorldPos.x + (getSetting("VISUALS", "viewmodel_pos_forward", 3)[1] or 0),
			originalWorldPos.y + (getSetting("VISUALS", "viewmodel_pos_right", 3)[1] or 0),
			originalWorldPos.z + (getSetting("VISUALS", "viewmodel_pos_up", 3)[1] or 0)
		)
		weaponRef.WorldAng2 = AngleCtor(
			baseWorldAng2.p + (getSetting("VISUALS", "viewmodel_ang_x", 3)[1] or 0),
			baseWorldAng2.y + (getSetting("VISUALS", "viewmodel_ang_y", 3)[1] or 0),
			baseWorldAng2.r + (getSetting("VISUALS", "viewmodel_ang_z", 3)[1] or 0)
		)

		local callOk, resultA, resultB, resultC, resultD, resultE, resultF = Kefir.pcall(zcityDrawWorldModelOriginal, weaponRef, ...)

		weaponRef.WorldPos = originalWorldPos
		weaponRef.WorldAng2 = originalWorldAng2

		zcityDrawWorldModelDepth = zcityDrawWorldModelDepth - 1

		if callOk and Kefir.isvector(weaponRef.handPos) and isangle(weaponRef.handAng) then
			local cleanPos, cleanAng = LocalToWorld(originalWorldPos, weaponRef.WorldAng + baseWorldAng2, weaponRef.handPos, weaponRef.handAng)

			cleanAng:RotateAroundAxis(cleanAng:Forward(), 180)

			if isfunction(weaponRef.ShouldUseFakeModel) and weaponRef:ShouldUseFakeModel() and Kefir.isvector(weaponRef.FakePos) and isangle(weaponRef.FakeAng) then
				cleanPos, cleanAng = LocalToWorld(weaponRef.FakePos, weaponRef.FakeAng, cleanPos, cleanAng)
			end

			weaponRef.desiredPos = cleanPos
			weaponRef.desiredAng = cleanAng
		else
			weaponRef.desiredPos = originalDesiredPos
			weaponRef.desiredAng = originalDesiredAng
		end

		if not callOk then
			Kefir.error(resultA, 0)
		end

		return resultA, resultB, resultC, resultD, resultE, resultF
	end

	hg.DrawWorldModel = zcityDrawWorldModelWrapper
end

Kefir:CreateHook("CalcView", function(unusedParamBZ, paramXL, paramXM, paramXN, paramXO, paramXP)
	if not localPlayer or not localPlayer:Alive() then
		return
	end

	local entityRefAH = activeWeapon

	if not IsValid(entityRefAH) then
		return
	end

	local classNameD = entityRefAH:GetClass() == "weapon_hands_sh" or Kefir:IsHGObject(entityRefAH) or Kefir.zpBase[entityRefAH.Base] or Kefir:IsMeleeObject(entityRefAH) or visualsEnabled and Kefir.thirdperson or Kefir:InFake(localPlayer)
	local getSettingResultAM = getSetting("VISUALS", "camerafov", 2)[1]
	local getSettingResultAN = getSetting("VISUALS", "apply_camerafov", 2)[1]
	local valueXX = visualsEnabled and getSettingResultAN
	local valueXY = runtimeApi.GetViewSetup()
	local valueXZ = valueXX and getSettingResultAM or nil

	if tableDataBG[entityRefAH:GetClass()] then
		return {
			fov = valueXZ,
			drawviewer = Kefir.thirdperson == true and true or nil
		}
	end

	if not classNameD then
		return
	end

	local var0110Result = mergeFn(valueXY, {
		origin = paramXL,
		angles = paramXM,
		fov = paramXN,
		znear = paramXO,
		zfar = paramXP
	})

	var0110Result.fov = valueXQ:GetFloat()

	if not shouldHideForScreenshot() then
		if entityRefAH.Camera then
			local valueYA = runtimeApi.GetViewSetup()
			local inVehicleResult = localPlayer:InVehicle()
			local getVehicleResult = inVehicleResult and localPlayer:GetVehicle()
			local getMoveTypeResult = localPlayer:GetMoveType() ~= MOVETYPE_NOCLIP and -(inVehicleResult and getVehicleResult:GetVelocity() or localPlayer:GetVelocity()) / (inVehicleResult and 550 or 200) or vector_origin
			local lengthResult = runtimeApi.hRun("Camera", localPlayer, valueYA.origin, valueYA.angles, valueYA, getMoveTypeResult:Length() * 200)
			local valueYB = lengthResult and lengthResult.fov or 0
			local getIntResult = valueXQ:GetInt()
			local valueYC = getIntResult < getSettingResultAM and getIntResult or getSettingResultAM

			Kefir.sightfov = valueYB - valueYC

			valueXP:SetFloat(1)

			if visualsEnabled and getSettingResultAN then
				var0110Result.fov = getSettingResultAM + Kefir.sightfov
			end
		else
			Kefir.sightfov = 0
		end
	end

	var0110Result.viewmodelfov = valueXZ
	var0110Result.drawviewer = true
	var0110Result.znear = 0.1

	return var0110Result
end, "zzzzzzzzzzzzzzzzzzz")
nativeApi.bax_fn("override_view", function(unusedParamCA)
	return
end)

Kefir:CreateHook("ShouldDrawLocalPlayer", function()
	if Kefir.thirdperson then
		return true
	end
end)

local zcityHeadScale = Vector(1, 1, 1)

local function installZCityThirdpersonHeadFix()
	if not Kefir.special_server.zcity then
		return
	end

	if Kefir._headFixHooked then
		return
	end

	Kefir._headFixHooked = true

	runtimeApi.hAdd("PostDrawPlayerRagdoll", "__kefir_headfix", function(ent, ply)
		local currentLocalPlayer = IsValid(localPlayer) and localPlayer or LocalPlayer()

		if Kefir.thirdperson and ply == currentLocalPlayer and IsValid(ent) then
			local headBone = ent:LookupBone("ValveBiped.Bip01_Head1")
			local headMatrix = headBone and ent:GetBoneMatrix(headBone)

			if headMatrix then
				headMatrix:SetScale(zcityHeadScale)

				if istable(hg) and isfunction(hg.bone_apply_matrix) then
					hg.bone_apply_matrix(ent, headBone, headMatrix)
				else
					ent:SetBoneMatrix(headBone, headMatrix)
				end
			end
		end
	end)
end

Kefir:CreateHook("Think", function()
	installZCityViewmodelChanger()
	installZCityThirdpersonHeadFix()

	if not IsValid(localPlayer) then
		return
	end

	local headBone = localPlayer:LookupBone("ValveBiped.Bip01_Head1")

	if not headBone then
		return
	end

	if Kefir.thirdperson then
		localPlayer:ManipulateBoneScale(headBone, Vector(1, 1, 1))
	elseif not localPlayer:GetManipulateBoneScale(headBone):IsZero() then
		localPlayer:ManipulateBoneScale(headBone, Vector(0, 0, 0))
	end

	if miscEnabled and getSetting("MISC", "fastzoom", 2)[1] and IsValid(activeWeapon) and activeWeapon.IsZoom then
		activeWeapon.k = activeWeapon:IsZoom() and 1 or 0
	end
end)

if isfunction(nativeApi.SetViewFov) then
	Kefir:CreateHook("PreRender", function()
		local enabled = visualsEnabled and getSetting("VISUALS", "apply_camerafov", 2)[1]

		nativeApi.SetViewFov(enabled and getSetting("VISUALS", "camerafov", 2)[1] or 0)
	end)
end
runtimeApi.gev.Listen("entity_killed")
Kefir:CreateHook("entity_killed", function(paramXQ)
	if fallbackMode then
		return
	end

	local entityResult = Entity(paramXQ.entindex_killed)

	if visualsEnabled and Kefir.attackers[entityResult] ~= nil and Kefir.attackers[entityResult] == localPlayer then
		if getSetting("VISUALS", "k_log", 2)[1] then
			local getLangTextResultP = runtimeApi.sformat("%s | %s", Kefir:GetLangText("Killed"), entityResult:Nick())

			Kefir:Log(getLangTextResultP, color_white)
			Kefir:ConMsg(color_white, getLangTextResultP)
		end

		if getSetting("VISUALS", "k_text", 2)[1] then
			local entityRefAI

			if IsValid(entityResult:GetNWEntity("RagdollDeath", Entity(0))) then
				entityRefAI = entityResult:GetNWEntity("RagdollDeath", Entity(0))
			else
				entityRefAI = entityResult
			end

			Kefir:AddScreenText(entityRefAI:GetPos(), Kefir:GetLangText("KILLED"), 32, getSetting("VISUALS", "k_text", 2)[6][1])
		end
	end

	if entityResult and entityResult:IsPlayer() then
		Kefir.attackers[entityResult] = nil
	end
end, "entitykilled")
Kefir:CreateHook("ShutDown", function()
	if info_posture ~= nil and info_posture[1] then
		Kefir.getconvar("hg_gunorigin_x"):SetFloat(info_posture[1])
		Kefir.getconvar("hg_gunorigin_y"):SetFloat(info_posture[2])
		Kefir.getconvar("hg_gunorigin_z"):SetFloat(info_posture[3])
		Kefir.runconsolecommand("hg_change_posture", info_posture[4])

		info_posture = nil
	end

	Kefir.bpacket = true

	local exportConfigResultA = Kefir:ExportConfig(Kefir.variables)
	local valueYD = runtimeApi.parse_table(exportConfigResultA)

	nativeApi.service_saveenv(valueYD)
end, "shutdown1")
Kefir:CreateHook("PostEntityFireBullets", function(unusedParamCB, paramXR)
	if fallbackMode or not IsFirstTimePredicted() then
		return
	end

	if paramXR.Attacker and paramXR.Attacker == localPlayer then
		local trace = paramXR.Trace
		local flagT = true
		local entityA = trace.Entity
		local valueYE

		if trace.Hit and (trace.Entity:IsPlayer() or trace.Entity:IsRagdoll()) then
			local hitPos = trace.HitPos
			local physicsBone = trace.PhysicsBone
			local entityB = trace.Entity

			valueYE = entityB:GetBoneName(entityB:TranslatePhysBoneToBone(physicsBone))

			local valueYF = entityB

			if entityB:IsRagdoll() then
				valueYF = runtimeApi.fn.ragdollowner(valueYF)
			end

			Kefir.attackers[valueYF] = paramXR.Attacker
			flagT = false
			entityA = valueYF

			if visualsEnabled then
				local getSettingResultAO = getSetting("VISUALS", "hs_text", 2)

				if getSettingResultAO[1] and valueYE == "ValveBiped.Bip01_Head1" then
					Kefir:AddScreenText(hitPos, "HEADSHOT", 26, getSettingResultAO[6][1] or runtimeApi.color.white)
				end

				if getSetting("VISUALS", "showhits", 2)[1] then
					if getSetting("VISUALS", "showhits_shape", 2)[1] then
						local tableDataBH = {
							runtimeApi.stime(),
							255
						}

						if dmginfo then
							tableDataBH[3] = hitPos
						end

						runtimeApi.insert(Kefir.hits, tableDataBH)
					end

					if getSetting("VISUALS", "showhits_text", 2)[1] then
						Kefir:AddScreenText(hitPos, Kefir:GetLangText("HIT"), getSetting("VISUALS", "showhits_size", 2)[1] or 19, getSetting("VISUALS", "showhits", 2)[6][1] or runtimeApi.color.white)
					end
				end

				local getSettingResultAP = getSetting("VISUALS", "showhits_line", 2)

				if getSettingResultAP[1] then
					local tableDataBI = {
						trace.StartPos,
						hitPos,
						getSettingResultAP[6][1],
						255,
						runtimeApi.stime()
					}

					runtimeApi.insert(Kefir.lines, tableDataBI)
				end
			end
		end

		local valueYG = Kefir.aimwork or not Kefir.aimwork and not flagT

		if Kefir.aimwork then
			entityA = Kefir.aimtarget
		end

		if visualsEnabled and getSetting("VISUALS", "showhits", 2)[1] and getSetting("VISUALS", "showhits_log", 2)[1] and valueYG then
			Kefir:RegisterHit(flagT, valueYE, entityA)
		end
	end
end, "firebulets")

function Kefir.CopyPoseParams(selfRefEA, paramXS, paramXT)
	for indexBC = 0, paramXS:GetNumPoseParameters() - 1 do
		local valueYH, valueYI = paramXS:GetPoseParameterRange(indexBC)
		local getPoseParameterNameResult = paramXS:GetPoseParameterName(indexBC)

		paramXT:SetPoseParameter(getPoseParameterNameResult, math.Remap(paramXS:GetPoseParameter(getPoseParameterNameResult), 0, 1, valueYH, valueYI))
	end
end

local flagU = false

local function helperD(entityRefAJ, paramXU, paramXV, colorRefH, paramXW, unusedParamCC, hiddenColorH)
	local rB = colorRefH.r
	local gB = colorRefH.g
	local bB = colorRefH.b
	local valueYJ = colorRefH.a or 255

	paramXW = paramXW or 255
	additive = additive or false

	local getNameResultA = paramXV:GetName() == "_original_"
	local valueYK = not miscEnabled or not getSetting("MISC", "anti_sg", 1)[1]

	if not IsValid(entityRefAJ) then
		return
	end

	if hiddenColorH ~= nil and valueYK then
		local valueYJHidden = hiddenColorH.a or 255

		localCache.ignoreDepth(true)

		if paramXU then
			localCache.suppressEngineLighting(true)
		end

		localCache.setRenderBlend((paramXW - (255 - valueYJHidden)) / 255)
		localCache.setColorModulation(hiddenColorH.r / 255, hiddenColorH.g / 255, hiddenColorH.b / 255)

		if not getNameResultA then
			localCache.overrideMaterial(paramXV)
		end

		entityRefAJ:DrawModel()

		if not getNameResultA then
			localCache.overrideMaterial()
		end

		localCache.setColorModulation(1, 1, 1)
		localCache.setRenderBlend(1)

		if paramXU then
			localCache.suppressEngineLighting(false)
		end

		localCache.ignoreDepth(false)
	elseif valueYK then
		localCache.ignoreDepth(true)
	end

	if paramXU then
		localCache.suppressEngineLighting(true)
	end

	localCache.setRenderBlend((paramXW - (255 - valueYJ)) / 255)
	localCache.setColorModulation(rB / 255, gB / 255, bB / 255)

	if not getNameResultA then
		localCache.overrideMaterial(paramXV)
	end

	entityRefAJ:DrawModel()

	if not getNameResultA then
		localCache.overrideMaterial()
	end

	localCache.setColorModulation(1, 1, 1)
	localCache.setRenderBlend(1)

	if paramXU then
		localCache.suppressEngineLighting(false)
	end

	if valueYK then
		localCache.ignoreDepth(false)
	end

	flagU = true
end

Kefir.fakeplyhuli = nil
Kefir.fangsds = Angle(0, 0, 0)

function Kefir.FakeChams(selfRefEB)
	if not localPlayer:Alive() then
		return
	end

	if not Kefir.thirdperson then
		return
	end

	if getSetting("VISUALS", "tperson", 3)[1] < 12.5 then
		return
	end

	if not tpss then
		return
	end

	if Kefir:InFake(localPlayer) then
		return
	end

	local entityRefAK = localPlayer
	local getRenderAnglesResult = entityRefAK:GetRenderAngles()
	local fakeanglesA = Kefir.fakeangles

	if not selfRefEB.fakeplyhuli or not selfRefEB.fakeplyhuli.SetModel or not IsValid(selfRefEB.fakeplyhuli) or selfRefEB.fakeplyhuli == nil then
		selfRefEB.fakeplyhuli = localCache.createClientsideModel(entityRefAK:GetModel())

		selfRefEB.fakeplyhuli:SetNoDraw(true)

		selfRefEB.fakeplyhuli.cs_filter = true
	end

	selfRefEB.fakeplyhuli:SetModel(entityRefAK:GetModel())
	selfRefEB.fakeplyhuli:SetSequence(entityRefAK:GetSequence())
	selfRefEB.fakeplyhuli:SetCycle(entityRefAK:GetCycle())
	selfRefEB.fakeplyhuli:SetPos(entityRefAK:GetPos())
	Kefir:CopyPoseParams(localPlayer, selfRefEB.fakeplyhuli)

	if fakeanglesA ~= nil then
		getRenderAnglesResult = fakeanglesA

		selfRefEB.fakeplyhuli:SetPoseParameter("aim_pitch", getRenderAnglesResult[1])
		selfRefEB.fakeplyhuli:SetPoseParameter("head_pitch", getRenderAnglesResult[1])
	end

	selfRefEB.fakeplyhuli:SetRenderAngles(Angle(0, getRenderAnglesResult[2], 0))

	local getCacheBoneResultB = selfRefEB:getCacheBone(selfRefEB.fakeplyhuli, "ValveBiped.Bip01_Head1")

	selfRefEB.fangsds[2] = -(Kefir.fakeHead[2] or 0)
	selfRefEB.fangsds[3] = -(Kefir.fakeHead[1] or 0)

	if getCacheBoneResultB then
		selfRefEB.fakeplyhuli:ManipulateBoneAngles(getCacheBoneResultB, selfRefEB.fangsds, false)
	end

	selfRefEB.fakeplyhuli:InvalidateBoneCache()

	local getMaterialChamsResult = selfRefEB:GetMaterialChams("VISUALS", "fakechams", 2, getSetting("VISUALS", "fakechams_additive", 2)[1])
	local getSettingResultAQ = getSetting("VISUALS", "fakechams", 2)[6][1]
	local getSettingResultAR = getSetting("VISUALS", "fakechams_light", 2)[1]

	helperD(selfRefEB.fakeplyhuli, getSettingResultAR, getMaterialChamsResult, getSettingResultAQ, 255, false)

	return tostring(getMaterialChamsResult)
end

function Kefir.PlayerChams(selfRefEC)
	local getSettingResultAS = getSetting("VISUALS", "playerchams_enable", 1)
	local getSettingResultAT = getSetting("VISUALS", "eyetrace", 1)
	local valueYL = getSettingResultAS[6][1]
	local valueYLH = getSettingResultAS[6][2]
	local xqzOnA = getSetting("VISUALS", "playerchams_xqz", 1)[1]
	local getMaterialChamsResultA = selfRefEC:GetMaterialChams("VISUALS", "playerchams", 1, getSetting("VISUALS", "playerchams_additive", 1)[1])
	local getSettingResultAU = getSetting("VISUALS", "playerchams_light", 1)[1]

	for keyBI, itemBF in localCache.iteratePlayers() do
		if IsValid(itemBF) and itemBF ~= localPlayer and not Kefir.espignore[itemBF] then
			local getNWEntityResultA = IsValid(itemBF) and itemBF:GetNWEntity("RagdollDeath", Entity(0))

			if not IsValid(getNWEntityResultA) then
				getNWEntityResultA = nil
			end

			local aliveResultA = itemBF:Alive()
			local getCharacterResultC = not aliveResultA and IsValid(getNWEntityResultA) and getNWEntityResultA or aliveResultA and Kefir:getCharacter(itemBF) or itemBF

			if IsValid(getCharacterResultC) and (getSetting("VISUALS", "dormant", 1)[1] or aliveResultA) and helperC(itemBF, getCharacterResultC) then
				local positionE = getCharacterResultC:GetPos():Distance(runtimeApi.ply_pos) / nativeApi.util_calcWeekend(0.038109756097561)
				local getSettingResultAV = getSetting("VISUALS", "alphadistance", 1)[1] and positionE or 0
				local valueYM = (valueVA[itemBF] or 255) - getSettingResultAV

				if valueYM > 0.1 and getSettingResultAS[1] then
					helperD(getCharacterResultC, supressligtrht, getMaterialChamsResultA, valueYL, valueYM, false, additivef, xqzOnA and valueYLH or nil)
				end
			end
		end
	end

	return tostring(getMaterialChamsResultA)
end

function Kefir.WeaponChams(selfRefED)
	if not localPlayer:Alive() then
		return
	end

	if not IsValid(activeWeapon) then
		return
	end

	local valueYN = activeWeapon
	local valueYO = valueYN.worldModel and valueYN.worldModel or valueYN.worldModel2 and valueYN.worldModel2 or valueYN
	local getViewModelResult = localPlayer:GetViewModel()

	if valueYO == valueYN and IsValid(getViewModelResult) then
		valueYO = getViewModelResult
	end

	local valueYP = valueYN
	local getSettingResultAW = getSetting("VISUALS", "weaponchams_enable", 2)

	if not getSettingResultAW[1] then
		return
	end

	local valueYQ = getSettingResultAW[6][1]
	local getMaterialChamsResultB = selfRefED:GetMaterialChams("VISUALS", "weaponchams", 2, getSetting("VISUALS", "weaponchams_additive", 2)[1])
	local textValueD = tostring(getMaterialChamsResultB)

	helperD(valueYO, false, getMaterialChamsResultB, valueYQ, 255, false)

	return textValueD
end

function Kefir.getPreviewData(selfRefEE)
	return {
		Usergroup = "Femboy",
		maxhp = 100,
		health = 85,
		nick = "Sad Salat",
		anick = "Timur4ik",
		organism = {
			lungsfunction = false,
			pulse = 100,
			otrub = true
		}
	}
end

Kefir.previewesp = Kefir.previewesp or nil
Kefir.filteresp = Kefir.filteresp or nil
Kefir.hitboxaim = Kefir.hitboxaim or nil

local numberValueCC = 370
local numberValueCD = 500
local tableDataBJ = {
	[0] = {
		"up",
		217.5,
		41,
		72,
		100
	},
	{
		"left",
		50,
		275,
		290,
		142
	},
	{
		"right",
		50,
		275,
		20,
		142
	},
	{
		"bottom",
		217.5,
		40,
		72,
		419
	}
}
local valueYR
local tableDataBK = {}

local function helperE(paramXX, unusedParamCD)
	if not tableDataBK[paramXX] then
		return false
	end

	return true
end

local function helperF(paramXY, paramXZ, unusedParamCE, paramYA, paramYB)
	local valueYS = runtimeApi.vCreate("DButton", paramXY)

	valueYS:SetSize(50, 20)
	valueYS:SetText("")

	valueYS.id = paramXZ
	valueYS.selectBox = 0

	function valueYS.OnRemove()
		valueYR = nil
	end

	function valueYS.OnMouseWheeled(paramYC, paramYD)
		if not helperE(paramXZ, paramYC) then
			return
		end

		paramYD = runtimeApi.clamp(paramYD, -0.3, 0.3)
		runtimeApi.var.ESPINTERACTIVE.data[paramXZ][6] = runtimeApi.clamp(runtimeApi.var.ESPINTERACTIVE.data[paramXZ][6] + paramYD, 1, 12)
	end

	function valueYS.Paint(paramYE, paramYF, paramYG)
		if not helperE(paramXZ, paramYE) then
			return
		end

		paramYE.selectBox = Kefir:Lerp(0.1, paramYE.selectBox, paramYE.m_bDragging and 100 or paramYE:IsHovered() and 50 or 0)

		local groupnameD = runtimeApi.color.groupname

		Kefir.paint:rectBox(paramYF, paramYG, 0, 0, Kefir.paint:HColorAlpha(color_black, paramYE.selectBox))
		localCache.setDrawColor(Kefir.paint:HColorAlpha(groupnameD, paramYE.selectBox))
		localCache.drawOutlinedRect(0, 0, paramYF, paramYG)
	end

	function valueYS.OnMousePressed(paramYH, paramYI)
		if not helperE(paramXZ, paramYH) then
			return
		end

		if paramYI == MOUSE_LEFT then
			paramYH.m_bDragging = true

			paramYH:MouseCapture(true)
		end
	end

	function valueYS.OnMouseReleased(paramYJ)
		if not helperE(paramXZ, paramYJ) then
			return
		end

		paramYJ.m_bDragging = false

		paramYJ:MouseCapture(false)

		if valueYR then
			runtimeApi.var.ESPINTERACTIVE.data[paramXZ][1] = valueYR
			valueYR = nil
		end
	end

	function valueYS.Think(paramYK)
		local valueYT = runtimeApi.var.ESPINTERACTIVE.data[paramXZ]

		if not helperE(paramXZ, paramYK) then
			return
		end

		if paramYK.m_bDragging then
			local valueYU, valueYV = paramXY:CursorPos()
			local getWideResult = paramXY:GetWide() / 2
			local getTallResult = paramXY:GetTall() / 2
			local valueYW = valueYU - getWideResult
			local valueYX = valueYV - getTallResult

			if runtimeApi.mabs(valueYW) > runtimeApi.mabs(valueYX) then
				valueYR = valueYW > 0 and 1 or 2
			else
				valueYR = valueYX > 0 and 3 or 0
			end
		else
			local valueYY = valueYT[2]
			local valueYZ = valueYT[3]

			if valueYY and valueYZ then
				paramYK:SetPos(valueYY - paramYA - paramYK:GetWide() / 2, valueYZ - paramYB - paramYK:GetTall() / 2)
				paramYK:SetSize(valueYT[4], valueYT[5])
			end
		end
	end
end

local function helperG(paramYL, paramYM, paramYN)
	return {
		current_ = "VISUALS",
		group = 1,
		data_var = Kefir.variables.VISUALS[1][paramYL],
		index = paramYL,
		object_x = paramYM,
		object_y = paramYN
	}
end

local function var4210Handler(paramYO, paramYP, paramYQ, paramYR, paramYS)
	paramYS = paramYS or Kefir.filteresp

	return paramYR + Kefir.drawlist[paramYO](Kefir, helperG(paramYP, paramYQ, paramYR), paramYS)
end

Kefir.TIMURCHIK = Kefir:RandomString(32)

local valueZA = localCache.mathMin(1024, screenWidth, screenHeight)
local getRenderTargetExResult = GetRenderTargetEx(Kefir.TIMURCHIK, valueZA, valueZA, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SHARED, 17, 0, IMAGE_FORMAT_RGBA8888)
local createMaterialResult = createMaterial(runtimeApi.NameStart .. Kefir.TIMURCHIK, "UnlitGeneric", {
	["$ignorez"] = 1,
	["$vertexalpha"] = 1,
	["$vertexcolor"] = 1,
	["$translucent"] = 1,
	["$basetexture"] = Kefir.TIMURCHIK
})

local function var42611Handler(paramYT, paramYU, paramYV, paramYW, paramYX, paramYY)
	local forwardResult = paramYV:Forward()
	local rightResult = paramYV:Right()
	local upResult = paramYV:Up()
	local valueZB = paramYT - paramYU
	local dotResult = valueZB:Dot(rightResult)
	local dotResultA = valueZB:Dot(upResult)
	local dotResultB = valueZB:Dot(forwardResult)

	if dotResultB <= 0 then
		return nil
	end

	local valueZC = runtimeApi.rad(paramYW)
	local valueZD = paramYY / (2 * runtimeApi.tan(valueZC / 2))
	local valueZE = paramYX / 2 + dotResult * valueZD / dotResultB
	local valueZF = paramYY / 2 - dotResultA * valueZD / dotResultB

	return valueZE, valueZF
end

local numberValueCE = 0

function Kefir.DRAWHITBOXES(selfRefEF, entityRefAL)
	if not IsValid(entityRefAL) then
		return
	end

	local valueZG, valueZH = entityRefAL:CursorPos()
	local activebonesA = Kefir.activebones
	local dwBone = Kefir.dw_bone
	local tableDataBL = {
		"",
		0,
		0
	}
	local flagV = false

	for indexBD = 1, #activebonesA do
		local valueZI = activebonesA[indexBD]
		local valueZJ = dwBone[valueZI]

		if not valueZJ then
			
		else
			local valueZK = valueZJ[1]
			local valueZL = valueZJ[2]
			local valueZM = runtimeApi.HasValue(Kefir.variables.AIM_HITBOX, valueZI)
			local valueZN = not flagV and runtimeApi.mDistance(valueZG, valueZH, valueZK, valueZL) < 10
			local valueZO = runtimeApi.IsKeyDown(MOUSE_LEFT)
			local groupnameE = valueZM and Kefir.color.selectedline or valueZN and Kefir.color.groupname or Kefir.color.groupname
			local valueZP = valueZN and Kefir.color.groupbox or color_white

			valueZJ[3] = valueZJ[3] or 5
			valueZJ[3] = Kefir:Lerp(0.3, valueZJ[3] or 5, valueZM and 8 or valueZN and 6 or 5)

			local valueZQ = runtimeApi.math.Round(valueZJ[3], 3)

			localCache.setDrawColor(0, 0, 0, 255)
			localCache.drawCircle(valueZK, valueZL, valueZQ, color_black)

			for indexBE = 1, valueZQ - 1 do
				localCache.drawCircle(valueZK, valueZL, indexBE, groupnameE)
			end

			Kefir.paint:EOText("", runtimeApi.floor(valueZQ), valueZK, valueZL, valueZP, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0.5, "icons", 255)

			if valueZN then
				tableDataBL = {
					valueZI,
					valueZK,
					valueZL,
					valueZQ
				}
				flagV = true

				if valueZO and numberValueCE < runtimeApi.stime() then
					if valueZM then
						runtimeApi.RemoveByValue(Kefir.variables.AIM_HITBOX, valueZI)
					else
						Kefir.variables.AIM_HITBOX[#Kefir.variables.AIM_HITBOX + 1] = valueZI
					end

					numberValueCE = runtimeApi.stime() + 0.1
				end
			end
		end
	end

	if tableDataBL[1] ~= "" then
		Kefir.paint:EOText(Kefir:GetLangText(Kefir.translatebone[tableDataBL[1]]), 16, tableDataBL[2], tableDataBL[3] - (tableDataBL[4] + 3), color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 0.1, "ofont", 255)
	end
end

local numberValueCF = 250
local numberValueCG = 320

function Kefir.paint.aimHitbox(selfRefEG)
	Kefir.hitboxaim = selfRefEG:CreateObject("jframe")

	Kefir.hitboxaim:SetSize(numberValueCG, 500)
	Kefir.hitboxaim:SetPos(0, 0)

	function Kefir.hitboxaim.Paint(unusedParamCF, paramYZ, paramZA)
		selfRefEG:rectBox(paramYZ, paramZA, 0, 0, color_black)
		selfRefEG:rectBox(paramYZ - 2, paramZA - 2, 1, 1, runtimeApi.color.groupname)
		selfRefEG:rectBox(paramYZ - 4, paramZA - 4, 2, 2, runtimeApi.color.kefir_black)
	end

	function Kefir.hitboxaim.Think(paramZB)
		Kefir:TrackMenu(paramZB, 805)
	end

	local var0201Result = var4210Handler("checkbox", "directionallighting_previewaim", 5, 5, Kefir.hitboxaim)
	local valueZR = runtimeApi.vCreate("DModelPanel", Kefir.hitboxaim)

	valueZR:Dock(FILL)
	valueZR:SetModel("models/player/Group01/male_01.mdl")

	valueZR.FAQ_INDEX = "X_aimbot_hitbox_preview_X"

	valueZR:SetFOV(15)
	valueZR:SetCamPos(Vector(335, 3, 35))
	valueZR:SetLookAt(Vector(135, 3, 35))

	function valueZR.LayoutEntity(selfRefEH, paramZC)
		local getSettingResultAX = getSetting("VISUALS", "directionallighting_previewaim", 1)[1]

		selfRefEH:SetDirectionalLight(BOX_RIGHT, getSettingResultAX and runtimeApi.color.groupbox or color_white)
		selfRefEH:SetDirectionalLight(BOX_LEFT, getSettingResultAX and runtimeApi.color.groupname or color_white)
		selfRefEH:SetDirectionalLight(BOX_FRONT, getSettingResultAX and runtimeApi.color.kefir_red or color_white)
		paramZC:SetAngles(Angle(0, 0, 0))
		paramZC:SetSequence(paramZC:LookupSequence("pose_standing_02"))
	end

	function valueZR.DrawModel(selfRefEI)
		local entityC = selfRefEI.Entity

		if selfRefEI:PreDrawModel(entityC) ~= false then
			entityC:DrawModel()
			selfRefEI:PostDrawModel(entityC)
		end
	end

	function valueZR.Paint(paramZD, paramZE, paramZF)
		local entityD = paramZD.Entity

		if not IsValid(entityD) then
			return
		end

		paramZD:LayoutEntity(entityD)

		local vCamPosA = paramZD.vCamPos
		local angleResult = (paramZD.vLookatPos - paramZD.vCamPos):Angle()
		local fFOVA = paramZD.fFOV

		render.PushRenderTarget(getRenderTargetExResult)
		render.Clear(0, 0, 0, 0, true, true)
		localCache.beginCameraMode("3D", vCamPosA, angleResult, fFOVA, 0, 0, valueZA, valueZA)
		localCache.suppressEngineLighting(true)
		localCache.setLightingOrigin(entityD:GetPos())
		localCache.resetModelLighting(paramZD.colAmbientLight.r / 255, paramZD.colAmbientLight.g / 255, paramZD.colAmbientLight.b / 255)
		localCache.setColorModulation(paramZD.colColor.r / 255, paramZD.colColor.g / 255, paramZD.colColor.b / 255)
		localCache.setRenderBlend(paramZD:GetAlpha() / 255 * (paramZD.colColor.a / 255))

		for indexBF = 0, 6 do
			local colorValueG = paramZD.DirectionalLight[indexBF]

			if colorValueG then
				localCache.setModelLighting(indexBF, colorValueG.r / 255, colorValueG.g / 255, colorValueG.b / 255)
			end
		end

		paramZD:DrawModel()

		local activebonesB = Kefir.activebones

		for indexBG = 1, #activebonesB do
			local valueZS = activebonesB[indexBG]
			local lookupBoneResultA = entityD:LookupBone("ValveBiped.Bip01_" .. valueZS)

			if not lookupBoneResultA then
				
			else
				local getBonePositionResultA = entityD:GetBonePosition(lookupBoneResultA)

				if not getBonePositionResultA then
					
				else
					local valueZT = valueZA - 210
					local valueZU, valueZV = var42611Handler(getBonePositionResultA, vCamPosA, angleResult, fFOVA, valueZT, valueZA)

					if valueZU and valueZV then
						local valueZW = valueZU * (paramZE / valueZT)
						local valueZX = valueZV * (paramZF / valueZA)

						Kefir.dw_bone[valueZS] = Kefir.dw_bone[valueZS] or {}
						Kefir.dw_bone[valueZS][1] = valueZW
						Kefir.dw_bone[valueZS][2] = valueZX
						Kefir.dw_bone[valueZS][3] = Kefir.dw_bone[valueZS][3] or 5
					end
				end
			end
		end

		localCache.suppressEngineLighting(false)
		localCache.endCameraMode("3D")
		render.PopRenderTarget()
		localCache.setSurfaceMaterial(createMaterialResult)
		localCache.setDrawColor(255, 255, 255, 255)

		local valueZY = paramZE / paramZF

		if valueZY < 1 then
			local valueZZ = valueZY
			local valueAAA = (1 - valueZZ) / 2

			localCache.drawTexturedRectUv(0, 0, paramZE, paramZF, valueAAA, 0, valueAAA + valueZZ, 1)
		else
			local numberValueCH = 1 / valueZY
			local valueAAB = (1 - numberValueCH) / 2

			localCache.drawTexturedRectUv(0, 0, paramZE / 1.1, paramZF / 1.1, 0, valueAAB, 1, valueAAB + numberValueCH)
		end

		Kefir:DRAWHITBOXES(paramZD)
	end
end

function Kefir.paint.espFilter(selfRefEJ)
	Kefir.filteresp = selfRefEJ:CreateObject("jframe")

	Kefir.filteresp:SetSize(numberValueCF, numberValueCD)
	Kefir.filteresp:SetPos((screenWidth - numberValueCF) / 8.3, (screenHeight - numberValueCD) / 2)

	Kefir.filteresp._preModeA = 0

	function Kefir.filteresp.Paint(unusedParamCG, paramZG, paramZH)
		selfRefEJ:rectBox(paramZG, paramZH, 0, 0, color_black)
		selfRefEJ:rectBox(paramZG - 2, paramZH - 2, 1, 1, runtimeApi.color.groupname)
		selfRefEJ:rectBox(paramZG - 4, paramZH - 4, 2, 2, runtimeApi.color.kefir_black)
	end

	function Kefir.filteresp.Think(paramZI)
		Kefir:TrackMenu(paramZI, 805)
	end

	local numberValueCI = 8
	local var0201ResultA = var4210Handler("slider", "filterdistance", -30, numberValueCI)
	local var0201ResultB = var4210Handler("checkbox", "filterteam", 8, var0201ResultA + 10)
	local var0201ResultC = var4210Handler("checkbox", "filterenemy", 8, var0201ResultB)
	local var0201ResultD = var4210Handler("checkbox", "filternoclip", 8, var0201ResultC)
	local var0201ResultE = var4210Handler("checkbox", "onlyvisible", 8, var0201ResultD)

	Kefir.filteresp:SetSize(numberValueCF, var0201ResultE + 5)
end

local valueAAC

Kefir.previewHuy = nil

function Kefir.paint.espPreview(selfRefEK)
	Kefir.previewesp = selfRefEK:CreateObject("jframe")

	Kefir.previewesp:SetSize(numberValueCC, numberValueCD)
	Kefir.previewesp:SetPos((screenWidth - numberValueCC) / 8.3, (screenHeight - numberValueCD) / 2)

	Kefir.previewesp._preModeA = 0

	function Kefir.previewesp.Paint(paramZJ, paramZK, paramZL)
		selfRefEK:rectBox(paramZK, paramZL, 0, 0, color_black)
		selfRefEK:rectBox(paramZK - 2, paramZL - 2, 1, 1, runtimeApi.color.groupname)
		selfRefEK:rectBox(paramZK - 4, paramZL - 4, 2, 2, runtimeApi.color.kefir_black)

		if valueAAC ~= valueYR then
			paramZJ._preModeA = 0
			valueAAC = valueYR
		end

		paramZJ._preModeA = Kefir:Lerp(0.01, paramZJ._preModeA or 0, valueYR and 255 or 0)

		if valueYR then
			local valueAAD = tableDataBJ[valueYR]
			local valueAAE = valueAAD[4]
			local valueAAF = valueAAD[5]
			local valueAAG = valueAAD[2]
			local valueAAH = valueAAD[3]
			local valueAAI = runtimeApi.material["vgui_" .. valueAAD[1]]

			gradientFn(Kefir.paint, valueAAE, valueAAF, valueAAG, valueAAH, selfRefEK:HColorAlpha(runtimeApi.color.black, paramZJ._preModeA), selfRefEK:HColorAlpha(runtimeApi.color.groupname, paramZJ._preModeA), false, valueAAI)
		end
	end

	local var0201ResultF = var4210Handler("checkbox", "directionallighting_previewesp", 130, 5, Kefir.previewesp)

	function Kefir.previewesp.OnRemove()
		Kefir.previewPly = nil
	end

	function Kefir.previewesp.Think(paramZM)
		Kefir:TrackMenu(paramZM, -(numberValueCC + 5))
	end

	local entityRefAM = runtimeApi.vCreate("DModelPanel", Kefir.previewesp)

	entityRefAM:SetSize(370, 500)
	entityRefAM:SetPos(0, 50)
	entityRefAM:SetModel("models/player/Group01/male_01.mdl")
	entityRefAM:SetFOV(10)
	entityRefAM:SetCamPos(Vector(350, 0, 10))
	entityRefAM:SetLookAt(Vector(0, 0, 10))

	local getPreviewDataResult = Kefir:getPreviewData()

	helperF(Kefir.previewesp, "playerweapon", "WEAPON", 0, -48)
	helperF(Kefir.previewesp, "playername", "NAME", 0, -40)
	helperF(Kefir.previewesp, "playerflags", "FLAGS", -10, -55)
	helperF(Kefir.previewesp, "playerothers", "INFO", 0, 2)

	function entityRefAM.LayoutEntity(selfRefEL, paramZN)
		paramZN:SetSequence(paramZN:LookupSequence("sit_zen"))
	end

	function entityRefAM.PostDrawModel(selfRefEM, paramZO)
		local getSettingResultAY = getSetting("VISUALS", "directionallighting_previewesp", 1)[1]

		selfRefEM:SetDirectionalLight(BOX_RIGHT, getSettingResultAY and runtimeApi.color.groupbox or color_white)
		selfRefEM:SetDirectionalLight(BOX_LEFT, getSettingResultAY and runtimeApi.color.groupname or color_white)
		selfRefEM:SetDirectionalLight(BOX_FRONT, getSettingResultAY and runtimeApi.color.kefir_red or color_white)

		Kefir.previewHuy = paramZO

		if visualsEnabled then
			local getSettingResultAZ = getSetting("VISUALS", "playerchams_enable", 1)

			if getSettingResultAZ[1] then
				local valueAAJ = getSettingResultAZ[6][1]
				local getMaterialChamsResultC = Kefir:GetMaterialChams("VISUALS", "playerchams", 1, getSetting("VISUALS", "playerchams_additive", 1)[1])
				local getSettingResultBA = getSetting("VISUALS", "playerchams_light", 1)[1]

				helperD(paramZO, getSettingResultBA, getMaterialChamsResultC, valueAAJ, 255)
			end
		end
	end

	function entityRefAM.PaintOver(paramZP, paramZQ, paramZR)
		local entityE = paramZP.Entity

		if not IsValid(entityE) then
			return
		end

		if not visualsEnabled then
			return
		end

		paramZR = paramZR - 40
		paramZQ = paramZQ - 30

		local numberValueCJ = 255
		local valueAAK = paramZQ * 0.15
		local valueAAL = paramZR * 0.2
		local valueAAM = valueAAK + 20
		local valueAAN = valueAAL
		local valueAAO = paramZQ - valueAAK
		local valueAAP = paramZR - valueAAL
		local tableDataBM = {
			PlayerClassName = "Furry",
			Team = function()
				return 1001
			end,
			GetTeamStatus = function()
				return "HG TEAM", color_white
			end,
			GetActiveWeapon = function()
				return {
					PrintName = "Paws",
					IsZoom = function()
						return true
					end,
					reload = runtimeApi.stime() + 0.5,
					Clip1 = function()
						return 30
					end,
					GetMaxClip1 = function()
						return 30
					end
				}
			end,
			Inventory = {
				Weapons = {
					hg_flashlight = true,
					hg_brassknuckles = true,
					hg_sling = true
				}
			},
			IsRagdoll = function()
				return false
			end
		}

		Kefir.hasfirearm[tableDataBM] = true
		Kefir.hasmelee[tableDataBM] = true
		Kefir.previewPly = tableDataBM

		Kefir.drawlist.esp.playerbox(valueAAM, valueAAN, valueAAO, valueAAP, numberValueCJ, tableDataBM)

		local valueAAQ, valueAAR, valueAAS, valueAAT = Kefir.drawlist.esp.playerhp(valueAAM, valueAAN, valueAAO, valueAAP, getPreviewDataResult.health, getPreviewDataResult.maxhp, numberValueCJ, 12, tableDataBM)

		runtimeApi.var.ESPINTERACTIVE.data.playerhp[2] = valueAAQ or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerhp[3] = valueAAR or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerhp[4] = valueAAS or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerhp[5] = valueAAT or 0

		local valueAAU, valueAAV, valueAAW, valueAAX, valueAAY = Kefir.drawlist.esp.playerflags(valueAAM, valueAAN, valueAAO, valueAAP, getPreviewDataResult.organism, numberValueCJ, 12, tableDataBM)

		runtimeApi.var.ESPINTERACTIVE.data.playerflags[2] = valueAAU or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerflags[3] = valueAAV or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerflags[4] = valueAAW or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerflags[5] = valueAAX or 0
		tableDataBK.playerflags = valueAAY

		local valueAAZ, valueABA, valueABB, valueABC, valueABD = Kefir.drawlist.esp.playername(valueAAM, valueAAN, valueAAO, valueAAP, getPreviewDataResult.nick, getPreviewDataResult.anick, numberValueCJ, 12)

		runtimeApi.var.ESPINTERACTIVE.data.playername[2] = valueAAZ or 0
		runtimeApi.var.ESPINTERACTIVE.data.playername[3] = valueABA or 0
		runtimeApi.var.ESPINTERACTIVE.data.playername[4] = valueABB or 0
		runtimeApi.var.ESPINTERACTIVE.data.playername[5] = valueABC or 0
		tableDataBK.playername = valueABD

		local valueABE, valueABF, valueABG, valueABH, valueABI = Kefir.drawlist.esp.playerothers(valueAAM, valueAAN, valueAAO, valueAAP, {
			tableDataBM:GetActiveWeapon(),
			getPreviewDataResult.Usergroup
		}, numberValueCJ, 12)

		runtimeApi.var.ESPINTERACTIVE.data.playerothers[2] = valueABE or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerothers[3] = valueABF or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerothers[4] = valueABG or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerothers[5] = valueABH or 0
		tableDataBK.playerothers = valueABI

		local valueABJ, valueABK, valueABL, valueABM, valueABN = Kefir.drawlist.esp.playerweapon(valueAAM, valueAAN, valueAAO, valueAAP, numberValueCJ, 12, false, {})

		runtimeApi.var.ESPINTERACTIVE.data.playerweapon[2] = valueABJ or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerweapon[3] = valueABK or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerweapon[4] = valueABL or 0
		runtimeApi.var.ESPINTERACTIVE.data.playerweapon[5] = valueABM or 0
		tableDataBK.playerweapon = valueABN

		if visualsEnabled and getSetting("VISUALS", "glow", 1)[1] then
			Kefir.glow:Render({
				IgnoreZ = true,
				Ents = {
					entityE
				},
				Color = getSetting("VISUALS", "glow", 1)[6][1],
				BlurX = getSetting("VISUALS", "glow_blur", 1)[1],
				BlurY = getSetting("VISUALS", "glow_blur", 1)[1],
				DrawPasses = getSetting("VISUALS", "glow_passes", 1)[1],
				Additive = getSetting("VISUALS", "glow_additive", 1)[1]
			})
		end
	end

	function entityRefAM.DrawModel(selfRefEN)
		local entityF = selfRefEN.Entity

		if selfRefEN:PreDrawModel(entityF) ~= false then
			entityF:DrawModel()
			selfRefEN:PostDrawModel(entityF)
		end
	end

	function entityRefAM.Paint(paramZS, paramZT, paramZU)
		local entityG = paramZS.Entity

		if not IsValid(entityG) then
			return
		end

		entityG:SetModelScale(0.9, 0)
		paramZS:LayoutEntity(entityG)
		render.PushRenderTarget(getRenderTargetExResult)
		render.Clear(0, 0, 0, 0, true, true)
		localCache.beginCameraMode("3D", paramZS.vCamPos, (paramZS.vLookatPos - paramZS.vCamPos):Angle(), paramZS.fFOV, 0, 0, valueZA, valueZA)
		localCache.suppressEngineLighting(true)
		localCache.setLightingOrigin(entityG:GetPos())
		localCache.resetModelLighting(paramZS.colAmbientLight.r / 255, paramZS.colAmbientLight.g / 255, paramZS.colAmbientLight.b / 255)
		localCache.setColorModulation(paramZS.colColor.r / 255, paramZS.colColor.g / 255, paramZS.colColor.b / 255)
		localCache.setRenderBlend(paramZS:GetAlpha() / 255 * (paramZS.colColor.a / 255))

		for indexBH = 0, 6 do
			local colorValueH = paramZS.DirectionalLight[indexBH]

			if colorValueH then
				localCache.setModelLighting(indexBH, colorValueH.r / 255, colorValueH.g / 255, colorValueH.b / 255)
			end
		end

		paramZS:DrawModel()
		localCache.suppressEngineLighting(false)
		localCache.endCameraMode("3D")
		render.PopRenderTarget()
		localCache.setSurfaceMaterial(createMaterialResult)
		localCache.setDrawColor(255, 255, 255, 255)

		local valueABO = paramZT / paramZU

		if valueABO < 1 then
			local valueABP = valueABO / 1
			local valueABQ = (1 - valueABP) / 2

			localCache.drawTexturedRectUv(0, 0, paramZT, paramZU, valueABQ, 0, valueABQ + valueABP, 1)
		else
			local numberValueCK = 1 / valueABO
			local valueABR = (1 - numberValueCK) / 2

			localCache.drawTexturedRectUv(0, 0, paramZT / 1.1, paramZU / 1.1, 0, valueABR, 1, valueABR + numberValueCK)
		end
	end

	return Kefir.previewesp
end

function Kefir.aRicochet(selfRefEO, paramZV)
	local normalA = paramZV.Normal
	local hitNormal = paramZV.HitNormal
	local hitPosA = paramZV.HitPos
	local valueABS = penetrationModifiers[paramZV.MatType] or 0.5
	local dotProductResult = -runtimeApi.deg(runtimeApi.asin(hitNormal:DotProduct(normalA)))
	local numberValueCL = 60 * valueABS * 1

	if paramZV.HitSky or not paramZV.Hit then
		return false
	end

	if dotProductResult < numberValueCL * 0.7 then
		local angleResultA = normalA:Angle()

		angleResultA:RotateAroundAxis(hitNormal, 180)

		local forwardResultA = angleResultA:Forward()
		local valueABT = hitPosA + hitNormal

		ricochetTraces[#ricochetTraces + 1] = runtimeApi.traceline({
			start = valueABT,
			endpos = valueABT + -forwardResultA * 56756,
			mask = MASK_SHOT
		})

		return true
	else
		ricochetTraces[#ricochetTraces + 1] = nil
	end

	return false
end

function Kefir.hRicochets(selfRefEP, paramZW)
	if paramZW.Entity.organism then
		return
	end

	if paramZW.HitSky or not paramZW.Hit then
		return
	end

	if selfRefEP:aRicochet(paramZW) then
		for indexBI = 1, 6 do
			selfRefEP:aRicochet(ricochetTraces[#ricochetTraces])
		end
	end
end

function Kefir.Ricochets(selfRefEQ)
	local getSettingResultBB = getSetting("VISUALS", "drawricochet", 3)

	if not visualsEnabled or not getSettingResultBB[1] then
		return
	end

	if not hg or not IsValid(localPlayer) or not localPlayer:Alive() then
		return
	end

	local entityRefAN = activeWeapon

	if not IsValid(entityRefAN) or not isfunction(entityRefAN.CallbackBullet) then
		return
	end

	local getCharacterResultD = Kefir:getCharacter(localPlayer)

	if not entityRefAN:GetMuzzleAtt(entityRefAN:GetWeaponEntity(), true) then
		return
	end

	if hg.ammotypeshuy[entityRefAN.Primary.Ammo].BulletSettings.noricochet then
		return
	end

	local valueABU, valueABV, valueABW = entityRefAN:GetTrace(true)

	ricochetTraces = {}

	selfRefEQ:hRicochets(valueABU)

	local valueABX = #ricochetTraces

	if ricochetTraces ~= nil and valueABX > 0 then
		for indexBJ = 1, #ricochetTraces do
			local valueABY = ricochetTraces[indexBJ]

			localCache.setRenderMaterial(tableData.Flat)
			localCache.drawBeam(valueABY.StartPos, valueABY.HitPos, 2, 0, 1, valueABY.Entity.organism and getSettingResultBB[6][2] or getSettingResultBB[6][1])
		end
	end
end

local getVectorResult = runtimeApi.material.Pulse:GetVector("$selfIllumFresnelMinMaxExp")

Kefir:AddRender(function(unusedParamCH, paramZX)
	if not visualsEnabled then
		return
	end

	flagU = false

	if not paramZX then
		localCache.beginCameraMode("3D")
	end

	Kefir:Ricochets()

	local playerChamsResult = Kefir:PlayerChams()
	local fakeChamsResult = Kefir:FakeChams()
	local weaponChamsResult = Kefir:WeaponChams()

	if not paramZX then
		localCache.endCameraMode("3D")
	end

	if flagU then
		local valueABZ = getVectorResult
		local valueACA = runtimeApi.cos(runtimeApi.stime() * 3) * 9
		local valueACB = runtimeApi.mabs(valueACA / 10)

		valueABZ[3] = runtimeApi.clamp(valueACB, 0.1, 1)

		materialCatalog.Pulse:SetVector("$selfIllumFresnelMinMaxExp", valueABZ)
		materialCatalog.Additive.Pulse:SetVector("$selfIllumFresnelMinMaxExp", valueABZ)
	end
end, 2)

function Kefir.Menu(selfRefER)
	if runtimeApi.IsKeyDown(getSetting("MISC", "menu_hotkey", 1)[1]) and Kefir.imenu then
		selfRefER.paint:ToggleMenu()

		Kefir.imenu = false

		runtimeApi.tSimple(0.2, function()
			Kefir.imenu = true
		end)
	end

	Kefir.drag_states = Kefir.drag_states or {}

	if not Kefir.drag_states.keybinds then
		Kefir.drag_states.keybinds = {
			dragging = false,
			offset = {
				x = 0,
				y = 0
			}
		}
	end

	if Kefir.menu and Kefir.menu:IsVisible() and not Kefir.drag_states.keybinds.dragging then
		local valueACC, valueACD = localCache.getMousePosition()
		local valueACE, valueACF = Kefir.menu:GetPos()

		if runtimeApi.IsMouseDown(MOUSE_LEFT) then
			if not flagP then
				if Kefir.paint:IsHovered(valueACE, valueACF, 800, 80) and Kefir.menu:HasFocus() then
					flagP = true
					vectorCtorResult = Vector(valueACC - valueACE, valueACD - valueACF, 0)
				end
			else
				Kefir.menu:SetPos(valueACC - vectorCtorResult.x, valueACD - vectorCtorResult.y)
			end
		else
			flagP = false
		end
	end
end

Kefir:CreateHook("EntityRemoved", function(paramZY)
	boneCache[paramZY] = nil
	Kefir.fakeatt_weapons[paramZY] = nil

	if valueFF[paramZY] then
		valueFF[paramZY] = nil
	end
end)

function Kefir.OnScreenSizeChanged(selfRefES, paramZZ, paramAAA)
	screenWidth = paramZZ
	screenHeight = paramAAA
	selfRefES.TIMURCHIK = selfRefES:RandomString(16)
	valueZA = localCache.mathMin(1024, screenWidth, screenHeight)
	getRenderTargetExResult = GetRenderTargetEx(Kefir.TIMURCHIK, valueZA, valueZA, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SHARED, 17, 0, IMAGE_FORMAT_RGBA8888)
	createMaterialResult = createMaterial(runtimeApi.NameStart .. Kefir.TIMURCHIK, "UnlitGeneric", {
		["$ignorez"] = 1,
		["$translucent"] = 1,
		["$basetexture"] = Kefir.TIMURCHIK
	})
end

nativeApi.bax_fn("send_net_msg", function(paramAAB, unusedParamCI, unusedParamCJ, unusedParamCK, unusedParamCL, unusedParamCM, unusedParamCN, unusedParamCO)
	if paramAAB == 18 then
		
	end
end)
nativeApi.bax_fn("pre_frame_stage_notify", function(paramAAC)
	if fallbackMode then
		return
	end

	if paramAAC == 3 then
		if Kefir.offdangerfn then
			return
		end

		if not getSetting("COMBAT", "inlinetargeting", 3)[1] then
			Kefir.aim:GetTarget()
		end
	end
end)

function Kefir.rage.ShouldAimSilent(selfRefET)
	local getSettingResultBC = getSetting("COMBAT", "silent", 2)[1] and getSetting("COMBAT", "silent_type_new", 2)[1] == "Server Silent"

	if combatEnabled then
		return not Kefir.aimwork and getSetting("COMBAT", "antiaim", 2)[1] or getSettingResultBC
	end

	return false
end

function Kefir.rage.GetPitch(selfRefEU, paramAAD, unusedParamCP, unusedParamCQ, unusedParamCR)
	if not paramAAD then
		return 0
	end

	if paramAAD == "Jitter" then
		Kefir.DevicePitch.Jitter = runtimeApi.random(0, 1) == 1 and -90 or 0
	end

	return Kefir.DevicePitch[paramAAD]
end

local tableDataBN = {
	[0] = 180,
	90,
	-90
}

if not cmDir then
	local numberValueCM = 0
end

function Kefir.rage.GetYaw(selfRefEV, paramAAE, paramAAF)
	if not paramAAE then
		return 0
	end

	local realanglesA = Kefir.realangles

	if not realanglesA then
		return 0
	end

	local valueACG = (realanglesA[2] + 180) % 360
	local manualdirB = Kefir.manualdir

	if paramAAF ~= 0 then
		if paramAAE == "Jitter" then
			return valueACG - runtimeApi.random(-paramAAF, paramAAF)
		elseif paramAAE == "Static" then
			return Kefir.bpacket and paramAAF or -paramAAF
		elseif paramAAE == "Spin" then
			local valueACH = paramAAF * 10

			return runtimeApi.stime() * valueACH
		end
	elseif paramAAE == "Manual" then
		return (realanglesA[2] + tableDataBN[manualdirB]) % 360
	elseif paramAAE == "Forward" then
		return realanglesA[2]
	elseif paramAAE == "Backward" then
		return Kefir.bpacket and valueACG or realanglesA[2]
	end
end

function Kefir.meMoving(selfRefEW)
	return not selfRefEW:InFake(localPlayer) and (localPlayer:KeyDown(IN_MOVELEFT) or localPlayer:KeyDown(IN_MOVERIGHT) or localPlayer:KeyDown(IN_FORWARD) or localPlayer:KeyDown(IN_BACK) or localPlayer:GetVelocity():Length2D() > 128)
end

function Kefir.rage.AntiAim(selfRefEX, commandRefA)
	local valueACI = activeWeapon

	if not IsValid(valueACI) then
		return nil
	end

	if Kefir.zpBase[valueACI.Base] then
		return nil
	end

	if localPlayer:KeyDown(IN_ATTACK) or localPlayer:KeyDown(IN_USE) then
		return nil
	end

	if commandRefA and commandRefA:KeyDown(IN_ATTACK) then
		return nil
	end

	if not combatEnabled then
		return nil
	end

	if not getSetting("COMBAT", "antiaim", 2)[1] then
		return nil
	end

	if not Kefir.silentangle then
		return nil
	end

	if not localPlayer:Alive() or Kefir.aimwork then
		return nil
	end

	if localPlayer:WaterLevel() >= 2 then
		return nil
	end

	if localPlayer:GetMoveType() ~= MOVETYPE_WALK then
		return nil
	end

	local getSettingResultBD = getSetting("COMBAT", "antiaim_pitch", 2)[1]
	local getSettingResultBE = getSetting("COMBAT", "antiaim_yaw", 2)[1]
	local valueACJ = Kefir.settingable_yaw[getSettingResultBE] ~= nil and getSetting("COMBAT", "antiaim_yaw_" .. runtimeApi.slower(getSettingResultBE), 2)[1] or 0
	local getPitchResult = selfRefEX:GetPitch(getSettingResultBD, getSettingResultBE, valueACJ, commandRefA)
	local getYawResult = selfRefEX:GetYaw(getSettingResultBE, valueACJ)

	return Angle(getPitchResult, getYawResult, 0)
end

function Kefir.Clamping(selfRefEY, paramAAG)
	if not selfRefEY.saveinit.max_forward or not selfRefEY.saveinit.max_side then
		selfRefEY.saveinit.max_side = selfRefEY.getconvar("cl_sidespeed"):GetInt()
		selfRefEY.saveinit.max_forward = selfRefEY.getconvar("cl_forwardspeed"):GetInt()

		return
	end

	local getForwardMoveResult = VectorCtor(paramAAG:GetForwardMove(), paramAAG:GetSideMove(), paramAAG:GetUpMove())
	local valueACK = miscEnabled and getSetting("MISC", "limitmv", 2)[1] and getSetting("MISC", "limitmv_amount", 2)[1] or 100
	local valueACL = selfRefEY.saveinit.max_forward - valueACK
	local valueACM = selfRefEY.saveinit.max_side - valueACK
	local numberValueCN = 10000 - valueACK

	getForwardMoveResult.x = runtimeApi.clamp(getForwardMoveResult.x, -valueACL, valueACL)
	getForwardMoveResult.y = runtimeApi.clamp(getForwardMoveResult.y, -valueACM, valueACM)
	getForwardMoveResult.z = runtimeApi.clamp(getForwardMoveResult.z, -numberValueCN, numberValueCN)

	localCache.setForwardMove(paramAAG, getForwardMoveResult.x)
	localCache.setSideMove(paramAAG, getForwardMoveResult.y)
	localCache.setUpMove(paramAAG, getForwardMoveResult.z)
end

function Kefir.aim.ShootTrace(selfRefEZ, paramAAH)
	local tableDataBO = {
		start = Kefir.relative_muzzle.pos,
		endpos = paramAAH[2],
		filter = localPlayer,
		mask = MASK_SHOT
	}

	return runtimeApi.traceline(tableDataBO)
end

local function var4645Handler(paramAAI)
	local tableDataBP = {}

	if IsValid(localPlayer) and localPlayer:IsNPC() then
		local getMuzzleAttResult = paramAAI:GetMuzzleAtt()

		return nil, getMuzzleAttResult.Pos, getMuzzleAttResult.Ang
	end

	local getWeaponEntityResult = paramAAI:GetWeaponEntity()

	if not IsValid(getWeaponEntityResult) then
		return
	end

	local valueACN, valueACO, valueACNHand, valueACOHand = paramAAI:WorldModel_Transform(true)
	local rebuiltServerTransform = false

	valueACN = valueACN or getWeaponEntityResult:GetPos()
	valueACO = valueACO or getWeaponEntityResult:GetAngles()

	if Kefir.isvector(valueACNHand) and isangle(valueACOHand) then
		valueACN, valueACO = LocalToWorld(paramAAI.WorldPos or ZERO_VECTOR, paramAAI.WorldAng or ZERO_ANGLE, valueACNHand, valueACOHand)
		valueACO:RotateAroundAxis(valueACO:Forward(), 180)
		rebuiltServerTransform = true
	end

	if not rebuiltServerTransform and paramAAI:ShouldUseFakeModel() then
		local matrixValueB = Matrix()

		matrixValueB:SetTranslation(paramAAI.FakePos)
		matrixValueB:SetAngles(paramAAI.FakeAng)

		local getInverseResult = matrixValueB:GetInverse()

		valueACN, valueACO = LocalToWorld(getInverseResult:GetTranslation(), getInverseResult:GetAngles(), valueACN, valueACO)
	end

	local valueACP, valueACQ = LocalToWorld(paramAAI.LocalMuzzlePos, paramAAI.LocalMuzzleAng, valueACN, valueACO)
	local forwardResultB = valueACQ:Forward()
	local inFakeResult = Kefir:InFake(localPlayer)

	tableDataBP.start = valueACP
	tableDataBP.endpos = valueACP + forwardResultB * 8000
	tableDataBP.filter = {
		getWeaponEntityResult,
		not localPlayer.suiciding and localPlayer or NULL,
		inFakeResult
	}

	return runtimeApi.traceline(tableDataBP), valueACP, valueACQ
end

function Kefir.aim.ShootMuzzle(selfRefFA)
	if not localPlayer then
		return
	end

	local entityRefAO = activeWeapon
	local eyePosition = localPlayer:EyePos()
	local eyeAnglesA = localPlayer:EyeAngles()

	if not entityRefAO or not IsValid(entityRefAO) then
		return eyePosition, eyeAnglesA, false
	end

	if Kefir.special_server.zcity and entityRefAO.GetTrace and entityRefAO.GetWeaponEntity then
		local valueACR, valueACS, valueACT = var4645Handler(entityRefAO)
		local forwardResultC = valueACT:Forward()
		local valueACU, valueACV = runtimeApi.utilDistanceToLine(valueACS, valueACS - forwardResultC * 50, localPlayer:EyePos())
		local tableDataBQ = {
			start = valueACV,
			endpos = valueACS,
			filter = {
				localPlayer,
				Kefir:getCharacter(localPlayer)
			}
		}
		local valueACW = runtimeApi.traceline(tableDataBQ)

		return valueACW.HitPos - valueACW.Normal, valueACT, true
	elseif Kefir.special_server.hgcom and entityRefAO.GetShootMatrix then
		return entityRefAO:GetShootMatrix()
	else
		return eyePosition, eyeAnglesA, false
	end
end

local valveBipedBip01 = "ValveBiped.Bip01_"
local vectorValueE = Vector()

function Kefir.aim.AutoWall(selfRefFB, paramAAJ, paramAAK, paramAAL, paramAAM)
	local primaryA = paramAAK.Primary

	if not primaryA or not primaryA.Ammo then
		return false
	end

	local istableResultD = istable(hg) and hg.ammotypeshuy ~= nil and hg.ammotypeshuy[primaryA.Ammo] or nil

	if not istableResultD or not istableResultD.BulletSettings then
		return false
	end

	local bulletSettings = istableResultD.BulletSettings
	local valueACX = (bulletSettings.Penetration or paramAAK.Penetration or 5) * (paramAAK.PenetrationMultiplier or 1)
	local normalB = paramAAJ.Normal
	local hitNormalA = paramAAJ.HitNormal
	local hitPosB = paramAAJ.HitPos
	local valueACY = penetrationModifiers[paramAAJ.MatType] or 0.5
	local dotResultC = hitNormalA:Dot(normalB)

	if -runtimeApi.deg(runtimeApi.asin(dotResultC)) <= 60 * valueACY * (bulletSettings.noricochet and 0 or 1) then
		return false
	end

	local valueACZ = valueACX * 3
	local valueADA = localCache.mathMin(valueACZ / valueACY * 0.4, 100)
	local numberValueCO = 5
	local vectorValueF

	while numberValueCO < valueADA do
		local vectorValueG = vectorValueE

		vectorValueG.x = hitPosB.x + normalB.x * numberValueCO
		vectorValueG.y = hitPosB.y + normalB.y * numberValueCO
		vectorValueG.z = hitPosB.z + normalB.z * numberValueCO

		local valueADB = runtimeApi.tracequick(vectorValueG, -normalB * numberValueCO)

		if not valueADB.StartSolid then
			vectorValueF = valueADB.HitPos
			valueACX = valueACX - valueACZ * numberValueCO / valueADA / 3

			break
		end

		numberValueCO = numberValueCO + 5
	end

	if vectorValueF then
		local vectorValueH = vectorValueE

		vectorValueH.x = vectorValueF.x + normalB.x
		vectorValueH.y = vectorValueF.y + normalB.y
		vectorValueH.z = vectorValueF.z + normalB.z

		local vectorValueI = Vector()

		vectorValueI.x = vectorValueF.x + normalB.x * 10000
		vectorValueI.y = vectorValueF.y + normalB.y * 10000
		vectorValueI.z = vectorValueF.z + normalB.z * 10000

		local valueADC = runtimeApi.traceline({
			start = vectorValueH,
			endpos = vectorValueI,
			mask = MASK_SHOT,
			filter = function(paramAAN)
				return paramAAN ~= paramAAJ.Entity
			end
		})

		if isfunction(paramAAL) and paramAAL(valueADC) then
			if paramAAM then
				Kefir.aimwall = true
			end

			return true
		end
	end

	return false
end

local valueADD

local function helperH(paramAAO)
	return Kefir:getCharacter(paramAAO.Entity) == valueADD
end

function Kefir.aim.BoneSelector(selfRefFC, paramAAP, paramAAQ, paramAAR)
	local ownerE = selfRefFC.__owner
	local hugeE = math.huge
	local valueADE
	local valueADF
	local valueADG
	local valueADH = paramAAQ[1]
	local tableDataBR = {
		valueADH,
		ZERO_VECTOR
	}
	local valueADI = paramAAQ[2]
	local valueADJ = paramAAQ[3]
	local valueADK = paramAAQ[4]
	local valueADL = paramAAQ[5]
	local valueADM = paramAAQ[6]
	local valueADN = paramAAQ[7]
	local valueADO = paramAAQ[9]
	local bBasicConditionResult = Kefir:bBasicCondition(valueADI, paramAAQ[8], paramAAR)
	local valueADP = valueADK and (valueADN or valueADL and valueADM > runtimeApi.health(paramAAR) or bBasicConditionResult)
	local activebonesC = Kefir.activebones
	local hsPriority = Kefir.hs_priority
	local aIMHITBOX = Kefir.variables.AIM_HITBOX

	if valueADP then
		activebonesC = Kefir.body_bones
	end

	local isHGObjectResultA = Kefir:IsHGObject(activeWeapon)

	for indexBK = 1, #activebonesC do
		local valueADQ = activebonesC[indexBK]

		if boneName == "-" or not valueADP and not runtimeApi.HasValue(aIMHITBOX, valueADQ) then
			
		else
			local valveBipedBip01A = "ValveBiped.Bip01_" .. valueADQ
			local valueADR = hsPriority[indexBK]
			local getCacheBoneResultC = ownerE:getCacheBone(paramAAP, valveBipedBip01A)

			if getCacheBoneResultC then
				local valueADS, valueADT = ownerE:getPositionBone(paramAAP, getCacheBoneResultC, valueADJ)

				if valueADS and valueADT then
					tableDataBR[2] = valueADS

					local shootTraceResult = selfRefFC:ShootTrace(tableDataBR)

					valueADD = paramAAP

					if (shootTraceResult.Entity == paramAAP or valueADO and isHGObjectResultA and selfRefFC:AutoWall(shootTraceResult, valueADI, helperH, true)) and (valueADR or math.huge) < hugeE then
						valueADE = valueADS
						valueADG = valueADT
						valueADF = valveBipedBip01A
						hugeE = valueADR
					end
				end
			end
		end
	end

	return valueADE, valueADG, valueADF
end

function Kefir.aim.PositionAdjustment(selfRefFD, paramAAS, paramAAT, paramAAU, paramAAV)
	local isRagdollResultC = paramAAS:IsRagdoll()
	local tickIntervalC = localCache.tickInterval
	local targetSpeedC = isRagdollResultC and 0 or paramAAS:GetVelocity():Length()
	local distToTargetC = paramAAT:DistTo(localPlayer:EyePos())

	local leadTimeC = tickIntervalC * 2

	if targetSpeedC > 180 then
		leadTimeC = tickIntervalC * 3
	end

	if distToTargetC > 1400 then
		leadTimeC = leadTimeC + tickIntervalC * 0.5
	end

	local velocity = ((isRagdollResultC and ZERO_VECTOR or paramAAS:GetVelocity()) - (localPlayer:GetMoveType() ~= MOVETYPE_NOCLIP and localPlayer:GetVelocity() or ZERO_VECTOR)) * leadTimeC

	if paramAAV == "ValveBiped.Bip01_Head1" or paramAAV == "ValveBiped.Bip01_Neck1" then
		paramAAT = paramAAT + paramAAU:Forward() * (not isRagdollResultC and 3.1 or 2.55)
	end

	paramAAT = paramAAT + velocity

	return paramAAT
end

function Kefir.aim.GetAimPos(selfRefFE, entityRefAP, paramAAW, paramAAX)
	if not IsValid(entityRefAP) then
		return ZERO_VECTOR
	end

	local valueADU, valueADV, valueADW = selfRefFE:BoneSelector(entityRefAP, paramAAW, paramAAX)

	if valueADU ~= nil and Kefir.isvector(valueADU) then
		return (selfRefFE:PositionAdjustment(entityRefAP, valueADU, valueADV, valueADW))
	end

	return ZERO_VECTOR
end

local friendlistA = Kefir.friendlist

Kefir.aim.team_validator = {
	Default = function(playerRefC)
		return localPlayer:Team() == playerRefC:Team()
	end,
	Adaptive = function(paramAAY)
		return Kefir:aIgnoreTeam(paramAAY)
	end
}

function Kefir.aim.TargetIsValid(selfRefFF, playerRefD, paramAAZ)
	if not IsValid(playerRefD) then
		return false
	end

	if playerRefD == localPlayer then
		return false
	end

	if not playerRefD:Alive() then
		return false
	end

	if playerRefD:IsDormant() then
		return false
	end

	if playerRefD:GetMoveType() == MOVETYPE_NOCLIP and not Kefir:InFake(playerRefD) then
		return false
	end

	if paramAAZ[1] and selfRefFF.team_validator[paramAAZ[3]](playerRefD) then
		return false
	end

	if paramAAZ[2] and playerRefD.organism and playerRefD.organism.otrub then
		return false
	end

	if paramAAZ[4] and Kefir:InFake(playerRefD) then
		return false
	end

	if runtimeApi.HasValue(friendlistA, playerRefD) then
		return false
	end

	return true
end

function Kefir.aim.SubSelection(selfRefFG, paramABA, paramABB, paramABC)
	local numberValueCP = 0
	local entityRefAQ = runtimeApi.activeweapon(paramABA)

	if IsValid(entityRefAQ) and paramABC == "Armed" and (Kefir:IsHGObject(entityRefAQ) or Kefir:IsMeleeObject(entityRefAQ)) then
		numberValueCP = numberValueCP - 100000
	end

	return paramABB + numberValueCP
end

function Kefir.aim.Target(selfRefFH, unusedParamCS, paramABD, paramABE)
	local valueADX
	local valueADY = ZERO_VECTOR
	local hugeF = math.huge
	local getSettingResultBF = getSetting("COMBAT", "main_selection", 1)[1]
	local getSettingResultBG = getSetting("COMBAT", "sub_selection", 1)[1]

	if not fallbackMode then
		for keyBJ, itemBG in localCache.iteratePlayers() do
			if selfRefFH:TargetIsValid(itemBG, paramABE) then
				local getCharacterResultE = Kefir:getCharacter(itemBG)
				local getAimPosResult = selfRefFH:GetAimPos(getCharacterResultE, paramABD, itemBG)

				if not getAimPosResult:IsZero() then
					local distToSqrResult = runtimeApi.ply_pos:DistToSqr(getAimPosResult)
					local valueADZ

					if getSettingResultBF == "Distance" then
						valueADZ = distToSqrResult
					elseif getSettingResultBF == "Crosshair" then
						local toScreenResultH = getAimPosResult:ToScreen()

						valueADZ = nativeApi.util_calcNearest(toScreenResultH.x, toScreenResultH.y, screenWidth, screenHeight)
					end

					local subSelectionResult = selfRefFH:SubSelection(itemBG, valueADZ, getSettingResultBG)

					if subSelectionResult < hugeF then
						valueADX = getCharacterResultE
						valueADY = getAimPosResult
						hugeF = subSelectionResult
					end
				end
			end
		end
	end

	return valueADX, valueADY
end

function Kefir.aim.MovementFix(selfRefFI, paramABF, paramABG)
	if not Kefir.silentangle then
		return
	end

	if localPlayer:WaterLevel() >= 2 then
		return
	end

	if localPlayer:GetMoveType() ~= MOVETYPE_WALK then
		return
	end

	local vectorValueJ = localCache.getCommandViewAngles(paramABF)
	local valueAEA = runtimeApi.angnormalize(vectorValueJ.x)
	local numberValueCQ = -1

	if valueAEA > 89 or valueAEA < -89 then
		numberValueCQ = 1
	end

	local valueAEB = runtimeApi.math.rad(runtimeApi.angnormalize((vectorValueJ.y - paramABG) * numberValueCQ))
	local getForwardMoveResultA = paramABF:GetForwardMove()
	local getSideMoveResult = paramABF:GetSideMove()
	local valueAEC = getForwardMoveResultA * -runtimeApi.cos(valueAEB) * numberValueCQ + getSideMoveResult * runtimeApi.sin(valueAEB)
	local valueAED = getForwardMoveResultA * runtimeApi.sin(valueAEB) * numberValueCQ + getSideMoveResult * runtimeApi.cos(valueAEB)

	localCache.setForwardMove(paramABF, valueAEC)
	localCache.setSideMove(paramABF, valueAED)
end

function Kefir.aim.DoShoot(selfRefFJ, commandRefB, paramABH)
	if paramABH.Primary and paramABH.Primary.Automatic or false then
		commandRefB:SetButtons(runtimeApi.bitbor(commandRefB:GetButtons(), IN_ATTACK))
	elseif not Kefir.shooted then
		commandRefB:SetButtons(runtimeApi.bitbor(commandRefB:GetButtons(), IN_ATTACK))

		Kefir.shooted = true
	else
		commandRefB:SetButtons(runtimeApi.bitband(commandRefB:GetButtons(), runtimeApi.bitbnot(IN_ATTACK)))

		Kefir.shooted = false
	end
end

local numberValueCR = 64

function Kefir.aim.ProcessShoot(selfRefFK, paramABI, unusedParamCT, entityRefAR)
	if not paramABI or not IsValid(entityRefAR) then
		return
	end

	local entityRefAS = activeWeapon

	if not IsValid(entityRefAS) or entityRefAS:Clip1() < 1 then
		return
	end

	selfRefFK:DoShoot(paramABI, entityRefAS)
end

function Kefir.rage.Silent(selfRefFL, paramABJ)
	Kefir.fakeangles = localCache.getCommandViewAngles(paramABJ)

	if not Kefir.silentangle then
		Kefir.realangles = nil

		return
	end

	if not Kefir.realangles then
		Kefir.realangles = localCache.getCommandViewAngles(paramABJ)
	end

	local getMouseXResult = paramABJ:GetMouseX()
	local getMouseYResult = paramABJ:GetMouseY()
	local getFloatResult = Kefir.getconvar("m_yaw"):GetFloat()

	Kefir.realangles = Kefir.realangles + Angle(getMouseYResult * getFloatResult, getMouseXResult * -getFloatResult, 0)
	Kefir.realangles.p = runtimeApi.clamp(Kefir.realangles.p, -89, 89)
	Kefir.realangles.y = runtimeApi.angnormalize(Kefir.realangles.y)
	Kefir.realangles.r = 0

	if localCache.getCommandNumber(paramABJ) == 0 then
		nativeApi.engine_setViewAngles(paramABJ, Kefir.realangles)

		return
	end
end

function Kefir.aim.PreInit(selfRefFM)
	Kefir.aimwork = false
end

local numberValueCS = 0

function Kefir.rage.Main(selfRefFN, commandRefC)
	if commandRefC:KeyDown(IN_ATTACK) then
		return
	end

	if combatEnabled and getSetting("COMBAT", "antiaim", 2)[1] then
		local valueAEE = runtimeApi.stime() - numberValueCS

		if getSetting("COMBAT", "antiaim_yaw", 2)[1] == "Manual" and valueAEE > 0 then
			local getSettingResultBH = getSetting("COMBAT", "antiaim_yaw_manual_left", 2)[1]
			local getSettingResultBI = getSetting("COMBAT", "antiaim_yaw_manual_right", 2)[1]
			local getSettingResultBJ = getSetting("COMBAT", "antiaim_yaw_manual_back", 2)[1]
			local valueAEF = runtimeApi.IsKeyDown(getSettingResultBH)
			local valueAEG = runtimeApi.IsKeyDown(getSettingResultBI)

			if runtimeApi.IsKeyDown(getSettingResultBJ) or valueAEF and Kefir.manualdir == 1 or valueAEG and Kefir.manualdir == 2 then
				Kefir.manualdir = 0
				numberValueCS = runtimeApi.stime() + 0.5

				return
			end

			if valueAEF then
				Kefir.manualdir = 1
				numberValueCS = runtimeApi.stime() + 0.5

				return
			end

			if valueAEG then
				Kefir.manualdir = 2
				numberValueCS = runtimeApi.stime() + 0.5

				return
			end
		end

		local antiAimResult = selfRefFN:AntiAim(commandRefC)

		Kefir.antiaim_angle = antiAimResult

		if antiAimResult ~= nil and runtimeApi.stime() >= Kefir.aimend + 0.25 then
			nativeApi.engine_setViewAngles(commandRefC, antiAimResult)
		end
	end
end

function Kefir.aim.GetTarget(selfRefFO)
	local ownerF = selfRefFO.__owner

	ownerF.aimtarget = nil
	ownerF.aimpos = ZERO_VECTOR

	local tableDataBS = {
		getSetting("COMBAT", "ignoreteam", 3)[1],
		getSetting("COMBAT", "ignoreotrub", 3)[1],
		getSetting("COMBAT", "type_ignoreteam", 3)[1],
		getSetting("COMBAT", "ignorefakergdl", 3)[1]
	}

	if not combatEnabled then
		return
	end

	if not localPlayer then
		return
	end

	if not localPlayer:Alive() then
		return
	end

	if not IsValid(activeWeapon) then
		return
	end

	if not getSetting("COMBAT", "aim", 1)[1] then
		return
	end

	local valueAEH = activeWeapon
	local eyePositionA = localPlayer:EyePos()

	if Kefir:IsHGObject(valueAEH) and Kefir.isvector(ownerF.command_muzzle.pos) then
		eyePositionA = ownerF.command_muzzle.pos
	end

	local getSettingResultBK = getSetting("COMBAT", "calcpos", 3)[1]
	local getSettingResultBL = getSetting("COMBAT", "force_baim", 1)[1]
	local flagW = false
	local valueAEI

	if getSettingResultBL and getSetting("COMBAT", "force_baim_onkey", 1)[1] then
		valueAEI = Kefir:KB_State("COMBAT", "baim_hotkey", 1)
	end

	local tableDataBT = {
		eyePositionA,
		valueAEH,
		getSettingResultBK,
		getSettingResultBL,
		getSetting("COMBAT", "force_baim_hp", 1)[1],
		getSetting("COMBAT", "force_baim_hp_int", 1)[1],
		valueAEI,
		getSetting("COMBAT", "force_baim_conditionsb", 1)[1],
		getSetting("COMBAT", "autowall", 2)[1]
	}
	local valueAEJ, valueAEK = selfRefFO:Target(valueAEH, tableDataBT, tableDataBS)

	if not valueAEJ then
		return
	end

	local toScreenResultI = eyePositionA:ToScreen()

	if not selfRefFO:FOV(valueAEJ, valueAEK, toScreenResultI, tableDataBT) then
		return
	end

	ownerF.aimtarget = valueAEJ
	ownerF.aimpos = valueAEK
end

local tableDataBU = {
	weapon_ar2 = Vector(0.02618, 0.02618, 0.02618),
	weapon_smg1 = Vector(0.07, 0.07, 0.07),
	weapon_pistol = Vector(0.01, 0.01, 0.01),
	weapon_shotgun = Vector(0.08716, 0.08716, 0.08716),
	weapon_357 = Vector(0, 0, 0),
	weapon_crossbow = Vector(0, 0, 0),
	weapon_alyxgun = Vector(0.0349, 0.0349, 0.0349)
}

function Kefir.Humanizator(selfRefFP, paramABK, vectorRefB, vectorRefC)
	local humanizerA = Kefir.humanizer
	local valueAEL = Kefir.frametime()
	local valueAEM = runtimeApi.stime()
	local numberValueCT = 0.6
	local getSettingResultBM = getSetting("COMBAT", "humanizator_noise", 1)[1] or 0.3
	local getSettingResultBN = getSetting("COMBAT", "humanizator_spring", 1)[1] or 8
	local getSettingResultBO = getSetting("COMBAT", "humanizator_jitter", 1)[1] or 0.15
	local valueAEN = getSettingResultBM / 50

	humanizerA.jitterTimer = humanizerA.jitterTimer or 0
	humanizerA.jitter = humanizerA.jitter or Angle(0, 0, 0)

	if valueAEM >= humanizerA.jitterTimer then
		humanizerA.jitter = Angle(runtimeApi.random(-getSettingResultBO, getSettingResultBO), runtimeApi.random(-getSettingResultBO, getSettingResultBO), 0)
		humanizerA.jitterTimer = valueAEM + runtimeApi.random(15, 45) * 0.01
	end

	humanizerA.jitter.p = humanizerA.jitter.p * 0.85
	humanizerA.jitter.y = humanizerA.jitter.y * 0.85

	if valueAEM >= humanizerA.noiseTimer then
		humanizerA.noiseTarget = Angle(runtimeApi.random(-valueAEN, valueAEN), runtimeApi.random(-valueAEN * 1.5, valueAEN * 1.5), 0)
		humanizerA.noiseTimer = valueAEM + runtimeApi.random(8, 20) * 0.01
	end

	local numberValueCU = 6

	humanizerA.noise.p = humanizerA.noise.p + (humanizerA.noiseTarget.p - humanizerA.noise.p) * valueAEL * numberValueCU
	humanizerA.noise.y = humanizerA.noise.y + (humanizerA.noiseTarget.y - humanizerA.noise.y) * valueAEL * numberValueCU

	local valueAEO = (vectorRefC.p - vectorRefB.p) * paramABK
	local valueAEP = ((vectorRefC.y - vectorRefB.y) * paramABK + 180) % 360 - 180

	humanizerA.vel.p = humanizerA.vel.p * numberValueCT + valueAEO * getSettingResultBN * valueAEL
	humanizerA.vel.y = humanizerA.vel.y * numberValueCT + valueAEP * getSettingResultBN * valueAEL
	humanizerA.vel.p = runtimeApi.clamp(humanizerA.vel.p, -12, 12)
	humanizerA.vel.y = runtimeApi.clamp(humanizerA.vel.y, -15, 15)

	return Angle(vectorRefB.p + humanizerA.vel.p + humanizerA.noise.p + humanizerA.jitter.p, vectorRefB.y + humanizerA.vel.y + humanizerA.noise.y + humanizerA.jitter.y, 0)
end

Kefir.aim_fraction = 0

function Kefir.GetSpread(selfRefFQ, weaponRefB)
	if not IsValid(weaponRefB) then
		return ZERO_VECTOR
	end

	local classNameE = tableDataBU[weaponRefB:GetClass()] ~= nil and tableDataBU[weaponRefB:GetClass()] or weaponRefB.Primary ~= nil and weaponRefB.Primary.Spread or nil

	return Kefir.isvector(classNameE) and classNameE or isnumber(classNameE) and Vector(classNameE, classNameE, 0) or nil
end

function Kefir.aim.Firearm(selfRefFR, paramABL, paramABM)
	if not localPlayer or not localPlayer.GetActiveWeapon then
		return
	end

	if not IsValid(activeWeapon) then
		return
	end

	local weaponRefC = activeWeapon
	local aimtargetB = Kefir.aimtarget
	local aimposA = Kefir.aimpos

	if weaponRefC:Clip1() < 0 then
		return
	end

	if aimposA:IsZero() then
		return
	end

	local isHGObjectResultB = Kefir:IsHGObject(weaponRefC)

	if isHGObjectResultB and weaponRefC:IsSprinting() then
		Kefir.last_speed = runtimeApi.stime()
	end

	if isHGObjectResultB and (Kefir.last_speed or 0) + 0.3 > runtimeApi.stime() then
		return
	end

	local valueAEQ
	local valueAER

	if isHGObjectResultB then
		local commandMuzzle = Kefir.special_server.hgcom and Kefir.relative_muzzle or Kefir.command_muzzle

		valueAEQ = commandMuzzle.pos
		valueAER = commandMuzzle.ang
	else
		valueAEQ = localPlayer:EyePos()
		valueAER = localPlayer:EyeAngles()
	end

	local valueAES = localCache.getCommandViewAngles(paramABL)
	local getSettingResultBP = getSetting("COMBAT", "smooth", 1)[1]
	local getSettingResultBQ = getSetting("COMBAT", "silent", 2)[1]
	local getSettingResultBR = getSetting("COMBAT", "silent_type_new", 2)[1]
	local valueAET = getSettingResultBQ and getSettingResultBR == "Server Silent"
	local vectorValueK

	if isHGObjectResultB then
		vectorValueK = nativeApi.util_calcAng2Diff(valueAEQ, aimposA, valueAER, valueAES, localPlayer:EyePos())
	else
		vectorValueK = (aimposA - valueAEQ):Angle()
	end

	if isHGObjectResultB then
		local distToSqrResultA = valueAEQ:DistToSqr(aimposA)
		local numberValueCV = 7.85
		local meMovingResultA = Kefir:meMoving() and 100 or 400
		local valueAEU = valueAET and numberValueCV or 10

		if distToSqrResultA < 5500 and getSettingResultBP < numberValueCV then
			local valueAEV = numberValueCV - runtimeApi.floor(distToSqrResultA / meMovingResultA)

			getSettingResultBP = runtimeApi.clamp(valueAEV, 1, valueAEU)
		end
	end

	local valueAEW = nativeApi.util_calcStepSide(getSettingResultBP, 0.1, 0.9)
	local valueAEX

	if not paramABM then
		return
	end

	local getSpreadResultA = Kefir:GetSpread(weaponRefC)

	if getSetting("COMBAT", "predictspread", 3)[1] and getSpreadResultA ~= nil and Kefir.isvector(getSpreadResultA) then
		vectorValueK = vectorValueK + nativeApi.engine_predictSpread(paramABL, getSpreadResultA):Angle()

		vectorValueK:Normalize()
	end

	if Kefir.dynamicfov_var then
		Kefir.dynamicfov = Kefir.aimpos
	else
		Kefir.dynamicfov = ZERO_VECTOR
	end

	local angleValue = Angle(vectorValueK.x, vectorValueK.y, 0)
	local humanizatorResult = getSetting("COMBAT", "humanizator", 1)[1] and not valueAET and Kefir:Humanizator(valueAEW, valueAES, angleValue) or Kefir.LerpAngle(valueAEW, valueAES, angleValue)

	if getSettingResultBQ and getSettingResultBR == "Camera Silent" and not Kefir.aimcsl then
		Kefir.aimcsl = localPlayer:EyeAngles()
	end

	local forwardResultD = valueAES:Forward()
	local forwardResultE = angleValue:Forward()
	local dotResultD = forwardResultD:Dot(forwardResultE)

	Kefir.aim_fraction = runtimeApi.clamp(dotResultD, 0, 1)
	Kefir.aimwork = true
	Kefir.view_angle = humanizatorResult
end

function Kefir.aim.ClearLock(selfRefFS)
	Kefir.dynamicfov = ZERO_VECTOR
end

function Kefir.aim.Core(selfRefFT, paramABN, paramABO)
	if not localPlayer then
		return
	end

	if not localPlayer:Alive() then
		return
	end

	if combatEnabled and getSetting("COMBAT", "aim", 1)[1] then
		selfRefFT:Firearm(paramABN, paramABO)
	end
end

function Kefir.HKeybind(selfRefFU)
	for indexBL = 0, 117 do
		if runtimeApi.IsKeyDown(indexBL) then
			if Kefir.toggle_states2[indexBL] == nil then
				Kefir.toggle_states[indexBL] = not Kefir.toggle_states[indexBL]
				Kefir.toggle_states2[indexBL] = true
			end
		else
			Kefir.toggle_states2[indexBL] = nil
		end
	end
end

Kefir.aimstart = 0

function Kefir.aim.PostInit(selfRefFV, paramABP, paramABQ)
	local aimworkB = Kefir.aimwork
	local valueAEY = runtimeApi.stime()

	if aimworkB then
		if Kefir.aimstart == 0 then
			Kefir.aimstart = valueAEY
		end

		Kefir.aimend = 0
	else
		Kefir.view_angle = nil
		Kefir.aimstart = 0

		if Kefir.aimend == 0 then
			Kefir.aimend = valueAEY
		end

		Kefir.aimwall = false
		Kefir.aimcsl = nil
	end

	local tableDataBV = {
		getSetting("COMBAT", "ignoreteam", 3)[1],
		getSetting("COMBAT", "ignoreotrub", 3)[1],
		getSetting("COMBAT", "type_ignoreteam", 3)[1]
	}

	if not aimworkB or paramABQ == "Always On" or not paramABP or not Kefir.dynamicfov_var then
		selfRefFV:ClearLock()
	end
end

function Kefir.aim.Main(selfRefFW, paramABR)
	if not combatEnabled then
		return
	end

	local getSettingResultBS = getSetting("COMBAT", "aim_hotkey", 1)[1]
	local kBStateResult = Kefir:KB_State("COMBAT", "aim_hotkey", 1, paramABR)

	if getSettingResultBS == "Always On" then
		selfRefFW:ClearLock()
	end

	selfRefFW:PreInit()

	if getSetting("COMBAT", "inlinetargeting", 3)[1] then
		selfRefFW:GetTarget()
	end

	selfRefFW:Core(paramABR, kBStateResult)
	selfRefFW:PostInit(kBStateResult, getSettingResultBS)
end

function Kefir.aim.ProcessAim(selfRefFX, paramABS)
	if combatEnabled then
		if getSetting("COMBAT", "autostop", 3)[1] then
			local getSettingResultBT = getSetting("COMBAT", "autostop_type", 3)[1]

			if getSettingResultBT == "Slide" then
				local getForwardMoveResultB = paramABS:GetForwardMove()
				local getSideMoveResultA = paramABS:GetSideMove()
				local numberValueCW = 8 / runtimeApi.math.sqrt(getForwardMoveResultB^2 + getSideMoveResultA^2)

				if Kefir:meMoving() then
					localCache.setForwardMove(paramABS, getForwardMoveResultB * numberValueCW)
					localCache.setSideMove(paramABS, getSideMoveResultA * numberValueCW)
				end
			elseif getSettingResultBT == "Full" then
				localCache.setForwardMove(paramABS, 0)
				localCache.setSideMove(paramABS, 0)
			end
		end

		if getSetting("COMBAT", "autocrouch", 3)[1] then
			paramABS:AddKey(IN_DUCK)
		end

		if combatEnabled and getSetting("COMBAT", "blockfire_nfr", 1)[1] and Kefir.aim_fraction <= 0.9999 then
			paramABS:RemoveKey(IN_ATTACK)
		end

		local getSettingResultBU = getSetting("COMBAT", "autofire_first_delay", 2)[1]
		local valueAEZ = getSettingResultBU / 1000
		local valueAFA = getSettingResultBU > 0 and valueAEZ <= runtimeApi.stime() - Kefir.aimstart or true

		if getSetting("COMBAT", "autofire", 2)[1] and valueAFA then
			if runtimeApi.startswith(activeWeapon:GetClass(), "m9k_") then
				paramABS:RemoveKey(IN_SPEED)
			end

			selfRefFX:ProcessShoot(paramABS, "autofire", Kefir.aimtarget)
		end
	end
end

function Kefir.Movement(selfRefFY, commandRefD)
	if not localPlayer then
		return
	end

	if miscEnabled and localPlayer:GetMoveType() == MOVETYPE_WALK and localPlayer:WaterLevel() < 3 and not localPlayer:IsOnGround() then
		if getSetting("MISC", "bunnyhop", 3)[1] and runtimeApi.IsKeyDown(runtimeApi.GetKeyCode(runtimeApi.LookupBinding("+jump"))) then
			commandRefD:SetButtons(runtimeApi.bitband(commandRefD:GetButtons(), runtimeApi.bitbnot(IN_JUMP)))
		end

		if getSetting("MISC", "autostrafe", 3)[1] then
			if commandRefD:GetMouseX() > 0 then
				localCache.setSideMove(commandRefD, 8500)
			elseif commandRefD:GetMouseX() < 0 then
				localCache.setSideMove(commandRefD, -8500)
			end
		end
	end
end

function Kefir.NeedReload(selfRefFZ)
	local entityRefAT = activeWeapon

	if not IsValid(entityRefAT) then
		return false
	end

	local clip1ResultB = entityRefAT:Clip1()

	if clip1ResultB < 0 then
		return false
	end

	local getPrimaryAmmoTypeResultA = entityRefAT:GetPrimaryAmmoType()
	local getAmmoCountResultA = localPlayer:GetAmmoCount(getPrimaryAmmoTypeResultA)

	return isfunction(entityRefAT.GetAnimPos_Insert) and not wep.drawBullet or getAmmoCountResultA > 0 and clip1ResultB <= 0
end

function Kefir.fPacketManip(selfRefGA, commandRefE)
	Kefir.bpacket = true
	nativeApi.engine_plugPacket(Kefir.bpacket)
end

function Kefir.DT(selfRefGB, paramABT)
	return false
end

Kefir:CreateHook("CreateMove", function(commandRefF)
	if fallbackMode then
		return
	end

	Kefir:fPacketManip(commandRefF)

	if Kefir.view_angle ~= nil then
		Kefir.view_angle[3] = 0

		nativeApi.engine_setViewAngles(commandRefF, Kefir.view_angle)

		if Kefir.aimwork then
			Kefir.aim:ProcessAim(commandRefF)
		end
	end

	if not Kefir.offdangerfn then
		Kefir.antiaim_angle = nil

		Kefir.rage:Main(commandRefF)
		Kefir.rage:Silent(commandRefF)
		Kefir:Movement(commandRefF)

		if combatEnabled and Kefir.realangles and Kefir.antiaim_angle ~= nil then
			Kefir.aim:MovementFix(commandRefF, Kefir.realangles.y)
		end
	end

	Kefir.silentangle = Kefir.rage:ShouldAimSilent()

	if combatEnabled and getSetting("COMBAT", "automaticpistol", 3)[1] and IsValid(activeWeapon) and activeWeapon.Primary and not activeWeapon.Primary.Automatic then
		if not commandRefF:KeyDown(IN_ATTACK) then
			was_attacking = false

			return
		end

		if was_attacking then
			commandRefF:SetButtons(runtimeApi.bitband(commandRefF:GetButtons(), runtimeApi.bitbnot(IN_ATTACK)))

			was_attacking = false
		else
			was_attacking = true
		end
	end

	Kefir:Clamping(commandRefF)

	if combatEnabled and getSetting("COMBAT", "autodraw", 3)[1] and Kefir:NeedReload() then
		commandRefF:AddKey(IN_RELOAD)
	end
end, "defrt")

nativeApi.bax_fn("prerender", function()
	if fallbackMode then
		return
	end

	if localPlayer then
		local valueAFG, valueAFH = Kefir.aim:ShootMuzzle()

		Kefir.relative_muzzle = {
			pos = valueAFG,
			ang = valueAFH
		}
	end
end)
Kefir:CreateHook("SetupMove", function(paramABU, unusedParamCU, paramABV)
	if fallbackMode or paramABU ~= localPlayer then
		return
	end

	if localPlayer then
		local valueAFI, valueAFJ = Kefir.aim:ShootMuzzle()

		Kefir.command_muzzle = {
			pos = valueAFI,
			ang = valueAFJ
		}
	end

	if not Kefir.offdangerfn then
		Kefir.aim:Main(paramABV)
	end
end, "nigga")

nativeApi.bax_fn("think", function()
	if fallbackMode then
		return
	end

	combatEnabled = getSetting("COMBAT", "toggle", 1)[1]
	visualsEnabled = getSetting("VISUALS", "toggle", 1)[1]
	miscEnabled = getSetting("MISC", "toggle", 1)[1]
	Kefir.dynamicfov_var = getSetting("COMBAT", "dynamicfov", 1)[1]
	unknownText = Kefir:GetLangText("unknown")

	local flagY = false

	if visualsEnabled and getSetting("VISUALS", "apply_tperson", 3)[1] then
		flagY = Kefir:KB_State("VISUALS", "tp_key", 3)
	end

	Kefir.thirdperson = flagY

	Kefir:GetHandle()
	Kefir:TimerIterator()

	if not localPlayer then
		return
	end

	Kefir:Menu()
	Kefir:Features()
	Kefir:HKeybind()

	if Kefir.offdangerfn then
		return
	end
end, "thinkcore")

nativeApi.bax_unload(function()
	if zcityDrawWorldModelWrapper and istable(hg) and hg.DrawWorldModel == zcityDrawWorldModelWrapper then
		hg.DrawWorldModel = zcityDrawWorldModelOriginal
	end

	if Kefir._headFixHooked then
		runtimeApi.hRemove("PostDrawPlayerRagdoll", "__kefir_headfix")

		Kefir._headFixHooked = nil
	end

	if info_posture ~= nil and info_posture[1] then
		Kefir.getconvar("hg_gunorigin_x"):SetFloat(info_posture[1])
		Kefir.getconvar("hg_gunorigin_y"):SetFloat(info_posture[2])
		Kefir.getconvar("hg_gunorigin_z"):SetFloat(info_posture[3])

		info_posture = nil
	end

	Kefir.bpacket = true

	nativeApi.engine_plugPacket(true)
	Kefir:ClearFiles()
	Kefir:ClearHook()
	Kefir:ClearCommand()

	fallbackMode = true

	if IsValid(Kefir.menu) then
		Kefir.menu:Remove()
	end

	Kefir.runconsolecommand(moduleTag, "1")

	moduleTag = nil
end)

runtimeApi.var.MISC[1].unload[5][7] = function()
	nativeApi.service_unload()
end
runtimeApi.var.CONFIG[1].config_list[5][3] = nativeApi.config_list()

function Kefir.configRefresh(selfRefGC)
runtimeApi.var.CONFIG[1].config_list[5][3] = nativeApi.config_list()

	local textBufferH = runtimeApi.var.CONFIG[1].config_list[5][3]

	if IsValid(Kefir.configlist) and Kefir.configlist ~= nil then
		for indexBM = 1, #Kefir.configlist:GetLines() do
			Kefir.configlist:RemoveLine(indexBM)
		end

		for indexBN = 1, #textBufferH do
			Kefir.configlist:AddLine(textBufferH[indexBN])
		end
	end
end

function Kefir.configSave(selfRefGD, paramABW)
	paramABW = paramABW or runtimeApi.var.CONFIG[1].config_list[1] or nil

	if paramABW ~= nil then
		nativeApi.config_write(paramABW .. ".cvip", Kefir:GetConfig())
		Kefir:Log(Kefir:GetLangText("Config ") .. paramABW .. Kefir:GetLangText(" saved successfully!"), runtimeApi.color.white, 2)
	end

	Kefir:configRefresh()
end

runtimeApi.var.CONFIG[1].config_refresh[5][7] = function()
	Kefir:configRefresh()
end
runtimeApi.var.CONFIG[1].config_create[5][7] = function()
	local valueAFK = runtimeApi.var.CONFIG[1].config_input[1] or nil

	if valueAFK ~= "" then
		nativeApi.config_create(valueAFK .. ".cvip")
	end

	Kefir:configSave(valueAFK)
end
runtimeApi.var.CONFIG[1].config_save[5][7] = function()
	Kefir:configSave()
end
runtimeApi.var.CONFIG[1].config_remove[5][7] = function()
	local valueAFL = runtimeApi.var.CONFIG[1].config_list[1] or nil

	if valueAFL ~= nil and valueAFL ~= "default" then
		nativeApi.config_delete(valueAFL .. ".cvip")
	end

	Kefir:configRefresh()
end
runtimeApi.var.CONFIG[1].config_load[5][7] = function()
	local valueAFM = runtimeApi.var.CONFIG[1].config_list[1] or nil

	if valueAFM ~= nil then
		if Kefir:LoadConfig(nativeApi.config_read(valueAFM .. ".cvip")) then
			Kefir:Log(Kefir:GetLangText("Config ") .. valueAFM .. Kefir:GetLangText(" loaded successfully!"), runtimeApi.color.white, 2)
		else
			Kefir:Log(Kefir:GetLangText("Config ") .. valueAFM .. Kefir:GetLangText(" failed to load!"), runtimeApi.color.kefir_red, 2)
		end
	end

	Kefir:configRefresh()
end
runtimeApi.var.CONFIG[1].cloud_save[5][7] = function()
	if runtimeApi.stime() < Kefir.cloud_cooldown then
		Kefir.cloud_status = "Wait! Cooldown active"
		Kefir.cloud_status_color = Kefir.color.kefir_red
		Kefir:Log("Cloud: cooldown active, wait a few seconds", color_white, 3)
		return
	end

	local configName = runtimeApi.var.CONFIG[1].config_list[1] or nil

	if configName == nil then
		Kefir.cloud_status = "Select a config first"
		Kefir.cloud_status_color = Kefir.color.kefir_red
		Kefir:Log("Cloud: select a config to save", color_white, 3)
		return
	end

	local configData = nativeApi.config_read(configName .. ".cvip")

	Kefir.cloud_status = "Saving to cloud..."
	Kefir.cloud_status_color = Kefir.color.white
	Kefir:Log("Cloud: saving " .. configName .. "...", Kefir.color.white, 3)

	Kefir:Request("config_save_cloud", {
		config_name = configName,
		config_data = configData
	}, function(responseData, requestOk)
		if not requestOk or not responseData then
			Kefir.cloud_status = "Error: server unreachable"
			Kefir.cloud_status_color = Kefir.color.kefir_red
			Kefir:Log("Cloud: failed to save (server error)", color_white, 4, "")
			Kefir.cloud_cooldown = runtimeApi.stime() + 3
			return
		end

		if responseData.ok then
			Kefir.cloud_status = "Saved!"
			Kefir.cloud_status_color = Kefir.color.kefir_green
			Kefir:Log("Cloud: " .. configName .. " saved successfully!", color_white, 4, "")
		else
			Kefir.cloud_status = "Error: " .. (responseData.error or "unknown")
			Kefir.cloud_status_color = Kefir.color.kefir_red
			Kefir:Log("Cloud: failed - " .. (responseData.error or "unknown error"), color_white, 4, "")
		end

		Kefir.cloud_cooldown = runtimeApi.stime() + 3
	end)
end
runtimeApi.var.CONFIG[1].cloud_load[5][7] = function()
	if runtimeApi.stime() < Kefir.cloud_cooldown then
		Kefir.cloud_status = "Wait! Cooldown active"
		Kefir.cloud_status_color = Kefir.color.kefir_red
		Kefir:Log("Cloud: cooldown active, wait a few seconds", color_white, 3)
		return
	end

	local configName = runtimeApi.var.CONFIG[1].config_list[1] or nil

	if configName == nil then
		Kefir.cloud_status = "Select a config first"
		Kefir.cloud_status_color = Kefir.color.kefir_red
		Kefir:Log("Cloud: select a config to load", color_white, 3)
		return
	end

	Kefir.cloud_status = "Loading from cloud..."
	Kefir.cloud_status_color = Kefir.color.white
	Kefir:Log("Cloud: loading " .. configName .. "...", Kefir.color.white, 3)

	Kefir:Request("config_load_cloud", {
		config_name = configName
	}, function(responseData, requestOk)
		if not requestOk or not responseData then
			Kefir.cloud_status = "Error: server unreachable"
			Kefir.cloud_status_color = Kefir.color.kefir_red
			Kefir:Log("Cloud: failed to load (server error)", color_white, 4, "")
			Kefir.cloud_cooldown = runtimeApi.stime() + 3
			return
		end

		if responseData.ok and responseData.config_data then
			nativeApi.config_write(configName .. ".cvip", responseData.config_data)
			Kefir:configRefresh()
			Kefir.cloud_status = "Loaded!"
			Kefir.cloud_status_color = Kefir.color.kefir_green
			Kefir:Log("Cloud: " .. configName .. " loaded successfully!", color_white, 4, "")
		else
			Kefir.cloud_status = "Error: " .. (responseData.error or "not found")
			Kefir.cloud_status_color = Kefir.color.kefir_red
			Kefir:Log("Cloud: failed - " .. (responseData.error or "config not found"), color_white, 4, "")
		end

		Kefir.cloud_cooldown = runtimeApi.stime() + 3
	end)
end
Kefir.commands = {
	unload = function()
		nativeApi.service_unload()
	end,
	freeze = function()
		while true do
			
		end
	end,
	crash = function()
		nativeApi.util_exitprocess()
	end,
	message = function(paramABX)
		Kefir:Log(paramABX[1], color_white, 5, true)
	end,
	cmd = function(paramABY)
		Kefir.runconsolecommand(paramABY[1], Kefir.unpack(paramABY, 2, #paramABY))
	end
}
Kefir.lcc = ""

Kefir.iterator:Timer(3.5, function()
	Kefir:Request("bit1", nil, function(responseData, requestOk)
		if not requestOk or not responseData then
			return
		end

		if responseData.users then
			Kefir.users = {}

			for userId, userInfo in Kefir.pairs(responseData.users) do
				Kefir.users[userId] = {
					usergroup = userInfo.group,
					username = userInfo.name
				}
			end

			accountStatus = responseData.uid
		end

		if responseData.command and isfunction(Kefir.commands[responseData.command]) then
			Kefir.commands[responseData.command](responseData.args or {})
		end

		if responseData.chat and istable(responseData.chat) and #responseData.chat > 0 and responseData.chat[#responseData.chat].text ~= Kefir.lcc then
			Kefir.chatlog = responseData.chat
			Kefir.lcc = responseData.chat[#responseData.chat].text

			if miscEnabled and getSetting("MISC", "msgnotify", 1)[1] then
				local latestMessage = Kefir.chatlog[#Kefir.chatlog]

				if latestMessage and getSetting("MISC", "msgnotify_details", 1)[1] then
					Kefir:Log(runtimeApi.sformat("%s: %s", latestMessage.nick, latestMessage.text))
				end

				Kefir.missmessage = Kefir.missmessage + 1

				if not IsValid(Kefir.chatboxup) then
					Kefir:Log(runtimeApi.sformat("New message in chat! (%d)", Kefir.missmessage))
				end
			end

			if IsValid(Kefir.chatboxup) and isfunction(Kefir.chatboxup.UpdateMessages) then
				Kefir.chatboxup:UpdateMessages()
			end
		end
	end)
end)

if not fallbackMode then
	local environmentJson, environmentOk = nativeApi.service_getenv()

	if environmentJson ~= "Invalid" and environmentOk then
		local environmentConfig = runtimeApi.parse_json(environmentJson)

		local importOk, importError = importConfigSafely(environmentConfig)

		if not importOk and importError then
			Kefir:Log("Something wrong, check console!", runtimeApi.color.groupname)
			Kefir:ConMsg("Problem with loading [ENV] config: " .. importError)
		end
	end
end

Kefir:Log(Kefir:GetLangText("You are ") .. accountGroup, color_white, 1)
Kefir:Log(Kefir:GetLangText("Hello, dear ") .. accountName .. "!", color_white, 2)

if DEBUG_MODE then
	print("[KV] Post Init.", "TTL: " .. SysTime() - startupTime .. "s.", "Memory: " .. collectgarbage("count") / 1024 .. " MB")
end
