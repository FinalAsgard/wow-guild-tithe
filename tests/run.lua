package.path = "./?.lua;./?/init.lua;" .. package.path

local test = require("tests.test_helper")

require("tests.spec.command_router_spec")
require("tests.spec.accounting_spec")
require("tests.spec.character_state_spec")
require("tests.spec.client_profile_spec")
require("tests.spec.client_integration_spec")
require("tests.spec.income_spec")
require("tests.spec.income_correlator_spec")
require("tests.spec.income_quest_vendor_spec")
require("tests.spec.income_mail_spec")
require("tests.spec.income_trade_exclusion_spec")
require("tests.spec.income_feedback_spec")
require("tests.spec.trace_replay_spec")
require("tests.spec.tithe_payment_spec")
require("tests.spec.event_trace_spec")
require("tests.spec.lifecycle_spec")
require("tests.spec.money_formatter_spec")
require("tests.spec.persistence_spec")
require("tests.spec.settings_controller_spec")
require("tests.spec.bootstrap_spec")

if not test.run() then
    os.exit(1)
end
