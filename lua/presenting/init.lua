--- *presenting.nvim*
--- *Presenting*
---
--- MIT License Copyright (c) 2024 Stefan Otte
---
--- ==============================================================================
---
--- Present your markdown, org-mode, or asciidoc files in a nice way,
--- i.e. directly in nvim.

local Presenting = {}
local H = {}
Presenting._state = nil

--- Module setup
---
---@param config table|nil
---@usage `require('presenting').setup({})`
Presenting.setup = function(config)
  _G.Presenting = Presenting
  config = H.setup_config(config)
  H.apply_config(config)

  vim.api.nvim_create_user_command("Presenting", Presenting.toggle, {})
  vim.api.nvim_create_user_command(
    "PresentingGoto",
    function(opts) Presenting.goto_slide(tonumber(opts.args)) end,
    { nargs = 1, complete = "number" }
  )
  vim.api.nvim_create_user_command("PresentingOverview", Presenting.overview, {})
  vim.api.nvim_create_user_command("PresentingDevMode", Presenting.dev_mode, {})

  local augroup = vim.api.nvim_create_augroup("PresentingAutoGroup", {})
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function() Presenting.resize() end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*",
    callback = function(args)
      if H.in_presenting_mode() and args.buf == Presenting._state.source_buf then
        H.reload_slides()
      end
    end,
  })
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
Presenting.config = {
  options = {
    width = 60,
    height = nil,
    vertical_center = true,
    horizontal_center = true,
    show_notes = true,
    notes_height = 5,
  },
  separator = {
    markdown = "^#+ ",
    org = "^*+ ",
    adoc = "^==+ ",
    asciidoctor = "^==+ ",
  },
  notes_open = "^:::%s*notes",
  notes_close = "^:::%s*$",
  keep_separator = true,
  parse_frontmatter = false,
  keymaps = {
    ["n"] = function() Presenting.next() end,
    ["p"] = function() Presenting.prev() end,
    ["q"] = function() Presenting.quit() end,
    ["f"] = function() Presenting.first() end,
    ["l"] = function() Presenting.last() end,
    ["g"] = function() Presenting.goto_prompt() end,
    ["o"] = function() Presenting.overview() end,
    ["<CR>"] = function() Presenting.next() end,
    ["<BS>"] = function() Presenting.prev() end,
  },
  configure_slide_buffer = function(buf) H.configure_slide_buffer(buf) end,
}

--- ==============================================================================
--- # Core functionality

Presenting.toggle = function(separator)
  if type(separator) == "table" then separator = nil end
  if H.in_presenting_mode() then
    Presenting.quit()
  else
    Presenting.start(separator)
  end
end

Presenting.start = function(separator)
  if H.in_presenting_mode() then
    vim.notify("Already presenting")
    return
  end

  if type(separator) == "table" then separator = nil end

  local filetype = vim.bo.filetype
  separator = separator or Presenting.config.separator[filetype]

  if separator == nil then
    vim.notify(
      "presenting.nvim does not support filetype "
        .. filetype
        .. ". You can specify a separator manually: Presenting.start('---')"
    )
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local parsed = H.parse_slides(lines, separator, Presenting.config.keep_separator)

  Presenting._state = {
    filetype = filetype,
    slides = parsed.slides,
    notes = parsed.notes,
    titles = parsed.titles,
    slide = 1,
    n_slides = #parsed.slides,
    slide_buf = nil,
    slide_win = nil,
    background_buf = nil,
    background_win = nil,
    footer_buf = nil,
    footer_win = nil,
    notes_buf = nil,
    notes_win = nil,
    source_buf = vim.api.nvim_get_current_buf(),
    view = nil,
  }

  H.create_slide_view(Presenting._state)
end

Presenting.quit = function()
  if not H.in_presenting_mode() then
    vim.notify("Not in presenting mode")
    return
  end
  local state = Presenting._state
  for _, key in ipairs({ "notes_buf", "slide_buf", "footer_buf", "background_buf" }) do
    if state[key] then pcall(vim.api.nvim_buf_delete, state[key], { force = true }) end
  end
  Presenting._state = nil
end

Presenting.next = function()
  if not H.in_presenting_mode() then return end
  H.set_slide_content(
    Presenting._state,
    math.min(Presenting._state.slide + 1, Presenting._state.n_slides)
  )
end

Presenting.prev = function()
  if not H.in_presenting_mode() then return end
  H.set_slide_content(Presenting._state, math.max(Presenting._state.slide - 1, 1))
end

Presenting.first = function()
  if not H.in_presenting_mode() then return end
  H.set_slide_content(Presenting._state, 1)
end

Presenting.last = function()
  if not H.in_presenting_mode() then return end
  H.set_slide_content(Presenting._state, Presenting._state.n_slides)
end

Presenting.goto_slide = function(n)
  if not H.in_presenting_mode() then return end
  n = math.max(1, math.min(n, Presenting._state.n_slides))
  H.set_slide_content(Presenting._state, n)
end

Presenting.goto_prompt = function()
  if not H.in_presenting_mode() then return end
  local input = vim.fn.input("Go to slide (1-" .. Presenting._state.n_slides .. "): ")
  if input == "" then return end
  local n = tonumber(input)
  if n then Presenting.goto_slide(n) end
end

Presenting.overview = function()
  if not H.in_presenting_mode() then return end
  local state = Presenting._state
  if state.n_slides == 0 then return end

  local items = {}
  for i = 1, state.n_slides do
    local title = state.titles[i] or "(no title)"
    table.insert(items, string.format("%3d: %s", i, title))
  end

  vim.ui.select(items, {
    prompt = "Select slide:",
    format_opts = { kind = "none" },
  }, function(choice)
    if choice then
      local n = tonumber(choice:match("%s*(%d+)"))
      if n then Presenting.goto_slide(n) end
    end
  end)
end

Presenting.resize = function()
  if not H.in_presenting_mode() then return end
  local state = Presenting._state
  if not state.background_win or not state.slide_win or not state.footer_win then return end

  local window_config = H.get_win_configs(state)
  vim.api.nvim_win_set_config(state.background_win, window_config.background)
  vim.api.nvim_win_set_config(state.footer_win, window_config.footer)
  vim.api.nvim_win_set_config(state.slide_win, window_config.slide)
  if state.notes_win then vim.api.nvim_win_set_config(state.notes_win, window_config.notes) end
  H.set_slide_content(state, state.slide)
end

Presenting.dev_mode = function()
  package.loaded["presenting"] = nil
  _G.Presenting = nil
  require("presenting").start()
end

--- ==============================================================================
--- Internal Helpers

H.default_config = vim.deepcopy(Presenting.config)

H.setup_config = function(config)
  vim.validate({ config = { config, "table", true } })
  return vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})
end

H.apply_config = function(config) Presenting.config = config end

---@param state table|nil
---@return table
H.get_win_configs = function(state)
  state = state or Presenting._state
  local slide_width = Presenting.config.options.width
  local width = vim.o.columns
  local height = vim.o.lines
  local offset = math.ceil((width - slide_width) / 2)

  local notes_h = 0
  if state and state.slide and Presenting.config.options.show_notes then
    local notes_text = state.notes and state.notes[state.slide]
    if notes_text then
      notes_h = math.min(#vim.split(notes_text, "\n"), Presenting.config.options.notes_height)
    end
  end

  local slide_height = Presenting.config.options.height or (height - 5 - notes_h)

  return {
    background = {
      style = "minimal",
      relative = "editor",
      focusable = false,
      width = width,
      height = height,
      row = 0,
      col = 0,
      zindex = 1,
    },
    slide = {
      style = "minimal",
      relative = "editor",
      width = slide_width,
      height = slide_height,
      row = 0,
      col = offset,
      zindex = 10,
    },
    footer = {
      style = "minimal",
      relative = "editor",
      width = slide_width,
      height = 1,
      row = height - 1,
      col = offset,
      focusable = false,
      zindex = 2,
    },
    notes = {
      style = "minimal",
      relative = "editor",
      width = slide_width,
      height = notes_h,
      row = slide_height,
      col = offset,
      focusable = false,
      zindex = 5,
    },
  }
end

H.create_slide_view = function(state)
  local window_config = H.get_win_configs(state)

  state.background_buf = vim.api.nvim_create_buf(false, true)
  state.background_win =
    vim.api.nvim_open_win(state.background_buf, false, window_config.background)

  state.footer_buf = vim.api.nvim_create_buf(false, true)
  state.footer_win = vim.api.nvim_open_win(state.footer_buf, false, window_config.footer)

  state.slide_buf = vim.api.nvim_create_buf(false, true)
  state.slide_win = vim.api.nvim_open_win(state.slide_buf, true, window_config.slide)
  Presenting.config.configure_slide_buffer(state.slide_buf)
  H.set_slide_keymaps(state.slide_buf, Presenting.config.keymaps)

  state.notes_buf = vim.api.nvim_create_buf(false, true)
  state.notes_win = vim.api.nvim_open_win(state.notes_buf, false, window_config.notes)
  vim.bo[state.notes_buf].buftype = "nofile"
  vim.bo[state.notes_buf].bufhidden = "wipe"
  vim.bo[state.notes_buf].modifiable = false

  H.set_slide_content(state, 1)
end

---@param lines table
---@param separator string
---@param keep_separator boolean
---@return table
H.parse_slides = function(lines, separator, keep_separator)
  if Presenting.config.parse_frontmatter then
    local in_frontmatter = false
    local new_lines = {}
    local frontmatter_found = 0
    for _, line in ipairs(lines) do
      if line:match("^%-%-%-%s*$") then
        frontmatter_found = frontmatter_found + 1
        if frontmatter_found == 1 then
          in_frontmatter = true
        elseif frontmatter_found == 2 then
          in_frontmatter = false
          goto continue
        end
        goto continue
      end
      if not in_frontmatter then table.insert(new_lines, line) end
      ::continue::
    end
    lines = new_lines
    while lines[1] and lines[1]:match("^%s*$") do
      table.remove(lines, 1)
    end
  end

  local raw_slides = {}
  local slide = {}
  for _, line in ipairs(lines) do
    if line:match(separator) then
      if #slide > 0 then
        table.insert(raw_slides, slide)
        slide = {}
      elseif #raw_slides == 0 then
        if keep_separator then table.insert(slide, line) end
        goto continue
      end
      if keep_separator then table.insert(slide, line) end
    else
      table.insert(slide, line)
    end
    ::continue::
  end
  if #slide > 0 then table.insert(raw_slides, slide) end

  local slides = {}
  local notes = {}
  local titles = {}
  local notes_open = Presenting.config.notes_open
  local notes_close = Presenting.config.notes_close
  local has_notes_markers = notes_open and notes_close

  for _, slide_lines in ipairs(raw_slides) do
    local content_lines = {}
    local note_lines = {}
    local in_note = false
    local added_title = false

    for _, line in ipairs(slide_lines) do
      if has_notes_markers then
        if line:match(notes_open) then
          in_note = true
          goto continue2
        end
        if line:match(notes_close) then
          in_note = false
          goto continue2
        end
      end

      if in_note then
        table.insert(note_lines, line)
      else
        if not added_title and not line:match("^%s*$") then
          titles[#titles + 1] =
            line:gsub("^#+%s*", ""):gsub("^%*+%s*", ""):gsub("^=+%s*", ""):gsub("^%s+", "")
          added_title = true
        end
        table.insert(content_lines, line)
      end
      ::continue2::
    end

    table.insert(slides, table.concat(content_lines, "\n"))
    table.insert(notes, #note_lines > 0 and table.concat(note_lines, "\n") or nil)
    if not added_title then table.insert(titles, nil) end
  end

  return { slides = slides, notes = notes, titles = titles }
end
Presenting._parse_slides = H.parse_slides

H.configure_slide_buffer = function(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = Presenting._state.filetype
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
end

H.set_slide_content = function(state, slide)
  state.slide = slide
  local raw_lines = vim.split(state.slides[slide], "\n")

  if Presenting.config.options.vertical_center then
    local win_height = vim.api.nvim_win_get_height(state.slide_win)
    local padding = math.max(0, math.floor((win_height - #raw_lines) / 2))
    for _ = 1, padding do
      table.insert(raw_lines, 1, "")
    end
  end

  if Presenting.config.options.horizontal_center then
    for i, line in ipairs(raw_lines) do
      if line ~= "" then
        local trimmed = line:match("^%s*(.-)%s*$")
        local pad = math.floor((Presenting.config.options.width - #trimmed) / 2)
        if pad > 0 then raw_lines[i] = string.rep(" ", pad) .. trimmed end
      end
    end
  end

  local orig_modifiable = vim.bo[state.slide_buf].modifiable
  vim.bo[state.slide_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.slide_buf, 0, -1, false, raw_lines)
  vim.bo[state.slide_buf].modifiable = orig_modifiable

  H.update_footer(state)
  H.update_notes(state)
end

H.update_footer = function(state)
  local bar_width = 12
  local fraction = state.slide / state.n_slides
  local filled = math.floor(fraction * bar_width)
  local bar = string.rep("█", filled) .. string.rep("░", bar_width - filled)
  local text = string.format("%s | %s %d/%d", "presenting.nvim", bar, state.slide, state.n_slides)
  vim.api.nvim_buf_set_lines(state.footer_buf, 0, -1, false, { text })
end

H.update_notes = function(state)
  if not Presenting.config.options.show_notes then
    if state.notes_win and vim.api.nvim_win_is_valid(state.notes_win) then
      vim.api.nvim_win_set_config(state.notes_win, { height = 0 })
    end
    return
  end

  local notes_text = state.notes and state.notes[state.slide]
  if not notes_text then
    if state.notes_win and vim.api.nvim_win_is_valid(state.notes_win) then
      vim.api.nvim_win_set_config(state.notes_win, { height = 0 })
    end
    return
  end

  local note_lines = vim.split(notes_text, "\n")

  local orig_modifiable = vim.bo[state.notes_buf].modifiable
  vim.bo[state.notes_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.notes_buf, 0, -1, false, note_lines)
  vim.bo[state.notes_buf].modifiable = orig_modifiable

  if state.notes_win and vim.api.nvim_win_is_valid(state.notes_win) then
    local config = H.get_win_configs(state)
    vim.api.nvim_win_set_config(state.notes_win, config.notes)
  end
end

H.set_slide_keymaps = function(buf, mappings)
  for k, v in pairs(mappings) do
    if type(v) == "string" then
      vim.keymap.set(
        "n",
        k,
        "<cmd>lua require('presenting')." .. v .. "()<CR>",
        { buffer = buf, noremap = true, silent = true }
      )
    elseif type(v) == "function" then
      vim.keymap.set("n", k, v, { buffer = buf, noremap = true, silent = true })
    end
  end
end

H.in_presenting_mode = function() return Presenting._state ~= nil end

H.reload_slides = function()
  local state = Presenting._state
  local source_buf = state.source_buf
  if not vim.api.nvim_buf_is_valid(source_buf) then return end

  local filetype = vim.bo[source_buf].filetype
  local separator = Presenting.config.separator[filetype] or state.separator
  local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  local parsed = H.parse_slides(lines, separator, Presenting.config.keep_separator)

  state.filetype = filetype
  state.slides = parsed.slides
  state.notes = parsed.notes
  state.titles = parsed.titles
  state.n_slides = #parsed.slides
  state.slide = math.min(state.slide, state.n_slides)

  H.set_slide_content(state, state.slide)
end

return Presenting
