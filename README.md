# DSH Pocket iOS

A native SwiftUI client for connecting to a computer running DeepSeek Harness with the `dsh-pocket` plugin.

## Current status

- Native SwiftUI connection screen
- Server URL and secure PIN entry
- PIN submission to the Pocket `/pocket-login` endpoint (302 + cookie = success, 200 login page = wrong PIN)
- Session cookies handled by `URLSession`
- Native session list with refresh, new-session actions, and archived-session exclusion
- Conversation history and live event updates over `session/follow` (verified: replies appear in ~1s)
- Block-based message rendering: line breaks preserved, lists/code blocks/headings formatted
- Native QR scanning for Pocket connection URLs

See [HANDOFF.md](./HANDOFF.md) for architecture notes, root causes fixed in the last pass, device
build commands, and Debug-only self-test hooks (`DSH_SERVER` / `DSH_PIN` / `DSH_OPEN` / `DSH_SEND`).

## Build

Open `DSHPocket.xcodeproj` in Xcode, select an iPhone simulator, and run the `DSHPocket` scheme. The project currently targets iOS 17.0 and newer.

For LAN testing, use the Pocket LAN URL shown in DSH settings, usually `http://<computer-ip>:3081`. Public tunnel URLs use HTTPS.

## Current limitations

- Messages currently render text blocks only; tool activity, images, approvals, and other rich content are not surfaced.
- The server address is remembered, but the PIN is not stored in Keychain. Existing URL session cookies restore a valid login when the server keeps them active.
- Newer DSH builds filter archived sessions in `session/list`. Older builds require a workspace snapshot fallback, so their archived session summaries still cross the network before iOS hides them.
