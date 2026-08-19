describe("preprocess.annotation", function()
  local annotation = require("gfm_preview.preprocess.annotation")

  local function make_deps(behavior)
    local captured = {}
    local deps = {
      cli = "/home/user/bin/lit-annotation",
      timeout_ms = 10000,
      captured = captured,
      run_cmd = function(argv, opts)
        captured.argv = argv
        captured.opts = opts
        if behavior == "delimited" then
          return { code = 0, stdout = '[{"body": "delimited body"}]' }
        elseif behavior == "bare" then
          return { code = 0, stdout = '[{"body": "bare body"}]' }
        elseif behavior == "nonzero" then
          return { code = 1, stdout = "" }
        elseif behavior == "bad_json" then
          return { code = 0, stdout = "not json" }
        elseif behavior == "multi" then
          return { code = 0, stdout = '[{"body": "one"}, {"body": "two"}]' }
        elseif behavior == "no_body" then
          return { code = 0, stdout = '[{"other": 1}]' }
        elseif behavior == "timeout" then
          return { code = "timeout", stdout = "" }
        elseif behavior == "missing" then
          return { code = "missing", stdout = "" }
        end
        error("unknown behavior " .. tostring(behavior))
      end,
    }
    return deps
  end

  it("extracts the body of a delimited annotation using --pretty", function()
    local deps = make_deps("delimited")
    local input = "  <!--- some annotation --->  "
    assert.are.equal("delimited body", annotation.extract_body(input, deps))
    assert.are.same({ "/home/user/bin/lit-annotation", "--pretty" }, deps.captured.argv)
    assert.are.equal("<!--- some annotation --->", deps.captured.opts.stdin)
    assert.are.equal(10000, deps.captured.opts.timeout)
  end)

  it("extracts the body of a bare annotation using --bare --pretty", function()
    local deps = make_deps("bare")
    assert.are.equal("bare body", annotation.extract_body("just text", deps))
    assert.are.same({ "/home/user/bin/lit-annotation", "--bare", "--pretty" }, deps.captured.argv)
  end)

  it("returns the original text when the CLI exits nonzero", function()
    local deps = make_deps("nonzero")
    local input = "<!--- x --->"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)

  it("returns the original text on malformed JSON output", function()
    local deps = make_deps("bad_json")
    local input = "text"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)

  it("returns the original text when multiple annotations are returned", function()
    local deps = make_deps("multi")
    local input = "text"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)

  it("returns the original text when the annotation has no body key", function()
    local deps = make_deps("no_body")
    local input = "text"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)

  it("returns the original text on timeout", function()
    local deps = make_deps("timeout")
    local input = "text"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)

  it("returns the original text when the CLI is missing", function()
    local deps = make_deps("missing")
    local input = "text"
    assert.are.equal(input, annotation.extract_body(input, deps))
  end)
end)
