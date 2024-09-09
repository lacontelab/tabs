import os 
import PySimpleGUI as sg

def parse_env_file(file_path):
    env_vars = {}
    with open(file_path, 'r') as file:
        for line in file:
            # Ignore comments and empty lines
            if line.startswith("#") or not line.strip():
                continue
            
            # Split lines of the form "KEY=VALUE"
            if "=" in line:
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                
                # Remove any trailing comments after variable
                value = value.split("#")[0].strip()
                
                # Add to environment variables dictionary
                env_vars[key] = value
    
    return env_vars

def load_env_vars(env_vars):
    for key, value in env_vars.items():
        os.environ[key] = value

def load_env(tabs_cfg_host_file=None, tabs_cfg_file=None):
    if os.path.exists(tabs_cfg_host_file):
        env_file = tabs_cfg_host_file
        load_env_vars(parse_env_file(env_file))
    elif os.path.exists(tabs_cfg_file):
        env_file = tabs_cfg_file
        load_env_vars(parse_env_file(env_file))
    else:
        # Open file dialog to select the configuration file
        sg.PopupOK(f"TABS environment file '{tabs_cfg_file}' does not exist!\n\nPlease select the configuration file")
        env_file = None

        env_file = sg.popup_get_file(
            'Please select a configuration file',
            file_types=(("Config files", "*.cfg"),),
            no_window=True
        )

        if env_file is not None:
            load_env_vars(parse_env_file(env_file))
        else:
            sg.PopupOK("No configuration file selected, exiting...")
            raise SystemExit(1)