# PROD RUN
docker compose down
docker compose up -d --build

docker compose build --no-cache
docker compose up -d

docker logs android-webView-auto-builder -f

# RECOVERY
docker compose up -d --build

git log --oneline -n 20

Copy-Item .env $env:TEMP\.env.backup
git reset --hard 80f714fc
git clean -fd
Copy-Item $env:TEMP\.env.backup .env -Force
git push origin master --force

# UPDATE
git add .
git commit -m "v0.0.28 - test 1"
git push

# DEV LOG
v0.0.1 - Initial Windows PowerShell automation
v0.0.2 - Implemented "Jokes Progress Bar"
v0.0.3 - Added Linux & macOS support (Bash sript)
v0.0.4 - Added Docker support for isolate builds
v0.0.5 - Multi-user concurrency suppor
v0.0.6 - Web UI with 3D background & SessionPersistence
v0.0.7 - Implement APK Signing & Keystor management
v0.0.8 - screenshots added to README.md
v0.0.9 - added to server apk.weforks.org
v0.0.10 - readme.md updated
v0.0.11 - Ultra Fast Builder - Binary Patching
v0.0.12 - UI Polish & Stability Improvements
v0.0.13 - README.md future tasks updated
v0.0.14 - fixed build issues
v0.0.15 - added github webhook to server auto update
v0.0.16 - fixed mobile desighn and added tools folder
v0.0.17 - added version sync
v0.0.18 - version test 1
v0.0.19 - version test 2
v0.0.20 - version test 3
v0.0.21 - version test 4
v0.0.22 - version sync checked and working
v0.0.23 - full file size refactoring
v0.0.24 - project upgraded with audit
v0.0.25 - added support for multi APK 
v0.0.26 - server update test 
v0.0.27 - added ROADMAP.md
v0.0.28 - test 1
