# containerd-sysext

A systemd-sysext image that installs the latest containerd version. Used to be
able to deploy containerd 2.0 on Flatcar before it is bundled with the OS.

The scripts in this repo have been adapted from [the Flatcar sysext-bakery](https://github.com/flatcar/sysext-bakery).

## Releasing

Simply merge to main and push a new tag. A github release with the
sysext-image as an artifact is automatically created.
