module("luci.controller.shuka_hybrid", package.seeall)

function index()
    entry({"admin", "services", "shuka"}, call("action_gui"), _("Shuka VPN"), 60).dependent = true
    entry({"admin", "services", "shuka", "sync"}, call("action_sync"), nil).leaf = true
    entry({"admin", "services", "shuka", "clear_sub"}, call("action_clear_sub"), nil).leaf = true
    entry({"admin", "services", "shuka", "data"}, call("action_data"), nil).leaf = true
    entry({"admin", "services", "shuka", "select"}, call("action_select"), nil).leaf = true
    entry({"admin", "services", "shuka", "delete"}, call("action_delete"), nil).leaf = true
    entry({"admin", "services", "shuka", "start"}, call("action_start"), nil).leaf = true
    entry({"admin", "services", "shuka", "stop"}, call("action_stop"), nil).leaf = true
    entry({"admin", "services", "shuka", "amnezia_upload"}, call("action_amnezia_upload"), nil).leaf = true
end

local function read_f(p) local f=io.open(p,"r"); if f then local c=f:read("*all"); f:close(); return (c:gsub("%s+","")) end; return "0" end

function action_data()
    local u = require "luci.util"; local h = require "luci.http"; local j = require "luci.jsonc"; local fs = require "nixio.fs"
    local st_raw = u.exec("cat /etc/sing-box/state.json 2>/dev/null"); local st = (st_raw ~= "") and j.parse(st_raw) or {}
    local is_s = fs.access("/sys/class/net/tun-shuka"); local is_a = fs.access("/sys/class/net/awg0")
    local rx, tx = "0", "0"
    if is_s then rx=read_f("/sys/class/net/tun-shuka/statistics/rx_bytes"); tx=read_f("/sys/class/net/tun-shuka/statistics/tx_bytes")
    elseif is_a then rx=read_f("/sys/class/net/awg0/statistics/rx_bytes"); tx=read_f("/sys/class/net/awg0/statistics/tx_bytes") end
    local ip = u.exec("curl -s --connect-timeout 2 ifconfig.me") or "Offline"
    local srv = {}
    local cfg_raw = fs.readfile("/etc/sing-box/config.json"); local cfg = (cfg_raw and cfg_raw ~= "") and j.parse(cfg_raw) or {}
    if cfg and cfg.outbounds then for _, o in ipairs(cfg.outbounds) do if o.type=="vless" or o.type=="shadowsocks" then table.insert(srv,{tag=o.tag,type=o.type}) end end end
    for f in (fs.dir("/etc/amneziawg/profiles/") or function() end) do if f:match("%.conf$") then table.insert(srv,{tag=f:gsub("%.conf$",""),type="AWG"}) end end
    h.prepare_content("application/json")
    h.write_json({ rx=rx, tx=tx, ip=ip, servers=srv, active_tag=st.active_tag or "", is_running=(is_s or is_a), interface_up=(tonumber(rx or 0)>0), syncing=fs.access("/tmp/shuka_syncing") })
end

function action_gui()
    local u = require "luci.util"; local url_raw = u.exec("cat /etc/sing-box/sub_url.txt 2>/dev/null"); local url = url_raw:gsub("%s+", "")
    local d = require "luci.dispatcher"; local base = d.build_url("admin", "services", "shuka")
    luci.http.prepare_content("text/html")
    luci.http.write([[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Shuka Hybrid</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; color: #f1f5f9; padding: 20px; }
        .card { background: #1e293b; padding: 20px; border-radius: 12px; max-width: 800px; margin: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 1px solid #334155; }
        .stats { display: flex; gap: 10px; margin-bottom: 20px; }
        .stat { flex: 1; background: #0003; padding: 12px; border-radius: 10px; text-align: center; }
        .btn { padding: 10px 20px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; text-decoration: none; display: inline-block; transition: 0.2s; }
        .btn-start { background: #38bdf8; color: #0f172a; }
        .btn-stop { background: #ef4444; color: #fff; }
        .btn-del { background: transparent; color: #ef4444; border: 1px solid #ef4444; padding: 2px 8px; font-size: 10px; border-radius: 4px; margin-left: 10px; }
        .btn-clear { background: #ef444420; color: #ef4444; border: 1px solid #ef444440; width: 100%; margin-top: 5px; }
        .list { background: #0003; border-radius: 10px; padding: 10px; max-height: 450px; overflow-y: auto; border: 1px solid #334155; }
        .item { padding: 10px; margin-bottom: 6px; background: #ffffff05; border-radius: 8px; display: flex; justify-content: space-between; align-items: center; border: 1px solid transparent; }
        .item:hover { background: #ffffff10; }
        .item.active { border-color: #38bdf8; background: #38bdf815; border: 1px solid #38bdf8; }
        .val { font-size: 18px; font-weight: bold; color: #38bdf8; display: block; }
        .spinner { display: inline-block; width: 12px; height: 12px; border: 2px solid #fff3; border-top-color: #fff; border-radius: 50%; animation: spin 1s linear infinite; vertical-align: middle; margin-right: 5px; }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
    <script>
        const API = "]]..base..[[";
        let manualSync = false;
        function formatBytes(b) { b = parseInt(b) || 0; if (b > 1073741824) return (b / 1073741824).toFixed(2) + " GB"; if (b > 1048576) return (b / 1048576).toFixed(2) + " MB"; return (b / 1024).toFixed(2) + " KB"; }
        
        function doSync() {
            const btn = document.getElementById('sync-btn');
            btn.disabled = true;
            btn.innerHTML = '<span class="spinner"></span> UPDATING...';
            manualSync = true;
            
            const u = document.getElementById('url').value;
            fetch(API + '/sync?url=' + encodeURIComponent(u));
            
            setTimeout(() => { manualSync = false; update(); }, 15000);
        }

        function update() {
            fetch(API + '/data').then(r => r.json()).then(d => {
                document.getElementById('ip').textContent = d.ip;
                const statusEl = document.getElementById('status');
                if (d.interface_up) { statusEl.textContent = 'ONLINE'; statusEl.style.color = '#22c55e'; }
                else if (d.is_running) { statusEl.textContent = 'STARTING...'; statusEl.style.color = '#f59e0b'; }
                else { statusEl.textContent = 'OFFLINE'; statusEl.style.color = '#ef4444'; }
                
                document.getElementById('rx').textContent = formatBytes(d.rx); 
                document.getElementById('tx').textContent = formatBytes(d.tx);
                
                const btn = document.getElementById('sync-btn');
                if (d.syncing || manualSync) { 
                    btn.disabled = true; btn.innerHTML = '<span class="spinner"></span> UPDATING...'; 
                } else { 
                    btn.disabled = false; btn.innerHTML = 'REFRESH LIST'; 
                }

                const list = document.getElementById('list'); list.innerHTML = '';
                d.servers.forEach(s => {
                    const div = document.createElement('div'); div.className = 'item' + (s.tag === d.active_tag ? ' active' : '');
                    const content = document.createElement('div'); content.style.flex = "1"; content.style.cursor = "pointer";
                    content.onclick = () => fetch(API + '/select?tag=' + encodeURIComponent(s.tag)).then(() => setTimeout(update, 500));
                    content.innerHTML = '<span>' + (s.tag === d.active_tag ? '🟢 ' : '') + s.tag + '</span><br><small style="color:#94a3b8">' + s.type.toUpperCase() + '</small>';
                    div.appendChild(content);
                    if (s.type === 'AWG') {
                        const delBtn = document.createElement('button'); delBtn.className = 'btn-del'; delBtn.textContent = 'DEL';
                        delBtn.onclick = (e) => { e.stopPropagation(); if(confirm('Delete ' + s.tag + '?')) fetch(API + '/delete?tag=' + encodeURIComponent(s.tag)).then(()=>update()); };
                        div.appendChild(delBtn);
                    }
                    list.appendChild(div);
                });
            }).catch(e => console.error(e));
        }
        setInterval(update, 3000); update();
    </script>
</head>
<body>
    <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:20px;">
            <h2 style="margin:0;">🚀 Shuka Hybrid</h2>
            <div><a href="]]..base..[[/start" class="btn btn-start">START</a><a href="]]..base..[[/stop" class="btn btn-stop">STOP</a></div>
        </div>
        <div class="stats">
            <div class="stat"><small>IP</small><span class="val" id="ip">...</span></div>
            <div class="stat"><small>STATUS</small><span class="val" id="status">...</span></div>
            <div class="stat"><small>RX</small><span class="val" id="rx">0 B</span></div>
            <div class="stat"><small>TX</small><span class="val" id="tx">0 B</span></div>
        </div>
        <div style="display:grid; grid-template-columns: 1fr 1fr; gap:25px;">
            <div>
                <h4>SUBSCRIPTION</h4>
                <input type="text" id="url" style="width:100%; background:#0003; color:#fff; border:1px solid #334155; padding:10px; border-radius:6px;" value="]]..url..[[">
                <!-- ВОТ ЗДЕСЬ ДОБАВЛЕН ВЫЗОВ DOSYNC() -->
                <button id="sync-btn" class="btn btn-start" style="width:100%; margin-top:12px;" onclick="doSync()">REFRESH LIST</button>
                <button class="btn btn-clear" onclick="if(confirm('Clear all?')) fetch(API + '/clear_sub').then(()=>update())">CLEAR ALL</button>
                <h4 style="margin-top:25px;">IMPORT CONFIG</h4>
                <form method="post" action="]]..base..[[/amnezia_upload" enctype="multipart/form-data"><input type="file" name="amneziadata" onchange="this.form.submit()"></form>
            </div>
            <div id="list" class="list">...</div>
        </div>
    </div>
</body>
</html>
]])
end

function action_sync()
    local h = require "luci.http"; local u = h.formvalue("url")
    if u and u ~= "" then local f = io.open("/etc/sing-box/sub_url.txt", "w"); if f then f:write(u); f:close() end end
    os.execute("touch /tmp/shuka_syncing")
    os.execute("(sleep 15 && rm -f /tmp/shuka_syncing) &")
    os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py sync > /dev/null 2>&1 &")
    h.prepare_content("application/json"); h.write_json({ok=true})
end

function action_clear_sub() os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py clear_sub"); require"luci.http".prepare_content("application/json"); require"luci.http".write_json({ok=true}) end
function action_select() local t=luci.http.formvalue("tag"); if t then os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py select "..luci.util.shellquote(t).." &") end; luci.http.prepare_content("application/json"); luci.http.write_json({ok=true}) end
function action_delete() local t=luci.http.formvalue("tag"); if t then os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py del_amnezia "..luci.util.shellquote(t)) end; luci.http.prepare_content("application/json"); luci.http.write_json({ok=true}) end
function action_start() os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py start &"); luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka")) end
function action_stop() os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py stop &"); luci.http.redirect(luci.dispatcher.build_url("admin", "services", "shuka")) end
function action_amnezia_upload()
    local h=require"luci.http"; local tmp="/tmp/amnezia_upload.conf"; local f=io.open(tmp, "w")
    h.setfilehandler(function(m,c,e) if c then f:write(c) end if e then f:close() end end)
    h.formvalue("amneziadata"); os.execute("/usr/bin/python3 /usr/bin/shuka_manager.py amnezia "..tmp.." &")
    h.redirect(luci.dispatcher.build_url("admin", "services", "shuka"))
end
