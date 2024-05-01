// Copyright (C) 2019-2020 Internet Systems Consortium, Inc. ("ISC")
//
// This Source Code Form is subject to the terms of the End User License
// Agreement. See COPYING file in the premium/ directory.

#include <config.h>
#include <hooks/hooks.h>
#include <dhcp/pkt4.h>
#include <dhcp/option4_client_fqdn.h>
#include <asiolink/io_address.h>
#include <stats/stats_mgr.h>

#include "log.hpp"
#include <vector>

using namespace isc;
using namespace isc::grape;
using namespace isc::dhcp;
using namespace isc::hooks;
using namespace isc::log;
using namespace isc::stats;



void checkFqdnOption(Pkt4Ptr query){

    //Unpacks wire data
    isc::util::InputBuffer buffer_in(&query->data_[0], query->data_.size());
    if (buffer_in.getLength() < Pkt4::DHCPV4_PKT_HDR_LEN) {
        isc_throw(OutOfRange, "Received truncated DHCPv4 packet (len="
                  << buffer_in.getLength() << " received, at least "
                  << Pkt4::DHCPV4_PKT_HDR_LEN << "is expected");
    }

    uint8_t op_ = buffer_in.readUint8();
    uint8_t htype = buffer_in.readUint8();
    uint8_t hlen = buffer_in.readUint8();
    uint8_t hops_ = buffer_in.readUint8();
    uint32_t transid_ = buffer_in.readUint32();
    uint16_t secs_ = buffer_in.readUint16();
    uint16_t flags_ = buffer_in.readUint16();
    asiolink::IOAddress ciaddr_ = asiolink::IOAddress(buffer_in.readUint32());
    asiolink::IOAddress yiaddr_ = asiolink::IOAddress(buffer_in.readUint32());
    asiolink::IOAddress siaddr_ = asiolink::IOAddress(buffer_in.readUint32());
    asiolink::IOAddress giaddr_ = asiolink::IOAddress(buffer_in.readUint32());

    std::vector<uint8_t> hw_addr(Pkt4::MAX_CHADDR_LEN, 0);
    uint8_t sname_[Pkt4::MAX_SNAME_LEN];
    uint8_t file_[Pkt4::MAX_FILE_LEN];

    buffer_in.readVector(hw_addr, Pkt4::MAX_CHADDR_LEN);
    buffer_in.readData(sname_, Pkt4::MAX_SNAME_LEN);
    buffer_in.readData(file_, Pkt4::MAX_FILE_LEN);

    hw_addr.resize(hlen);

    HWAddrPtr hwaddr = HWAddrPtr(new HWAddr(hw_addr, htype));

    if (buffer_in.getLength() == buffer_in.getPosition()) {
        // this is *NOT* DHCP packet. It does not have any DHCPv4 options. In
        // particular, it does not have magic cookie, a 4 byte sequence that
        // differentiates between DHCP and RFC 951 BOOTP packets.
        isc_throw(InvalidOperation, "Received BOOTP packet without vendor information extensions.");
    }

    if (buffer_in.getLength() - buffer_in.getPosition() < 4) {
        // there is not enough data to hold magic DHCP cookie
        isc_throw(Unexpected, "Truncated or no DHCP packet.");
    }

    uint32_t magic = buffer_in.readUint32();
    if (magic != DHCP_OPTIONS_COOKIE) {
        isc_throw(Unexpected, "Invalid or missing DHCP magic cookie");
    }

    size_t opts_len = buffer_in.getLength() - buffer_in.getPosition();
    size_t options_start=buffer_in.getPosition();
    // Use readVector because a function which parses option requires
    // a vector as an input.
    std::vector<uint8_t> buf(opts_len, 0);
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
}

// Functions accessed by the hooks framework use C linkage to avoid the name
// mangling that accompanies use of the C++ compiler as well as to avoid
// issues related to namespaces.
extern "C" {

/// @brief This callout is called at the "buffer4_receive" hook.
///
/// Ignore DHCP and BOOTREPLY messages.
/// Remaining packets should be BOOTP requests so add the BOOTP client class
/// and set the message type to DHCPREQUEST.
///
/// @param handle CalloutHandle.
///
/// @return 0 upon success, non-zero otherwise.
int buffer4_receive(CalloutHandle& handle) {
    // Get the received unpacked message.
    Pkt4Ptr query;
    handle.getArgument("query4", query);

    try {
        checkFqdnOption(query);
    } catch (const SkipRemainingOptionsError& ex) {
        // An option failed to unpack but we are to attempt to process it
        // anyway.  Log it and let's hope for the best.
        LOG_DEBUG(grape_logger, DBGLVL_TRACE_BASIC,
                  GRAPE_PACKET_OPTIONS_SKIPPED)
            .arg(ex.what());
    } catch (const std::exception& ex) {
        // Failed to parse the packet.
        LOG_DEBUG(grape_logger, DBGLVL_TRACE_BASIC,
                  GRAPE_PACKET_UNPACK_FAILED)
            .arg(query->getRemoteAddr().toText())
            .arg(query->getLocalAddr().toText())
            .arg(query->getIface())
            .arg(ex.what());

        // Increase the statistics of parse failures and dropped packets.
        StatsMgr::instance().addValue("pkt4-parse-failed",
                                      static_cast<int64_t>(1));
        StatsMgr::instance().addValue("pkt4-receive-drop",
                                      static_cast<int64_t>(1));

        handle.setStatus(CalloutHandle::NEXT_STEP_DROP);

        return (0);
    }

    // Avoid to unpack it a second time!
    handle.setStatus(CalloutHandle::NEXT_STEP_CONTINUE);
    return (0);
}


/// @brief This function is called when the library is loaded.
///
/// @return always 0.
int load(LibraryHandle& /* handle */) {
    LOG_INFO(grape_logger, GRAPE_LOAD);
    return (0);
}

/// @brief This function is called when the library is unloaded.
///
/// @return always 0.
int unload() {
    LOG_INFO(grape_logger, GRAPE_UNLOAD);
    return (0);
}

} // end extern "C"
