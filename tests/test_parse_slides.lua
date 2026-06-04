local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["parse_slides splits markdown by headings"] = function()
  local lines = { "# Slide 1", "content a", "", "# Slide 2", "content b" }
  local slides = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#slides, 2)
  eq(string.match(slides[1], "# Slide 1"), "# Slide 1")
  eq(string.match(slides[1], "content a"), "content a")
  eq(string.match(slides[2], "# Slide 2"), "# Slide 2")
  eq(string.match(slides[2], "content b"), "content b")
end

T["parse_slides keeps separator when configured"] = function()
  local lines = { "# A", "x", "# B", "y" }
  local slides = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(string.match(slides[1], "^# A"), "# A")
  eq(string.match(slides[2], "^# B"), "# B")
end

T["parse_slides strips separator when keep_separator is false"] = function()
  local lines = { "---", "x", "---", "y" }
  local slides = require("presenting")._parse_slides(lines, "^---$", false)
  eq(string.match(slides[1], "^x$"), "x")
  eq(string.match(slides[2], "^y$"), "y")
end

T["parse_slides strips frontmatter when configured"] = function()
  local lines = { "---", "key: val", "---", "# Slide", "content" }
  local orig = require("presenting").config.parse_frontmatter
  require("presenting").config.parse_frontmatter = true
  local slides = require("presenting")._parse_slides(lines, "^#+ ", true)
  require("presenting").config.parse_frontmatter = orig
  eq(#slides, 1)
  eq(string.match(slides[1], "# Slide"), "# Slide")
end

T["parse_slides handles empty content"] = function()
  local slides = require("presenting")._parse_slides({}, "^#+ ", true)
  eq(#slides, 0)
end

T["parse_slides handles single slide with no separator"] = function()
  local lines = { "just", "some", "text" }
  local slides = require("presenting")._parse_slides(lines, "^#+ ", true)
  eq(#slides, 1)
  eq(slides[1], "just\nsome\ntext")
end

return T
