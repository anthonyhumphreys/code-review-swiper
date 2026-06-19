# Code Review Swiper

Code Review Swiper is a SwiftUI mobile app for reviewing GitHub pull requests one changed file at a time. It turns each file into a Tinder-style swipe card with an Apple Foundation Models summary on the front, the raw diff on the back, and accept/reject gestures that are compiled into PR feedback when the deck is finished.

## Features

- GitHub sign-in through OAuth device flow.
- Personal access token fallback for local development and simulators.
- Pull request picker for any `owner/repository` the signed-in user can access.
- One swipe card per changed file.
- Apple Foundation Models summaries when the framework is available, with a deterministic fallback summary on older platforms.
- Tap a card to flip between summary and diff.
- Swipe right or tap **Accept** to approve a file change.
- Swipe left or tap **Reject** to flag a file change.
- Final markdown summary that can be posted back as a GitHub PR review comment.

## Configuration

Create a GitHub OAuth app with device flow enabled, then add this value to your app's Info.plist or generated build settings:

- `GITHUB_CLIENT_ID`: the OAuth app client id.

The app opens GitHub's device verification page and polls for an access token, avoiding any client secret in the mobile app. It also supports pasting a GitHub personal access token for development.

## Running

Open the package in Xcode with an Apple SDK that includes SwiftUI and, for on-device LLM summaries, Foundation Models. Select an iOS destination and run the `CodeReviewSwiper` executable target.

```bash
swift build
```
