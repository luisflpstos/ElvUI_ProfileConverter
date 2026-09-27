local _, PC = ...
local E = unpack(ElvUI)

local LibBase64     = LibStub("LibBase64-1.0-ElvUI")
local LibCompress   = LibStub("LibCompress")
local LibDeflate    = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")
local ElvUIPlugin   = E.Libs.EP

local _G = _G
local strbyte, strsub, strmatch = strbyte, strsub, strmatch
local floor, ldexp, huge = math.floor, math.ldexp, math.huge

PC = LibStub("AceAddon-3.0"):NewAddon("ElvUI Profile Converter")

-- Profile key used when a !E2! string carries no "::type::key" suffix
local DEFAULT_PROFILE_KEY = "Converted"

-- Same list the retail Distributor accepts
local profileTypes = {
   profile = true,
   private = true,
   global = true,
   filters = true,
}

-- Minimal CBOR (RFC 8949) decoder in pure Lua 5.1, replacing retail's
-- C_EncodingUtil.DeserializeCBOR which doesn't exist on 3.3.5.
local function DecodeCBOR(data)
   local pos = 1
   local len = #data
   local readItem

   local function readUInt(numBytes)
      if pos + numBytes - 1 > len then error("truncated CBOR data") end
      local n = 0
      for i = pos, pos + numBytes - 1 do
         n = n * 256 + strbyte(data, i)
      end
      pos = pos + numBytes
      return n
   end

   local function readArgument(info)
      if info < 24 then return info end
      if info == 24 then return readUInt(1) end
      if info == 25 then return readUInt(2) end
      if info == 26 then return readUInt(4) end
      if info == 27 then return readUInt(8) end
      if info == 31 then return nil end -- indefinite length
      error("invalid CBOR length encoding")
   end

   local function isBreak()
      if pos > len then error("truncated CBOR data") end
      if strbyte(data, pos) == 0xFF then
         pos = pos + 1
         return true
      end
   end

   local function readHalf()
      local n = readUInt(2)
      local sign = n >= 0x8000 and -1 or 1
      local exp = floor(n / 0x400) % 0x20
      local mant = n % 0x400
      if exp == 0 then return sign * ldexp(mant, -24) end
      if exp == 0x1F then return mant == 0 and sign * huge or 0/0 end
      return sign * ldexp(mant + 0x400, exp - 25)
   end

   local function readSingle()
      local n = readUInt(4)
      local sign = n >= 0x80000000 and -1 or 1
      local exp = floor(n / 0x800000) % 0x100
      local mant = n % 0x800000
      if exp == 0 then return sign * ldexp(mant, -149) end
      if exp == 0xFF then return mant == 0 and sign * huge or 0/0 end
      return sign * ldexp(mant + 0x800000, exp - 150)
   end

   local function readDouble()
      -- split in two words: a 64-bit integer doesn't fit exactly in a Lua number
      local hi, lo = readUInt(4), readUInt(4)
      local sign = hi >= 0x80000000 and -1 or 1
      local exp = floor(hi / 0x100000) % 0x800
      local mant = (hi % 0x100000) * 0x100000000 + lo
      if exp == 0 then return sign * ldexp(mant, -1074) end
      if exp == 0x7FF then return mant == 0 and sign * huge or 0/0 end
      return sign * ldexp(mant + 0x10000000000000, exp - 1075)
   end

   local function readString(info)
      local size = readArgument(info)
      if size == nil then
         local chunks = {}
         while not isBreak() do
            chunks[#chunks + 1] = readItem()
         end
         return table.concat(chunks)
      end
      if pos + size - 1 > len then error("truncated CBOR data") end
      local s = strsub(data, pos, pos + size - 1)
      pos = pos + size
      return s
   end

   function readItem()
      if pos > len then error("truncated CBOR data") end
      local byte = strbyte(data, pos)
      pos = pos + 1
      local major, info = floor(byte / 32), byte % 32

      if major == 0 then
         return readArgument(info)
      elseif major == 1 then
         return -1 - readArgument(info)
      elseif major == 2 or major == 3 then
         return readString(info)
      elseif major == 4 then
         local t, count = {}, readArgument(info)
         local i = 0
         while (count and i < count) or (not count and not isBreak()) do
            i = i + 1
            t[i] = readItem()
         end
         return t
      elseif major == 5 then
         local t, count = {}, readArgument(info)
         local i = 0
         while (count and i < count) or (not count and not isBreak()) do
            i = i + 1
            local key = readItem()
            local value = readItem()
            if key ~= nil then t[key] = value end
         end
         return t
      elseif major == 6 then
         readArgument(info) -- tags carry no meaning for ElvUI data
         return readItem()
      else -- major 7: simple values and floats
         if info == 20 then return false end
         if info == 21 then return true end
         if info == 22 or info == 23 then return nil end
         if info == 25 then return readHalf() end
         if info == 26 then return readSingle() end
         if info == 27 then return readDouble() end
         error("unsupported CBOR simple value")
      end
   end

   local result = readItem()
   if pos <= len then error("unexpected trailing CBOR data") end
   return result
end

-- Port of retail D:GetExportInfo: splits "<data>::<type>::<key>" or "<data>::<type>"
local function GetExportInfo(str)
   local profileData, profileType, profileKey = strmatch(str, "^(.+)::([^:]-)::(.-)$")
   if profileTypes[profileType] then
      return profileData, profileType, profileKey
   end

   local exportData, exportType = strmatch(str, "^(.+)::([^:]-)$")
   if profileTypes[exportType] then
      return exportData, exportType
   end
end

-- Decodes a retail !E2! string into the OLD format ElvUI 3.3.5 imports:
-- Base64(LibCompress(AceSerializer(data) .. "::type::key"))
local function ConvertE2ToOld(dataString)
   local data = gsub(dataString, "^!E2!", "")
   data = gsub(data, "%s", "")

   local decodedData = LibBase64:Decode(data)
   local decompressed = LibDeflate:DecompressDeflate(decodedData) or LibDeflate:DecompressZlib(decodedData)
   if not decompressed then
      return nil, "Could not decompress !E2! profile."
   end

   local cborData, profileType, profileKey = GetExportInfo(decompressed)
   if not cborData then
      -- some exports carry no suffix; assume a regular profile
      cborData, profileType = decompressed, "profile"
   end
   if profileType == "profile" and (not profileKey or profileKey == "") then
      profileKey = DEFAULT_PROFILE_KEY
   end

   local profileData = DecodeCBOR(cborData)
   if type(profileData) ~= "table" then
      return nil, "Could not deserialize !E2! profile."
   end

   local serialized = AceSerializer:Serialize(profileData)
   local exportString
   if profileType == "profile" then
      exportString = format("%s::%s::%s", serialized, profileType, profileKey)
   else
      exportString = format("%s::%s", serialized, profileType)
   end

   return LibBase64:Encode(LibCompress:Compress(exportString))
end

function PC:Convert(dataString)
   -- Detect retail format (starts with !E2!): CBOR, not usable on 3.3.5
   if strfind(dataString, "^%s*!E2!") then
      local ok, result, err = pcall(ConvertE2ToOld, strmatch(dataString, "^%s*(.-)%s*$"))

      if not ok or not result then
         PC.resultType = "error"
         return "Error: " .. tostring(ok and err or result)
      end

      PC.resultType = "e2_to_old"
      return result -- return OLD format
   end

   -- Detect NEW format (starts with !E1!)
   if strfind(dataString, "^!E1!") then
      local data = gsub(dataString, "^!E1!", "")
      local decodedData = LibDeflate:DecodeForPrint(data)
      local decompressed = LibDeflate:DecompressDeflate(decodedData)

      if not decompressed then
         PC.resultType = "error"
         return "Error: Could not decompress NEW-format profile."
      end

      local compressedData = LibCompress:Compress(decompressed)
      local profileExport = LibBase64:Encode(compressedData)

      PC.resultType = "new_to_old"
      return profileExport -- return OLD format
   end

   -- Detect OLD format (Base64)
   if LibBase64:IsBase64(dataString) then
      local decodedData = LibBase64:Decode(dataString)
      local decompressedData, err = LibCompress:Decompress(decodedData)

      if not decompressedData then
         PC.resultType = "error"
         return format("Error: Could not decompress OLD-format profile.")
      end

      local compressedData = LibDeflate:CompressDeflate(decompressedData, {level = 5})
      local profileExport = LibDeflate:EncodeForPrint(compressedData)

      PC.resultType = "old_to_new"
      return "!E1!" .. profileExport -- return NEW format
   end

   PC.resultType = "error"
   return "Error: Input doesn't look like a valid profile string."
end

function PC:GetStatusMessage()
   if PC.resultType == "new_to_old" then
      return "|cff00ff00".._G.SUCCESS.."!|r Converted to |cffff0000OLD|r string format."
   elseif PC.resultType == "e2_to_old" then
      return "|cff00ff00".._G.SUCCESS.."!|r Converted |cff1784d1!E2!|r (retail) to |cffff0000OLD|r string format."
   elseif PC.resultType == "old_to_new" then
      return "|cff00ff00".._G.SUCCESS.."!|r Converted to |cff00ff00NEW|r string format."
   elseif PC.resultType == "error" then
      return "|cffff0000Invalid profile string!|r"
   else
      return "Paste a profile (old, !E1! or !E2! format) into the editbox below:"
   end
end

function PC:OnInitialize()
   PC.status = ""
   PC.resultType = "none"

   local optionsTable = {
      type = "group",
      name = "Profile Converter",
      order = 66,
      args = {
         header = {
            order = 1,
            type = "description",
            name = function() return PC:GetStatusMessage() end,
         },
         convert = {
            order = 2,
            name = "",
            type = "input",
            width = "full",
            multiline = 30,
            set = function(_, value) PC.status = PC:Convert(value) end,
            get = function(_) return PC.status end,
         },
         reset = {
            order = 3,
            type = "execute",
            name = _G.RESET,
            hidden = function() return PC.resultType == "none" end,
            func = function()
               PC.status = ""
               PC.resultType = "none"
            end,
         },
      },
   }

   ElvUIPlugin:RegisterPlugin("ElvUI_ProfileConverter", function()
      E.Options.args.profileconverter = optionsTable
   end)
end
