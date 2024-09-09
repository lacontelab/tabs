#
# Temporary Adaptive Brain State (TABS) 
# user interface (UI) for running scripts
#

import PySimpleGUI as sg
import subprocess
import threading
import os
import tabs_ui_utils as ui_utils
from threading import Lock

# defines
prog_name = 'tabsUI'
default_editor = 'gvim'
sg.set_options(font=('Helvetica', 14))
sg.theme('Default1')

base_path = os.path.join(os.getcwd())

# Load tabs environment variables
# assuming cfg resides in the directory from which script is called
hostname = os.popen('hostname').read().strip()

# Load tabs environment variables
ui_utils.load_env(tabs_cfg_host_file=os.path.join(base_path, f"tabs_env_{hostname}.cfg"),
 tabs_cfg_file=os.path.join(base_path, f"tabs_env.cfg"))

# Define the common paths for scripts and logs
script_path = os.path.join(os.environ.get('TABS_PATH'), 'bin')
log_path = os.path.join(os.environ.get('TABS_PATH'), 'log')

# Ensure the log directory exists
os.makedirs(log_path, exist_ok=True)

# lock script processes for concurrency management
process_lock = Lock()

# Define main scripts, their names, and tooltips
main_scripts = {
    "MASK (AFTER MASK scan)": {"path": os.path.join(script_path, "tabs_process_mask_post+rsn_mask.sh"),
                  "name": "MASK\n (AFTER scan)",
                  "tooltip": "Run AFTER MASK scan",
                  "logfile_name": None,
                  "args": []},

    "RSN TRAINING (AFTER REST scan)": {"path": os.path.join(script_path, "tabs_process_train_post+rsn_train.sh"),
                  "name": "REST\n (AFTER scan)",
                  "tooltip": "Run AFTER REST scan",
                  "logfile_name": None,
                  "args": []},

    "DMN FEEDBACK (BEFORE FEEDBACK scan)": {"path": os.path.join(script_path, "tabs_process_test_pre+rsn_test.sh"),
                  "name": "FEEDBACK\n (BEFORE scan)",
                  "tooltip": "Run BEFORE FEEDBACK scan",
                  "logfile_name": None,
                  "args": []},
}

# Define additional scripts for the File menu
file_menu_scripts = {
    "[Re]Start afni": {"path": os.path.join(script_path, "tabs_start_afni.sh"),
                       "tooltip": "Start or restart afni controllers",
                       "logfile_name": None,
                       "args": []},

    "Start DICOM server": {"path": os.path.join(script_path, "tabs_start_dicomserver.sh"),
                       "tooltip": "Start DICOM server (storescp)",
                       "logfile_name": None,
                       "args": []},
}

# Define additional scripts for the Run menu
run_menu_scripts = {
}

# Define exit scripts that should run before exiting
exit_scripts = {
    "Close afni": {"path": os.path.join(script_path, "tabs_start_afni.sh"),
                   "tooltip": "Close afni controllers",
                   "logfile_name": "afni.log",
                   "args": ['-kill']},

    "Stop DICOM server": {"path": os.path.join(script_path, "tabs_start_dicomserver.sh"),
                       "tooltip": "Stop DICOM server",
                       "logfile_name": None,
                       "args": ['-kill']},
}

current_script_process = None
current_script_name = None

def run_script(script_name, script_info, window=None):
    """Run the script in a separate thread and update the GUI safely."""
    global current_script_process, current_script_name
    try:
        # Lock before updating shared variables
        with process_lock:
            current_script_name = script_name
            log_file_name = script_info.get("logfile_name") or os.path.splitext(os.path.basename(script_info["path"]))[0] + '.log'
            log_file_path = os.path.join(log_path, log_file_name)

        if window:
            window.write_event_value('UPDATE_BUTTONS', None)
            window.write_event_value('UPDATE_STATUS', f"Running: {script_name}")

        command = [script_info["path"]] + script_info.get("args", [])

        # Run the script and write logs
        with open(log_file_path, "w") as log_file:
            current_script_process = subprocess.Popen(command, stdout=log_file, stderr=subprocess.STDOUT)
            current_script_process.wait()

    except Exception as e:
        if window:
            window.write_event_value('ERROR', str(e))
    finally:
        with process_lock:
            current_script_name = None
            current_script_process = None
        if window:
            window.write_event_value('UPDATE_BUTTONS', None)
            window.write_event_value('UPDATE_STATUS', "")

def kill_script():
    """Terminate the currently running script."""
    global current_script_process
    with process_lock:
        if current_script_process:
            current_script_process.terminate()

def update_buttons(window):
    """Update the state of the buttons based on the current running script."""
    with process_lock:
        for script in main_scripts:
            window[script].update(disabled=(current_script_name is not None))
            window[f"Edit/Kill_{script}"].update("Kill" if script == current_script_name else "Edit")

def edit_script(script_path):
    """Open the script in an editor."""
    editor = os.getenv('EDITOR', default_editor)
    subprocess.Popen([editor, script_path])

def view_logs(script_name):
    """View the logs of the script."""
    log_file_name = main_scripts[script_name].get("logfile_name") or os.path.splitext(os.path.basename(main_scripts[script_name]["path"]))[0] + '.log'
    log_file_path = os.path.join(log_path, log_file_name)
    editor = os.getenv('EDITOR', default_editor)
    subprocess.Popen([editor, log_file_path])

def run_file_menu_script(script_name):
    """Run the scripts from the File menu."""
    if script_name in file_menu_scripts:
        threading.Thread(target=run_script, args=(script_name, file_menu_scripts[script_name], window), daemon=True).start()

def run_run_menu_script(script_name):
    """Run the scripts from the Run menu."""
    if script_name in run_menu_scripts:
        threading.Thread(target=run_script, args=(script_name, run_menu_scripts[script_name], window), daemon=True).start()

def run_exit_scripts():
    """Run all exit scripts before exiting."""
    threads = []
    for script_name, script_info in exit_scripts.items():
        t = threading.Thread(target=run_script, args=(script_name, script_info, None), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

# Append main scripts to run_menu_scripts
run_menu_scripts.update(main_scripts)

# Dynamically create the menu based on file_menu_scripts and run_menu_scripts
menu_def = [
    ['File', [key for key in file_menu_scripts.keys()] + ['Exit']],
    ['Run', [key for key in run_menu_scripts.keys()]],
]

layout = [[sg.Menu(menu_def, font=('Helvetica', 14))]]

# Add buttons for main scripts to the layout
for script_name, script_info in main_scripts.items():
    button_column = sg.Column([
        [sg.Button("Edit", key=f"Edit/Kill_{script_name}", size=(10, 1))],
        [sg.Button("View Logs", key=f"View_Logs_{script_name}", size=(10, 1))]
    ])

    layout.append([
        sg.Button(script_info["name"], key=script_name, tooltip=script_info["tooltip"], size=(20, 3), font=('Helvetica', 14, 'bold')),
        button_column
    ])

# Add a status window at the bottom of the layout to show currently running script
layout.append([sg.Text("", key="status_text", size=(40, 1), font=('Helvetica', 14), justification='left')])

layout.append([sg.Button("Exit")])

# Create the Window
window = sg.Window(prog_name, layout)

# Event Loop
while True:
    event, values = window.read()
    
    if event in (sg.WIN_CLOSED, "Exit"):
        run_exit_scripts()
        break
    elif event == 'UPDATE_BUTTONS':
        update_buttons(window)
    elif event == 'UPDATE_STATUS':
        window['status_text'].update(values[event])
    elif event == 'ERROR':
        sg.Popup("Unexpected error:", values[event])
    
    # Check if a script from the main buttons was clicked
    if event in main_scripts and current_script_name is None:
        threading.Thread(target=run_script, args=(event, main_scripts[event], window), daemon=True).start()
    elif "Edit/Kill" in event:
        script_name = event.split("_")[1]
        if script_name == current_script_name:
            kill_script()
        else:
            edit_script(main_scripts[script_name]["path"])
    elif "View_Logs" in event:
        script_name = event.split("_")[2]
        if script_name in main_scripts:
            view_logs(script_name)

    # Check if a script from the File menu was selected
    elif event in file_menu_scripts:
        run_file_menu_script(event)

    # Check if a script from the Run menu was selected
    elif event in run_menu_scripts:
        run_run_menu_script(event)

window.close()
