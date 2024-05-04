local my_cool_module = require("grug-far.my_cool_module")

local M = {}

local function with_defaults(options)
  return {
    resultsHeader = options.resultsHeader or "Results:",
    -- TODO (sbadragan): remove?
    resultsHeaderHighlight = options.resultsHeaderHighlight or "Comment"
  }
end

-- This function is supposed to be called explicitly by users to configure this
-- plugin
function M.setup(options)
  -- avoid setting global values outside of this function. Global state
  -- mutations are hard to debug and test, so having them in a single
  -- function/module makes it easier to reason about all possible changes
  M.options = with_defaults(options or {})

  -- TODO (sbadragan): should these be just top level things?
  M.namespace = vim.api.nvim_create_namespace('grug-far.nvim')
  M.extmarkIds = {}

  vim.api.nvim_create_user_command("GrugFar", M.grugFar, {})
end

function M.is_configured()
  return M.options ~= nil
end

-- TODO (sbadragan): implemment g?
local function renderHelp(params)
  local buf = params.buf
  local helpLine = unpack(vim.api.nvim_buf_get_lines(buf, 0, 1, false))
  if #helpLine ~= 0 then
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "" })
  end

  local helpExtmarkPos = M.extmarkIds.help and
    vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, M.extmarkIds.help, {}) or {}
  if helpExtmarkPos[1] ~= 0 then
    M.extmarkIds.help = vim.api.nvim_buf_set_extmark(buf, M.namespace, 0, 0, {
      id = M.extmarkIds.help,
      end_row = 0,
      end_col = 0,
      virt_text = {
        { "Press g? for help", 'Comment' }
      },
      virt_text_pos = 'overlay'
    })
  end
end

-- TODO (sbadragan): move to another module
local uv = vim.loop
local function setTimeout(callback, timeout)
  local timer = uv.new_timer()
  timer:start(timeout, 0, function()
    timer:stop()
    timer:close()
    vim.schedule(callback)
  end)
  return timer
end

local function clearTimeout(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function debounce(callback, timeout)
  local timer
  return function(params)
    clearTimeout(timer)
    timer = setTimeout(function()
      callback(params)
    end, timeout)
  end
end

local function renderResultList(params)
  params.on_start()

  local inputs = params.inputs

  -- TODO (sbadragan): use uv.spawn() to spawn rg process with
  -- rg local --replace=bob --context=1 --heading --json --glob='*.md' ./
  params.on_fetch_chunk("------- dummy results")
  params.on_fetch_chunk("------- more results")
  P(vim.inspect(inputs))
end

-- TODO (sbadragan): make debounce timeout configurable
local asyncRenderResultList = debounce(renderResultList, 500)

local function renderResults(params)
  local buf = params.buf
  local minLineNr = params.minLineNr

  local headerRow = unpack(M.extmarkIds.results_header and
    vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, M.extmarkIds.results_header, {}) or {})
  local newHeaderRow = nil
  if headerRow == nil or headerRow < minLineNr then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for _ = #lines, minLineNr do
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
    end

    newHeaderRow = minLineNr
  end

  -- TODO (sbadragan): maybe show some sort of search status in the virt lines ?
  -- like a clock or a checkmark when replacment has been done?
  -- show some sort of total ?
  if newHeaderRow ~= nil then
    M.extmarkIds.results_header = vim.api.nvim_buf_set_extmark(buf, M.namespace, newHeaderRow, 0, {
      id = M.extmarkIds.results_header,
      end_row = newHeaderRow,
      end_col = 0,
      virt_lines = {
        { { " 󱎸 ──────────────────────────────────────────────────────────", 'SpecialComment' } },
      },
      virt_lines_leftcol = true,
      virt_lines_above = true,
      right_gravity = false
    })
  end

  -- TODO (sbadragan): need to figure out params
  asyncRenderResultList({
    inputs = params.inputs,
    on_start = function()
      -- remove all lines after heading
      P(newHeaderRow)
      vim.api.nvim_buf_set_lines(buf, newHeaderRow or headerRow, -1, false, {})
    end,
    on_fetch_chunk = function(chunk)
      P(chunk)
      -- TODO (sbadragan): might need some sort of wrapper
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { chunk })
    end
  })
end

local function renderInput(params)
  local buf = params.buf
  local lineNr = params.lineNr
  local extmarkName = params.extmarkName
  local label_virt_lines = params.label_virt_lines

  local line = unpack(vim.api.nvim_buf_get_lines(buf, lineNr, lineNr + 1, false))
  if line == nil then
    vim.api.nvim_buf_set_lines(buf, lineNr, lineNr, false, { "" })
  end

  if label_virt_lines then
    local labelExtmarkName = extmarkName .. "_label"
    local labelExtmarkPos = M.extmarkIds[labelExtmarkName] and
      vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, M.extmarkIds[labelExtmarkName], {}) or {}
    if labelExtmarkPos[1] ~= lineNr then
      M.extmarkIds[labelExtmarkName] = vim.api.nvim_buf_set_extmark(buf, M.namespace, lineNr, 0, {
        id = M.extmarkIds[labelExtmarkName],
        end_row = lineNr,
        end_col = 0,
        virt_lines = label_virt_lines,
        virt_lines_leftcol = true,
        virt_lines_above = true,
        right_gravity = false
      })
    end
  end

  return line or ""
end

local function onBufferChange(params)
  local buf = params.buf
  local inputs = {}

  renderHelp({ buf = buf })
  inputs.search = renderInput({
    buf = buf,
    lineNr = 1,
    extmarkName = "search",
    label_virt_lines = {
      { { "  Search", 'DiagnosticInfo' } },
    },
  })
  inputs.replacement = renderInput({
    buf = buf,
    lineNr = 2,
    extmarkName = "replace",
    label_virt_lines = {
      { { "  Replace", 'DiagnosticInfo' } },
    },
  })
  inputs.filesGlob = renderInput({
    buf = buf,
    lineNr = 3,
    extmarkName = "files_glob",
    label_virt_lines = {
      { { " 󱪣 Files Glob", 'DiagnosticInfo' } },
    },
  })
  inputs.flags = renderInput({
    buf = buf,
    lineNr = 4,
    extmarkName = "flags",
    label_virt_lines = {
      { { "  Flags", 'DiagnosticInfo' } },
    },
  })
  renderResults({
    buf = buf,
    minLineNr = 6,
    inputs = inputs
  })
end

-- public API
function M.grugFar()
  if not M.is_configured() then
    return
  end

  -- create split buffer
  vim.cmd('vsplit')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'Grug Find and Replace')
  vim.api.nvim_win_set_buf(win, buf)

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = onBufferChange
  })

  -- TODO (sbadragan): remove
  -- try to keep all the heavy logic on pure functions/modules that do not
  -- depend on Neovim APIs. This makes them easy to test
  -- local greeting = my_cool_module.greeting(M.options.name)
  -- print(greeting)
end

M.options = nil
return M
