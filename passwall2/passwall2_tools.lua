module("luci.controller.passwall2_tools", package.seeall)

function index()
    -- Ini akan menambah tab "Autoswitch" di bawah menu Passwall2
    entry({"admin", "services", "passwall2", "autoswitch"}, cbi("passwall2/autoswitch"), _("Autoswitch"), 55).leaf = true
end
