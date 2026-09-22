# Third-Party Notices

This project includes original ECNU OpenConnect GUI code and bundled
third-party runtime components. The root `LICENSE` file applies only to the
original GUI code. Third-party components remain under their own licenses.

## OpenConnect

- Component: OpenConnect command-line client and bundled runtime files under
  `internal/openconnect`
- Bundled version: OpenConnect v9.21
- Upstream project: https://gitlab.com/openconnect/openconnect
- License: GNU Lesser General Public License v2.1 only
- License text: `licenses/COPYING.LGPL-2.1-openconnect.txt`

If you redistribute a binary package containing the bundled OpenConnect
runtime, keep this notice and the LGPL license text with the package, and keep
the upstream source location available to users.

## vpnc-scripts / vpnc-script-win.js

- Component: `internal/openconnect/vpnc-script-win.js`
- Upstream project: https://gitlab.com/openconnect/vpnc-scripts
- License: GNU General Public License v2 or later, as indicated by the
  upstream vpnc-scripts packaging metadata and license text
- License text: `licenses/COPYING.GPL-vpnc-scripts.txt`

This repository contains a modified `vpnc-script-win.js` for ECNU client-side
split tunneling behavior. Keep the source file and this notice available when
redistributing the project or a packaged build.

## Runtime DLLs

The bundled OpenConnect runtime directory also contains DLL dependencies such
as GnuTLS, libxml2, nettle, iconv, zlib, and related Windows runtime libraries.
Those files are redistributed as part of the OpenConnect runtime environment
and remain under their respective upstream licenses. Before publishing a formal
binary release, review the exact runtime package source and keep any upstream
license notices that accompany those dependencies.

## Credential Files

Local runtime files such as saved login credentials, logs, PID files, and route
state files are intentionally excluded by `.gitignore` and should not be
published.
