module("luci.controller.fibocom", package.seeall)

function index()
    entry({"admin", "network", "fibocom"}, call("action_gui"), _("Fibocom Modem"), 99).dependent = true
    entry({"admin", "network", "fibocom", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "network", "fibocom", "set_band"}, call("action_set_band"), nil).leaf = true
    entry({"admin", "network", "fibocom", "at_cmd"}, call("action_at_cmd"), nil).leaf = true
end

function action_data()
    local u = require "luci.util"
    local h = require "luci.http"
    local j = require "luci.jsonc"
    
    local res_raw = u.exec("python3 /usr/bin/fibocom_modem.py status")
    local res = j.parse(res_raw) or { error = "Failed to parse Python output" }
    
    h.prepare_content("application/json")
    h.write_json(res)
end

function action_set_band()
    local u = require "luci.util"
    local h = require "luci.http"
    local bands = h.formvalue("bands")
    
    if bands then
        local res = u.exec("python3 /usr/bin/fibocom_modem.py set_band " .. u.shellquote(bands))
        h.prepare_content("text/plain")
        h.write(res)
    else
        h.status(400, "Missing bands")
    end
end

function action_at_cmd()
    local u = require "luci.util"
    local h = require "luci.http"
    local cmd = h.formvalue("cmd")
    
    if cmd then
        local res = u.exec("python3 /usr/bin/fibocom_modem.py cmd " .. u.shellquote(cmd))
        h.prepare_content("text/plain")
        h.write(res)
    else
        h.status(400, "Missing command")
    end
end

function action_gui()
    luci.template.render("fibocom_status")
end
