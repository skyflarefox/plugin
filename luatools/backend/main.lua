local millennium = require("millennium")

local function esc(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
  return value
end

local function json_ok(extra)
  extra = extra or ""
  if extra ~= "" then extra = "," .. extra end
  return '{"success":true' .. extra .. "}"
end

local function json_fail(message)
  return '{"success":false,"error":"' .. esc(message or "Unknown error") .. '"}'
end

local function json_string(value)
  return '"' .. esc(value or "") .. '"'
end

local startup_message = ""

local function steam_path()
  local ok, value = pcall(millennium.steam_path)
  if ok and value then return tostring(value) end
  return ""
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function path_exists(path)
  path = tostring(path or "")
  if path == "" then return false end
  if exists(path) then return true end
  local ok, _, code = os.rename(path, path)
  return ok == true or code == 13
end

local function plugin_root()
  local source = debug.getinfo(1, "S").source or ""
  source = source:gsub("^@", ""):gsub("\\", "/")
  return source:gsub("/backend/main%.lua$", "")
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local data = f:read("*a") or ""
  f:close()
  return data
end

local function write_file(path, data)
  path = tostring(path or "")
  if path == "" then return false end
  local tmp = path .. ".tmp." .. tostring(os.time()) .. "." .. tostring(math.random(1000, 9999))
  local f = io.open(tmp, "wb")
  if not f then return false end
  local ok, err = pcall(function() f:write(data or "") end)
  f:close()
  if not ok then
    os.remove(tmp)
    if log_line then log_line("write_file failed for " .. path .. ": " .. tostring(err)) end
    return false
  end
  os.remove(path)
  if os.rename(tmp, path) then return true end
  os.remove(tmp)
  return false
end

local function copy_file(src, dst)
  local data = read_file(src)
  if data == "" then return false end
  if read_file(dst) == data then return true end
  return write_file(dst, data)
end

local base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_encode(data)
  data = tostring(data or "")
  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local n = a * 65536 + b * 256 + c
    local pad = (i + 1 > len and 2) or (i + 2 > len and 1) or 0
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = base64_chars:sub(c1 + 1, c1 + 1)
    out[#out + 1] = base64_chars:sub(c2 + 1, c2 + 1)
    out[#out + 1] = pad >= 2 and "=" or base64_chars:sub(c3 + 1, c3 + 1)
    out[#out + 1] = pad >= 1 and "=" or base64_chars:sub(c4 + 1, c4 + 1)
    i = i + 3
  end
  return table.concat(out)
end

local log_line

local function appid_from_args(args)
  if type(args) == "table" then
    if args.appid or args[1] then return tonumber(args.appid or args[1]) end
    for k, v in pairs(args) do
      local nk = tostring(k):lower()
      if nk == "appid" or nk == "app_id" or nk == "id" then return tonumber(v) end
      if tonumber(v) and tostring(v):match("^%d+$") then return tonumber(v) end
    end
  end
  if type(args) == "string" then
    local from_json = args:match('"appid"%s*:%s*"?([0-9]+)"?') or
      args:match('"app_id"%s*:%s*"?([0-9]+)"?') or
      args:match('"id"%s*:%s*"?([0-9]+)"?')
    if from_json then return tonumber(from_json) end
  end
  return tonumber(args)
end

local function dump_args(label, args)
  if not log_line then return end
  if type(args) ~= "table" then
    log_line(label .. " arg type=" .. type(args) .. " value=" .. tostring(args))
    return
  end
  local parts = {}
  for k, v in pairs(args) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  log_line(label .. " table args: " .. table.concat(parts, ", "))
end

local function url_from_args(args)
  if type(args) == "table" then return tostring(args.url or args[1] or "") end
  return tostring(args or "")
end

local function url_encode(value)
  return tostring(value or ""):gsub("([^%w%-%._~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function ps_quote(value)
  return '"' .. tostring(value or ""):gsub('"', '\\"') .. '"'
end

local function ps_single_quote(value)
  return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function cmd_quote(value)
  return '"' .. tostring(value or ""):gsub('"', '""') .. '"'
end

local function vdf_value(text, key)
  local safe_key = tostring(key or ""):gsub("([^%w])", "%%%1")
  local value = tostring(text or ""):match('"' .. safe_key .. '"%s+"([^"]*)"')
  if not value then return "" end
  return value:gsub("\\\\", "\\")
end

log_line = function(message)
  local root = plugin_root()
  local f = io.open(root .. "/backend/lua_runtime.log", "ab")
  if f then
    f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(message) .. "\n")
    f:close()
  end
end

local require_json_cached = nil
local require_json_warned = false

local function require_json()
  if require_json_cached ~= nil then return require_json_cached end
  if not require_json_warned then
    log_line("cjson native loader disabled; using text parsers")
    require_json_warned = true
  end
  require_json_cached = false
  return nil
end

local function decode_json(text)
  local json = require_json()
  if json then
    local ok, data = pcall(json.decode, text or "")
    if ok and type(data) == "table" then return data end
  end
  return nil
end

local function get_morrenus_key()
  local settings = read_file(plugin_root() .. "/backend/data/settings.json")
  local key = settings:match('"morrenusApiKey"%s*:%s*"([^"]*)"') or ""
  return key:gsub("%s+", "")
end

local function api_config_path()
  return plugin_root() .. "/backend/api.json"
end

local function default_api_entries()
  return {
    {
      name = "Morrenus",
      url = "https://hubcapmanifest.com/api/v1/manifest/<appid>?api_key=<moapikey>",
      success_code = 200,
      unavailable_code = 404,
      enabled = true,
    },
    {
      name = "SkyApi",
      url = "https://github.com/skyflarefox/Skyapi/raw/refs/heads/main/<appid>.zip",
      success_code = 200,
      unavailable_code = 404,
      enabled = true,
    },
    {
      name = "Ryuu",
      url = "http://167.235.229.108/<appid>",
      success_code = 200,
      unavailable_code = 404,
      enabled = true,
    },
    {
      name = "TwentyTwo Cloud",
      url = "https://api.twentytwocloud.com/download?appid=<appid>",
      success_code = 200,
      unavailable_code = 404,
      enabled = true,
    },
    {
      name = "Sushi",
      url = "https://github.com/sushi-dev55-alt/sushitools-games-repo-alt/raw/refs/heads/main/<appid>.zip",
      success_code = 200,
      unavailable_code = 404,
      enabled = true,
    },
  }
end

local function json_unescape(value)
  value = tostring(value or "")
  value = value:gsub("\\/", "/")
  value = value:gsub('\\"', '"')
  value = value:gsub("\\\\", "\\")
  value = value:gsub("\\n", "\n"):gsub("\\r", "\r"):gsub("\\t", "\t")
  return value
end

local function parse_api_entries(text)
  text = tostring(text or "")
  local data = decode_json(text)
  local apis = {}
  if data and type(data.api_list) == "table" then
    for _, api in ipairs(data.api_list) do
      if type(api) == "table" then
        apis[#apis + 1] = {
          name = tostring(api.name or "Unknown"),
          url = tostring(api.url or ""),
          success_code = tonumber(api.success_code or 200) or 200,
          unavailable_code = tonumber(api.unavailable_code or 404) or 404,
          enabled = api.enabled ~= false,
        }
      end
    end
  end
  if #apis == 0 then
    for object in text:gmatch("{(.-)}") do
      local name = object:match('"name"%s*:%s*"([^"]+)"')
      local url = object:match('"url"%s*:%s*"([^"]+)"')
      local code = tonumber(object:match('"success_code"%s*:%s*(%d+)') or "200") or 200
      local unavailable = tonumber(object:match('"unavailable_code"%s*:%s*(%d+)') or "404") or 404
      local disabled = object:match('"enabled"%s*:%s*false')
      if name and url then
        apis[#apis + 1] = {
          name = json_unescape(name),
          url = json_unescape(url),
          success_code = code,
          unavailable_code = unavailable,
          enabled = not disabled,
        }
      end
    end
  end
  return apis
end

local function load_api_entries()
  local entries = parse_api_entries(read_file(api_config_path()))
  if #entries == 0 then return default_api_entries() end
  return entries
end

local function load_apis()
  local apis = {}
  for _, api in ipairs(load_api_entries()) do
    if api.enabled ~= false then
      apis[#apis + 1] = {
        name = api.name,
        url = api.url,
        success_code = api.success_code,
        unavailable_code = api.unavailable_code,
        enabled = true,
      }
    end
  end
  return apis
end

local function api_entries_json(entries)
  local items = {}
  for _, api in ipairs(entries or {}) do
    items[#items + 1] =
      '{"name":' .. json_string(api.name or "") ..
      ',"url":' .. json_string(api.url or "") ..
      ',"success_code":' .. tostring(tonumber(api.success_code or 200) or 200) ..
      ',"unavailable_code":' .. tostring(tonumber(api.unavailable_code or 404) or 404) ..
      ',"enabled":' .. (api.enabled ~= false and "true" or "false") .. "}"
  end
  return "[" .. table.concat(items, ",") .. "]"
end

local function write_api_entries(entries)
  local lines = { '{"api_list": [' }
  for i, api in ipairs(entries or {}) do
    lines[#lines + 1] = "  {"
    lines[#lines + 1] = '    "name": ' .. json_string(api.name or "") .. ","
    lines[#lines + 1] = '    "url": ' .. json_string(api.url or "") .. ","
    lines[#lines + 1] = '    "success_code": ' .. tostring(tonumber(api.success_code or 200) or 200) .. ","
    lines[#lines + 1] = '    "unavailable_code": ' .. tostring(tonumber(api.unavailable_code or 404) or 404) .. ","
    lines[#lines + 1] = '    "enabled": ' .. (api.enabled ~= false and "true" or "false")
    lines[#lines + 1] = "  }" .. (i < #entries and "," or "")
  end
  lines[#lines + 1] = "]}"
  return write_file(api_config_path(), table.concat(lines, "\n"))
end

local function api_url_for_app(api, appid, morrenus_key)
  local url = tostring(api.url or "")
  if url:find("<moapikey>", 1, true) then
    if morrenus_key == "" then return nil end
    url = url:gsub("<moapikey>", url_encode(morrenus_key))
  end
  return url:gsub("<appid>", tostring(appid))
end

local function api_should_list_for_download(api, morrenus_key)
  local url = tostring(api.url or "")
  return not url:find("<moapikey>", 1, true) or tostring(morrenus_key or "") ~= ""
end

local function powershell_http_get(url, timeout)
  url = tostring(url or "")
  if url == "" then return nil, "Missing URL" end
  timeout = tonumber(timeout or 10) or 10
  local script = table.concat({
    "$ProgressPreference='SilentlyContinue'",
    "$ErrorActionPreference='Stop'",
    "$headers=@{'User-Agent'='discord(dot)gg/luatools'}",
    "try {",
    "$r=Invoke-WebRequest -Uri " .. ps_single_quote(url) .. " -UseBasicParsing -MaximumRedirection 10 -TimeoutSec " .. tostring(timeout) .. " -Headers $headers",
    "Write-Output ('__LT_STATUS__' + [int]$r.StatusCode)",
    "Write-Output '__LT_BODY__'",
    "Write-Output $r.Content",
    "} catch {",
    "$code=0",
    "if ($_.Exception.Response) { try { $code=[int]$_.Exception.Response.StatusCode } catch {} }",
    "Write-Output ('__LT_STATUS__' + $code)",
    "Write-Output '__LT_ERROR__'",
    "Write-Output $_.Exception.Message",
    "if ($_.ErrorDetails -and $_.ErrorDetails.Message) { Write-Output '__LT_BODY__'; Write-Output $_.ErrorDetails.Message }",
    "}"
  }, "; ")
  local cmd = 'powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command ' .. ps_quote(script)
  local pipe = io.popen(cmd, "r")
  if not pipe then return nil, "Failed to start HTTP request" end
  local output = pipe:read("*a") or ""
  pipe:close()
  local status = tonumber(output:match("__LT_STATUS__(%d+)") or "0") or 0
  local body = output:match("__LT_BODY__%s*(.*)") or ""
  body = body:gsub("^%s+", ""):gsub("%s+$", "")
  local err = output:match("__LT_ERROR__%s*([^\r\n]*)") or ""
  return { status = status, body = body }, err ~= "" and err or nil
end

local add_state = {}
local fix_state = {}
local unfix_state = {}
local morrenus_stats_cache = {}
local fixes_index = nil
local FIXES_INDEX_URL = "https://index.luatools.work/fixes-index.json"

local win_ffi_loaded = false
local win_ffi_available = nil
local win_ffi = nil
local win_shell32 = nil
local win_kernel32 = nil
local use_native_win32 = false

local function load_win_ffi()
  if not use_native_win32 then
    win_ffi_loaded = true
    win_ffi_available = false
    return false
  end
  if win_ffi_loaded then return win_ffi_available end
  win_ffi_loaded = true

  local ok, ffi = pcall(require, "ffi")
  if not ok then
    log_line("ffi unavailable: " .. tostring(ffi))
    win_ffi_available = false
    return false
  end

  local cdef_ok, cdef_err = pcall(function()
    ffi.cdef[[
      void *ShellExecuteA(void *hwnd, const char *operation, const char *file, const char *parameters, const char *directory, int show_cmd);
      int CreateDirectoryA(const char *path, void *security_attributes);
    ]]
  end)
  if not cdef_ok then
    log_line("ffi cdef failed: " .. tostring(cdef_err))
    win_ffi_available = false
    return false
  end

  local shell_ok, shell32 = pcall(ffi.load, "shell32")
  local kernel_ok, kernel32 = pcall(ffi.load, "kernel32")
  if not shell_ok or not kernel_ok then
    log_line("ffi dll load failed: shell32=" .. tostring(shell32) .. " kernel32=" .. tostring(kernel32))
    win_ffi_available = false
    return false
  end

  win_ffi = ffi
  win_shell32 = shell32
  win_kernel32 = kernel32
  win_ffi_available = true
  return true
end

local function native_create_dir(path)
  path = tostring(path or "")
  if path == "" or path_exists(path) then return true end
  if not load_win_ffi() then return false end

  local ok, result = pcall(win_kernel32.CreateDirectoryA, path, nil)
  if ok and result ~= 0 then return true end
  return path_exists(path)
end

local function native_shell_execute(exe, args)
  if not load_win_ffi() then return false end

  local ok, result = pcall(win_shell32.ShellExecuteA, nil, "open", tostring(exe or ""), tostring(args or ""), nil, 0)
  if not ok then
    log_line("ShellExecuteA failed: " .. tostring(result))
    return false
  end

  local code = tonumber(win_ffi.cast("intptr_t", result)) or 0
  if code <= 32 then
    log_line("ShellExecuteA returned error code: " .. tostring(code))
    return false
  end
  return true
end

local function ensure_dir(path)
  path = tostring(path or ""):gsub("/", "\\")
  if path == "" then return end
  if path_exists(path) then return end
  if native_create_dir(path) then return end
  local ok = os.execute('mkdir ' .. cmd_quote(path) .. ' >nul 2>nul')
  if ok == true or ok == 0 then return end
  log_line("ensure_dir failed for: " .. tostring(path))
end

local function filename(path)
  return (tostring(path):gsub("/", "\\"):match("([^\\]+)$") or tostring(path))
end

local function join_path(...)
  local parts = { ... }
  local out = ""
  for _, part in ipairs(parts) do
    part = tostring(part or ""):gsub("/", "\\")
    if part ~= "" then
      if out == "" then
        out = part
      else
        out = out:gsub("\\+$", "") .. "\\" .. part:gsub("^\\+", "")
      end
    end
  end
  return out
end

local function parse_vdf_simple(content)
  local result, stack, current_key = {}, {}, nil
  stack[1] = result
  local tokens = {}
  for line in tostring(content or ""):gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and not line:match("^//") then
      local pos = 1
      while pos <= #line do
        local q1 = line:find('"', pos, true)
        local b1 = line:find("{", pos, true)
        local b2 = line:find("}", pos, true)
        local best = nil
        for _, n in ipairs({ q1, b1, b2 }) do
          if n and (not best or n < best) then best = n end
        end
        if not best then break end
        local ch = line:sub(best, best)
        if ch == '"' then
          local q2 = best + 1
          while true do
            q2 = line:find('"', q2, true)
            if not q2 or line:sub(q2 - 1, q2 - 1) ~= "\\" then break end
            q2 = q2 + 1
          end
          if not q2 then break end
          tokens[#tokens + 1] = line:sub(best, q2)
          pos = q2 + 1
        else
          tokens[#tokens + 1] = ch
          pos = best + 1
        end
      end
    end
  end
  for _, raw in ipairs(tokens) do
    if raw == "{" then
      if current_key then
        local child = {}
        stack[#stack][current_key] = child
        stack[#stack + 1] = child
        current_key = nil
      end
    elseif raw == "}" then
      if #stack > 1 then stack[#stack] = nil end
    else
      local token = raw:gsub('^"', ""):gsub('"$', ""):gsub("\\\\", "\\")
      if current_key == nil then
        current_key = token
      else
        stack[#stack][current_key] = token
        current_key = nil
      end
    end
  end
  return result
end

local function appmanifest_info(path)
  local text = read_file(path)
  if text == "" then return nil end
  return {
    appid = vdf_value(text, "appid"),
    name = vdf_value(text, "name"),
    installdir = vdf_value(text, "installdir"),
  }
end

local function steam_library_paths()
  local base = steam_path():gsub("/", "\\")
  local paths, seen = {}, {}
  local function add(path)
    path = tostring(path or ""):gsub("/", "\\"):gsub("\\\\", "\\")
    if path ~= "" and not seen[path:lower()] then
      seen[path:lower()] = true
      paths[#paths + 1] = path
    end
  end
  add(base)
  local library_vdf = join_path(base, "config", "libraryfolders.vdf")
  local text = read_file(library_vdf)
  local data = parse_vdf_simple(text)
  local folders = type(data.libraryfolders) == "table" and data.libraryfolders or {}
  for _, folder in pairs(folders) do
    if type(folder) == "table" and folder.path then add(folder.path) end
  end
  for raw_path in text:gmatch('"path"%s+"([^"]+)"') do add(raw_path) end
  return paths
end

local function installed_appids_from_libraryfolders()
  local base = steam_path():gsub("/", "\\")
  local text = read_file(join_path(base, "config", "libraryfolders.vdf"))
  local appids, seen = {}, {}
  for id in text:gmatch('"%d+"%s+"%d+"') do
    local appid = id:match('"(%d+)"')
    if appid and not seen[appid] then
      seen[appid] = true
      appids[#appids + 1] = appid
    end
  end
  return appids
end

local function app_names_by_appid()
  local names = {}
  for _, lib in ipairs(steam_library_paths()) do
    local manifest_dir = join_path(lib, "steamapps")
    local cmd = 'dir /b /a-d ' .. cmd_quote(join_path(manifest_dir, "appmanifest_*.acf")) .. ' 2>nul'
    local pipe = io.popen(cmd, "r")
    if pipe then
      for file in pipe:lines() do
        file = filename(file):gsub("^\239\187\191", ""):match("^%s*(.-)%s*$") or ""
        local appid = tostring(file or ""):match("appmanifest_(%d+)%.acf")
        if appid and not names[appid] then
          local info = appmanifest_info(join_path(manifest_dir, file)) or {}
          if tostring(info.name or "") ~= "" then names[appid] = tostring(info.name) end
        end
      end
      pipe:close()
    end
  end
  return names
end

local function app_entries_from_file(path)
  local text = read_file(path)
  local entries = {}
  local matches = {}
  local pos = 1
  while true do
    local s, e, id = text:find("(%d+):", pos)
    if not s then break end
    matches[#matches + 1] = { start = s, after = e + 1, appid = id }
    pos = e + 1
  end
  for i, item in ipairs(matches) do
    local next_start = matches[i + 1] and matches[i + 1].start or (#text + 1)
    local name = text:sub(item.after, next_start - 1):gsub("[\r\n]+", ""):match("^%s*(.-)%s*$") or ""
    if name ~= "" then entries[#entries + 1] = { appid = item.appid, name = name } end
  end
  return entries
end

local function repair_mojibake(text)
  text = tostring(text or "")
  local replacements = {
    ["ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢"] = "™",
    ["Ã¢â€žÂ¢"] = "™",
    ["â„¢"] = "™",
    ["Ãƒâ€šÃ‚Â®"] = "®",
    ["Ã‚Â®"] = "®",
    ["Â®"] = "®",
    ["Ãƒâ€šÃ‚Â©"] = "©",
    ["Ã‚Â©"] = "©",
    ["Â©"] = "©",
    ["ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢"] = "'",
    ["Ã¢â‚¬â„¢"] = "'",
    ["â€™"] = "'",
    ["ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ"] = '"',
    ["ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â"] = '"',
    ["Ã¢â‚¬Å“"] = '"',
    ["Ã¢â‚¬Â"] = '"',
    ["â€œ"] = '"',
    ["â€"] = '"',
    ["ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦"] = "...",
    ["Ã¢â‚¬Â¦"] = "...",
    ["â€¦"] = "...",
    ["Ãƒâ€šÃ‚Â"] = "",
    ["Ã‚Â"] = "",
    ["Â"] = "",
  }
  local changed = true
  while changed do
    changed = false
    for bad, good in pairs(replacements) do
      local next_text = text:gsub(bad, good)
      if next_text ~= text then
        text = next_text
        changed = true
      end
    end
  end
  return text
end

local appid_log_entries

local function loaded_apps_entries()
  return app_entries_from_file(plugin_root() .. "/backend/loadedappids.txt")
end

local function installed_lua_entries()
  local entries = app_entries_from_file(plugin_root() .. "/backend/installed_lua_apps.txt")
  if #entries > 0 then return entries end
  return appid_log_entries()
end

local function loaded_app_name_map()
  local names = {}
  for _, entry in ipairs(loaded_apps_entries()) do
    names[tostring(entry.appid)] = repair_mojibake(entry.name)
  end
  return names
end

local function installed_lua_name_map()
  local names = {}
  for _, entry in ipairs(installed_lua_entries()) do
    names[tostring(entry.appid)] = repair_mojibake(entry.name)
  end
  return names
end

appid_log_entries = function()
  local text = read_file(plugin_root() .. "/backend/appidlogs.txt")
  local entries, order, seen_order = {}, {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local added_id, added_name = line:match("^%[ADDED.-%]%s+(%d+)%s+%-%s+(.-)%s+%-%s+%d%d%d%d%-%d%d%-%d%d")
    if added_id then
      entries[added_id] = { appid = added_id, name = added_name }
      if not seen_order[added_id] then
        seen_order[added_id] = true
        order[#order + 1] = added_id
      end
    else
      local removed_id = line:match("^%[REMOVED%]%s+(%d+)%s+%-")
      if removed_id then entries[removed_id] = nil end
    end
  end
  local out = {}
  for _, appid in ipairs(order) do
    if entries[appid] then out[#out + 1] = entries[appid] end
  end
  return out
end

local function remove_loaded_appid(appid)
  appid = tostring(appid or "")
  if appid == "" then return end
  local function remove_from(path)
    local kept = {}
    for _, entry in ipairs(app_entries_from_file(path)) do
      if tostring(entry.appid) ~= appid then
        kept[#kept + 1] = tostring(entry.appid) .. ":" .. tostring(entry.name or "")
      end
    end
    write_file(path, table.concat(kept, "\n"))
  end
  remove_from(plugin_root() .. "/backend/loadedappids.txt")
  remove_from(plugin_root() .. "/backend/installed_lua_apps.txt")
end

local function steam_lua_scripts()
  local scripts, seen = {}, {}
  local loaded_names = loaded_app_name_map()
  local installed_names = installed_lua_name_map()
  local steam_names = app_names_by_appid()
  local function add(entry)
    local appid = tostring(entry.appid or "")
    if appid ~= "" and not seen[appid] then
      seen[appid] = true
      local name = repair_mojibake(entry.name)
      if name == "" or name:match("^UNKNOWN%s*%(") or name:match("^Unknown Game%s*%(") then name = loaded_names[appid] or "" end
      if name == "" or name:match("^UNKNOWN%s*%(") or name:match("^Unknown Game%s*%(") then name = installed_names[appid] or "" end
      if name == "" or name:match("^UNKNOWN%s*%(") or name:match("^Unknown Game%s*%(") then name = repair_mojibake(steam_names[appid] or "") end
      if name == "" then name = "Unknown Game (" .. appid .. ")" end
      scripts[#scripts + 1] = {
        appid = appid,
        gameName = name,
        fileName = tostring(entry.fileName or (appid .. ".lua")),
        isDisabled = entry.isDisabled == true,
      }
    end
  end
  local dir = join_path(steam_path(), "config", "stplug-in")
  local pipe = io.popen('dir /b /a-d ' .. cmd_quote(join_path(dir, "*.lua*")) .. ' 2>nul', "r")
  if pipe then
    for file in pipe:lines() do
      file = filename(file):gsub("^\239\187\191", ""):match("^%s*(.-)%s*$") or ""
      local appid = file:match("^(%d+)%.lua$") or file:match("^(%d+)%.lua%.disabled$")
      if appid then
        add({
          appid = appid,
          name = "",
          fileName = file,
          isDisabled = file:match("%.disabled$") ~= nil,
        })
      end
    end
    pipe:close()
  end
  return scripts
end

local function parse_fix_log(path, appid, game_name, install_path)
  local fixes = {}
  local content = read_file(path)
  if content:find("%[FIX%]") then
    for block in content:gmatch("%[FIX%](.-)%[/FIX%]") do
      local fix = {
        appid = appid,
        gameName = game_name,
        installPath = install_path,
        date = "",
        fixType = "",
        downloadUrl = "",
        files = {},
      }
      local in_files = false
      for line in block:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line == "---" then break end
        if line:match("^Date:") then
          fix.date = line:gsub("^Date:%s*", "")
        elseif line:match("^Game:") then
          local name = line:gsub("^Game:%s*", "")
          if name ~= "" then fix.gameName = name end
        elseif line:match("^Fix Type:") then
          fix.fixType = line:gsub("^Fix Type:%s*", "")
        elseif line:match("^Download URL:") then
          fix.downloadUrl = line:gsub("^Download URL:%s*", "")
        elseif line == "Files:" then
          in_files = true
        elseif in_files and line ~= "" then
          fix.files[#fix.files + 1] = line
        end
      end
      fix.filesCount = #fix.files
      if fix.date ~= "" then fixes[#fixes + 1] = fix end
    end
  end
  return fixes
end

local function fix_to_json(fix)
  local files = {}
  for _, file in ipairs(fix.files or {}) do files[#files + 1] = json_string(file) end
  return '{"appid":' .. tostring(fix.appid or 0) ..
    ',"gameName":' .. json_string(fix.gameName or "") ..
    ',"installPath":' .. json_string(fix.installPath or "") ..
    ',"date":' .. json_string(fix.date or "") ..
    ',"fixType":' .. json_string(fix.fixType or "") ..
    ',"downloadUrl":' .. json_string(fix.downloadUrl or "") ..
    ',"filesCount":' .. tostring(fix.filesCount or #(fix.files or {})) ..
    ',"files":[' .. table.concat(files, ",") .. "]}";
end

local function dlc_count_from_lua(path, base_appid)
  local text = read_file(path)
  local count = tonumber(text:match("%-%-%s*[Tt]otal%s+DLCs%s*:%s*(%d+)") or "")
  if count and count > 0 then return count end

  local depots = {}
  for id in text:gmatch("[Ss]etManifestid%s*%(%s*(%d+)") do
    depots[tostring(id)] = true
  end

  local dlcs = {}
  local base = tostring(base_appid or "")
  for id in text:gmatch("[Aa]ddappid%s*%(%s*(%d+)") do
    id = tostring(id)
    if id ~= base and not depots[id] then
      dlcs[id] = true
    end
  end

  local total = 0
  for _ in pairs(dlcs) do total = total + 1 end
  return total
end

local function append_loaded_app(appid, name)
  local path = plugin_root() .. "/backend/loadedappids.txt"
  local lines = {}
  local prefix = tostring(appid) .. ":"
  for line in read_file(path):gmatch("[^\r\n]+") do
    if line:sub(1, #prefix) ~= prefix then lines[#lines + 1] = line end
  end
  lines[#lines + 1] = tostring(appid) .. ":" .. repair_mojibake(name or ("UNKNOWN (" .. tostring(appid) .. ")"))
  write_file(path, table.concat(lines, "\n") .. "\n")
end

local function state_path(appid)
  return plugin_root() .. "/backend/temp_dl/status_" .. tostring(appid) .. ".json"
end

local function state_json(appid)
  local text = read_file(state_path(appid))
  text = text:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$") or text
  if text ~= "" then return text end
  return nil
end

local function status_field(text, name)
  return tostring(text or ""):match('"' .. name .. '"%s*:%s*"([^"]*)"')
end

local function status_number(text, name)
  return tonumber(tostring(text or ""):match('"' .. name .. '"%s*:%s*(%d+)') or "")
end

local function normalized_state_json(appid)
  local text = state_json(appid)
  if not text then return nil end
  local status = status_field(text, "status") or "downloading"
  local current_api = status_field(text, "currentApi") or status_field(text, "api") or ""
  local err = status_field(text, "error")
  local bytes = status_number(text, "bytesRead") or 0
  local total = status_number(text, "totalBytes") or 0
  local manifests = status_number(text, "manifests")
  local dlcs = status_number(text, "dlcs")
  local success = tostring(text):match('"success"%s*:%s*true') ~= nil
  local out = {
    '"status":"' .. esc(status) .. '"',
    '"bytesRead":' .. tostring(bytes),
    '"totalBytes":' .. tostring(total),
  }
  if current_api ~= "" then out[#out + 1] = '"currentApi":"' .. esc(current_api) .. '"' end
  if current_api ~= "" then out[#out + 1] = '"api":"' .. esc(current_api) .. '"' end
  if manifests then out[#out + 1] = '"manifests":' .. tostring(manifests) end
  if dlcs then out[#out + 1] = '"dlcs":' .. tostring(dlcs) end
  if success then out[#out + 1] = '"success":true' end
  if err and err ~= "" then out[#out + 1] = '"error":"' .. esc(err) .. '"' end
  return "{" .. table.concat(out, ",") .. "}"
end

local function run_hidden(exe, args)
  local root = plugin_root():gsub("/", "\\")
  local temp = root .. "\\backend\\temp_dl"
  local queue = temp .. "\\queue"
  ensure_dir(temp)
  ensure_dir(queue)

  local daemon = root .. "\\backend\\worker_daemon.vbs"
  local launcher = root .. "\\backend\\run_hidden.vbs"
  if not exists(daemon) then
    log_line("run_hidden daemon missing: " .. tostring(daemon))
    return false
  end
  if not exists(launcher) then
    log_line("run_hidden launcher missing: " .. tostring(launcher))
    return false
  end

  local daemon_heartbeat = temp .. "\\worker_daemon.heartbeat"
  local heartbeat_fresh = false
  local heartbeat = read_file(daemon_heartbeat)
  local heartbeat_time = tonumber(heartbeat:match("(%d+)") or "")
  if heartbeat_time and os.time() - heartbeat_time < 20 then heartbeat_fresh = true end

  if not heartbeat_fresh then
    local daemon_command_tmp = temp .. "\\worker_daemon_start.tmp"
    local daemon_command_file = temp .. "\\worker_daemon_start.txt"
    if not write_file(daemon_command_tmp, 'cmd.exe /c start "" /min wscript.exe //B //Nologo ' .. cmd_quote(daemon) .. ' ' .. cmd_quote(root)) then
      log_line("worker daemon launch command write failed")
      return false
    end
    os.remove(daemon_command_file)
    os.rename(daemon_command_tmp, daemon_command_file)

    local launch_cmd = 'wscript.exe //B //Nologo ' .. cmd_quote(launcher) .. ' /file ' .. cmd_quote(daemon_command_file)
    local ok, reason, code = os.execute(launch_cmd)
    local success = ok == true or ok == 0 or code == 0
    if not success then
      log_line("worker daemon launch failed: " .. tostring(reason or ok) .. " code=" .. tostring(code))
      return false
    end
  end

  local job_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local command_file_tmp = queue .. "\\job_" .. job_id .. ".tmp"
  local command_file = queue .. "\\job_" .. job_id .. ".job"
  local command = cmd_quote(exe) .. " " .. tostring(args or "")
  if not write_file(command_file_tmp, command) then
    log_line("run_hidden failed to write queued command: " .. tostring(command_file_tmp))
    return false
  end
  local renamed = os.rename(command_file_tmp, command_file)
  if not renamed then
    log_line("run_hidden failed to publish queued command: " .. tostring(command_file))
    return false
  end
  return true
end

local function write_state_file(appid, json)
  ensure_dir(plugin_root() .. "\\backend\\temp_dl")
  write_file(state_path(appid), json)
end

local function launch_download_worker(appid, url, api_name)
  local root = plugin_root():gsub("/", "\\")
  local script = root .. "\\backend\\download_worker.ps1"
  local args = table.concat({
    '-WindowStyle Hidden',
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-File ' .. ps_quote(script),
    '-AppId ' .. ps_quote(appid),
    '-Url ' .. ps_quote(url),
    '-ApiName ' .. ps_quote(api_name),
    '-PluginRoot ' .. ps_quote(root),
    '-SteamPath ' .. ps_quote(steam_path()),
  }, " ")
  log_line("Launching download worker for " .. tostring(appid) .. " via " .. tostring(api_name))
  return run_hidden("powershell.exe", args)
end

local function fix_state_path(appid)
  return plugin_root() .. "\\backend\\temp_dl\\fix_status_" .. tostring(appid) .. ".json"
end

local function launch_fix_worker(appid, url, fix_type, install_path, game_name)
  local root = plugin_root():gsub("/", "\\")
  local script = root .. "\\backend\\fix_worker.ps1"
  local args = table.concat({
    '-WindowStyle Hidden',
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-File ' .. ps_quote(script),
    '-AppId ' .. ps_quote(appid),
    '-Url ' .. ps_quote(url),
    '-FixType ' .. ps_quote(fix_type),
    '-InstallPath ' .. ps_quote(install_path),
    '-GameName ' .. ps_quote(game_name),
    '-PluginRoot ' .. ps_quote(root),
  }, " ")
  log_line("Launching fix worker for " .. tostring(appid) .. " type=" .. tostring(fix_type))
  return run_hidden("powershell.exe", args)
end

local function redact_secrets(text)
  return tostring(text or ""):gsub("smm_[0-9a-fA-F]+", "smm_[REDACTED]")
end

function LoggerLog(args) log_line("[Frontend] " .. redact_secrets(type(args) == "table" and args.message or args)); return json_ok() end
function LoggerWarn(args) log_line("[Frontend WARN] " .. redact_secrets(type(args) == "table" and args.message or args)); return json_ok() end
function LoggerError(args) log_line("[Frontend ERROR] " .. redact_secrets(type(args) == "table" and args.message or args)); return json_ok() end

function GetPluginDir() return plugin_root() end
function InitApis() return json_ok('"message":"' .. esc(startup_message or "") .. '"') end
function GetInitApisMessage()
  local msg = startup_message or ""
  startup_message = ""
  return json_ok('"message":"' .. esc(msg) .. '"')
end
function FetchFreeApisNow() return json_ok('"count":0') end
function CheckForUpdatesNow() return json_ok('"message":""') end
function RestartSteam()
  local root = plugin_root():gsub("/", "\\")
  local script = root .. "\\backend\\restart_steam.ps1"
  local args = table.concat({
    '-WindowStyle Hidden',
    '-NoProfile',
    '-ExecutionPolicy Bypass',
    '-File ' .. ps_quote(script),
    '-SteamPath ' .. ps_quote(steam_path()),
  }, " ")
  log_line("RestartSteam requested")
  if run_hidden("powershell.exe", args) then
    return json_ok()
  end
  return json_fail("Failed to launch Steam restart worker")
end

function HasLuaToolsForApp(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  local base = steam_path()
  local p1 = base .. "\\config\\stplug-in\\" .. tostring(appid) .. ".lua"
  local p2 = base .. "\\config\\stplug-in\\" .. tostring(appid) .. ".lua.disabled"
  return json_ok('"exists":' .. ((exists(p1) or exists(p2)) and "true" or "false"))
end

function GetIconDataUrl()
  local data = read_file(plugin_root() .. "/public/luatools-icon.png")
  if data == "" then return json_fail("Icon not found") end
  return json_ok('"dataUrl":"data:image/png;base64,' .. base64_encode(data) .. '"')
end

function GetApiList()
  local key = get_morrenus_key()
  local items = {}
  for i, api in ipairs(load_apis()) do
    if api_should_list_for_download(api, key) then
      items[#items + 1] = '{"name":"' .. esc(api.name) .. '","index":' .. tostring(i - 1) .. "}"
    end
  end
  log_line("GetApiList returned " .. tostring(#items) .. " APIs")
  return json_ok('"apis":[' .. table.concat(items, ",") .. "]")
end

function GetDownloadApiConfig()
  local apis = load_api_entries()
  return json_ok('"apis":' .. api_entries_json(apis))
end

function SaveDownloadApiConfig(args)
  local apis_json = ""
  if type(args) == "table" then
    apis_json = tostring(args.apisJson or args.apis or args[1] or "")
  else
    apis_json = tostring(args or "")
  end

  local parsed = parse_api_entries(apis_json)
  local cleaned = {}
  local enabled_count = 0
  for _, api in ipairs(parsed) do
    local name = tostring(api.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local url = tostring(api.url or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local success_code = tonumber(api.success_code or 200) or 200
    local unavailable_code = tonumber(api.unavailable_code or 404) or 404
    if name ~= "" and url ~= "" then
      if not url:match("^https?://") then
        return json_fail("API URL must start with http:// or https://")
      end
      if not url:find("<appid>", 1, true) then
        return json_fail("API URL must contain <appid>")
      end
      cleaned[#cleaned + 1] = {
        name = name,
        url = url,
        success_code = success_code,
        unavailable_code = unavailable_code,
        enabled = api.enabled ~= false,
      }
      if api.enabled ~= false then enabled_count = enabled_count + 1 end
    end
  end

  if #cleaned == 0 then
    return json_fail("Add at least one download API")
  end
  if enabled_count == 0 then
    return json_fail("Keep at least one download API enabled")
  end
  local current_api_json = read_file(api_config_path())
  if current_api_json ~= "" then
    write_file(api_config_path() .. ".bak", current_api_json)
  end
  if not write_api_entries(cleaned) then
    return json_fail("Failed to write api.json")
  end
  log_line("Download API config saved with " .. tostring(#cleaned) .. " entries")
  return json_ok('"apis":' .. api_entries_json(cleaned))
end

function ResetDownloadApiConfig()
  local defaults = default_api_entries()
  local current_api_json = read_file(api_config_path())
  if current_api_json ~= "" then
    write_file(api_config_path() .. ".bak", current_api_json)
  end
  if not write_api_entries(defaults) then
    return json_fail("Failed to restore default download APIs")
  end
  log_line("Download API config restored to defaults")
  return json_ok('"apis":' .. api_entries_json(defaults))
end

function RestoreDownloadApiConfigBackup()
  local backup_path = api_config_path() .. ".bak"
  local backup = read_file(backup_path)
  if backup == "" then return json_fail("No API backup found") end
  local entries = parse_api_entries(backup)
  if #entries == 0 then return json_fail("API backup is empty or invalid") end
  local current_api_json = read_file(api_config_path())
  if current_api_json ~= "" then
    write_file(api_config_path() .. ".redo.bak", current_api_json)
  end
  if not write_file(api_config_path(), backup) then
    return json_fail("Failed to restore API backup")
  end
  log_line("Download API config restored from backup")
  return json_ok('"apis":' .. api_entries_json(entries))
end

function CheckApisForApp(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end

  local key = get_morrenus_key()
  log_line("API live probes skipped for " .. tostring(appid) .. " to avoid visible cmd windows")

  local results = {}
  for _, api in ipairs(load_apis()) do
    local url = api_url_for_app(api, appid, key)
    if url then
      results[#results + 1] =
        '{"name":"' .. esc(api.name) .. '","available":true,"url":"' .. esc(url) .. '"}'
    end
  end

  return json_ok('"results":[' .. table.concat(results, ",") .. "]")
end
function StartAddViaLuaTools(args, maybe_url, maybe_api_name)
  dump_args("StartAddViaLuaTools", args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  log_line("StartAddViaLuaTools called for " .. tostring(appid))
  local key = get_morrenus_key()
  add_state[appid] = { status = "checking", bytesRead = 0, totalBytes = 0 }
  for _, api in ipairs(load_apis()) do
    local url = api_url_for_app(api, appid, key)
    if url then
      write_state_file(appid, '{"status":"downloading","currentApi":"' .. esc(api.name) .. '","bytesRead":0,"totalBytes":0}')
      if not launch_download_worker(appid, url, api.name) then
        add_state[appid] = { status = "failed", error = "Failed to launch download worker" }
        write_state_file(appid, '{"status":"failed","error":"Failed to launch download worker"}')
      end
      return json_ok()
    end
  end
  add_state[appid] = { status = "failed", error = "Not available on any API" }
  return json_ok()
end

function StartAddViaLuaToolsFromUrl(args, maybe_url, maybe_api_name)
  dump_args("StartAddViaLuaToolsFromUrl", args)
  local appid = appid_from_args(args)
  local url = ""
  local api_name = "Unknown"
  if type(args) == "table" then
    url = tostring(args.url or args.URL or "")
    api_name = tostring(args.apiName or args.apiname or args.api_name or args.name or "Unknown")
    if api_name == "Unknown" and args[1] then api_name = tostring(args[1]) end
    if not appid and args[2] then appid = tonumber(args[2]) end
    if url == "" and args[3] then url = tostring(args[3]) end
    if url == "" then
      for _, v in pairs(args) do
        local s = tostring(v)
        if s:match("^https?://") then url = s end
      end
    end
  else
    if appid then
      url = tostring(maybe_url or "")
      api_name = tostring(maybe_api_name or "Unknown")
    else
      api_name = tostring(args or "Unknown")
      appid = tonumber(maybe_url)
      url = tostring(maybe_api_name or "")
    end
  end
  if not appid then return json_fail("Invalid appid") end
  if url == "" and api_name ~= "" and api_name ~= "Unknown" then
    local key = get_morrenus_key()
    for _, api in ipairs(load_apis()) do
      if tostring(api.name):lower() == tostring(api_name):lower() then
        url = api_url_for_app(api, appid, key) or ""
        break
      end
    end
  end
  if url == "" then return json_fail("Missing URL") end
  log_line("StartAddViaLuaToolsFromUrl called for " .. tostring(appid) .. " via " .. tostring(api_name))
  add_state[appid] = { status = "downloading", currentApi = api_name, bytesRead = 0, totalBytes = 0 }
  write_state_file(appid, '{"status":"downloading","currentApi":"' .. esc(api_name) .. '","bytesRead":0,"totalBytes":0}')
  launch_download_worker(appid, url, api_name)
  return json_ok()
end

function GetAddViaLuaToolsStatus(args)
  local appid = appid_from_args(args)
  local file_state = appid and normalized_state_json(appid) or nil
  if file_state then return json_ok('"state":' .. file_state) end
  local state = add_state[appid or 0] or {}
  local parts = {}
  for k, v in pairs(state) do
    if type(v) == "number" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. tostring(v)
    elseif type(v) == "boolean" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. (v and "true" or "false")
    else parts[#parts + 1] = '"' .. esc(k) .. '":"' .. esc(v) .. '"' end
  end
  return json_ok('"state":{' .. table.concat(parts, ",") .. "}")
end

function CancelAddViaLuaTools(args)
  local appid = appid_from_args(args)
  if appid then
    add_state[appid] = { status = "cancelled", error = "Cancelled by user" }
    write_state_file(appid, '{"status":"cancelled","error":"Cancelled by user"}')
  end
  return json_ok()
end

function GetGamesDatabase()
  local path = plugin_root() .. "/backend/temp_dl/games.json"
  local data = read_file(path)
  if data ~= "" then return data end
  return "{}"
end

function ReadLoadedApps()
  local apps = {}
  local seen = {}
  for _, entry in ipairs(loaded_apps_entries()) do
    local id = tostring(entry.appid or "")
    if id ~= "" and not seen[id] then
      seen[id] = true
      apps[#apps + 1] = '{"appid":' .. id .. ',"name":"' .. esc(repair_mojibake(entry.name)) .. '"}'
    end
  end
  if #apps > 0 then
    write_file(plugin_root() .. "/backend/loadedappids.txt", "")
  end
  return json_ok('"apps":[' .. table.concat(apps, ",") .. "]")
end

function DismissLoadedApps()
  write_file(plugin_root() .. "/backend/loadedappids.txt", "")
  return json_ok()
end

function DeleteLuaToolsForApp(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  local base = steam_path() .. "\\config\\stplug-in\\"
  local deleted = {}
  local p1 = base .. tostring(appid) .. ".lua"
  local p2 = base .. tostring(appid) .. ".lua.disabled"
  if exists(p1) and os.remove(p1) then deleted[#deleted + 1] = p1 end
  if exists(p2) and os.remove(p2) then deleted[#deleted + 1] = p2 end
  remove_loaded_appid(appid)
  local log_path = plugin_root() .. "/backend/appidlogs.txt"
  local stamp = os.date("%Y-%m-%d %H:%M:%S")
  local f = io.open(log_path, "ab")
  if f then
    f:write("[REMOVED] " .. tostring(appid) .. " - LuaTools - " .. stamp .. "\n")
    f:close()
  end
  local items = {}
  for _, path in ipairs(deleted) do items[#items + 1] = json_string(path) end
  return json_ok('"deleted":[' .. table.concat(items, ",") .. '],"count":' .. tostring(#deleted))
end

local function parse_fixes_index(text)
  local generic, online = {}, {}
  local generic_block = tostring(text or ""):match('"genericFixes"%s*:%s*%[(.-)%]')
  local online_block = tostring(text or ""):match('"onlineFixes"%s*:%s*%[(.-)%]')
  if generic_block then
    for id in generic_block:gmatch("%d+") do generic[tonumber(id)] = true end
  end
  if online_block then
    for id in online_block:gmatch("%d+") do online[tonumber(id)] = true end
  end
  return { generic = generic, online = online }
end

local function fetch_fixes_index()
  if fixes_index ~= nil then return fixes_index end
  log_line("Fixes index live fetch skipped to avoid visible cmd windows")
  fixes_index = false
  return nil
end

function CheckForFixes(args)
  local appid = appid_from_args(args) or 0
  if appid == 0 then return json_fail("Invalid appid") end

  local generic_url = "https://files.luatools.work/GameBypasses/" .. tostring(appid) .. ".zip"
  local online_url = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip"
  local generic_status, online_status = 0, 0
  local generic_available, online_available = false, false
  local index = fetch_fixes_index()

  if index then
    generic_available = index.generic[appid] == true
    online_available = index.online[appid] == true
    generic_status = generic_available and 200 or 404
    online_status = online_available and 200 or 404
  else
    generic_status = 0
    online_status = 0
    generic_available = false
    online_available = false
  end

  return '{"success":true,"appid":' .. tostring(appid) ..
    ',"gameName":""' ..
    ',"genericFix":{"status":' .. tostring(generic_status) ..
    ',"available":' .. (generic_available and "true" or "false") ..
    (generic_available and (',"url":' .. json_string(generic_url)) or "") .. "}" ..
    ',"onlineFix":{"status":' .. tostring(online_status) ..
    ',"available":' .. (online_available and "true" or "false") ..
    (online_available and (',"url":' .. json_string(online_url)) or "") .. "}}"
end

function ApplyGameFix(args, maybe_download_url, maybe_fix_type, maybe_install_path, maybe_game_name)
  if type(args) == "string" then
    local raw = args
    local text = raw:match('^%s*"(.*)"%s*$') or raw
    text = text:gsub('\\"', '"'):gsub("\\/", "/")
    if text:match("{") then
      args = text
    end
  end
  if type(args) == "string" and args:match("{") then
    local json_text = args:match("({.*})") or args
    local parsed = decode_json(json_text)
    if type(parsed) == "table" then
      args = parsed
    else
      args = {
        appid = tonumber(json_text:match('"appid"%s*:%s*(%d+)') or ""),
        downloadUrl = (json_text:match('"downloadUrl"%s*:%s*"([^"]*)"') or ""):gsub("\\/", "/"),
        download_url = (json_text:match('"download_url"%s*:%s*"([^"]*)"') or ""):gsub("\\/", "/"),
        url = (json_text:match('"url"%s*:%s*"([^"]*)"') or ""):gsub("\\/", "/"),
        installPath = (json_text:match('"installPath"%s*:%s*"([^"]*)"') or ""):gsub("\\\\", "\\"),
        install_path = (json_text:match('"install_path"%s*:%s*"([^"]*)"') or ""):gsub("\\\\", "\\"),
        fixType = (json_text:match('"fixType"%s*:%s*"([^"]*)"') or ""),
        fix_type = (json_text:match('"fix_type"%s*:%s*"([^"]*)"') or ""),
        gameName = (json_text:match('"gameName"%s*:%s*"([^"]*)"') or ""),
        game_name = (json_text:match('"game_name"%s*:%s*"([^"]*)"') or ""),
      }
    end
  end
  local appid = appid_from_args(args)
  if not appid then
    dump_args("ApplyGameFix invalid appid", args)
    return json_fail("Invalid appid")
  end
  local download_url = ""
  local install_path = ""
  local fix_type = ""
  local game_name = ""

  if type(args) == "table" then
    download_url = tostring(args.downloadUrl or args.download_url or args.url or args[2] or "")
    install_path = tostring(args.installPath or args.install_path or args.path or args[4] or "")
    fix_type = tostring(args.fixType or args.fix_type or args.type or args[3] or "")
    game_name = tostring(args.gameName or args.game_name or args.name or args[5] or "")
  else
    download_url = tostring(maybe_download_url or "")
    fix_type = tostring(maybe_fix_type or "")
    install_path = tostring(maybe_install_path or "")
    game_name = tostring(maybe_game_name or "")
  end

  if download_url ~= "" and not download_url:match("^https?://") then
    if tostring(maybe_fix_type or "") == "" then
      fix_type = download_url
    end
    download_url = ""
  end

  if download_url == "" then
    local fix_lower = fix_type:lower()
    if fix_lower:find("unsteam", 1, true) or fix_lower:find("all%-in%-one") or fix_lower:find("all in one") then
      download_url = "https://github.com/madoiscool/lt_api_links/releases/download/unsteam/Win64.zip"
    elseif fix_lower:find("32", 1, true) or fix_lower:find("steam fix", 1, true) then
      download_url = "https://github.com/madoiscool/lt_api_links/releases/download/unsteam/latest32bitsteam.zip"
    elseif fix_lower:find("online", 1, true) then
      download_url = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip"
    elseif fix_lower:find("generic", 1, true) then
      download_url = "https://files.luatools.work/GameBypasses/" .. tostring(appid) .. ".zip"
    end
  end
  if download_url == "" and fix_type == "" then
    log_line("ApplyGameFix received only appid; defaulting to Online Fix (Unsteam) for " .. tostring(appid))
    fix_type = "Online Fix (Unsteam)"
    download_url = "https://github.com/madoiscool/lt_api_links/releases/download/unsteam/Win64.zip"
  end
  if download_url == "" then
    dump_args("ApplyGameFix missing URL", args)
    return json_fail("Missing fix URL")
  end
  if install_path == "" then
    local path_result = GetGameInstallPath({ appid = appid })
    local install = tostring(path_result):match('"installPath"%s*:%s*"([^"]+)"')
    install_path = install and install:gsub("\\\\", "\\") or ""
  end
  if install_path == "" or not path_exists(install_path) then return json_fail("Install path does not exist") end

  fix_state[appid] = { status = "downloading", bytesRead = 0, totalBytes = 0 }
  ensure_dir(plugin_root() .. "\\backend\\temp_dl")
  write_file(fix_state_path(appid), '{"status":"downloading","bytesRead":0,"totalBytes":0}')
  if not launch_fix_worker(appid, download_url, fix_type, install_path, game_name) then
    fix_state[appid] = { status = "failed", error = "Failed to launch fix worker" }
    write_file(fix_state_path(appid), '{"status":"failed","error":"Failed to launch fix worker"}')
  end
  return json_ok()
end

function GetApplyFixStatus(args)
  local appid = appid_from_args(args)
  if appid then
    local text = read_file(fix_state_path(appid))
    if text ~= "" and text:match("^%s*{") then
      return json_ok('"state":' .. text)
    end
  end
  local state = fix_state[appid or 0] or {}
  local parts = {}
  for k, v in pairs(state) do
    if type(v) == "number" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. tostring(v)
    elseif type(v) == "boolean" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. (v and "true" or "false")
    else parts[#parts + 1] = '"' .. esc(k) .. '":"' .. esc(v) .. '"' end
  end
  return json_ok('"state":{' .. table.concat(parts, ",") .. "}")
end

function ApplyUnsteamFix(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  return ApplyGameFix({
    appid = appid,
    downloadUrl = "https://github.com/madoiscool/lt_api_links/releases/download/unsteam/Win64.zip",
    fixType = "Online Fix (Unsteam)",
  })
end

function ApplySteam32Fix(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  return ApplyGameFix({
    appid = appid,
    downloadUrl = "https://github.com/madoiscool/lt_api_links/releases/download/unsteam/latest32bitsteam.zip",
    fixType = "Steam Fix (32-bit)",
  })
end

function ApplyOnlineFix(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  return ApplyGameFix({
    appid = appid,
    downloadUrl = "https://files.luatools.work/OnlineFix1/" .. tostring(appid) .. ".zip",
    fixType = "Online Fix",
  })
end

function ApplyGenericFix(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  return ApplyGameFix({
    appid = appid,
    downloadUrl = "https://files.luatools.work/GameBypasses/" .. tostring(appid) .. ".zip",
    fixType = "Generic Fix",
  })
end

function CancelApplyFix(args)
  local appid = appid_from_args(args)
  if appid then fix_state[appid] = { status = "cancelled", success = false, error = "Cancelled by user" } end
  return json_ok()
end
function UnFixGame(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end
  local install_path = type(args) == "table" and tostring(args.installPath or args.install_path or "") or ""
  local fix_date = type(args) == "table" and tostring(args.fixDate or args.fix_date or "") or ""
  if install_path == "" then
    local path_result = GetGameInstallPath({ appid = appid })
    local install = tostring(path_result):match('"installPath"%s*:%s*"([^"]+)"')
    install_path = install and install:gsub("\\\\", "\\") or ""
  end
  if install_path == "" or not path_exists(install_path) then return json_fail("Install path does not exist") end

  local log_path = join_path(install_path, "luatools-fix-log-" .. tostring(appid) .. ".log")
  if not exists(log_path) then
    unfix_state[appid] = { status = "failed", success = false, error = "No fix log found. Cannot un-fix." }
    return json_ok()
  end

  unfix_state[appid] = { status = "removing", progress = "Reading log file..." }
  local fixes = parse_fix_log(log_path, appid, "", install_path)
  local files, remaining = {}, {}
  for _, fix in ipairs(fixes) do
    local selected = fix_date == "" or fix.date == fix_date
    if selected then
      for _, rel in ipairs(fix.files or {}) do files[rel] = true end
    else
      remaining[#remaining + 1] = fix
    end
  end

  local deleted = 0
  for rel in pairs(files) do
    rel = tostring(rel or ""):gsub("/", "\\")
    if rel ~= "" and not rel:find("%.%.", 1, true) and not rel:match("^%a:[\\/]") and not rel:match("^[\\/]") then
      local full = join_path(install_path, rel)
      if exists(full) then
        os.remove(full)
        deleted = deleted + 1
      end
    end
  end

  if #remaining > 0 then
    local blocks = {}
    for _, fix in ipairs(remaining) do
      blocks[#blocks + 1] = "[FIX]\nDate: " .. tostring(fix.date or "") ..
        "\nGame: " .. tostring(fix.gameName or "") ..
        "\nFix Type: " .. tostring(fix.fixType or "") ..
        "\nDownload URL: " .. tostring(fix.downloadUrl or "") ..
        "\nFiles:\n" .. table.concat(fix.files or {}, "\n") .. "\n[/FIX]\n"
    end
    write_file(log_path, table.concat(blocks, "\n---\n\n"))
  else
    os.remove(log_path)
  end

  unfix_state[appid] = { status = "done", success = true, filesRemoved = deleted }
  return json_ok()
end

function GetUnfixStatus(args)
  local appid = appid_from_args(args)
  local state = unfix_state[appid or 0] or {}
  local parts = {}
  for k, v in pairs(state) do
    if type(v) == "number" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. tostring(v)
    elseif type(v) == "boolean" then parts[#parts + 1] = '"' .. esc(k) .. '":' .. (v and "true" or "false")
    else parts[#parts + 1] = '"' .. esc(k) .. '":"' .. esc(v) .. '"' end
  end
  return json_ok('"state":{' .. table.concat(parts, ",") .. "}")
end

function GetInstalledFixes()
  local out = {}
  local appids = installed_appids_from_libraryfolders()
  for _, lib in ipairs(steam_library_paths()) do
    for _, appid_key in ipairs(appids) do
      local manifest = join_path(lib, "steamapps", "appmanifest_" .. tostring(appid_key) .. ".acf")
      if exists(manifest) then
        local appid = tonumber(appid_key)
        if appid then
          local app_state = appmanifest_info(manifest) or {}
          local install_dir = tostring(app_state.installdir or "")
          local game_name = repair_mojibake(app_state.name or ("Unknown Game (" .. tostring(appid) .. ")"))
          if install_dir ~= "" then
            local install_path = join_path(lib, "steamapps", "common", install_dir)
            local log_path = join_path(install_path, "luatools-fix-log-" .. tostring(appid) .. ".log")
            if exists(log_path) then
              for _, fix in ipairs(parse_fix_log(log_path, appid, game_name, install_path)) do
                out[#out + 1] = fix_to_json(fix)
              end
            end
          end
        end
      end
    end
  end
  return json_ok('"fixes":[' .. table.concat(out, ",") .. "]")
end
function GetInstalledLuaScripts()
  local items = {}
  for _, script in ipairs(steam_lua_scripts()) do
    items[#items + 1] =
      '{"appid":' .. tostring(script.appid) ..
      ',"gameName":' .. json_string(script.gameName) ..
      ',"fileName":' .. json_string(script.fileName) ..
      ',"isDisabled":' .. (script.isDisabled and "true" or "false") .. "}"
  end
  log_line("GetInstalledLuaScripts returned " .. tostring(#items) .. " scripts")
  return json_ok('"scripts":[' .. table.concat(items, ",") .. "]")
end

function GetGameInstallPath(args)
  local appid = appid_from_args(args)
  if not appid then return json_fail("Invalid appid") end

  local base = steam_path():gsub("/", "\\")
  if base == "" then return json_fail("Could not find Steam installation path") end

  local appid_key = tostring(appid)
  local appid_candidates = { appid_key }
  if appid_key == "271590" then
    appid_candidates[#appid_candidates + 1] = "3240220"
  elseif appid_key == "3240220" then
    appid_candidates[#appid_candidates + 1] = "271590"
  end

  local library_vdf = join_path(base, "config", "libraryfolders.vdf")
  if not exists(library_vdf) then
    log_line("GetGameInstallPath: libraryfolders.vdf missing at " .. tostring(library_vdf))
    return json_fail("Could not find libraryfolders.vdf")
  end

  local library_text = read_file(library_vdf)
  local data = parse_vdf_simple(library_text)
  local folders = type(data.libraryfolders) == "table" and data.libraryfolders or {}
  local paths, seen = {}, {}
  local library_path = nil

  local function add_library_path(path)
    path = tostring(path or ""):gsub("/", "\\"):gsub("\\\\", "\\")
    if path ~= "" and not seen[path:lower()] then
      seen[path:lower()] = true
      paths[#paths + 1] = path
    end
  end

  add_library_path(base)
  for _, folder in pairs(folders) do
    if type(folder) == "table" then
      local p = tostring(folder.path or ""):gsub("/", "\\"):gsub("\\\\", "\\")
      if p ~= "" then
        add_library_path(p)
        if type(folder.apps) == "table" then
          for _, candidate_appid in ipairs(appid_candidates) do
            if folder.apps[candidate_appid] ~= nil then
              library_path = p
              appid_key = candidate_appid
              break
            end
          end
        end
      end
    end
  end

  for raw_path in library_text:gmatch('"path"%s+"([^"]+)"') do
    add_library_path(raw_path)
  end

  for _, p in ipairs(paths) do
    for _, candidate_appid in ipairs(appid_candidates) do
      local candidate = join_path(p, "steamapps", "appmanifest_" .. candidate_appid .. ".acf")
      if exists(candidate) then
        local info = appmanifest_info(candidate) or {}
        local install_dir = tostring(info.installdir or "")
        local full = install_dir ~= "" and join_path(p, "steamapps", "common", install_dir) or ""
        if install_dir ~= "" and path_exists(full) then
          log_line("GetGameInstallPath: direct manifest found " .. candidate_appid .. " at " .. tostring(full))
          return json_ok(
            '"installPath":' .. json_string(full) ..
            ',"installDir":' .. json_string(install_dir) ..
            ',"libraryPath":' .. json_string(p) ..
            ',"path":' .. json_string(full) ..
            ',"gameName":' .. json_string(info.name or "") ..
            ',"resolvedAppId":' .. json_string(candidate_appid)
          )
        end
        log_line("GetGameInstallPath: manifest exists but install dir failed for " .. candidate_appid .. " manifest=" .. tostring(candidate) .. " installdir=" .. tostring(install_dir) .. " full=" .. tostring(full))
      end
    end
  end

  local manifest_path = nil
  if library_path then
    manifest_path = join_path(library_path, "steamapps", "appmanifest_" .. appid_key .. ".acf")
    if not exists(manifest_path) then
      manifest_path = nil
      library_path = nil
    end
  end

  if not library_path then
    for _, p in ipairs(paths) do
      for _, candidate_appid in ipairs(appid_candidates) do
        local candidate = join_path(p, "steamapps", "appmanifest_" .. candidate_appid .. ".acf")
        if exists(candidate) then
          library_path = p
          manifest_path = candidate
          appid_key = candidate_appid
          break
        end
      end
      if library_path then break end
    end
  end

  if not library_path or not manifest_path then
    log_line("GetGameInstallPath: appmanifest not found for " .. appid_key .. " in " .. table.concat(paths, "; "))
    return json_fail("menu.error.notInstalled")
  end

  local app_state = appmanifest_info(manifest_path) or {}
  local install_dir = tostring(app_state.installdir or "")
  local game_name = tostring(app_state.name or "")
  if install_dir == "" then
    log_line("GetGameInstallPath: installdir missing in " .. tostring(manifest_path))
    return json_fail("Install directory not found")
  end

  local full = join_path(library_path, "steamapps", "common", install_dir)
  if not path_exists(full) then
    log_line("GetGameInstallPath: game dir missing for " .. appid_key .. " at " .. tostring(full))
    return json_fail("Game directory not found")
  end

  log_line("GetGameInstallPath: found " .. appid_key .. " at " .. tostring(full))
  return json_ok(
    '"installPath":' .. json_string(full) ..
    ',"installDir":' .. json_string(install_dir) ..
    ',"libraryPath":' .. json_string(library_path) ..
    ',"path":' .. json_string(full) ..
    ',"gameName":' .. json_string(game_name) ..
    ',"resolvedAppId":' .. json_string(appid_key)
  )
end

function OpenGameFolder(args)
  return json_fail("Open folder disabled to avoid native access violation")
end

function OpenExternalUrl(args)
  return json_fail("Open URL disabled to avoid native access violation")
end

local LOCALE_CODES = {
  "ar", "bg", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hu",
  "id", "it", "ja", "ko", "nl", "no", "peakstupid", "pirate", "pl", "pt",
  "pt-BR", "pt-decria", "ro", "ru", "sv", "th", "tr", "uk", "vi", "zh-CN",
  "zh-TW",
}

local STEAM_LANG_TO_LOCALE = {
  arabic = "ar", brazilian = "pt-BR", bulgarian = "bg", czech = "cs",
  danish = "da", dutch = "nl", english = "en", finnish = "fi", french = "fr",
  german = "de", greek = "el", hebrew = "he", hungarian = "hu",
  indonesian = "id", italian = "it", japanese = "ja", koreana = "ko",
  latam = "es", norwegian = "no", polish = "pl", portuguese = "pt",
  romanian = "ro", russian = "ru", schinese = "zh-CN", spanish = "es",
  swedish = "sv", tchinese = "zh-TW", thai = "th", turkish = "tr",
  ukrainian = "uk", vietnamese = "vi",
}

local function json_string(value)
  return '"' .. esc(value or "") .. '"'
end

local function settings_path()
  return plugin_root() .. "/backend/data/settings.json"
end

local function setting_string(text, key, default)
  local value = tostring(text or ""):match('"' .. key .. '"%s*:%s*"([^"]*)"')
  if value == nil or value == "" then return default end
  return value
end

local function setting_bool(text, key, default)
  local value = tostring(text or ""):match('"' .. key .. '"%s*:%s*(true)') or tostring(text or ""):match('"' .. key .. '"%s*:%s*(false)')
  if value == "true" then return true end
  if value == "false" then return false end
  return default
end

local function normalize_lua_display_limit(value)
  value = tonumber(value) or 50
  if value < 10 then value = 10 end
  if value > 100 then value = 100 end
  return math.floor((value + 5) / 10) * 10
end

local function setting_number(text, key, default, min_value, max_value)
  if tostring(key or "") == "" then return tonumber(default) or 0 end
  local value = tonumber(tostring(text or ""):match('"' .. key .. '"%s*:%s*"?([0-9]+)"?'))
  if not value then value = tonumber(default) or 0 end
  if min_value and value < min_value then value = min_value end
  if max_value and value > max_value then value = max_value end
  return math.floor((value + 5) / 10) * 10
end

local function normalize_locale_code(value)
  local raw = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if raw == "" then return "en" end
  local lower = raw:lower():gsub("_", "-")
  local aliases = {
    ["brazilian"] = "pt-BR",
    ["pt-br"] = "pt-BR",
    ["schinese"] = "zh-CN",
    ["zh-cn"] = "zh-CN",
    ["tchinese"] = "zh-TW",
    ["zh-tw"] = "zh-TW",
    ["latam"] = "es",
    ["es-419"] = "es",
  }
  if aliases[lower] then return aliases[lower] end
  for _, code in ipairs(LOCALE_CODES) do
    if lower == code:lower() then return code end
  end
  return raw
end

local function read_settings_values()
  local text = read_file(settings_path())
  return {
    useSteamLanguage = setting_bool(text, "useSteamLanguage", true),
    language = normalize_locale_code(setting_string(text, "language", "en")),
    donateKeys = setting_bool(text, "donateKeys", true),
    theme = setting_string(text, "theme", "original"),
    fastDownload = setting_bool(text, "fastDownload", true),
    installedLuaDisplayLimit = normalize_lua_display_limit(setting_number(text, "installedLuaDisplayLimit", 50, 10, 100)),
    morrenusApiKey = setting_string(text, "morrenusApiKey", ""),
  }
end

local function settings_values_json(values)
  values = values or read_settings_values()
  return '{"general":{"useSteamLanguage":' .. (values.useSteamLanguage ~= false and "true" or "false") ..
    ',"language":' .. json_string(values.language or "en") ..
    ',"donateKeys":' .. (values.donateKeys ~= false and "true" or "false") ..
    ',"theme":' .. json_string(values.theme or "original") ..
    ',"fastDownload":' .. (values.fastDownload ~= false and "true" or "false") ..
    ',"installedLuaDisplayLimit":' .. tostring(normalize_lua_display_limit(values.installedLuaDisplayLimit)) ..
    ',"morrenusApiKey":' .. json_string(values.morrenusApiKey or "") .. "}}"
end

local function write_settings_values(values)
  ensure_dir(plugin_root() .. "\\backend\\data")
  return write_file(settings_path(), '{\n  "version": 1,\n  "values": ' .. settings_values_json(values) .. "\n}\n")
end

local function locales_json()
  local items = {}
  for _, code in ipairs(LOCALE_CODES) do
    local path = plugin_root() .. "/backend/locales/" .. code .. ".json"
    if exists(path) then
      local text = read_file(path)
      local name = text:match('"__name"%s*:%s*"([^"]+)"') or code
      local native = text:match('"__nativeName"%s*:%s*"([^"]+)"') or name
      items[#items + 1] = '{"code":' .. json_string(code) .. ',"name":' .. json_string(name) .. ',"nativeName":' .. json_string(native) .. "}"
    end
  end
  if #items == 0 then items[#items + 1] = '{"code":"en","name":"English","nativeName":"English"}' end
  return "[" .. table.concat(items, ",") .. "]"
end

local function themes_json()
  local text = read_file(plugin_root() .. "/public/themes/themes.json")
  text = text:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$") or text
  if text ~= "" and text:sub(1, 1) == "[" then return text end
  return '[{"value":"original","label":"Original"}]'
end

local function settings_schema_json()
  local locale_choices = {}
  for _, code in ipairs(LOCALE_CODES) do
    if exists(plugin_root() .. "/backend/locales/" .. code .. ".json") then
      locale_choices[#locale_choices + 1] = '{"value":' .. json_string(code) .. ',"label":' .. json_string(code) .. "}"
    end
  end
  local lua_limit_choices = {}
  for value = 10, 100, 10 do
    lua_limit_choices[#lua_limit_choices + 1] = '{"value":' .. json_string(tostring(value)) .. ',"label":' .. json_string(tostring(value)) .. "}"
  end
  return '[{"key":"general","label":"General","description":"Global LuaTools preferences.","options":[' ..
    '{"key":"useSteamLanguage","label":"Use Steam Language","type":"toggle","description":"Use the Steam client language for LuaTools.","default":true,"choices":[],"requiresRestart":false,"metadata":{"yesLabel":"Yes","noLabel":"No"}},' ..
    '{"key":"language","label":"Language","type":"select","description":"Choose the language used by LuaTools.","default":"en","choices":[' .. table.concat(locale_choices, ",") .. '],"requiresRestart":false,"metadata":{"dynamicChoices":"locales"}},' ..
    '{"key":"donateKeys","label":"Donate Keys","type":"toggle","description":"Allow LuaTools to donate spare Steam keys.","default":true,"choices":[],"requiresRestart":false,"metadata":{"yesLabel":"Yes","noLabel":"No"}},' ..
    '{"key":"theme","label":"Theme","type":"select","description":"Choose the color theme for LuaTools interface.","default":"original","choices":' .. themes_json() .. ',"requiresRestart":false,"metadata":{"dynamicChoices":"themes"}},' ..
    '{"key":"fastDownload","label":"Fast Download","type":"toggle","description":"Automatically choose the first available source when adding a game.","default":true,"choices":[],"requiresRestart":false,"metadata":{"yesLabel":"Yes","noLabel":"No"}},' ..
    '{"key":"installedLuaDisplayLimit","label":"Shown games limit","type":"select","description":"Choose how many LuaTools games are shown before using search.","default":50,"choices":[' .. table.concat(lua_limit_choices, ",") .. '],"requiresRestart":false,"metadata":{}},' ..
    '{"key":"morrenusApiKey","label":"Morrenus API Key","type":"text","description":"API Key required to use Sadie Source. Get from hubcapmanifest.com","default":"","choices":[],"requiresRestart":false,"metadata":{"placeholder":"Enter your API key..."}}' ..
    "]}]"
end

local function detect_steam_locale()
  local base = steam_path()
  if base == "" then return nil end
  local candidates = {
    base .. "/config/config.vdf",
    base .. "\\config\\config.vdf",
  }
  for _, path in ipairs(candidates) do
    local text = read_file(path)
    if text ~= "" then
      local raw = text:match('"%s*[Ll]anguage%s*"%s*"([^"]+)"') or
        text:match('"%s*[Ss]team[Ll]anguage%s*"%s*"([^"]+)"')
      if raw and raw ~= "" then
        local mapped = STEAM_LANG_TO_LOCALE[tostring(raw):lower()] or raw
        mapped = normalize_locale_code(mapped)
        if exists(plugin_root() .. "/backend/locales/" .. tostring(mapped) .. ".json") then
          return mapped
        end
      end
    end
  end
  return nil
end

local function current_settings_language(values)
  values = values or read_settings_values()
  if values.useSteamLanguage ~= false then
    local detected = detect_steam_locale()
    if detected then return detected end
    return "en"
  end
  if exists(plugin_root() .. "/backend/locales/" .. tostring(values.language or "") .. ".json") then return tostring(values.language) end
  return "en"
end

local function translations_json(language)
  local lang = language and normalize_locale_code(language) or current_settings_language()
  local path = plugin_root() .. "/backend/locales/" .. tostring(lang) .. ".json"
  if not exists(path) then lang = "en"; path = plugin_root() .. "/backend/locales/en.json" end
  local text = read_file(path)
  text = text:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$") or text
  if text == "" or text:sub(1, 1) ~= "{" then text = "{}" end
  return lang, text
end

local function apply_setting_payload(values, payload)
  local text = type(payload) == "string" and payload or ""
  if type(payload) == "table" then
    local general = type(payload.general) == "table" and payload.general or payload
    if general.useSteamLanguage ~= nil then values.useSteamLanguage = general.useSteamLanguage == true end
    if general.language ~= nil then
      values.language = normalize_locale_code(general.language)
      if general.useSteamLanguage ~= true then values.useSteamLanguage = false end
    end
    if general.donateKeys ~= nil then values.donateKeys = general.donateKeys == true end
    if general.theme ~= nil then values.theme = tostring(general.theme) end
    if general.fastDownload ~= nil then values.fastDownload = general.fastDownload == true end
    if general.installedLuaDisplayLimit ~= nil then values.installedLuaDisplayLimit = normalize_lua_display_limit(general.installedLuaDisplayLimit) end
    if general.morrenusApiKey ~= nil then values.morrenusApiKey = tostring(general.morrenusApiKey):gsub("%s+", "") end
    return values
  end
  local function maybe_bool(key)
    local v = setting_bool(text, key, nil)
    if v ~= nil then values[key] = v end
  end
  local explicit_use_steam_language = setting_bool(text, "useSteamLanguage", nil)
  if explicit_use_steam_language ~= nil then values.useSteamLanguage = explicit_use_steam_language end
  maybe_bool("donateKeys")
  maybe_bool("fastDownload")
  local next_language = setting_string(text, "language", values.language)
  values.language = normalize_locale_code(next_language)
  if text:find('"language"%s*:') and explicit_use_steam_language ~= true then values.useSteamLanguage = false end
  values.theme = setting_string(text, "theme", values.theme)
  values.installedLuaDisplayLimit = normalize_lua_display_limit(setting_number(text, "installedLuaDisplayLimit", values.installedLuaDisplayLimit, 10, 100))
  values.morrenusApiKey = setting_string(text, "morrenusApiKey", values.morrenusApiKey):gsub("%s+", "")
  return values
end

function GetSettingsConfig()
  local values = read_settings_values()
  local lang, strings = translations_json(current_settings_language(values))
  return json_ok('"schemaVersion":1,"schema":' .. settings_schema_json() .. ',"values":' .. settings_values_json(values) .. ',"language":' .. json_string(lang) .. ',"locales":' .. locales_json() .. ',"translations":' .. strings)
end

function ApplySettingsChanges(args)
  local values = read_settings_values()
  local payload = args
  if type(args) == "table" then payload = args.changes or args.changesJson or args.general or args end
  values = apply_setting_payload(values, payload)
  write_settings_values(values)
  local lang, strings = translations_json(current_settings_language(values))
  log_line("Settings saved: language=" .. tostring(values.language) .. " useSteamLanguage=" .. tostring(values.useSteamLanguage) .. " resolved=" .. tostring(lang) .. " theme=" .. tostring(values.theme))
  return json_ok('"values":' .. settings_values_json(values) .. ',"language":' .. json_string(lang) .. ',"translations":' .. strings .. ',"locales":' .. locales_json())
end

function GetAvailableLocales() return json_ok('"locales":' .. locales_json()) end
function GetTranslations(args)
  local language = type(args) == "table" and (args.language or args[1]) or args
  if language == "" then language = nil end
  local lang, strings = translations_json(language)
  return json_ok('"language":' .. json_string(lang) .. ',"locales":' .. locales_json() .. ',"strings":' .. strings)
end
function GetThemes() return json_ok('"themes":' .. themes_json()) end
function GetAvailableThemes() return GetThemes() end
function GetMorrenusStats(args)
  local key = ""
  local force_refresh = false
  if type(args) == "table" then
    key = tostring(args.api_key or args.apiKey or args[1] or "")
    force_refresh = args.force_refresh == true or args.forceRefresh == true
  else
    key = tostring(args or "")
  end
  key = key:gsub("%s+", "")
  if key == "" then return json_fail("Missing API key") end

  local now = os.time()
  if not force_refresh and morrenus_stats_cache[key] and now - morrenus_stats_cache[key].time < 600 then
    return morrenus_stats_cache[key].data
  end

  local res, err = powershell_http_get("https://hubcapmanifest.com/api/v1/user/stats?api_key=" .. url_encode(key), 10)
  if res and tonumber(res.status) == 200 and tostring(res.body or "") ~= "" then
    morrenus_stats_cache[key] = { time = now, data = res.body }
    return res.body
  end

  local detail = ""
  if res and tostring(res.body or "") ~= "" then
    detail = tostring(res.body)
    detail = detail:match('"detail"%s*:%s*"([^"]+)"') or detail:match('"error"%s*:%s*"([^"]+)"') or detail
  end
  if detail == "" then
    detail = err or ("HTTP " .. tostring(res and res.status or 0))
  end
  local data = json_fail(detail)
  morrenus_stats_cache[key] = { time = now, data = data }
  return data
end

local function on_frontend_loaded()
  local root = plugin_root()
  local dst = steam_path() .. "\\steamui\\LuaTools"
  ensure_dir(dst)
  local ok_js = copy_file(root .. "/public/luatools.js", dst .. "\\luatools.js")
  local ok_icon = copy_file(root .. "/public/luatools-icon.png", dst .. "\\luatools-icon.png")
  if not ok_js then log_line("Failed to copy luatools.js to Steam UI") end
  if not ok_icon then log_line("Failed to copy luatools-icon.png to Steam UI") end
end

local function on_load()
  log_line("LuaTools bootstrap loading")
  local ok_ready, ready_err = pcall(millennium.ready)
  if not ok_ready then log_line("millennium.ready failed: " .. tostring(ready_err)) end
  local ok_frontend, frontend_err = pcall(on_frontend_loaded)
  if not ok_frontend then log_line("on_frontend_loaded failed: " .. tostring(frontend_err)) end
  local ok_js, js_err = pcall(millennium.add_browser_js, "LuaTools/luatools.js")
  if not ok_js then log_line("add_browser_js failed: " .. tostring(js_err)) end
  log_line("LuaTools bootstrap ready")
end

local function on_unload()
  log_line("LuaTools bootstrap unloading")
end

local function safe_method(name, fn)
  return function(...)
    local ok, result = pcall(fn, ...)
    if ok then
      if result == nil then return json_ok() end
      return result
    end
    log_line("Method " .. tostring(name) .. " failed: " .. tostring(result))
    return json_fail(tostring(result))
  end
end

return {
  on_load = on_load,
  on_unload = on_unload,
  on_frontend_loaded = on_frontend_loaded,
  LoggerLog = safe_method("LoggerLog", LoggerLog),
  LoggerWarn = safe_method("LoggerWarn", LoggerWarn),
  LoggerError = safe_method("LoggerError", LoggerError),
  GetPluginDir = safe_method("GetPluginDir", GetPluginDir),
  InitApis = safe_method("InitApis", InitApis),
  GetInitApisMessage = safe_method("GetInitApisMessage", GetInitApisMessage),
  FetchFreeApisNow = safe_method("FetchFreeApisNow", FetchFreeApisNow),
  CheckForUpdatesNow = safe_method("CheckForUpdatesNow", CheckForUpdatesNow),
  RestartSteam = safe_method("RestartSteam", RestartSteam),
  HasLuaToolsForApp = safe_method("HasLuaToolsForApp", HasLuaToolsForApp),
  GetIconDataUrl = safe_method("GetIconDataUrl", GetIconDataUrl),
  GetApiList = safe_method("GetApiList", GetApiList),
  GetDownloadApiConfig = safe_method("GetDownloadApiConfig", GetDownloadApiConfig),
  SaveDownloadApiConfig = safe_method("SaveDownloadApiConfig", SaveDownloadApiConfig),
  ResetDownloadApiConfig = safe_method("ResetDownloadApiConfig", ResetDownloadApiConfig),
  RestoreDownloadApiConfigBackup = safe_method("RestoreDownloadApiConfigBackup", RestoreDownloadApiConfigBackup),
  CheckApisForApp = safe_method("CheckApisForApp", CheckApisForApp),
  StartAddViaLuaTools = safe_method("StartAddViaLuaTools", StartAddViaLuaTools),
  StartAddViaLuaToolsFromUrl = safe_method("StartAddViaLuaToolsFromUrl", StartAddViaLuaToolsFromUrl),
  GetAddViaLuaToolsStatus = safe_method("GetAddViaLuaToolsStatus", GetAddViaLuaToolsStatus),
  CancelAddViaLuaTools = safe_method("CancelAddViaLuaTools", CancelAddViaLuaTools),
  GetGamesDatabase = safe_method("GetGamesDatabase", GetGamesDatabase),
  ReadLoadedApps = safe_method("ReadLoadedApps", ReadLoadedApps),
  DismissLoadedApps = safe_method("DismissLoadedApps", DismissLoadedApps),
  DeleteLuaToolsForApp = safe_method("DeleteLuaToolsForApp", DeleteLuaToolsForApp),
  CheckForFixes = safe_method("CheckForFixes", CheckForFixes),
  ApplyGameFix = safe_method("ApplyGameFix", ApplyGameFix),
  ApplyUnsteamFix = safe_method("ApplyUnsteamFix", ApplyUnsteamFix),
  ApplySteam32Fix = safe_method("ApplySteam32Fix", ApplySteam32Fix),
  ApplyOnlineFix = safe_method("ApplyOnlineFix", ApplyOnlineFix),
  ApplyGenericFix = safe_method("ApplyGenericFix", ApplyGenericFix),
  GetApplyFixStatus = safe_method("GetApplyFixStatus", GetApplyFixStatus),
  CancelApplyFix = safe_method("CancelApplyFix", CancelApplyFix),
  UnFixGame = safe_method("UnFixGame", UnFixGame),
  GetUnfixStatus = safe_method("GetUnfixStatus", GetUnfixStatus),
  GetInstalledFixes = safe_method("GetInstalledFixes", GetInstalledFixes),
  GetInstalledLuaScripts = safe_method("GetInstalledLuaScripts", GetInstalledLuaScripts),
  GetGameInstallPath = safe_method("GetGameInstallPath", GetGameInstallPath),
  OpenGameFolder = safe_method("OpenGameFolder", OpenGameFolder),
  OpenExternalUrl = safe_method("OpenExternalUrl", OpenExternalUrl),
  GetSettingsConfig = safe_method("GetSettingsConfig", GetSettingsConfig),
  ApplySettingsChanges = safe_method("ApplySettingsChanges", ApplySettingsChanges),
  GetAvailableLocales = safe_method("GetAvailableLocales", GetAvailableLocales),
  GetTranslations = safe_method("GetTranslations", GetTranslations),
  GetThemes = safe_method("GetThemes", GetThemes),
  GetAvailableThemes = safe_method("GetAvailableThemes", GetAvailableThemes),
  GetMorrenusStats = safe_method("GetMorrenusStats", GetMorrenusStats),
}

-- KazzKyy gostoso da pirataria
