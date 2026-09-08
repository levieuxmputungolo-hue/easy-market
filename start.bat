@echo off
cd /d "%~dp0"
echo Installation des dependances...
pip install -r requirements.txt
echo Seed de la base de donnees...
python -m app.seed
echo Demarrage du serveur Aisy Market sur http://localhost:8000
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
pause
