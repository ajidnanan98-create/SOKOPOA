# Run SOKOPOA development milestone 1

## Windows PowerShell
1. Extract the `SOKOPOA` folder.
2. Open PowerShell inside `SOKOPOA/app`.
3. Run:
   ```powershell
   flutter create . --platforms=android,windows
   flutter pub get
   flutter run -d windows
   ```
4. To run on an Android phone, enable Developer Options and USB debugging, connect it,
   then run:
   ```powershell
   flutter devices
   flutter run -d <your-device-id>
   ```

## Backend (separate terminal)
1. Open PowerShell inside `SOKOPOA/backend`.
2. Run:
   ```powershell
   py -3.11 -m venv .venv
   .venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   copy .env.example .env
   ```
3. Configure real environment variables only in your local `.env`.
4. Run:
   ```powershell
   uvicorn app.main:app --reload
   ```

Do not expose the backend publicly or enter real business data until production authentication,
database persistence, HTTPS, tenant isolation and authorization have been completed.
