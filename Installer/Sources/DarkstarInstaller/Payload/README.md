# Installer payload (staged at build time)

`bash dev.sh dist` (Scripts/package.sh) copies the freshly built
`Darkstar Robotics.app` into this folder before building the installer, so
the installer always ships the app it was built with. The staged app is
gitignored; only this note is committed, which keeps `swift build` working
in a clean checkout and in CI. An installer built without a staged app
refuses to install and says the payload is missing.
