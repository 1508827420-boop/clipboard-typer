# Third-party software

## AutoHotkey

- Project: [AutoHotkey/AutoHotkey](https://github.com/AutoHotkey/AutoHotkey)
- Version used for validation: 2.0.30
- Release and source: [v2.0.30](https://github.com/AutoHotkey/AutoHotkey/releases/tag/v2.0.30)
- Runtime ZIP: [AutoHotkey_2.0.30.zip](https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.30/AutoHotkey_2.0.30.zip)
- SHA-256: `1E0ECE7ECB2D5646E55758150472677996A57F9DB5C83D2996D8B47B9E2F31A4`
- License: upstream GNU General Public License. The unmodified archive includes `license.txt`; retain that file with the downloaded runtime.

AutoHotkey is a separate interpreter dependency. Its executable, upstream source and documentation are not distributed in this repository or the source release ZIP. `prepare-runtime.ps1` retrieves the official unmodified archive directly from the upstream GitHub release and verifies its checksum. This project's MIT license does not replace or relicense the AutoHotkey runtime.
