describe("browser", function()
  local browser = require("gfm_preview.browser")

  it("opens a file:// URL for the given path", function()
    local opened
    local deps = {
      open_url = function(url)
        opened = url
      end,
    }
    browser.open("/tmp/foo/preview.html", deps)
    assert.are.equal("file:///tmp/foo/preview.html", opened)
  end)

  it("propagates the open_url result", function()
    local deps = {
      open_url = function()
        return "ok"
      end,
    }
    assert.are.equal("ok", browser.open("/tmp/x.html", deps))
  end)
end)
