# TrollInject
iOS dynamic injector for TrollStore

## What does it do
It prints some information on the target App process, launches the App with 
`.dylib` injected, or injects a `.dylib` into a running App process. Unlike
TrollFool, all the injection work is dynamic, with no files touched, leaving 
the traces to the minimal for the App to detect. Note this is only for 
development usage. If the system kills the App when it's in the background, 
you will not get a injected process when you switch back. The injection must 
be operated again manually to work.

## System requirements
Only works under iOS 17.0 for TrollStore. No other system compatibilities planned.

## How to build
Open `.xcodeproj` file and build. You will find `.tipa` file under source root.

## Credits / Thanks
- File signer by TrollFool
- UI by TrollDecrypt
- App Icon by Gemini
