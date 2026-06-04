local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_slides splits markdown by headings"] = function()
  local lines = { "# Slide 1", "content a", "", "# Slide 2", "content b" }
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#result.slides, 2)
  eq(string.match(result.slides[1], "# Slide 1"), "# Slide 1")
  eq(string.match(result.slides[1], "content a"), "content a")
  eq(string.match(result.slides[2], "# Slide 2"), "# Slide 2")
  eq(string.match(result.slides[2], "content b"), "content b")
end

T["parse_slides keeps separator when configured"] = function()
  local lines = { "# A", "x", "# B", "y" }
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(string.match(result.slides[1], "^# A"), "# A")
  eq(string.match(result.slides[2], "^# B"), "# B")
end

T["parse_slides strips separator when keep_separator is false"] = function()
  local lines = { "---", "x", "---", "y" }
  local result = require("presenting")._parse_slides(lines, "^---$", false)
  eq(string.match(result.slides[1], "^x$"), "x")
  eq(string.match(result.slides[2], "^y$"), "y")
end

T["parse_slides extracts titles from first non-blank line"] = function()
  local lines = { "## Slide One", "body", "# Slide Two", "more" }
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#result.titles, 2)
  eq(result.titles[1], "Slide One")
  eq(result.titles[2], "Slide Two")
end

T["parse_slides strips frontmatter when configured"] = function()
  local lines = { "---", "key: val", "---", "# Slide", "content" }
  local orig = require("presenting").config.parse_frontmatter
  require("presenting").config.parse_frontmatter = true
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  require("presenting").config.parse_frontmatter = orig
  eq(#result.slides, 1)
  eq(string.match(result.slides[1], "# Slide"), "# Slide")
end

T["parse_slides extracts notes blocks"] = function()
  local lines = {
    "# Slide",
    "content",
    "::: notes",
    "note line 1",
    "note line 2",
    ":::",
    "more content",
  }
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#result.slides, 1)
  eq(string.match(result.slides[1], "note line"), nil)
  eq(result.notes[1], "note line 1\nnote line 2")
end

T["parse_slides handles empty content"] = function()
  local result = require("presenting")._parse_slides({}, "^#+ ", true)
  eq(#result.slides, 0)
  eq(#result.notes, 0)
  eq(#result.titles, 0)
end

T["parse_slides handles single slide with no separator"] = function()
  local lines = { "just", "some", "text" }
  local result = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#result.slides, 1)
  eq(result.slides[1], "just\nsome\ntext")
end

return T
