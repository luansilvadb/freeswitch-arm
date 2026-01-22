# FreeSWITCH Windows Troubleshooting Guide

## DLL Load Errors (Error 126)
If you see `[CRIT] switch_loadable_module.c:1754 Error Loading module ... dll open error [126l]`, it means a dependency is missing.

### Missing mod_b64.dll or mod_xml_curl.dll Dependencies
On Windows, FreeSWITCH modules often depend on external libraries.

1. **Check for libcurl**:
   `mod_xml_curl` requires `libcurl.dll`. Ensure it is in the same directory as `freeswitch.exe` or in your system PATH.
2. **OpenSSL Libs**:
   Ensure `libssl-1_1-x64.dll` and `libcrypto-1_1-x64.dll` (or equivalent versions) are present.
3. **Microsoft Visual C++ Redistributable**:
   Ensure the latest VC++ Redistributable is installed.

### NAT/STUN Detection
- If you see `switch_nat.c:438 No PMP or UPnP NAT devices detected!`, this is non-critical for local development but might affect external calls.
- To fix, ensure your router has UPnP enabled or manually configure `external-ip` in `sofia.conf.xml`.

### SIP Profile Binding
- **Error**: `Error Creating SIP UA for profile: internal-ipv6`.
- **Cause**: Port 5060 is already in use by IPv4, or IPv6 is disabled on the network interface.
- **Fix**: Update `autoload_configs/sofia.conf.xml` to use `$${local_ip_v4}` and ensure `auto-v6` is false.

## HTTP 404 Errors during XML Fetch
If you see `[ERR] mod_xml_curl.c:319 Received HTTP error 404 trying to fetch http://localhost:3000/freeswitch/xml`, it means the backend does not have a template for the requested configuration file.

- **Status**: As of feature `005-fix-freeswitch-config-error`, the backend now returns `200 OK` with an empty document fallback to prevent these errors and allow FreeSWITCH to use local defaults.
- **Verification**: Ensure the backend core is updated and running.
