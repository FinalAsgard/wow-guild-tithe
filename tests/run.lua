package.path = "./?.lua;./?/init.lua;" .. package.path

local test = require("tests.test_helper")

require("tests.spec.command_router_spec")
require("tests.spec.lifecycle_spec")

if not test.run() then
    os.exit(1)
end
