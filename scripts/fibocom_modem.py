#!/usr/bin/env python3
import os
import time
import sys
import json
import re

PORT = '/dev/ttyACM2'

def send_at(cmd, timeout=2):
    try:
        fd = os.open(PORT, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    except Exception as e:
        return f"ERROR: {e}"

    # Flush buffer
    try:
        while os.read(fd, 4096): pass
    except: pass

    os.write(fd, (cmd + '\r\n').encode())
    res = ''
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            chunk = os.read(fd, 4096).decode()
            if chunk:
                res += chunk
                if 'OK' in res or 'ERROR' in res: break
        except BlockingIOError:
            time.sleep(0.1)
    
    os.close(fd)
    return res.strip()

def get_status():
    csq_res = send_at('AT+CSQ')
    xact_res = send_at('AT+XACT?')
    cops_res = send_at('AT+COPS?')
    # Get IP and APN info
    addr_res = send_at('AT+CGPADDR=1')
    cgdcont_res = send_at('AT+CGDCONT?')
    
    # Parse CSQ
    csq = "N/A"
    csq_match = re.search(r'\+CSQ:\s*(\d+,\d+)', csq_res)
    if csq_match:
        csq = csq_match.group(1)
        
    # Parse Bands
    active_bands = []
    bands_match = re.search(r'\+XACT:\s*\d+,\d+,,([\d,]+)', xact_res)
    if bands_match:
        active_bands = [int(b) for b in bands_match.group(1).split(',')]
    
    # Parse Operator
    operator = "Unknown"
    mode = "N/A"
    # Example: +COPS: 0,0,"MegaFon",7
    cops_match = re.search(r'\+COPS:\s*\d+,\d+,"([^"]+)",(\d+)', cops_res)
    if cops_match:
        operator = cops_match.group(1)
        rat_map = {"0":"2G", "2":"3G", "7":"LTE", "13":"eMTC"}
        mode = rat_map.get(cops_match.group(2), "Unknown")

    # Parse IP
    ip_addr = "N/A"
    addr_match = re.search(r'\+CGPADDR:\s*1,"([^"]+)"', addr_res)
    if addr_match:
        ip_addr = addr_match.group(1)

    # Parse APN
    apn = "N/A"
    apn_match = re.search(r'\+CGDCONT:\s*1,"[^"]+","([^"]+)"', cgdcont_res)
    if apn_match:
        apn = apn_match.group(1)
    
    return json.dumps({
        "csq": csq,
        "active_bands": active_bands,
        "operator": operator,
        "mode": mode,
        "ip": ip_addr,
        "apn": apn,
        "raw_csq": csq_res,
        "raw_xact": xact_res,
        "raw_cops": cops_res
    })

def set_bands(bands_str):
    # bands_str should be like "103,107"
    # Ensure only valid bands are sent
    valid_bands = ["103", "107", "120"]
    req_bands = [b.strip() for b in bands_str.split(',') if b.strip() in valid_bands]
    
    if not req_bands:
        return "ERROR: No valid bands specified"
    
    cmd = f"AT+XACT=2,2,,{','.join(req_bands)}"
    return send_at(cmd)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: fibocom_modem.py [status|set_band <bands>|cmd <at_command>]")
        sys.exit(1)
        
    action = sys.argv[1]
    
    if action == "status":
        print(get_status())
    elif action == "set_band":
        if len(sys.argv) < 3:
            print("ERROR: Missing bands")
        else:
            print(set_bands(sys.argv[2]))
    elif action == "cmd":
        if len(sys.argv) < 3:
            print("ERROR: Missing AT command")
        else:
            print(send_at(sys.argv[2]))
    else:
        print(f"ERROR: Unknown action {action}")
