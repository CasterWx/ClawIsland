#!/usr/bin/env python3
import sys
import json
import socket
import os
import datetime

SOCKET_PATH = "/tmp/clawisland.sock"
LOG_FILE = "/tmp/clawisland_hook.log"

def log(msg):
    try:
        with open(LOG_FILE, "a") as f:
            f.write(f"[{datetime.datetime.now()}] {msg}\n")
    except:
        pass

def main():
    log("=== Hook Triggered ===")
    # Read stdin JSON from Claude Code
    try:
        payload_str = sys.stdin.read()
        if not payload_str.strip():
            log("Empty payload received from stdin.")
            return
            
        log(f"Raw payload: {payload_str}")
        payload = json.loads(payload_str)
        log(f"Parsed payload event type: {payload.get('hook_event_name') or payload.get('type')}")
    except Exception as e:
        log(f"Failed to parse stdin: {e}")
        return

    # Check if socket exists
    if not os.path.exists(SOCKET_PATH):
        log(f"Socket {SOCKET_PATH} does not exist. App might not be running.")
        print(json.dumps({"error": "App not running", "approved": True}))
        return

    # Connect to UNIX Domain Socket
    log(f"Connecting to socket {SOCKET_PATH}...")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(SOCKET_PATH)
        log("Socket connected! Sending payload...")
        sock.sendall(payload_str.encode('utf-8'))
        
        # If it's an event that requires synchronous response (like PermissionRequest)
        event_name = payload.get("hook_event_name") or payload.get("type")
        if event_name in ["PermissionRequest"]:
            log(f"Event '{event_name}' requires waiting for response...")
            # Signal EOF for the write direction to unblock Swift's fileHandle.read(upToCount: ...)
            sock.shutdown(socket.SHUT_WR)
            
            # Block and wait for app to send back response
            response_data = sock.recv(4096)
            if response_data:
                decoded = response_data.decode('utf-8')
                log(f"Received response from Swift app: {decoded}")
                print(decoded)
            else:
                log("Received EMPTY response from Swift app.")
        else:
            log("Event does not require blocking. Sent successfully.")
                
    except Exception as e:
        log(f"Socket error or execution error: {e}")
        print(json.dumps({"error": str(e), "approved": True}))
    finally:
        sock.close()
        log("=== Hook Execution Finished ===")

if __name__ == "__main__":
    main()
