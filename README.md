# KYARI Plant Care

Expo mobile app for iOS and Android, with a small private-key bridge for Kindwise Plant.id.

## Run on a phone with Expo Go

1. Install Node.js and Expo Go on the phone.
2. In the project folder run `npm install`, then `powershell -ExecutionPolicy Bypass -File .\start-phone.ps1`.
3. Scan the QR code with Expo Go. Keep the PowerShell window open while using the app. For AI photo features, the phone and computer should share a Wi-Fi network.

The garden is stored on-device. Photo picking, manual plant entry, plant identification, diagnosis, and local watering reminders are available in the app. AI photo features need the optional service setup below.

## Enable plant ID and health checks

The AI service needs a Kindwise Plant.id API key. Kindwise currently gives new API accounts 100 free credits for testing. Plant identification and plant health use credits; check your Kindwise dashboard for the remaining balance before broader use.

1. Register at [Kindwise](https://admin.kindwise.com/signup), then sign in to its admin panel.
2. Select **Create new API key**, choose **Plant.id**, name the key, and assign test credits to it.
3. In PowerShell at the project root, run the secure key setup script. It prompts for the key without displaying it, then saves it to the ignored `server/.env` file:

   ```powershell
   .\server\set-api-key.ps1
   ```

   Keep this key in `server/.env`; never put it in the mobile app or share it in chat. The running bridge picks it up on the next photo request. If PowerShell blocks local scripts, run `powershell -ExecutionPolicy Bypass -File .\server\set-api-key.ps1` from the project root.
4. Find your computer's Wi-Fi IPv4 address with `ipconfig`. Copy the root app template and edit it:

   ```powershell
   Copy-Item .env.example .env
   notepad .env
   ```

   Set `EXPO_PUBLIC_API_URL` to `http://<your-computer-ip>:8787`, for example `http://192.168.1.20:8787`. Do not use `localhost` in the phone app.
5. Keep the phone and computer on the same Wi-Fi network. Open one terminal in `server` and run `node index.js`; open a second terminal in the project root and run `npm start`. Restart Expo after editing `.env` so it loads the new URL.

The start script updates the ignored root `.env` with this computer's private Wi-Fi address when one is available, starts the local AI bridge, and opens Expo's tunnel on port 8082. If the computer is offline, the app still starts without photo analysis. The tunnel carries the app bundle to Expo Go; the local AI bridge still needs to be reachable over Wi-Fi. For phones on another network, host the bridge over HTTPS and use that service URL instead.

For a hosted app, deploy the server over HTTPS and set the app URL to that service. The app never needs to contain the Kindwise API key.
The included bridge is intended for local testing and applies a small per-IP daily request cap. Add real user authentication and stronger abuse controls before exposing it to the public internet.

## Current scope

- Home, My Garden, and Diagnose tabs styled from the KYARI UI reference.
- On-device garden storage, photo capture/library picker, care task completion, and local watering notifications that start when a plant is added and repeat until watering is logged.
- Photo identification offers up to five ranked matches for the user to confirm; health checks list up to three possible issues and available treatment notes.
- Photo uploads are resized to at most 1,400 pixels on the longest side before sending to the plant service.
- Live plant identification and health assessment through the server bridge when credentials and a reachable service URL are configured.
- Plants can be added manually, removed, and given a 3, 6, 7, 10, 14, or 21 day watering interval.
- Sign-in and cloud sync are not included yet; garden data stays on this phone.
