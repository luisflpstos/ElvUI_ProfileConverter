# ElvUI Profile Converter

An ElvUI plugin addon for World of Warcraft 3.3.5a (Wrath of the Lich King) that converts ElvUI profile export strings between formats. This allows profiles exported from other ElvUI versions to be imported into ElvUI 3.3.5, with automatic format detection.

## Note: This is a Fork

This is a fork of the [upstream ElvUI_ProfileConverter](https://github.com/ElvUI-WotLK/ElvUI_ProfileConverter) with added support for the !E2! retail export format. The fork's changes were proposed to upstream in [Pull Request #1](https://github.com/ElvUI-WotLK/ElvUI_ProfileConverter/pull/1).

## Features

- **Automatic format detection**: Identifies the input profile format and converts accordingly without manual selection.
- **Retail !E2! support**: Decodes the current retail ElvUI export format (introduced in this fork) using a pure Lua 5.1 CBOR decoder that works on the 3.3.5 client.
- **Bidirectional conversion**: Converts between OLD and !E1! formats in both directions.
- **One-way !E2! conversion**: Converts retail !E2! exports to the OLD format (3.3.5 compatible); converting from 3.3.5 to !E2! is not supported due to missing retail APIs.
- **Error handling**: Displays clear status messages in the UI instead of throwing Lua errors on invalid input.
- **Embedded libraries**: Bundles LibDeflate, LibBase64, and LibCompress, reducing external dependencies.
- **Default profile naming**: !E2! strings without a suffix are automatically imported as a profile named "Converted" (customizable after import).

## Supported Formats

| Format | Description | Import to 3.3.5 |
|--------|-------------|-----------------|
| OLD | Base64(LibCompress(AceSerializer(data) + "::type::key")). Plain Base64 string, no prefix. Native 3.3.5 format. | Yes, directly |
| !E1! | Prefix `!E1!` + LibDeflate EncodeForPrint(Deflate(AceSerializer payload)). Older "new" ElvUI format. | Yes, via conversion |
| !E2! | Prefix `!E2!` + Base64(Deflate(CBOR(data) + "::type::key")). Current retail ElvUI export format. | Yes, via conversion (new) |

**Conversions supported**:
- OLD ↔ !E1! (bidirectional)
- !E2! → OLD (one-way)

## Requirements

- World of Warcraft client: **3.3.5a (Wrath of the Lich King)**
- **ElvUI for 3.3.5** installed and enabled
- AddOns enabled in character select

## Installation

1. Download the addon:
   - Visit https://github.com/luisflpstos/ElvUI_ProfileConverter
   - Click Code → Download ZIP (or use `git clone https://github.com/luisflpstos/ElvUI_ProfileConverter.git`)

2. Extract and place in AddOns folder:
   - The ZIP extracts to a folder named `ElvUI_ProfileConverter-master/`
   - Inside it is the actual addon folder `ElvUI_ProfileConverter/` (containing `ElvUI_ProfileConverter.toc`)
   - Copy this inner `ElvUI_ProfileConverter/` folder to `<WoW folder>/Interface/AddOns/`
   - The final path must be: `Interface/AddOns/ElvUI_ProfileConverter/ElvUI_ProfileConverter.toc`

3. Enable the addon:
   - Start World of Warcraft
   - On the character-select screen, click AddOns
   - Ensure "ElvUI_ProfileConverter" is checked
   - If the game was running while you copied the folder, restart it completely: `/reload` does not detect newly installed addons

## Usage

1. Open the ElvUI configuration panel:
   ```
   /ec
   ```

2. Navigate to **Profile Converter** (appears as a section in the config tree)

3. Paste your profile string into the large edit box below the status line

4. Click the edit box's **Accept** button to run the conversion

5. Check the status line:
   - Green "Success!" message confirms conversion
   - Red "Invalid profile string!" message indicates an error (see error details below)

6. Select and copy the converted string:
   - `Ctrl+A` to select all
   - `Ctrl+C` to copy
   - The converted string appears in the same edit box

7. Import into ElvUI:
   - In ElvUI config, go to **Profiles → Import Profile**
   - Paste the converted string
   - Click Import

8. Reset for another profile:
   - Click the **Reset** button below the edit box to clear it and convert another

## Status and Error Messages

### Success Messages

- `Success! Converted !E2! (retail) to OLD string format.` — A retail !E2! export was successfully converted
- `Success! Converted to OLD string format.` — An !E1! export was successfully converted
- `Success! Converted to NEW string format.` — An OLD export was successfully converted to !E1!

### Error Messages

- `Invalid profile string!` — Displayed when an error occurs (see details below for specific error)
- `Error: Could not decompress !E2! profile.` — The !E2! string could not be decompressed (truncated or corrupted)
- `Error: Could not deserialize !E2! profile.` — The decompressed !E2! data is not valid CBOR (corrupted)
- `Error: Could not decompress NEW-format profile.` — The !E1! string could not be decompressed
- `Error: Could not decompress OLD-format profile.` — The OLD format string could not be decompressed
- `Error: Input doesn't look like a valid profile string.` — The input does not match any known format
- (Base64 decode error) — Invalid Base64 characters in the input string

## Limitations

- **Version incompatibility**: A profile from retail ElvUI contains settings that do not exist in ElvUI 3.3.5. These unknown settings are safely ignored by ElvUI, so the result will not be pixel-perfect compared to the original.
- **Default naming for !E2! without suffix**: If a !E2! export string has no `::type::key` suffix, it is imported as a profile named "Converted". You can rename it in ElvUI after import.
- **String completeness**: The entire profile string must be copied; truncated or partial strings will fail to decompress.
- **No !E2! export**: This addon can import !E2! retail formats, but it cannot export to !E2! (3.3.5 lacks the required retail APIs like `C_EncodingUtil`).

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Profile Converter section does not appear in config | Verify the addon folder is at `Interface/AddOns/ElvUI_ProfileConverter/` with `ElvUI_ProfileConverter.toc` inside. Ensure ElvUI is installed and enabled. Try `/reload` to refresh. Enable "Load out of date AddOns" if the addon shows as out of date. |
| "Input doesn't look like a valid profile string." | Copy the entire string again, including the prefix (!E1!, !E2!, or Base64 leading characters). Ensure no characters are missing or truncated. Paste into a text editor first to verify. |
| "Could not decompress" errors | The string is corrupted or truncated. Verify the full string was copied from the export. Check for special characters or encoding issues if pasted from an external source. |
| Converted profile has missing settings | This is expected if converting from retail. Retail ElvUI has options for features that don't exist in ElvUI 3.3.5; those values are ignored on import. |

## How It Works

### Format Specifications

**OLD Format** (3.3.5 native):
```
Base64(
  LibCompress.Compress(
    AceSerializer.Serialize(data) .. "::type::key"
  )
)
```
Produces a plain Base64 string with no prefix.

**!E1! Format** (older "new" format):
```
"!E1!" .. LibDeflate.EncodeForPrint(
  LibDeflate.CompressDeflate(
    AceSerializer.Serialize(data) .. "::type::key"
  )
)
```
Uses LibDeflate compression and EncodeForPrint encoding.

**!E2! Format** (current retail, added in this fork):
```
"!E2!" .. C_EncodingUtil.EncodeBase64(
  C_EncodingUtil.CompressString(            -- Deflate
    C_EncodingUtil.SerializeCBOR(data) .. "::type::key"
  )
)
```
Uses CBOR serialization instead of AceSerializer, and standard Base64 instead of EncodeForPrint. The `C_EncodingUtil` API only exists on retail clients, so this addon reimplements the decoding side in pure Lua (LibBase64 + LibDeflate + its own CBOR decoder).

### Conversion Pipelines

Each input format has its own pipeline. Only `!E2!` requires decoding the profile data itself; `!E1!` and OLD share the same AceSerializer payload, so converting between them only swaps the compression and encoding layers.

1. **!E2! → OLD**:
   - Strip `!E2!` prefix
   - Base64 decode
   - Decompress (raw Deflate with zlib fallback)
   - Parse `::type::key` suffix (default to `profile::Converted` if absent)
   - CBOR decode (pure Lua decoder)
   - AceSerializer re-encode
   - LibCompress re-compress
   - Base64 re-encode
   - Result: plain Base64 string

2. **!E1! → OLD**:
   - Strip `!E1!` prefix
   - LibDeflate DecodeForPrint
   - LibDeflate decompress
   - LibCompress re-compress
   - Base64 re-encode
   - Result: plain Base64 string

3. **OLD → !E1!**:
   - Base64 decode
   - LibCompress decompress
   - LibDeflate compress
   - LibDeflate EncodeForPrint
   - Prepend `!E1!`
   - Result: !E1! string

### CBOR Decoder

The addon includes a pure Lua 5.1 CBOR (Concise Binary Object Representation, RFC 8949) decoder that handles:
- Unsigned and negative integers
- Text strings (UTF-8) and byte strings
- Arrays (fixed and indefinite length)
- Maps (fixed and indefinite length)
- Half-precision, single-precision, and double-precision floats
- CBOR tags (skipped; the wrapped value is decoded normally)
- Indefinite-length sequences (terminated by the CBOR break marker 0xFF)

This decoder replaces retail's `C_EncodingUtil.DeserializeCBOR`, which does not exist on the 3.3.5 client.

## Testing

The !E2! support has been validated as follows:

- **Real retail export**: Converted an actual retail !E2! profile export successfully
- **Data integrity**: Re-imported the converted output using the same decode pipeline as ElvUI 3.3.5 (Base64 → LibCompress → split on `^^::` → AceSerializer). All 836 profile values matched an independent Python CBOR decode.
- **Error handling**: Malformed, truncated, and garbage inputs all produce appropriate error messages without throwing Lua exceptions
- **Round-trip**: OLD → !E1! → OLD returns identical profile data
- **Lua runtime**: Tested under LuaJIT with Lua 5.1 semantics using WoW API stubs

**Note**: !E2! support has not yet been verified in-game on a live 3.3.5 client. Test results so far are confined to a Lua 5.1 sandbox with API stubs.

## Project Structure

```
ElvUI_ProfileConverter/
├── ElvUI_ProfileConverter.toc      # AddOn metadata
├── ElvUI_ProfileConverter.lua      # Main addon code: conversion logic, CBOR decoder, options UI
├── Embeds.xml                      # Loads the bundled libraries
├── LICENSE.txt                     # Unlicense (public domain)
└── Libs/
    ├── LibBase64-1.0/
    ├── LibCompress-1.0/
    └── LibDeflate/
```

## License

The addon code is released into the **public domain** under the Unlicense (see `LICENSE.txt`).

Bundled libraries retain their original licenses:
- **LibBase64-1.0**: ckknight, MIT License
- **LibCompress-1.0**: jjsheets and Galmok, GNU General Public License v2
- **LibDeflate**: Haoqian He, zlib License

## Credits

- **AcidWeb**: Original ElvUI_ProfileConverter addon
- **Crum**: 3.3.5 modifications
- **ElvUI team**: ElvUI framework and upstream development
- **Library authors**: ckknight, jjsheets, Galmok, Haoqian He
- **!E2! support**: Added in this fork
