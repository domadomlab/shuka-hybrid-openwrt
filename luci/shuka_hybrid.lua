module("luci.controller.shuka_hybrid", package.seeall)

function index()
    entry({"admin", "services", "shuka"}, call("action_gui"), "Shuka VPN", 60)
    entry({"admin", "services", "shuka", "sync"}, call("action_sync"), nil).leaf = true
    entry({"admin", "services", "shuka", "clear_sub"}, call("action_clear_sub"), nil).leaf = true
    entry({"admin", "services", "shuka", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "shuka", "select"}, call("action_select"), nil).leaf = true
    entry({"admin", "services", "shuka", "delete"}, call("action_delete"), nil).leaf = true
    entry({"admin", "services", "shuka", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "shuka", "stop"}, call("action_stop"), nil).leaf = true
    entry({"admin", "services", "shuka", "amnezia_upload"}, call("action_amnezia_upload"), nil).leaf = true
end

function action_data()
    local util = require "luci.util"; local http = require "luci.http"; local json = require "luci.jsonc"; local fs = require "nixio.fs"
    local state = json.parse(util.exec("cat /etc/sing-box/state.json 2>/dev/null") or "{}") or {}
    local active_tag = state.active_tag or ""
    local is_sing = (util.exec("pgrep sing-box") ~= "")
    local handshake = tonumber(util.exec("awg show awg0 latest-handshakes 2>/dev/null | awk '{print $NF}'") or "0") or 0
    local is_awg = (handshake > 0)
    local rx, tx = "0", "0"
    if is_sing then rx = util.exec("cat /sys/class/net/tun-shuka/statistics/rx_bytes 2>/dev/null"); tx = util.exec("cat /sys/class/net/tun-shuka/statistics/tx_bytes 2>/dev/null")
    elseif is_awg then rx = util.exec("cat /sys/class/net/awg0/statistics/rx_bytes 2>/dev/null"); tx = util.exec("cat /sys/class/net/awg0/statistics/tx_bytes 2>/dev/null") end
    local ip = util.exec("curl -s --connect-timeout 2 ifconfig.me")
    if ip == "" then ip = "Offline" end
    local servers = {}
    local cfg = json.parse(util.exec("cat /etc/sing-box/config.json 2>/dev/null") or "{}")
    if cfg and cfg.outbounds then
        for _, o in ipairs(cfg.outbounds) do if o.type == "vless" or o.type == "shadowsocks" then table.insert(servers, {tag = o.tag, type = o.type}) end end
    end
    for f in (fs.dir("/etc/amneziawg/profiles/") or function() end) do if f:match("%.conf$") then table.insert(servers, {tag = f:gsub("%.conf$", ""), type = "amneziawg"}) end end
    http.prepare_content("application/json")
    http.write_json({ rx = rx, tx = tx, ip = ip, servers = servers, active_tag = active_tag, is_running = is_sing or is_awg, interface_up = (tonumber(rx or 0) or 0) > 0, syncing = (util.exec("pgrep -f '/usr/bin/shuka_manager.py sync'") ~= "") })
end

function action_gui()
    local util = require "luci.util"; local sub_url = util.exec("cat /etc/sing-box/sub_url.txt 2>/dev/null") or ""
    luci.http.prepare_content("text/html")
    luci.http.write([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Shuka Hybrid</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; color: #f1f5f9; padding: 20px; }
        .card { background: #1e293b; padding: 20px; border-radius: 12px; max-width: 800px; margin: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
        .stats { display: flex; gap: 10px; margin-bottom: 20px; }
        .stat { flex: 1; background: #0003; padding: 10px; border-radius: 8px; text-align: center; }
        .btn { padding: 8px 16px; border-radius: 6px; border: none; cursor: pointer; font-weight: bold; transition: 0.2s; }
        .btn-start { background: #38bdf8; color: #0f172a; }
        .btn-stop { background: #ef4444; color: #fff; }
        .btn-del { background: transparent; color: #ef4444; border: 1px solid #ef4444; padding: 2px 8px; font-size: 10px; margin-left: 10px; }
        .btn-clear { background: #ef444430; color: #ef4444; border: 1px solid #ef4444; width: 100%; margin-top: 5px; }
        .btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .list { background: #0003; border-radius: 8px; padding: 10px; max-height: 400px; overflow-y: auto; border: 1px solid #333; }
        .item { padding: 10px; margin-bottom: 5px; background: #ffffff05; border-radius: 6px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; border: 1px solid transparent; }
        .item:hover { background: #ffffff10; }
        .item.active { border-color: #38bdf8; background: #38bdf820; }
        .val { font-size: 18px; font-weight: bold; color: #38bdf8; }
        .spinner { display: inline-block; width: 12px; height: 12px; border: 2px solid #fff3; border-top-color: #fff; border-radius: 50%; animation: spin 1s linear infinite; vertical-align: middle; margin-right: 5px; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
    <script>
        function formatBytes(b) { b = parseInt(b) || 0; if (b > 1073741824) return (b / 1073741824).toFixed(2) + " GB"; if (b > 1048576) return (b / 1048576).toFixed(2) + " MB"; if (b > 1024) return (b / 1024).toFixed(2) + " KB"; return b + " B"; }
        function update() {
            fetch('shuka/data').then(r => r.json()).then(d => {
                document.getElementById('ip').textContent = d.ip;
                document.getElementById('status').textContent = d.interface_up ? 'ONLINE' : (d.is_running ? 'STARTING...' : 'OFFLINE');
                document.getElementById('status').style.color = d.interface_up ? '#22c55e' : (d.is_running ? '#f59e0b' : '#ef4444');
                document.getElementById('rx').textContent = formatBytes(d.rx); document.getElementById('tx').textContent = formatBytes(d.tx);
                
                const syncBtn = document.getElementById('sync-btn');
                if (d.syncing) { syncBtn.disabled = true; syncBtn.innerHTML = '<span class="spinner"></span> UPDATING...'; } 
                else { syncBtn.disabled = false; syncBtn.innerHTML = 'REFRESH'; }

                const list = document.getElementById('list'); list.innerHTML = '';
                d.servers.forEach(s => {
                    const div = document.createElement('div'); div.className = 'item' + (s.tag === d.active_tag ? ' active' : '');
                    const content = document.createElement('div'); content.style.flex = "1"; content.onclick = () => fetch('shuka/select?tag=' + encodeURIComponent(s.tag)).then(() => setTimeout(update, 1000));
                    content.innerHTML = '<span>' + (s.tag === d.active_tag ? '🟢 ' : '') + s.tag + '</span><br><small style="color:#94a3b8">' + s.type.toUpperCase() + '</small>';
                    div.appendChild(content);
                    if (s.type === 'amneziawg') {
                        const delBtn = document.createElement('button'); delBtn.className = 'btn-del'; delBtn.textContent = 'DEL';
                        delBtn.onclick = (e) => { e.stopPropagation(); if (confirm('Delete profile ' + s.tag + '?')) fetch('shuka/delete?tag=' + encodeURIComponent(s.tag)).then(() => update()); };
                        div.appendChild(delBtn);
                    }
                    list.appendChild(div);
                });
            });
        }
        function startSync() {
            const url = document.getElementById('url').value;
            fetch('shuka/sync?url=' + encodeURIComponent(url)).then(() => update());
        }
        setInterval(update, 3000); update();
    </script>
</head>
<body>
    <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center;">
            <h2>🚀 Shuka Hybrid</h2>
            <div>
                <button class="btn btn-start" onclick="location.href='shuka/start'">START</button>
                <button class="btn btn-stop" onclick="location.href='shuka/stop'">STOP</button>
            </div>
        </div>
        <div class="stats">
            <div class="stat"><small>IP</small><br><span class="val" id="ip">...</span></div>
            <div class="stat"><small>STATUS</small><br><span class="val" id="status">...</span></div>
            <div class="stat"><small>RX</small><br><span class="val" id="rx">0 B</span></div>
            <div class="stat"><small>TX</small><br><span class="val" id="tx">0 B</span></div>
        </div>
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:20px;">
            <div>
                <h4>SUBSCRIPTION</h4>
                <input type="text" id="url" style="width:100%; background:#0003; color:#fff; border:1px solid #333; padding:8px; border-radius:4px;" value="]]..sub_url..[[">
                <button id="sync-btn" class="btn btn-start" style="width:100%; margin-top:10px;" onclick="startSync()">REFRESH</button>
                <button class="btn btn-clear" onclick="if(confirm('Clear all?')) fetch('shuka/clear_sub').then(()=>update())">CLEAR ALL</button>
                <h4 style="margin-top:20px;">IMPORT AMNEZIA</h4>
                <form method="post" action="shuka/amnezia_upload" enctype="multipart/form-data">
                    <input type="file" name="amneziadata" onchange="this.form.submit()">
                </form>
            </div>
            <div>
                <h4>SERVERS</h4>
                <div id="list" class="list">Loading...</div>
            </div>
        </div>
    </div>
</body>
</html>
]])
end

function action_clear_sub()
    os.execute("/usr/bin/shuka_manager.py clear_sub")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_sync()
    local url = luci.http.formvalue("url")
    if url and url ~= "" then
        local fd = io.open("/etc/sing-box/sub_url.txt", "w")
        if fd then fd:write(url); fd:close() end
    end
    os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py sync &")
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_select()
    local tag = luci.http.formvalue("tag")
    if tag then os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py select " .. luci.util.shellquote(tag) .. " &") end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_delete()
    local tag = luci.http.formvalue("tag")
    if tag then os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py del_amnezia " .. luci.util.shellquote(tag)) end
    luci.http.prepare_content("application/json")
    luci.http.write_json({status = "ok"})
end

function action_start()
    os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py start &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_stop()
    os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py stop &")
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end

function action_amnezia_upload()
    local http = require "luci.http"
    local tmp = "/tmp/amnezia_upload.conf"
    local fp = io.open(tmp, "w")
    http.setfilehandler(function(m, c, e) if c then fp:write(c) end if e then fp:close() end end)
    http.formvalue("amneziadata")
    os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py amnezia " .. tmp .. " &")
    http.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end
