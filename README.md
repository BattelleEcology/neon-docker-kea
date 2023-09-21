
Description
===========
[Kea] provides DHCPv4 and DHCPv6 servers, a dynamic DNS update module, a portable DHCP library, libdhcp++, a control agent that provides a management REST interface, a NETCONF agent that provides a YANG/NETCONF interface for Kea,and a DHCP benchmarking tool, perfdhcp.

Kea is developed by Internet Systems Consortium, Inc.

[Kea]: https://gitlab.isc.org/isc-projects/kea.

This a hook for the Kea DHCP server to support a bug in NEON's data logger ("Grape") DHCP protocol.
According to [RFC4702], when the Fully Qualified Domain Name (FQDN) Option Flag bit "N is set to 1 the S bit MUST be 0". The Grape fails to do this and both bits are set to 1 which causes the kea server to drop Grape's packet.

To solve the problem this hook unpacks the unprocessed wire buffer using _**buffer4_receive**_ hook. If N and S are set to 1, N is forced to 0 to avoid throwing an exception and dropping the package.

```cpp
    // The format of the Client FQDN option is:

    //     Code   Len    Flags  RCODE1 RCODE2   Domain Name
    //    +------+------+------+------+------+------+--
    //    |  81  |   n  |      |      |      |       ...
    //    +------+------+------+------+------+------+--    
    // The format of the 1-octet Flags field is:

    //     0 1 2 3 4 5 6 7
    //    +-+-+-+-+-+-+-+-+
    //    |  MBZ  |N|E|O|S|
    //    +-+-+-+-+-+-+-+-+

    std::vector<uint8_t> buf;
    buffer_in.readVector(buf, opts_len);
    size_t offset=0;
    while(offset < buf.size()){
        size_t last_offset=offset;
        uint8_t opt_type = buf[offset++];
        uint8_t len=buf[offset++];
        if(opt_type==DHO_FQDN){
            if((buf[last_offset+2] & 0x09) == 0x09)
                query->data_[last_offset+options_start+2] &=0xF7;
        }
        offset+=len;
        if(opt_type==DHO_END)
            break;
    }


```

## How to build

You first need to compile the hook.  For this, you need Kea and Boost
development headers installed: on Debian, the packages are `kea-dev` and
`libboost-dev`.

To build, simply run:

    $ make


## How to use this hook

If all goes well, you should obtain a `kea-hook-grape.so` file.
Then, here is how to tell Kea to use this hook, for DHCPv4:

    {
    "Dhcp4":
    {
      "hooks-libraries": [
        {
          "library": "/path/to/hea-hook-runscript/kea-hook-grape.so",
          "parameters": {
            "wait": true
          }
        }
      ],
      ...
    }
    }

The `wait` parameter indicates whether Kea waits for the script to exit.  That is,
if set to `true`, Kea will block while the script is running.
Refer to the Kea documentation for more information about each hook point:

- DHCPv4 hooks reference: <https://jenkins.isc.org/job/Kea_doc/doxygen/de/df3/dhcpv4Hooks.html>
- DHCPv6 hooks reference: <https://jenkins.isc.org/job/Kea_doc/doxygen/d1/d02/dhcpv6Hooks.html>

[RFC4702]:https://datatracker.ietf.org/doc/rfc4702/



