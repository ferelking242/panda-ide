# FFmpeg runtime

Panda IDE does not bundle FFmpeg or `ffmpeg_kit_flutter_new` in the APK.
FFmpeg is installed only when the user provisions the terminal runtime.

## Install

Open a Panda terminal after the Ubuntu, Debian, or Alpine rootfs has been
installed and run:

```sh
panda update
```

The command installs FFmpeg with the selected distribution package manager:

- Ubuntu/Debian: `apt-get install ffmpeg`
- Alpine: `apk add ffmpeg`

The package manager downloads the package after installation and verifies it
against the distribution's signed repository metadata. This keeps the APK
small and avoids shipping an unverified native multimedia library.

## Verify

Run:

```sh
panda doctor
ffmpeg -version
```

`panda doctor` reports the installed FFmpeg version. If it reports
`not installed`, run `panda update` again while the terminal has network
access. FFmpeg is available to terminal commands and agent-launched commands
through the rootfs `PATH`; it is not available as an Android-host library.