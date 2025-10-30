module("luci.controller.sshws", package.seeall)

function index()
    -- Daftarkan entri menu di bawah 'Services'
    entry({"admin", "services", "sshws"}, call("action_sshws"), _("SSHWS Tunnel"), 100).leaf = true
end

function action_sshws()
    local fs = require "nixio.fs"
    local json = require "luci.jsonc"
    local sys = require "luci.sys"
    local http = require "luci.http"

    local config_path = "/root/config.json"
    local cfg = {}
    local message = nil

    -- Baca konfigurasi semasa dari config.json
    if fs.access(config_path) then
        local content = fs.readfile(config_path)
        if content and content ~= "" then
            -- Cuba parse JSON. Guna jsonc.parse yang lebih toleran jika ada komen.
            cfg = json.parse(content) or {}
        end
    end
    
    -- Pastikan struktur SSH wujud untuk mengelakkan ralat jika cfg kosong
    if not cfg.ssh then
        cfg.ssh = {}
    end

    -- Mengendalikan tindakan butang
    if http.formvalue("action") == "reload" then
        -- Muat semula halaman
        http.redirect(luci.dispatcher.build_url("admin/services/sshws"))
        return
        
    elseif http.formvalue("action") == "save" then
        -- Update JSON fields dari form (borang)
        local newcfg = {
            mode = http.formvalue("mode") or "proxy",
            proxyHost = http.formvalue("proxyHost") or "",
            
            -- PENTING: Kekalkan proxyPort sebagai STRING ("80")
            proxyPort = http.formvalue("proxyPort") or "80", 
            
            ssh = {
                host = http.formvalue("ssh_host") or "",
                -- port kekal sebagai nombor (integer)
                port = tonumber(http.formvalue("ssh_port")) or 22, 
                username = http.formvalue("ssh_username") or "",
                password = http.formvalue("ssh_password") or ""
            },
            httpPayload = http.formvalue("httpPayload") or "",
            -- connectionTimeout kekal sebagai nombor (integer)
            connectionTimeout = tonumber(http.formvalue("connectionTimeout")) or 30
        }
        
        -- ⭐ PERUBAHAN KRITIKAL: Guna json.stringify(newcfg) tanpa parameter 'true'
        -- Ini menghasilkan JSON yang dirapatkan (minified) tanpa indentation/spacing
        -- yang menyebabkan masalah dengan binari Go.
        fs.writefile(config_path, json.stringify(newcfg))
        
        cfg = newcfg -- Update cfg untuk paparan borang seterusnya
        message = "✅ Konfigurasi disimpan ke /root/config.json"
        
    elseif http.formvalue("action") == "start" then
        -- Mulakan/Restart perkhidmatan sshws
        sys.call("/etc/init.d/sshws restart >/dev/null 2>&1 &")
        message = "🟢 SSHWS dimulakan"
        
    elseif http.formvalue("action") == "stop" then
        -- Hentikan perkhidmatan sshws
        sys.call("/etc/init.d/sshws stop >/dev/null 2>&1 &")
        message = "🔴 SSHWS dihentikan"
    end

    -- Paparkan borang konfigurasi
    luci.template.render("sshws", { cfg = cfg, message = message })
end
