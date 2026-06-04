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
  vim.api.nvim_create_user_command("PresentingDevMode", Presenting.dev_mode, {})

  local augroup = vim.api.nvim_create_augroup("PresentingAutoGroup", {})
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function() Presenting.resize() end,
  })
end

--- Module config
---
--- Default values:
---@eval return MiniDoc.afterlines_to_code(MiniDoc.current.eval_section)
Presenting.config = {
  options = {
    width = 60,
  },
  separator = {
    markdown = "^#+ ",
    org = "^*+ ",
    adoc = "^==+ ",
    asciidoctor = "^==+ ",
  },
  keep_separator = true,
  parse_frontmatter = false,
  keymaps = {
    ["n"] = function() Presenting.next() end,
    ["p"] = function() Presenting.prev() end,
    ["q"] = function() Presenting.quit() end,
    ["f"] = function() Presenting.first() end,
    ["l"] = function() Presenting.last() end,
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
  local slides = H.parse_slides(lines, separator, Presenting.config.keep_separator)

  Presenting._state = {
    filetype = filetype,
    slides = slides,
    slide = 1,
    n_slides = #slides,
    slide_buf = nil,
    slide_win = nil,
    background_buf = nil,
    background_win = nil,
    footer_buf = nil,
    footer_win = nil,
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
  for _, key in ipairs({ "slide_buf", "footer_buf", "background_buf" }) do
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

Presenting.resize = function()
  if not H.in_presenting_mode() then return end
  local state = Presenting._state
  if not state.background_win or not state.slide_win or not state.footer_win then return end

  local window_config = H.get_win_configs()
  vim.api.nvim_win_set_config(state.background_win, window_config.background)
  vim.api.nvim_win_set_config(state.footer_win, window_config.footer)
  vim.api.nvim_win_set_config(state.slide_win, window_config.slide)
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

---@return table
H.get_win_configs = function()
  local slide_width = Presenting.config.options.width
  local width = vim.o.columns
  local height = vim.o.lines
  local offset = math.ceil((width - slide_width) / 2)
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
      height = height - 5,
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
  }
end

H.create_slide_view = function(state)
  local window_config = H.get_win_configs()

  state.background_buf = vim.api.nvim_create_buf(false, true)
  state.background_win =
    vim.api.nvim_open_win(state.background_buf, false, window_config.background)

  state.footer_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(state.footer_buf, 0, -1, false, { "presenting.nvim" })
  state.footer_win = vim.api.nvim_open_win(state.footer_buf, false, window_config.footer)

  state.slide_buf = vim.api.nvim_create_buf(false, true)
  state.slide_win = vim.api.nvim_open_win(state.slide_buf, true, window_config.slide)
  Presenting.config.configure_slide_buffer(state.slide_buf)
  H.set_slide_keymaps(state.slide_buf, Presenting.config.keymaps)

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

  local slides = {}
  local slide = {}
  for _, line in ipairs(lines) do
    if line:match(separator) then
      if #slide > 0 then
        table.insert(slides, table.concat(slide, "\n"))
      elseif #slides == 0 then
        if keep_separator then table.insert(slide, line) end
        goto continue
      end
      slide = {}
      if keep_separator then table.insert(slide, line) end
    else
      table.insert(slide, line)
    end
    ::continue::
  end
  if #slide > 0 then table.insert(slides, table.concat(slide, "\n")) end

  return slides
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
  local lines = vim.split(state.slides[slide], "\n")

  local orig_modifiable = vim.bo[state.slide_buf].modifiable
  vim.bo[state.slide_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.slide_buf, 0, -1, false, lines)
  vim.bo[state.slide_buf].modifiable = orig_modifiable

  local footer_text = "presenting.nvim | " .. state.slide .. "/" .. state.n_slides
  vim.api.nvim_buf_set_lines(state.footer_buf, 0, -1, false, { footer_text })
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

return Presenting
