// Copyright (C) 2019-2020 Internet Systems Consortium, Inc. ("ISC")
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

#include <config.h>
#include <hooks/hooks.h>
#include <dhcp/dhcp4.h>
#include <dhcp/pkt4.h>
#include <dhcp/option4_client_fqdn.h>
#include <exceptions/exceptions.h>
#include <stats/stats_mgr.h>
#include <util/io.h>

#include "log.hpp"
#include <vector>

using namespace isc;
using namespace isc::grape;
using namespace isc::dhcp;
using namespace isc::hooks;
using namespace isc::stats;

namespace {

// Both flags set is what the Grape loggers send, and RFC 4702 forbids.
const uint8_t FLAGS_N_AND_S = Option4ClientFqdn::FLAG_N | Option4ClientFqdn::FLAG_S;

/// @brief Clears the N flag of a Client FQDN option (81) that has both N and S
/// set, in the query's raw wire data, before Kea parses it.
///
/// Throws on packets Kea's own parser would reject (truncated, BOOTP without
/// options, bad magic cookie), so the callout can drop them.
void checkFqdnOption(const Pkt4Ptr& query) {
    std::vector<uint8_t>& data = query->data_;
    const size_t cookie_pos = Pkt4::DHCPV4_PKT_HDR_LEN;

    if (data.size() < cookie_pos) {
        isc_throw(OutOfRange, "Received truncated DHCPv4 packet (len="
                  << data.size() << " received, at least "
                  << cookie_pos << " is expected)");
    }
    if (data.size() == cookie_pos) {
        // No magic cookie, so this is an RFC 951 BOOTP packet, not DHCP.
        isc_throw(InvalidOperation, "Received BOOTP packet without vendor information extensions.");
    }
    if (data.size() < cookie_pos + 4) {
        isc_throw(Unexpected, "Truncated or no DHCP packet.");
    }
    if (util::readUint32(&data[cookie_pos], 4) != DHCP_OPTIONS_COOKIE) {
        isc_throw(Unexpected, "Invalid or missing DHCP magic cookie");
    }

    // Walk the options: code, length, data. Pad and End are a single byte.
    size_t offset = cookie_pos + 4;
    while (offset < data.size()) {
        const uint8_t code = data[offset++];
        if (code == DHO_PAD) {
            continue;
        }
        if (code == DHO_END || offset >= data.size()) {
            break;
        }
        const uint8_t len = data[offset++];
        // The flags are the first byte of the option data.
        if (code == DHO_FQDN && len >= 1 && offset < data.size()) {
            uint8_t& flags = data[offset];
            if ((flags & FLAGS_N_AND_S) == FLAGS_N_AND_S) {
                flags &= ~Option4ClientFqdn::FLAG_N;
                LOG_DEBUG(grape_logger, isc::log::DBGLVL_TRACE_BASIC, GRAPE_QUERY)
                    .arg(query->getRemoteAddr().toText());
            }
        }
        offset += len;
    }
}

} // anonymous namespace

// Functions accessed by the hooks framework use C linkage to avoid the name
// mangling that accompanies use of the C++ compiler as well as to avoid
// issues related to namespaces.
extern "C" {

/// @brief This callout is called at the "buffer4_receive" hook.
///
/// Fixes the Client FQDN flags of the query before Kea parses it, and drops
/// the queries that can't be parsed.
///
/// @param handle CalloutHandle.
///
/// @return always 0.
int buffer4_receive(CalloutHandle& handle) {
    Pkt4Ptr query;
    handle.getArgument("query4", query);

    try {
        checkFqdnOption(query);
    } catch (const std::exception& ex) {
        LOG_DEBUG(grape_logger, isc::log::DBGLVL_TRACE_BASIC,
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

    // Kea parses the (fixed) wire data as usual.
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
