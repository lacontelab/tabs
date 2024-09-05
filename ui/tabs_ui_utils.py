import os 

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