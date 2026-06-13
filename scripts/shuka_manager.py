#!/usr/bin/env python3
import json, os, sys, urllib.request, urllib.parse, base64, re, time

CONFIG_PATH = "/etc/sing-box/config.json"
TEMPLATE_PATH = "/etc/sing-box/config.json.template"
SUB_URL_FILE = "/etc/sing-box/sub_url.txt"
AMNEZIA_PROFILES = "/etc/amneziawg/profiles/"
STATE_FILE = "/etc/sing-box/state.json"
CONN_FLAG = "/tmp/shuka_connecting"

def load_json(path):
    if os.path.exists(path):
        try:
            with open(path, 'r') as f: return json.load(f)
        except: pass
    return {}

def save_json(path, data):
    with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)

def set_state(tag, engine):
    save_json(STATE_FILE, {"active_tag": tag, "engine": engine})

def stop_all():
    os.system("killall sing-box 2>/dev/null")
    os.system("killall amneziawg-go 2>/dev/null")
    os.system("ip link delete awg0 2>/dev/null")
    os.system("/usr/bin/amneziawg-stop.sh 2>/dev/null")
    os.system("ip route flush cache")

def apply_fw(iface):
    os.system("iptables -I FORWARD -i br-lan -o " + iface + " -j ACCEPT 2>/dev/null")
    os.system("iptables -t nat -I POSTROUTING -o " + iface + " -j MASQUERADE 2>/dev/null")

def select_server(tag):
    if not tag: return
    os.system("touch " + CONN_FLAG)
    tag_clean = tag.replace(".conf", "")
    conf_path = AMNEZIA_PROFILES + tag_clean + ".conf"
    
    if os.path.exists(conf_path):
        stop_all()
        os.system("ip link add dev awg0 type amneziawg")
        os.system("cp '" + conf_path + "' /etc/amneziawg/awg0.conf")
        os.system("/usr/bin/start_shuka.sh &")
        set_state(tag_clean, "amneziawg")
    else:
        c = load_json(CONFIG_PATH)
        if "route" in c and "rules" in c["route"]:
            for r in c["route"]["rules"]:
                if r.get("action") == "hijack-dns": continue
                if r.get("outbound") not in ["direct","dns-out","block","any"]: r["outbound"] = tag
        if "dns" in c and "servers" in c["dns"]:
            for s in c["dns"]["servers"]:
                if s.get("tag") == "dns-proxy": s["detour"] = tag
        save_json(CONFIG_PATH, c)
        stop_all()
        cmd = "export ENABLE_DEPRECATED_LEGACY_DNS_SERVERS=true; export ENABLE_DEPRECATED_OUTBOUND_DNS_RULE_ITEM=true; export ENABLE_DEPRECATED_MISSING_DOMAIN_RESOLVER=true; /usr/bin/sing-box run -c /etc/sing-box/config.json &"
        os.system(cmd)
        apply_fw("tun-shuka")
        set_state(tag, "sing-box")
    os.system("(sleep 15 && rm -f " + CONN_FLAG + ") &")

def main():
    if len(sys.argv) < 2: return
    cmd = sys.argv[1]
    if cmd == "sync":
        if not os.path.exists(SUB_URL_FILE): return
        with open(SUB_URL_FILE) as f: url = f.read().strip()
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'v2rayNG/1.8.5'})
            with urllib.request.urlopen(req, timeout=15) as r:
                d = r.read().decode('utf-8').strip()
                if not d.startswith(('vless://', 'ss://')): d = base64.b64decode(d + '='*(-len(d)%4)).decode('utf-8')
                links = d.splitlines(); obs = []
                for l in links:
                    if l.startswith("vless://"):
                        parts = l[8:].split("@")
                        if len(parts) >= 2:
                            uuid = parts[0]; rest = parts[1].split("?"); host_port = rest[0].split(":")
                            host = host_port[0]; port = int(host_port[1]) if len(host_port) > 1 else 443
                            tag = "VLESS"; params = {}
                            if len(rest) > 1:
                                pt = rest[1].split("#"); params = dict(urllib.parse.parse_qsl(pt[0]))
                                if len(pt) > 1: tag = urllib.parse.unquote(pt[1])
                            out = {"type":"vless","tag":tag,"server":host,"server_port":port,"uuid":uuid,"tls":{"enabled":params.get("security") in ["tls","reality"],"server_name":params.get("sni",""),"utls":{"enabled":True,"fingerprint":"chrome"}}}
                            if params.get("security") == "reality": out["tls"]["reality"] = {"enabled":True,"public_key":params.get("pbk",""),"short_id":params.get("sid","")}
                            obs.append(out)
                if obs:
                    cfg = load_json(TEMPLATE_PATH)
                    cfg["outbounds"] = obs + [o for o in cfg.get("outbounds",[]) if o["type"] not in ["vless","shadowsocks"]]
                    save_json(CONFIG_PATH, cfg)
        except: pass
    elif cmd == "select": select_server(sys.argv[2])
    elif cmd == "clear_sub":
        if os.path.exists(SUB_URL_FILE): os.remove(SUB_URL_FILE)
        save_json(CONFIG_PATH, load_json(TEMPLATE_PATH))
        stop_all(); set_state("", "none")
    elif cmd == "stop": stop_all(); set_state("", "none"); os.system("rm -f " + CONN_FLAG)
    elif cmd == "start":
        state = load_json(STATE_FILE)
        if state.get("active_tag"): select_server(state["active_tag"])
    elif cmd == "amnezia":
        path = sys.argv[2]
        if os.path.exists(path):
            name = "Imported-" + base64.b32encode(os.urandom(2)).decode().strip("=")
            if not os.path.exists(AMNEZIA_PROFILES): os.makedirs(AMNEZIA_PROFILES)
            os.system("cp '" + path + "' '" + AMNEZIA_PROFILES + name + ".conf'")
    elif cmd == "del_amnezia":
        tag = sys.argv[2]; path = AMNEZIA_PROFILES + tag + ".conf"
        if os.path.exists(path): os.remove(path)

if __name__ == "__main__": main()
