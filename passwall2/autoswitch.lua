local m, s, o
local api = require "luci.passwall2.api"
local i18n = require "luci.i18n"
local fs = require "nixio.fs"

m = Map("autoswitch", i18n.translate("Auto Switch"), i18n.translate("By Raducksijaa"))

s = m:section(TypedSection, "global", i18n.translate("Failover Setting"))
s.anonymous = true

-- Status Semasa
local current_node_id = api.uci:get("passwall2", "@global[0]", "node") or "None"
local current_remarks = "Unknown"
if current_node_id ~= "None" then
    current_remarks = api.uci:get("passwall2", current_node_id, "remarks") or current_node_id
end

o = s:option(DummyValue, "_current", i18n.translate("Node Aktif Sekarang"))
o.value = current_remarks
o.description = "ID: " .. current_node_id

o = s:option(Flag, "enabled", i18n.translate("Aktifkan Autoswitch"))
o.rmempty = false

o = s:option(Value, "fail_threshold", i18n.translate("Had Kegagalan Ping"))
o.default = "3"
o.datatype = "uinteger"

o = s:option(ListValue, "mode", i18n.translate("Mode Failover"))
o:value("dynamic_vless", i18n.translate("Dynamic (All VLESS)"))
o:value("specific", i18n.translate("Specific Node"))
o.default = "dynamic_vless"

o = s:option(ListValue, "backup_node", i18n.translate("Choose Node Failover"))
o:depends("mode", "specific")
api.uci:foreach("passwall2", "nodes", function(n)
    if n.remarks and n.protocol == "vless" then
        o:value(n[".name"], n.remarks)
    end
end)

--- BOX WATCH LOG ---
s = m:section(TypedSection, "global", i18n.translate("Auto Switch Log"))
s.anonymous = true

o = s:option(TextValue, "log_view")
o.readonly = true
o.rows = 10
o.cfgvalue = function(self, section)
    return fs.readfile("/var/log/autoswitch.log") or i18n.translate("No Log Found!!, Makesure script running!!.")
end

return m
