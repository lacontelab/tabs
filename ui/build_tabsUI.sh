# build tabs ui

# clean up previous build
if [ -d build ]; then
  rm -rf build
fi

if [ -d dist ]; then
  rm -rf dist
fi  

if [ -f tabsUI.spec ]; then
  rm tabsUI.spec
fi  

# build it 
pyinstaller --onefile --windowed tabsUI.py

if [ ! -d dist ]; then
  echo "ERROR: Build failed!"
  exit 1
fi  

# mv executable to Desktop
#cp dist/tabsUI ~/Desktop/tabsUI
cp dist/tabsUI ../.
