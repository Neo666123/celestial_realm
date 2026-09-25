@echo off
start msedge --app=http://localhost:8000
python -m http.server 8000