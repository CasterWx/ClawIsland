#!/usr/bin/env python3
import json
import os
import sys
import shutil

def main():
    # Setup target directory
    target_dir = os.path.expanduser("~/.clawisland/hook")
    os.makedirs(target_dir, exist_ok=True)
    
    # Source hook is assumed to be next to this install script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_hook = os.path.join(script_dir, "clawisland-hook.py")
    target_hook = os.path.join(target_dir, "clawisland-hook.py")
    
    if os.path.exists(source_hook):
        shutil.copy2(source_hook, target_hook)
        os.chmod(target_hook, 0o755)
    else:
        print(f"Warning: source hook not found at {source_hook}")
        if not os.path.exists(target_hook):
            print("Target hook doesn't exist either. Aborting.")
            return

    settings_path = os.path.expanduser("~/.claude/settings.json")
    hook_command = f"/usr/bin/python3 {target_hook}"
    
    if not os.path.exists(settings_path):
        print("settings.json not found in ~/.claude/")
        return
        
    with open(settings_path, 'r') as f:
        data = json.load(f)
        
    if "hooks" not in data:
        data["hooks"] = {}
        
    events_to_listen = ["SessionStart", "SessionEnd", "PermissionRequest", "Stop", "UserPromptSubmit", "PostToolUse", "PreToolUse"]
    
    for event in events_to_listen:
        if event not in data["hooks"]:
            data["hooks"][event] = []
            
        # Check if we already exist in the event
        exists = False
        for listener in data["hooks"][event]:
            if "hooks" in listener:
                for sub_hook in listener["hooks"]:
                    if sub_hook.get("command") == hook_command:
                        exists = True
                        break
            if exists:
                break
                
        if not exists:
            new_hook = {
                "hooks": [
                    {
                        "command": hook_command,
                        "type": "command"
                    }
                ],
                "matcher": "*"
            }
            if event == "PermissionRequest":
                new_hook["hooks"][0]["timeout"] = 86400
                
            data["hooks"][event].append(new_hook)
            
    with open(settings_path, 'w') as f:
        json.dump(data, f, indent=2)
        
    print("Successfully injected clawisland-hook.py into ~/.claude/settings.json!")

if __name__ == "__main__":
    main()
