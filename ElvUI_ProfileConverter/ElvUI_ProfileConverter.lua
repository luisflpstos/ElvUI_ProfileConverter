local _, PC = ...
local E = unpack(ElvUI)

local LibBase64   = LibStub("LibBase64-1.0-ElvUI")
local LibCompress = LibStub("LibCompress")
local LibDeflate  = E.Libs.Deflate
local ElvUIPlugin = E.Libs.EP

local _G = _G

PC = LibStub("AceAddon-3.0"):NewAddon("ElvUI Profile Converter")

function PC:Convert(dataString)
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
   elseif PC.resultType == "old_to_new" then
      return "|cff00ff00".._G.SUCCESS.."!|r Converted to |cff00ff00NEW|r string format."
   elseif PC.resultType == "error" then
      return "|cffff0000Invalid profile string!|r"
   else
      return "Paste a profile (old or new format) into the editbox below:"
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
